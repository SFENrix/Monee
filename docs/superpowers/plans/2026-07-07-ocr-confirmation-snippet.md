# OCR Confirmation Snippet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Committing is deferred**: this plan's tasks end with a build-verification step, not a `git commit` step — the harness this plan runs under only commits when the user explicitly asks, so ask the user before committing once all tasks are done.

**Goal:** Replace the receipt-capture flow's "parse and save immediately, no confirmation" behavior with an interactive confirmation step — an App Intents snippet (Income/Expense buttons) for the Action Button/Shortcut path, and an equivalent in-extension confirmation screen for the Share Extension path.

**Architecture:** `ReceiptCaptureService.capture(rawText:)` (parse+save in one call) splits into `stage(rawText:)` (parse only) and `save(...)` (persist, callable once category is confirmed). `ScanReceiptTextIntent` returns an iOS 26 interactive App Intents snippet (`ShowsSnippetView`) with Income/Expense buttons, each wired via `Button(intent:)` to a small sibling `AppIntent` that calls `save(...)` and ends the flow. The Share Extension isn't an App Intents surface, so it gets a plain SwiftUI confirmation view (no snippet restrictions) hosted in a `UIHostingController`, with ordinary buttons calling the same `save(...)`.

**Tech Stack:** SwiftUI, AppIntents (iOS 26 interactive snippets), SwiftData, UIKit (Share Extension host).

## Global Constraints

- No XCTest target exists in this project (confirmed earlier this session: zero `XCTest` references in `project.pbxproj`, no `*Tests*` directories). Every task verifies via **build (`xcodebuild`) + manual run**, not automated tests.
- This plan uses iOS 26's App Intents interactive-snippet API (`ShowsSnippetView`, `Button(intent:)` inside a snippet), introduced at WWDC25 — a newer API surface with limited precedent in training data. Treat each task's build-verification step as load-bearing, not a formality: small signature mismatches (init requirements, parameter summaries) are plausible and this is where they get caught.
- Confirmed constraint from Apple's own WWDC25 material: `TextField`, `Toggle`, and any local-`@State`-backed control do **not** work inside an App Intents snippet — only `Button`/`Text`/`Image`/layout containers, and all interactivity must trigger a new `AppIntent` instance, never mutate local view state.
- IDR-only currency formatting (`Double.idrFormatted`) — matches existing codebase convention, no other currency support.
- Amount/date correction via a follow-up text-input intent is explicitly **out of scope** for this plan — only category labeling (Income/Expense) is being built now.
- `ScanReceiptTextIntent.swift` already hosts `ScanReceiptShortcutsProvider` — only one `AppShortcutsProvider` conformance is allowed per app target, so new intents must NOT add a second one.

---

## File Structure

| File | Change |
|---|---|
| `Monee/Core/Capture/ReceiptCaptureService.swift` | **Modify** — replace `capture(rawText:)` with `stage(rawText:) -> CaptureOutcome` (parse only) and `save(title:amount:date:category:rawKeyword:) -> Transaction` (persist). |
| `Monee/AppTargets/ScanReceiptTextIntent.swift` | **Modify** — `perform()` returns `some IntentResult & ShowsSnippetView`, presenting a confirmation snippet instead of saving directly. |
| `Monee/AppTargets/ReceiptConfirmationSnippetView.swift` | **Create** — the snippet's SwiftUI view (single concrete type, internal enum state for error vs. confirming). |
| `Monee/AppTargets/ConfirmReceiptIntents.swift` | **Create** — `ConfirmReceiptAsIncomeIntent` and `ConfirmReceiptAsExpenseIntent`, the two intents the snippet's buttons trigger. |
| `Monee/AppTargets/ShareExtension/ShareConfirmationView.swift` | **Create** — plain SwiftUI confirmation view for the Share Extension (no snippet restrictions apply here). |
| `Monee/AppTargets/ShareExtension/ShareViewController.swift` | **Modify** — present `ShareConfirmationView` via `UIHostingController` instead of saving immediately. |

---

### Task 1: Split `ReceiptCaptureService` into `stage()` + `save()`

**Files:**
- Modify: `Monee/Core/Capture/ReceiptCaptureService.swift`

**Interfaces:**
- Consumes: `RegexParser.parse(_:) -> ParsedReceiptData` (existing, unchanged — fields: `amount: Double?`, `date: Date?`, `keyword: String?`, `category: TransactionCategory`, `suggestedTitle: String`, `isIncome: Bool`, `rawText: String`). `Transaction(title:amount:date:category:source:rawKeyword:)` (existing init). `NotificationService.scheduleCaptureNotification(for:)` (existing, unchanged).
- Produces: `enum CaptureOutcome { case needsConfirmation(ParsedReceiptData); case amountNotFound }`. `ReceiptCaptureService.stage(rawText: String) -> CaptureOutcome`. `ReceiptCaptureService.save(title: String, amount: Double, date: Date, category: TransactionCategory, rawKeyword: String?) -> Transaction` — later tasks (2, 3, 6) call this exact signature.

- [x] **Step 1: Rewrite the file**

```swift
//
//  ReceiptCaptureService.swift
//  Monee
//
//  Shared by the Action Button intent (main app target) and the Share Extension target.
//  Owns the "raw text in -> parsed fields out" decision, and the actual persistence, as
//  two separate steps: `stage` parses only (never touches the database), `save` persists
//  once the caller has confirmed (and possibly corrected) the category. This split exists
//  so both entry points can show a confirmation UI — an interactive App Intents snippet
//  for the Action Button, a plain SwiftUI view for the Share Extension — before anything
//  is written, instead of the old "parse and save in one step, fix it later" design.
//
//  Rule unchanged from before: if RegexParser finds an amount, staging succeeds and the
//  caller must ask the user to confirm/label it. If it doesn't find an amount, nothing is
//  ever saved — no staged/partial record.
//

import Foundation
import SwiftData

enum CaptureOutcome {
    case needsConfirmation(ParsedReceiptData)
    case amountNotFound
}

enum ReceiptCaptureService {
    /// Parses only — never inserts or saves anything. The caller (an AppIntent's
    /// perform(), or the Share Extension) is responsible for presenting a confirmation
    /// UI and calling `save` once the user has picked Income or Expense.
    static func stage(rawText: String) -> CaptureOutcome {
        let parsed = RegexParser.parse(rawText)
        guard parsed.amount != nil else {
            return .amountNotFound
        }
        return .needsConfirmation(parsed)
    }

    /// Persists a confirmed transaction and schedules the "logged" notification.
    /// Called only after the user has confirmed (and chosen a category for) a staged
    /// parse — never called directly from `stage`.
    @discardableResult
    static func save(
        title: String,
        amount: Double,
        date: Date,
        category: TransactionCategory,
        rawKeyword: String?
    ) -> Transaction {
        let transaction = Transaction(
            title: title,
            amount: amount,
            date: date,
            category: category,
            source: .ocr,
            rawKeyword: rawKeyword
        )

        let context = ModelContext(SwiftDataService.makeContainer())
        context.insert(transaction)
        try? context.save()

        NotificationService.scheduleCaptureNotification(for: transaction)
        return transaction
    }
}
```

- [ ] **Step 2: Build to confirm this file compiles standalone (callers fixed in later tasks)**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: Errors only in `ScanReceiptTextIntent.swift` and `ShareViewController.swift` (both still call the now-deleted `ReceiptCaptureService.capture(rawText:)` and reference the now-deleted `CaptureOutcome.saved` case). No errors inside `ReceiptCaptureService.swift` itself.

---

### Task 2: Confirmation intents for the snippet's buttons

**Files:**
- Create: `Monee/AppTargets/ConfirmReceiptIntents.swift`

**Interfaces:**
- Consumes: `ReceiptCaptureService.save(title:amount:date:category:rawKeyword:) -> Transaction` (Task 1). `TransactionCategory` (existing enum, `Monee/Core/Database/Models/Transaction.swift` — has a `rawValue: String` since it's `String`-backed).
- Produces: `ConfirmReceiptAsIncomeIntent(amount:date:transactionTitle:rawKeyword:)` and `ConfirmReceiptAsExpenseIntent(amount:date:transactionTitle:categoryRawValue:rawKeyword:)` — Task 3's snippet view constructs these directly inside `Button(intent:)`, so the parameter names/order here are exactly what Task 3 must match.

- [ ] **Step 1: Write the file**

```swift
//
//  ConfirmReceiptIntents.swift
//  Monee
//
//  The two intents ReceiptConfirmationSnippetView's buttons trigger. Each one carries
//  the parsed fields as plain parameters (TextField isn't available inside a snippet, so
//  there's no live-editing here — just picking Income vs. Expense) and performs the
//  actual save, ending the interactive flow with a final dialog rather than another
//  snippet. TransactionCategory can't be an @Parameter type directly, so the expense
//  path carries it as its rawValue and reconstructs it in perform().
//

import AppIntents
import Foundation

struct ConfirmReceiptAsIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Receipt as Income"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Date")
    var date: Date

    @Parameter(title: "Title")
    var transactionTitle: String

    @Parameter(title: "Raw Keyword")
    var rawKeyword: String?

    init() {}

    init(amount: Double, date: Date, transactionTitle: String, rawKeyword: String?) {
        self.amount = amount
        self.date = date
        self.transactionTitle = transactionTitle
        self.rawKeyword = rawKeyword
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let transaction = ReceiptCaptureService.save(
            title: transactionTitle,
            amount: amount,
            date: date,
            category: .income,
            rawKeyword: rawKeyword
        )
        return .result(dialog: "Logged \(transaction.amount.idrFormatted) as income.")
    }
}

struct ConfirmReceiptAsExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Receipt as Expense"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Date")
    var date: Date

    @Parameter(title: "Title")
    var transactionTitle: String

    @Parameter(title: "Category")
    var categoryRawValue: String

    @Parameter(title: "Raw Keyword")
    var rawKeyword: String?

    init() {}

    init(amount: Double, date: Date, transactionTitle: String, categoryRawValue: String, rawKeyword: String?) {
        self.amount = amount
        self.date = date
        self.transactionTitle = transactionTitle
        self.categoryRawValue = categoryRawValue
        self.rawKeyword = rawKeyword
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let category = TransactionCategory(rawValue: categoryRawValue) ?? .unassigned
        let transaction = ReceiptCaptureService.save(
            title: transactionTitle,
            amount: amount,
            date: date,
            category: category,
            rawKeyword: rawKeyword
        )
        return .result(dialog: "Logged \(transaction.amount.idrFormatted) as an expense.")
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: This file compiles clean. Same pre-existing errors as Task 1 remain in `ScanReceiptTextIntent.swift` / `ShareViewController.swift`. If `@Parameter` requires an explicit `IntentParameterSummary` or a different init pattern on this SDK, the error will show here — adjust the property wrappers/inits to match the compiler's exact complaint before moving on; the shape above is the standard documented pattern but the wrapper's exact requirements are the one thing worth double-checking against the compiler.

---

### Task 3: The confirmation snippet view + wiring `ScanReceiptTextIntent`

**Files:**
- Create: `Monee/AppTargets/ReceiptConfirmationSnippetView.swift`
- Modify: `Monee/AppTargets/ScanReceiptTextIntent.swift`

**Interfaces:**
- Consumes: `ReceiptCaptureService.stage(rawText:) -> CaptureOutcome` (Task 1), `ConfirmReceiptAsIncomeIntent` / `ConfirmReceiptAsExpenseIntent` (Task 2).
- Produces: `struct ReceiptConfirmationSnippetView: View` with `init(state: ReceiptConfirmationSnippetView.State)`, `enum State { case error(String); case confirming(title: String, amount: Double, date: Date, category: TransactionCategory, rawKeyword: String?) }` — nothing later depends on this beyond Task 3 itself.

- [ ] **Step 1: Write the snippet view**

```swift
//
//  ReceiptConfirmationSnippetView.swift
//  Monee
//
//  The view ScanReceiptTextIntent.perform() returns via ShowsSnippetView. A single
//  concrete view type switching on an internal enum state — required because the
//  intent's `some IntentResult & ShowsSnippetView` return type needs one concrete type
//  across every branch (screenshot missing, no text found, no amount found, or the
//  happy-path confirmation), not a different View type per branch.
//
//  Buttons are intent-driven, not state-driven, per the snippet interactivity model:
//  TextField/local @State edits don't work inside a snippet, so there's no live editing
//  here — tapping Income or Expense immediately triggers the matching ConfirmReceipt...
//  Intent, which does the actual save and ends the flow.
//

import SwiftUI

struct ReceiptConfirmationSnippetView: View {
    enum State {
        case error(String)
        case confirming(title: String, amount: Double, date: Date, category: TransactionCategory, rawKeyword: String?)
    }

    let state: State

    var body: some View {
        switch state {
        case .error(let message):
            Text(message)
                .padding()

        case .confirming(let title, let amount, let date, let category, let rawKeyword):
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                Text(amount.idrFormatted)
                    .font(.title2.bold())
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button(intent: ConfirmReceiptAsExpenseIntent(
                        amount: amount,
                        date: date,
                        transactionTitle: title,
                        categoryRawValue: category.rawValue,
                        rawKeyword: rawKeyword
                    )) {
                        Text("Expense")
                    }

                    Button(intent: ConfirmReceiptAsIncomeIntent(
                        amount: amount,
                        date: date,
                        transactionTitle: title,
                        rawKeyword: rawKeyword
                    )) {
                        Text("Income")
                    }
                }
            }
            .padding()
        }
    }
}
```

- [ ] **Step 2: Rewrite `ScanReceiptTextIntent.perform()`**

Replace the `perform()` function in `ScanReceiptTextIntent.swift` (currently lines 41–63):

```swift
    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        // Defensive — a background-launched intent may skip the app's normal init path,
        // and categories must be registered before a notification using them can post.
        NotificationService.configure()

        guard let screenshot = await ScreenshotFetcher.fetchMostRecent() else {
            return .result(view: ReceiptConfirmationSnippetView(
                state: .error("Couldn't access your most recent screenshot — check Photo Library access in Settings.")
            ))
        }

        let rawText = (try? await VisionOCRService.recognizeText(from: screenshot)) ?? ""
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(view: ReceiptConfirmationSnippetView(
                state: .error("I couldn't read any text from that screenshot.")
            ))
        }

        switch ReceiptCaptureService.stage(rawText: trimmed) {
        case .needsConfirmation(let parsed):
            return .result(view: ReceiptConfirmationSnippetView(
                state: .confirming(
                    title: parsed.suggestedTitle,
                    amount: parsed.amount ?? 0,
                    date: parsed.date ?? Date(),
                    category: parsed.category,
                    rawKeyword: parsed.keyword
                )
            ))
        case .amountNotFound:
            return .result(view: ReceiptConfirmationSnippetView(
                state: .error("Read the screenshot, but couldn't find an amount — nothing was saved.")
            ))
        }
    }
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: `ScanReceiptTextIntent.swift` and `ReceiptConfirmationSnippetView.swift` compile clean. Only `ShareViewController.swift` still has errors (Task 5/6). If the compiler rejects `.result(view:)` or `ShowsSnippetView`'s exact conformance requirements, adjust to match the compiler's actual complaint — this is the bleeding-edge-API risk called out in Global Constraints.

---

### Task 4: Share Extension confirmation view

**Files:**
- Create: `Monee/AppTargets/ShareExtension/ShareConfirmationView.swift`

**Interfaces:**
- Consumes: `ParsedReceiptData` (existing, from `RegexParser.swift`).
- Produces: `struct ShareConfirmationView: View` with `init(parsed: ParsedReceiptData, onConfirm: @escaping (Bool) -> Void)` — `onConfirm` is called with `true` for Income, `false` for Expense. Task 5 constructs this exact type.

- [ ] **Step 1: Write the file**

```swift
//
//  ShareConfirmationView.swift
//  Monee
//
//  Plain SwiftUI confirmation shown inside the Share Extension before saving. Unlike
//  ReceiptConfirmationSnippetView (an App Intents snippet, where TextField/local @State
//  don't work), this runs as an ordinary hosted SwiftUI view inside the extension's own
//  process — no snippet restrictions apply here, so this is a closure-driven view like
//  any other SwiftUI screen.
//
//  ⚠️ UI PLACEHOLDER — plain layout, functional only.
//

import SwiftUI

struct ShareConfirmationView: View {
    let parsed: ParsedReceiptData
    let onConfirm: (Bool) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(parsed.suggestedTitle)
                .font(.headline)

            Text((parsed.amount ?? 0).idrFormatted)
                .font(.largeTitle.bold())

            if let date = parsed.date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Button {
                    onConfirm(false)
                } label: {
                    Text("Expense")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onConfirm(true)
                } label: {
                    Text("Income")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: This file compiles clean (verify it's added to the Share Extension target membership in Xcode's File Inspector — same requirement `ShareViewController.swift`'s header comment already documents for its other dependencies). `ShareViewController.swift` still has pre-existing errors, fixed in Task 5.

---

### Task 5: Wire the Share Extension to stage + confirm instead of capture-and-save

**Files:**
- Modify: `Monee/AppTargets/ShareExtension/ShareViewController.swift`

**Interfaces:**
- Consumes: `ReceiptCaptureService.stage(rawText:) -> CaptureOutcome`, `ReceiptCaptureService.save(title:amount:date:category:rawKeyword:)` (Task 1), `ShareConfirmationView(parsed:onConfirm:)` (Task 4).

- [x] **Step 1: Rewrite the file**

```swift
//
//  ShareViewController.swift
//  Monee
//
//  Handles shared plain text and shared images identically: extract text (directly for
//  text shares, via VisionOCRService for image shares), then stage it through
//  ReceiptCaptureService — the exact same parsing rule the Action Button flow uses.
//  Unlike the old version, nothing is saved until the user confirms Income/Expense on
//  ShareConfirmationView. A failed/empty OCR result on an image share behaves the same
//  as "no amount found": nothing is staged, and the photo itself is not retained
//  anywhere after this runs.
//
//  ⚠️ Requires this file's Info.plist NSExtensionActivationRule to accept BOTH
//  public.plain-text and public.image (see ShareExtension/Info.plist).
//
//  ⚠️ Target membership: this file needs RegexParser.swift, Transaction.swift,
//  AppGroup.swift, VisionOCRServiceError.swift, CurrencyFormat.swift,
//  NotificationService.swift, ReceiptCaptureService.swift, and
//  ShareConfirmationView.swift all added to the ShareExtension target in Xcode's File
//  Inspector.
//
//  ⚠️ UI PLACEHOLDER — bare loading/confirmation states, not a designed screen.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let loadingLabel: UILabel = {
        let label = UILabel()
        label.text = "Reading receipt…"
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(loadingLabel)
        NSLayoutConstraint.activate([
            loadingLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        Task { await handleSharedItem() }
    }

    private func handleSharedItem() async {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachment = item.attachments?.first else {
            finish()
            return
        }

        if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            await handleSharedText(attachment)
        } else if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            await handleSharedImage(attachment)
        } else {
            finish()
        }
    }

    private func handleSharedText(_ attachment: NSItemProvider) async {
        guard let data = try? await attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil),
              let text = data as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            finish()
            return
        }

        stageAndConfirm(rawText: text)
    }

    private func handleSharedImage(_ attachment: NSItemProvider) async {
        guard let data = try? await attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) else {
            finish()
            return
        }

        var image: UIImage?
        if let url = data as? URL, let imgData = try? Data(contentsOf: url) {
            image = UIImage(data: imgData)
        } else if let img = data as? UIImage {
            image = img
        } else if let imgData = data as? Data {
            image = UIImage(data: imgData)
        }

        guard let image else {
            finish()
            return
        }

        let text = (try? await VisionOCRService.recognizeText(from: image)) ?? ""
        stageAndConfirm(rawText: text)
    }

    private func stageAndConfirm(rawText: String) {
        NotificationService.configure() // defensive — extension launch may skip app init

        switch ReceiptCaptureService.stage(rawText: rawText) {
        case .amountNotFound:
            finish()
        case .needsConfirmation(let parsed):
            DispatchQueue.main.async { [weak self] in
                self?.presentConfirmation(for: parsed)
            }
        }
    }

    private func presentConfirmation(for parsed: ParsedReceiptData) {
        loadingLabel.removeFromSuperview()

        let confirmationView = ShareConfirmationView(parsed: parsed) { [weak self] isIncome in
            let category: TransactionCategory = isIncome ? .income : parsed.category
            ReceiptCaptureService.save(
                title: parsed.suggestedTitle,
                amount: parsed.amount ?? 0,
                date: parsed.date ?? Date(),
                category: category,
                rawKeyword: parsed.keyword
            )
            self?.finish()
        }

        let hosting = UIHostingController(rootView: confirmationView)
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
    }

    private func finish() {
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: BUILD SUCCEEDED — this was the last file with outstanding errors from Task 1's split.

---

### Task 6: End-to-end manual verification

**Files:** none (verification only)

- [ ] **Step 1: Verify the Action Button / Shortcut snippet**

Build and run on a physical device or Simulator with the "Scan Receipt Text" Shortcut wired to the Action Button (per `ScanReceiptTextIntent.swift`'s header comment). Take a screenshot of a sample receipt/transfer confirmation, trigger the Action Button.
Expected: A snippet appears (in the Shortcuts/system surface, not the app) showing the parsed title, amount, and date, with "Expense" and "Income" buttons — no dialog-only response like before, and the app itself does not open.

- [ ] **Step 2: Verify tapping a category button saves correctly**

Tap "Expense" on the snippet from Step 1.
Expected: A brief dialog confirms "Logged ... as an expense." Open the Tracker tab in the app — a new transaction appears with the parsed title/amount/date and RegexParser's originally-guessed category (not forced to `.unassigned` or `.income`).

- [ ] **Step 3: Verify the Income override**

Repeat with a different screenshot, tap "Income" this time.
Expected: The saved transaction's category is `.income` regardless of what `RegexParser.parseKeyword` guessed.

- [ ] **Step 4: Verify the error states still short-circuit correctly**

Trigger the Action Button with Photo Library access revoked (Settings), then re-grant and trigger with a screenshot that has no legible text (e.g. a blank image).
Expected: Each case shows the matching error text in the snippet ("check Photo Library access…" / "couldn't read any text…") — no transaction is created, and no Expense/Income buttons are shown for these states.

- [ ] **Step 5: Verify the Share Extension confirmation**

From Photos or Safari, share a receipt screenshot/text to Monee via the share sheet.
Expected: Instead of the old instant "Saving to Monee…" flash, `ShareConfirmationView` appears showing the parsed title/amount/date with Expense/Income buttons. Tapping either saves the transaction (verify in Tracker) and dismisses the share sheet.

---

## Self-Review

**Spec coverage:**
- Interactive snippet for Action Button OCR confirmation → Task 3. ✅
- Income/Expense labeling buttons on the snippet → Task 2 (intents), Task 3 (view wiring). ✅
- Share Extension gets an equivalent confirmation (per user's original "OCR scan or share extension" framing) → Task 4, 5. ✅
- Amount/date correction explicitly excluded → stated in Global Constraints, no task builds it. ✅
- No `git commit` steps included; committing deferred to user confirmation → confirmed, no task above includes one.

**Placeholder scan:** No "TBD"/"handle appropriately" language in any step; every code block is complete and directly usable.

**Type consistency:** `ReceiptCaptureService.save(title:amount:date:category:rawKeyword:)` signature identical across Task 1 (produced), Task 2, and Task 5 (consumed). `ConfirmReceiptAsIncomeIntent`/`ConfirmReceiptAsExpenseIntent` parameter names/order identical between Task 2 (produced) and Task 3 (consumed). `ShareConfirmationView(parsed:onConfirm:)` identical between Task 4 (produced) and Task 5 (consumed). `CaptureOutcome` cases (`.needsConfirmation`, `.amountNotFound`) used consistently in Tasks 3 and 5.
