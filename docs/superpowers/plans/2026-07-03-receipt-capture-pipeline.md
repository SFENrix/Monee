# Receipt Capture Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unblock the currently-broken Action Button and Share Extension receipt-capture
flows so both save a real `Transaction` directly (no staging layer), notify the user with a
simple tap-to-edit notification, and support editing that transaction — then tune
`RegexParser` against real sample data.

**Architecture:** A single shared `ReceiptCaptureService` (rawText in → `Transaction` saved-or-not)
is called by both `ScanReceiptTextIntent` (Action Button, main app target) and
`ShareViewController` (Share Extension target). A new `NotificationService` fires one
tap-to-edit local notification per successful capture. `NotificationDelegate` routes the tap
through `DeepLink.editTransaction(id:)` to a new edit mode on the existing manual-entry form.

**Tech Stack:** Swift, SwiftUI, SwiftData, AppIntents, UserNotifications, Vision framework
(via existing `VisionOCRService`, unchanged).

**Reference spec:** `docs/superpowers/specs/2026-07-03-receipt-capture-pipeline-design.md`

## Global Constraints

- IDR-only currency handling — do not add USD/decimal-cents parsing (per `RegexParser`'s
  existing scope decision, unchanged by this plan).
- No new UI styling — all touched views remain functional-placeholder, matching existing
  `⚠️ UI PLACEHOLDER` convention in the codebase.
- No test target exists in this Xcode project (POC, 2-day sprint) — verification is manual
  build/run for anything touching SwiftUI/SwiftData/UIKit/UserNotifications/AppIntents. Pure
  `Foundation`-only logic (`RegexParser`) gets an automated check via a standalone `swift`
  script instead (Task 7), not XCTest.
- Do not touch AI Buddy / `PromptBuilder` / Threshold Savings — explicitly out of scope.
- Commit after every task using the repo's existing commit style (no `Co-Authored-By` trailer
  requirement was observed in prior commits on this branch — match whatever the executing
  skill's standard commit process produces).

---

### Task 1: Cleanup — dead code, App Group ID, Info.plist

**Files:**
- Delete: `Monee/App/ContainerExtension.swift`
- Modify: `Monee/Core/Sharing/AppGroup.swift`
- Modify: `ShareExtension/Info.plist`
- Git housekeeping: unstage the bogus `Monee/App/\` index entry

**Interfaces:**
- Produces: `AppGroup.identifier == "group.com.rioferdinand.monee"` (matches all three
  `.entitlements` files already in the repo).

- [ ] **Step 1: Delete the dead notification-delegate duplicate**

```bash
git rm Monee/App/ContainerExtension.swift
```

This file is an extension on `AppContainer` that references a `modelContainer` property
`AppContainer` does not have — it cannot compile. `NotificationDelegate.swift` (Task 3) is
the sole notification-delegate implementation going forward.

- [ ] **Step 2: Fix the App Group identifier mismatch**

In `Monee/Core/Sharing/AppGroup.swift`, change:

```swift
static let identifier = "group.com.rioferdinand.freelancefinance"
```

to:

```swift
static let identifier = "group.com.rioferdinand.monee"
```

This must match the `com.apple.security.application-groups` entry already present in
`Monee/Monee.entitlements`, `ShareExtension/ShareExtension.entitlements`, and
`WidgetExtension/WidgetExtension.entitlements`.

- [ ] **Step 3: Fix the Share Extension's text-activation rule**

In `ShareExtension/Info.plist`, find:

```xml
<key>NSExtensionActivationSupportsText</key>
<string></string>
```

Change to:

```xml
<key>NSExtensionActivationSupportsText</key>
<true/>
```

An empty string is not a valid boolean value for this key — the extension will not reliably
activate on shared plain text without this fix.

- [ ] **Step 4: Remove the stray git index entry**

```bash
git status --porcelain | grep '\\\\'
```

Expected output: a line like `AD "Monee/App/\\"` (a bogus staged file with no content on
disk, left over from earlier work). Remove it from the index:

```bash
git rm --cached "Monee/App/\\"
```

- [ ] **Step 5: Verify the project still opens/builds in Xcode**

Open `Monee.xcodeproj` in Xcode, select the `Monee` scheme, and build
(<kbd>Cmd+B</kbd>). Expect it to still fail to build at this point (later tasks fix the
remaining missing types) — the goal of this step is only to confirm Xcode still opens the
project cleanly and doesn't choke on the deleted/renamed files.

- [ ] **Step 6: Commit**

```bash
git add Monee/Core/Sharing/AppGroup.swift ShareExtension/Info.plist
git commit -m "fix: correct App Group identifier mismatch, Share Extension text rule, remove dead ContainerExtension.swift"
```

---

### Task 2: `NotificationService` + `ReceiptCaptureService`

**Files:**
- Create: `Monee/Core/Notifications/NotificationService.swift`
- Create: `Monee/Core/Capture/ReceiptCaptureService.swift`
- Modify: `Monee/Core/Utilities/RegexParser.swift` (add stub fields, Step 2b)

**Interfaces:**
- Consumes: `RegexParser.parse(_:) -> ParsedReceiptData` (existing).
- Produces (via Step 2b): `ParsedReceiptData.suggestedTitle: String` and
  `ParsedReceiptData.isIncome: Bool`, both stub-valued until Task 7 replaces them with real
  logic.
- Consumes: `SwiftDataService.makeContainer() -> ModelContainer` (existing).
- Consumes: `Transaction.init(title:amount:date:category:source:rawKeyword:)` (existing).
- Consumes: `Double.idrFormatted` (existing, `Monee/Core/Utilities/CurrencyFormat.swift`).
- Produces: `NotificationUserInfoKey.transactionID: String` (dictionary key constant).
- Produces: `NotificationService.configure()`, `NotificationService.scheduleCaptureNotification(for: Transaction)`.
- Produces: `enum CaptureOutcome { case saved(Transaction), case amountNotFound }`,
  `ReceiptCaptureService.capture(rawText: String) -> CaptureOutcome`.

- [ ] **Step 1: Create `NotificationService.swift`**

```swift
//
//  NotificationService.swift
//  Monee
//
//  Fires the "already saved — tap to fix" confirmation notification. No notification
//  actions: a single tap is the only interaction. ReceiptCaptureService has already saved
//  the Transaction by the time this fires, so there's no "Save" action to offer.
//

import Foundation
import UserNotifications

enum NotificationUserInfoKey {
    static let transactionID = "transactionID"
}

enum NotificationCategory {
    static let transactionLogged = "TRANSACTION_LOGGED"
}

enum NotificationService {
    /// Registers the notification category. Call defensively at the start of every entry
    /// point (Action Button intent, Share Extension) — a background-launched process may
    /// skip the main app's normal init path, and categories must be registered before a
    /// notification using them can post.
    static func configure() {
        let category = UNNotificationCategory(
            identifier: NotificationCategory.transactionLogged,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func scheduleCaptureNotification(for transaction: Transaction) {
        let content = UNMutableNotificationContent()
        content.title = "Logged"
        content.body = "\(transaction.title) — \(transaction.amount.idrFormatted)"
        content.categoryIdentifier = NotificationCategory.transactionLogged
        content.userInfo = [NotificationUserInfoKey.transactionID: transaction.id.uuidString]

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 2: Create `ReceiptCaptureService.swift`**

```swift
//
//  ReceiptCaptureService.swift
//  Monee
//
//  Shared by the Action Button intent (main app target) and the Share Extension target.
//  Owns the single "raw text in -> Transaction saved or not" decision so both entry points
//  can't drift out of sync on what counts as a usable capture.
//
//  Rule: if RegexParser finds an amount, save immediately as a real Transaction. If it
//  doesn't, save nothing — no staged/partial record. This replaces the old "stage first,
//  confirm via an actionable notification, then save" design.
//

import Foundation
import SwiftData

enum CaptureOutcome {
    case saved(Transaction)
    case amountNotFound
}

enum ReceiptCaptureService {
    static func capture(rawText: String) -> CaptureOutcome {
        let parsed = RegexParser.parse(rawText)

        guard let amount = parsed.amount else {
            return .amountNotFound
        }

        let category: TransactionCategory = parsed.isIncome ? .income : parsed.category
        let transaction = Transaction(
            title: parsed.suggestedTitle,
            amount: amount,
            date: parsed.date ?? Date(),
            category: category,
            source: .ocr,
            rawKeyword: parsed.keyword
        )

        let context = ModelContext(SwiftDataService.makeContainer())
        context.insert(transaction)
        try? context.save()

        NotificationService.scheduleCaptureNotification(for: transaction)
        return .saved(transaction)
    }
}
```

Note: this references `parsed.suggestedTitle` and `parsed.isIncome`, which do not exist on
`ParsedReceiptData` yet. Step 2b below adds temporary stub values for both so the project
can keep compiling task-by-task; Task 7 replaces the stubs with the real tuned logic.

- [ ] **Step 2b: Add temporary stub fields to `ParsedReceiptData`**

In `Monee/Core/Utilities/RegexParser.swift`, add two fields to `ParsedReceiptData` with
placeholder values — real logic for both lands in Task 7 (lowest priority, last, per the
spec's explicit crucial-fixes-first ordering). This keeps the project buildable at every
checkpoint from here on instead of only at the very end.

Change:

```swift
struct ParsedReceiptData {
    var amount: Double?
    var date: Date?
    var keyword: String?
    var category: TransactionCategory
    var rawText: String

    var isComplete: Bool {
        amount != nil && date != nil
    }
}
```

to:

```swift
struct ParsedReceiptData {
    var amount: Double?
    var date: Date?
    var keyword: String?
    var category: TransactionCategory
    /// Stub for now — Task 7 replaces this with a real "ke <Name>" extraction pattern.
    var suggestedTitle: String = "Receipt"
    /// Stub for now — Task 7 replaces this with real income/expense direction detection.
    var isIncome: Bool = false
    var rawText: String

    var isComplete: Bool {
        amount != nil && date != nil
    }
}
```

- [ ] **Step 3: Set target membership**

In Xcode, select both new files in the Project Navigator, open the File Inspector (right
panel), and under "Target Membership" check both **Monee** and **ShareExtension** (leave
**WidgetExtension** unchecked — it never calls either type).

- [ ] **Step 4: Commit**

```bash
git add Monee/Core/Notifications/NotificationService.swift Monee/Core/Capture/ReceiptCaptureService.swift
git commit -m "feat: add NotificationService and ReceiptCaptureService"
```

---

### Task 3: Notification → edit routing

**Files:**
- Modify: `Monee/Core/Sharing/DeepLink.swift`
- Modify: `Monee/Core/Notifications/NotificationDelegate.swift`
- Modify: `Monee/App/FreelanceFinanceApp.swift`
- Modify: `Monee/App/ContentView.swift`

**Interfaces:**
- Consumes: `NotificationUserInfoKey.transactionID` (from Task 2).
- Consumes: `AppContainer.shared.pendingRoute: DeepLink?` (existing).
- Produces: `DeepLink.editTransaction(id: UUID)` case.
- Produces: `NotificationDelegate.shared: NotificationDelegate` singleton.

- [ ] **Step 1: Add the edit-transaction case to `DeepLink`**

Replace the full contents of `Monee/Core/Sharing/DeepLink.swift`:

```swift
//
//  DeepLink.swift
//  Monee
//
//  Core/Sharing/DeepLink.swift
//
//  .quickEntry: Widget's Quick Entry tap. .editTransaction: tapping the "Logged" notification
//  after an Action Button / Share Extension capture — routes to editing that already-saved
//  Transaction (see NotificationDelegate + ReceiptCaptureService).
//

import Foundation

enum DeepLink: Equatable {
    case quickEntry
    case editTransaction(id: UUID)

    var url: URL {
        switch self {
        case .quickEntry:
            return URL(string: "moneeapp://quickEntry")!
        case .editTransaction(let id):
            return URL(string: "moneeapp://editTransaction?id=\(id.uuidString)")!
        }
    }

    init?(url: URL) {
        switch url.host {
        case "quickEntry":
            self = .quickEntry
        case "editTransaction":
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let idString = components.queryItems?.first(where: { $0.name == "id" })?.value,
                  let id = UUID(uuidString: idString) else {
                return nil
            }
            self = .editTransaction(id: id)
        default:
            return nil
        }
    }
}
```

- [ ] **Step 2: Rewrite `NotificationDelegate` as a singleton with one job**

Replace the full contents of `Monee/Core/Notifications/NotificationDelegate.swift`:

```swift
//
//  NotificationDelegate.swift
//  Monee
//
//  Handles taps on the "Logged" notification ReceiptCaptureService fires after an Action
//  Button / Share Extension capture. There's only one interaction: tap to edit — no Save
//  action (already saved) and no Dismiss action (swipe-to-delete in the Tracker list covers
//  discarding a bad capture).
//
//  `shared` exists because UNUserNotificationCenter.delegate is a WEAK reference — an
//  unretained instance would be deallocated immediately and silently stop receiving
//  callbacks. FreelanceFinanceApp.init() assigns `NotificationDelegate.shared` as the
//  delegate, which keeps it alive for the app's lifetime.
//

import Foundation
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    private override init() {}

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard let idString = response.notification.request.content.userInfo[NotificationUserInfoKey.transactionID] as? String,
              let id = UUID(uuidString: idString) else {
            return
        }

        Task { @MainActor in
            AppContainer.shared.pendingRoute = .editTransaction(id: id)
        }
    }

    /// Also show the banner if a capture happens to complete while the app is already in
    /// the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
```

- [ ] **Step 3: Register the delegate on app launch**

In `Monee/App/FreelanceFinanceApp.swift`, add the `UserNotifications` import and an `init()`:

```swift
import SwiftUI
import SwiftData
import UserNotifications

@main struct FreelanceFinanceApp: App {
    let container = SwiftDataService.makeContainer()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(AppContainer.shared)
                .onOpenURL { url in
                    AppContainer.shared.handle(url: url)
                }
        }
        .modelContainer(container)
    }
}
```

- [ ] **Step 4: Route `.editTransaction` in `ContentView`**

Replace the full contents of `Monee/App/ContentView.swift`:

```swift
//
//  ContentView.swift
//  FreelanceFinance
//
//  ⚠️ UI PLACEHOLDER: Dashboard layout, "+" menu — functional-only. UI team, restyle freely.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }

            AIChatView()
                .tabItem { Label("AI Buddy", systemImage: "bubble.left.and.bubble.right.fill") }
        }
    }
}

// MARK: - Dashboard

private struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var showingQuickAdd = false
    @State private var showingScanReceipt = false
    @State private var editingTransaction: Transaction?

    private var totalSpent: Double {
        transactions.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }
    }

    private var totalIncome: Double {
        transactions.filter { $0.isIncome }.reduce(0) { $0 + $1.amount }
    }

    private var reserveSummary: CashReserveSummary {
        CashReserveCalculator.summarize(
            transactions: transactions,
            fallbackMonthlyIncome: UserFinancialProfile.estimatedMonthlyIncome
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SummaryCard(totalSpent: totalSpent, totalIncome: totalIncome, count: transactions.count)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    ReserveCard(summary: reserveSummary)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if transactions.isEmpty {
                    ContentUnavailableView(
                        "No Transactions Yet",
                        systemImage: "tray",
                        description: Text("Tap + to log your first expense.")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    Section("Recent") {
                        ForEach(transactions) { transaction in
                            TransactionRow(transaction: transaction)
                        }
                        .onDelete(perform: deleteTransactions)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Monee")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // ⚠️ UI PLACEHOLDER — a Menu is the quickest way to expose two entry
                    // points without crowding the toolbar. Restyle freely.
                    Menu {
                        Button {
                            showingQuickAdd = true
                        } label: {
                            Label("Manual Entry", systemImage: "square.and.pencil")
                        }
                        Button {
                            showingScanReceipt = true
                        } label: {
                            Label("Scan Receipt", systemImage: "doc.text.viewfinder")
                        }
                    } label: {
                        Label("Add Transaction", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingQuickAdd) {
                QuickEntryFormView()
            }
            .sheet(isPresented: $showingScanReceipt) {
                ReceiptConfirmationView()
            }
            .sheet(item: $editingTransaction) { transaction in
                QuickEntryFormView(editing: transaction)
            }
        }
        .onChange(of: appContainer.pendingRoute) { _, newRoute in
            handleRoute(newRoute)
        }
        .onAppear {
            handleRoute(appContainer.pendingRoute)
        }
    }

    private func deleteTransactions(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(transactions[index])
        }
    }

    private func handleRoute(_ route: DeepLink?) {
        guard let route else { return }
        switch route {
        case .quickEntry:
            showingQuickAdd = true
        case .editTransaction(let id):
            editingTransaction = transactions.first(where: { $0.id == id })
        }
        appContainer.pendingRoute = nil
    }
}

// MARK: - Summary Card

private struct SummaryCard: View {
    let totalSpent: Double
    let totalIncome: Double
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Total Spent")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(totalSpent, format: .idr)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.green)
                Text("Income logged: \(totalIncome, format: .idr)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(count) transaction\(count == 1 ? "" : "s") logged")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Reserve Card

private struct ReserveCard: View {
    let summary: CashReserveSummary

    private var runwayText: String {
        guard let runway = summary.runwayDays else { return "Not enough data to estimate runway yet" }
        let days = Int(runway.rounded())
        if days < 0 { return "Reserve is already negative" }
        return "\(days) day\(days == 1 ? "" : "s") of runway at current pace"
    }

    private var tint: Color {
        guard let runway = summary.runwayDays else { return .secondary }
        if runway < 0 { return .red }
        if runway < 14 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "gauge.with.needle.fill")
                    .foregroundStyle(tint)
                Text("Cash Reserve")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if !summary.isDataSufficient {
                    Text("LOW CONFIDENCE")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
            }
            Text(summary.currentReserve, format: .idr)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(summary.currentReserve < 0 ? .red : .primary)
            Text(runwayText)
                .font(.caption)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Transaction Row

private struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.category.iconName)
                .font(.title3)
                .foregroundStyle(transaction.category.tint)
                .frame(width: 32, height: 32)
                .background(transaction.category.tint.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.title)
                    .font(.body)
                Text(transaction.date, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text((transaction.isIncome ? "+" : "-") + transaction.amount.formatted(.idr))
                .font(.body.monospacedDigit())
                .foregroundStyle(transaction.isIncome ? .green : .primary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .modelContainer(SwiftDataService.makePreviewContainer(seeded: true))
        .environment(AppContainer.shared)
}
```

`QuickEntryFormView(editing:)` doesn't exist yet — that's Task 4. This task will not compile
in isolation; that's expected given the plan's ordering.

- [ ] **Step 5: Commit**

```bash
git add Monee/Core/Sharing/DeepLink.swift Monee/Core/Notifications/NotificationDelegate.swift Monee/App/FreelanceFinanceApp.swift Monee/App/ContentView.swift
git commit -m "feat: route notification taps to an edit-transaction deep link"
```

---

### Task 4: Edit mode for `QuickEntryViewModel` / `QuickEntryFormView`

**Files:**
- Modify: `Monee/Features/Tracker/ViewModels/QuickEntryViewModel.swift`
- Modify: `Monee/Features/Tracker/UI/QuickEntryFormView.swift`

**Interfaces:**
- Consumes: `Transaction` (existing model, `Monee/Core/Database/Models/Transaction.swift`).
- Produces: `QuickEntryViewModel.load(from: Transaction)`.
- Produces: `QuickEntryFormView.init(onSaved: (() -> Void)?, editing: Transaction?)`.

- [ ] **Step 1: Add edit mode to `QuickEntryViewModel`**

Replace the full contents of `Monee/Features/Tracker/ViewModels/QuickEntryViewModel.swift`:

```swift
//
//  QuickEntryViewModel.swift
//  Monee
//
//  Owns form state + validation + persistence for manual transaction entry, AND for editing
//  an already-existing Transaction (used by the notification tap-to-edit route in
//  NotificationDelegate -> ContentView). Deliberately has no knowledge of how it's presented
//  (sheet, deep link) — the view handles presentation, this just handles data.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class QuickEntryViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var amount: Double?
    @Published var category: TransactionCategory = .unassigned
    @Published var date: Date = .now
    @Published var validationError: String?

    /// Drives the Income/Expense segmented control. Setting this reassigns `category`
    /// so the two can never disagree — no separate "type" field needed.
    @Published var isIncome: Bool = false {
        didSet { category = isIncome ? .income : .unassigned }
    }

    /// Defaults to manual entry; ReceiptConfirmationView sets this to `.ocr` after prefilling.
    @Published var source: TransactionSource = .manual
    @Published var rawKeyword: String?

    /// Non-nil while editing an existing Transaction — `save()` updates it in place instead
    /// of inserting a new one.
    private var editingTransaction: Transaction?

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (amount ?? 0) > 0
    }

    /// Loads an existing Transaction's fields for editing.
    ///
    /// `isIncome` MUST be set before `category` — `isIncome`'s didSet resets `category` to
    /// `.unassigned`/`.income` as a side effect, so `category` has to be the last write to
    /// actually stick (same gotcha already documented in ReceiptConfirmationView).
    func load(from transaction: Transaction) {
        editingTransaction = transaction
        title = transaction.title
        amount = transaction.amount
        date = transaction.date
        source = transaction.source
        rawKeyword = transaction.rawKeyword
        isIncome = transaction.isIncome
        category = transaction.category
    }

    @discardableResult
    func save(using modelContext: ModelContext) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            validationError = "Give this transaction a short description."
            return false
        }
        guard let amount, amount > 0 else {
            validationError = "Enter an amount greater than zero."
            return false
        }

        if let editingTransaction {
            editingTransaction.title = trimmedTitle
            editingTransaction.amount = amount
            editingTransaction.date = date
            editingTransaction.category = category
            editingTransaction.source = source
            editingTransaction.rawKeyword = rawKeyword
        } else {
            let transaction = Transaction(
                title: trimmedTitle,
                amount: amount,
                date: date,
                category: category,
                source: source,
                rawKeyword: rawKeyword
            )
            modelContext.insert(transaction)
        }

        do {
            try modelContext.save()
            reset()
            return true
        } catch {
            validationError = "Couldn't save: \(error.localizedDescription)"
            return false
        }
    }

    func reset() {
        title = ""
        amount = nil
        category = .unassigned
        date = .now
        validationError = nil
        source = .manual
        rawKeyword = nil
        isIncome = false
        editingTransaction = nil
    }
}
```

- [ ] **Step 2: Add an edit-mode entry point to `QuickEntryFormView`**

Replace the full contents of `Monee/Features/Tracker/UI/QuickEntryFormView.swift`:

```swift
//
//  QuickEntryFormView.swift
//  Monee
//
//  Focused input form for manual transaction entry — and, via `editing`, for fixing up an
//  already-saved OCR capture (reached from the notification tap-to-edit route).
//
//  ⚠️ UI PLACEHOLDER: plain Form/Picker styling, functional only. UI team — swap freely,
//  nothing downstream depends on how this looks, only on QuickEntryViewModel's public API.
//

import SwiftUI
import SwiftData

struct QuickEntryFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = QuickEntryViewModel()

    var onSaved: (() -> Void)?

    /// Non-nil when opened to fix up an already-saved Transaction (notification tap-to-edit).
    var editing: Transaction?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $viewModel.isIncome) {
                        Text("Expense").tag(false)
                        Text("Income").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Details") {
                    TextField("What was it for?", text: $viewModel.title)
                    TextField("Amount", value: $viewModel.amount, format: .idr)
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
                }

                if !viewModel.isIncome {
                    Section("Category") {
                        Picker("Category", selection: $viewModel.category) {
                            ForEach(TransactionCategory.allCases.filter { $0 != .income }, id: \.self) { cat in
                                Label(cat.rawValue, systemImage: cat.iconName).tag(cat)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                if let error = viewModel.validationError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle(editing != nil ? "Edit Transaction" : (viewModel.isIncome ? "Add Income" : "Add Transaction"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if viewModel.save(using: modelContext) {
                            onSaved?()
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
            .task {
                if let editing {
                    viewModel.load(from: editing)
                }
            }
        }
    }
}

#Preview {
    QuickEntryFormView()
        .modelContainer(SwiftDataService.makePreviewContainer())
}
```

- [ ] **Step 3: Verify by inspection (full build isn't possible yet)**

`Monee/AppTargets/ScanReceiptTextIntent.swift` and
`Monee/AppTargets/ShareExtension/ShareViewController.swift` still reference the old
`PendingReceiptStore`/`NotificationService` API until Task 6 rewrites them, so the Monee
scheme cannot build end-to-end yet — that's expected at this point in the plan. Instead,
re-read the diff for this task and confirm by inspection: (1) `QuickEntryViewModel.save()`
mutates `editingTransaction` in place when it's non-nil, and only inserts a new `Transaction`
when it's nil; (2) `load(from:)` sets `isIncome` before `category`, matching the ordering
comment; (3) `QuickEntryFormView`'s `.task` only calls `viewModel.load(from:)` when `editing`
is non-nil, so the plain "Add Transaction" path (`editing == nil`) is untouched. The actual
build-and-run regression check for the manual-entry path happens as part of Task 6 Step 4,
once the whole project compiles again.

- [ ] **Step 4: Commit**

```bash
git add Monee/Features/Tracker/ViewModels/QuickEntryViewModel.swift Monee/Features/Tracker/UI/QuickEntryFormView.swift
git commit -m "feat: add edit mode to QuickEntryViewModel/QuickEntryFormView"
```

---

### Task 5: Simplify `ReceiptConfirmationView` to manual-capture-only

**Files:**
- Modify: `Monee/Features/ReceiptScanner/UI/ReceiptConfirmationView.swift`

**Interfaces:**
- Consumes: `ScannerViewModel` (existing, unchanged), `QuickEntryViewModel` (Task 4).
- Consumes: `ParsedReceiptData.suggestedTitle: String`, `ParsedReceiptData.isIncome: Bool`
  (stub-valued since Task 2's Step 2b, real values from Task 7 — either way this file
  compiles once this task's changes are applied).

- [ ] **Step 1: Remove the staged-entry (`pendingEntryID`) path entirely**

Replace the full contents of `Monee/Features/ReceiptScanner/UI/ReceiptConfirmationView.swift`:

```swift
//
//  ReceiptConfirmationView.swift
//  Monee
//
//  Manual in-app capture only: PhotosPicker -> live Vision OCR right here. The old staged-
//  entry review path (Action Button / Share Extension low-confidence captures reviewed via
//  a PendingReceiptStore-backed pendingEntryID) is retired — those flows now save directly
//  via ReceiptCaptureService and, if the user needs to fix something, route to
//  QuickEntryFormView's edit mode instead (see NotificationDelegate + Task 4).
//
//  ⚠️ UI PLACEHOLDER: everything here is functional-only styling. UI team — restyle freely;
//  ScannerViewModel and QuickEntryViewModel are the only real contracts this depends on.
//

import SwiftUI
import SwiftData
import PhotosUI

struct ReceiptConfirmationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var scannerViewModel = ScannerViewModel()
    @StateObject private var entryViewModel = QuickEntryViewModel()

    @State private var selectedPhoto: PhotosPickerItem?

    /// Manual in-app capture only — PhotosPicker -> live OCR right here.
    var pendingImage: UIImage? = nil

    private var scanFailedBinding: Binding<Bool> {
        Binding(
            get: { scannerViewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented { scannerViewModel.errorMessage = nil }
            }
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if scannerViewModel.isProcessing {
                    ProcessingView()
                } else if scannerViewModel.parsedData != nil {
                    ConfirmationForm(
                        image: scannerViewModel.capturedImage,
                        isComplete: scannerViewModel.parsedData?.isComplete ?? true,
                        viewModel: entryViewModel
                    )
                } else if pendingImage == nil {
                    CaptureChooserView(selectedPhoto: $selectedPhoto)
                } else {
                    // pendingImage is set but processing hasn't started yet — .task below
                    // kicks it off; this is a brief transitional frame.
                    ProcessingView()
                }
            }
            .navigationTitle("Confirm Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if scannerViewModel.parsedData != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Retake") {
                            scannerViewModel.reset()
                            entryViewModel.reset()
                            selectedPhoto = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(!entryViewModel.canSave)
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                Task { await loadAndProcess(newItem) }
            }
            .task {
                if let pendingImage, scannerViewModel.parsedData == nil, !scannerViewModel.isProcessing {
                    await scannerViewModel.processImage(pendingImage)
                    applyParsedDataIfAvailable()
                }
            }
            .alert("Scan Failed", isPresented: scanFailedBinding) {
                Button("OK") { scannerViewModel.reset() }
            } message: {
                Text(scannerViewModel.errorMessage ?? "")
            }
        }
    }

    private func loadAndProcess(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }

        await scannerViewModel.processImage(image)
        applyParsedDataIfAvailable()
    }

    private func applyParsedDataIfAvailable() {
        guard let parsed = scannerViewModel.parsedData else { return }
        entryViewModel.title = parsed.suggestedTitle
        entryViewModel.amount = parsed.amount
        entryViewModel.date = parsed.date ?? .now
        // isIncome must be set BEFORE category — QuickEntryViewModel resets category to
        // .unassigned as a side effect of isIncome's didSet, so category has to be the
        // last write to actually stick.
        entryViewModel.isIncome = parsed.isIncome
        entryViewModel.category = parsed.isIncome ? .income : parsed.category
        entryViewModel.source = .ocr
        entryViewModel.rawKeyword = parsed.keyword
    }

    private func save() {
        if entryViewModel.save(using: modelContext) {
            dismiss()
        }
    }
}

// MARK: - Capture

private struct CaptureChooserView: View {
    @Binding var selectedPhoto: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Scan a Receipt")
                .font(.title3.weight(.semibold))
            Text("Pick a photo of a receipt and we'll pull out the amount, date, and category.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Processing

private struct ProcessingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Reading receipt…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Confirmation

private struct ConfirmationForm: View {
    let image: UIImage?
    let isComplete: Bool
    @ObservedObject var viewModel: QuickEntryViewModel

    var body: some View {
        Form {
            if let image {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if !isComplete {
                Section {
                    Label(
                        "We couldn't confidently read every field — double-check the amount and date below.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }

            Section {
                Picker("Type", selection: $viewModel.isIncome) {
                    Text("Expense").tag(false)
                    Text("Income").tag(true)
                }
                .pickerStyle(.segmented)
            }

            Section("Details") {
                TextField("What was it for?", text: $viewModel.title)
                TextField("Amount", value: $viewModel.amount, format: .idr)
                    .keyboardType(.decimalPad)
                DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
            }

            if !viewModel.isIncome {
                Section("Category") {
                    Picker("Category", selection: $viewModel.category) {
                        ForEach(TransactionCategory.allCases.filter { $0 != .income }, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.iconName).tag(cat)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }

            if let error = viewModel.validationError {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

#Preview {
    ReceiptConfirmationView()
        .modelContainer(SwiftDataService.makePreviewContainer())
}
```

- [ ] **Step 2: Commit**

```bash
git add Monee/Features/ReceiptScanner/UI/ReceiptConfirmationView.swift
git commit -m "refactor: drop retired staged-entry path from ReceiptConfirmationView"
```

---

### Task 6: Wire `ScanReceiptTextIntent` and `ShareViewController` to `ReceiptCaptureService`

**Files:**
- Modify: `Monee/AppTargets/ScanReceiptTextIntent.swift`
- Modify: `Monee/AppTargets/ShareExtension/ShareViewController.swift`

**Interfaces:**
- Consumes: `NotificationService.configure()`, `ReceiptCaptureService.capture(rawText:) -> CaptureOutcome` (Task 2).
- Consumes: `VisionOCRService.recognizeText(from:) async throws -> String` (existing, unchanged).

- [ ] **Step 1: Rewrite `ScanReceiptTextIntent.perform()`**

Replace the full contents of `Monee/AppTargets/ScanReceiptTextIntent.swift`:

```swift
//
//  ScanReceiptTextIntent.swift
//  Monee
//
//  Entry point for the Action Button flow. Lives in the MAIN APP target, not
//  WidgetExtension — unlike QuickEntryIntent (which the widget UI calls directly), nothing
//  inside the app calls this one; it's invoked externally by a user-built Shortcut.
//
//  Intended Shortcut (built once, by hand, in the Shortcuts app):
//    1. Take Screenshot
//    2. Extract Text from Image  (Shortcuts' built-in Live Text OCR action)
//    3. Run App Intent → Monee → "Scan Receipt Text", with Captured Text ← step 2's output
//  Then: Settings → Action Button → Shortcut → pick the above.
//
//  `openAppWhenRun = false` is the whole point — capturing a transaction should never
//  interrupt whatever the user was looking at when they pressed the button. This intent's
//  only job is to hand captured text to ReceiptCaptureService; everything else (saving,
//  notifying, editing) happens there and in the app proper.
//

import AppIntents
import Foundation

struct ScanReceiptTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Receipt Text"
    static var description = IntentDescription(
        "Parses on-screen receipt or payment text (captured via Shortcuts) and logs it as a transaction."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Captured Text")
    var rawText: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Defensive — a background-launched intent may skip the app's normal init path,
        // and categories must be registered before a notification using them can post.
        NotificationService.configure()

        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "I didn't get any text to scan.")
        }

        switch ReceiptCaptureService.capture(rawText: trimmed) {
        case .saved(let transaction):
            return .result(dialog: "Logged \(transaction.amount.idrFormatted) — check the notification to fix anything.")
        case .amountNotFound:
            return .result(dialog: "Captured the text, but couldn't find an amount — nothing was saved.")
        }
    }
}

// MARK: - Optional: Siri / Spotlight discoverability
//
// Only ONE type per app target may conform to AppShortcutsProvider — if you already
// have one elsewhere, merge this phrase into it instead of adding a second conformance.
struct ScanReceiptShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanReceiptTextIntent(),
            phrases: ["Scan receipt with \(.applicationName)"],
            shortTitle: "Scan Receipt",
            systemImageName: "text.viewfinder"
        )
    }
}
```

- [ ] **Step 2: Rewrite `ShareViewController`'s capture handling**

Replace the full contents of `Monee/AppTargets/ShareExtension/ShareViewController.swift`:

```swift
//
//  ShareViewController.swift
//  Monee
//
//  Handles shared plain text and shared images identically: extract text (directly for
//  text shares, via VisionOCRService for image shares), then hand off to
//  ReceiptCaptureService — the exact same save-or-skip rule the Action Button flow uses.
//  A failed/empty OCR result on an image share behaves the same as "no amount found":
//  nothing is saved, and the photo itself is not retained anywhere after this runs.
//
//  ⚠️ Requires this file's Info.plist NSExtensionActivationRule to accept BOTH
//  public.plain-text and public.image (see ShareExtension/Info.plist).
//
//  ⚠️ Target membership: this file needs RegexParser.swift, Transaction.swift,
//  AppGroup.swift, VisionOCRServiceError.swift, CurrencyFormat.swift,
//  NotificationService.swift, and ReceiptCaptureService.swift all added to the
//  ShareExtension target in Xcode's File Inspector.
//
//  ⚠️ UI PLACEHOLDER — bare loading state, not a designed screen.
//

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "Saving to Monee…"
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
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

        capture(rawText: text)
        finish()
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
        capture(rawText: text)
        finish()
    }

    private func capture(rawText: String) {
        NotificationService.configure() // defensive — extension launch may skip app init
        _ = ReceiptCaptureService.capture(rawText: rawText)
    }

    private func finish() {
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
```

- [ ] **Step 3: Verify ShareExtension target membership**

In Xcode, select `Monee/Core/Utilities/RegexParser.swift`,
`Monee/Core/Database/Models/Transaction.swift`, `Monee/Core/Sharing/AppGroup.swift`,
`Monee/Features/ReceiptScanner/Logic/VisionOCRServiceError.swift`,
`Monee/Core/Utilities/CurrencyFormat.swift` in the Project Navigator and confirm
**ShareExtension** is checked in each one's Target Membership panel (in addition to
**Monee**). Fix any that are missing it.

- [ ] **Step 4: Manual verification (requires a physical device or Shortcuts-capable simulator)**

This is the first point in the plan where the whole project should build — every prior task
either left a piece of the old broken API in place (fixed here) or was working against
`ParsedReceiptData`'s Task 2 stub values (`suggestedTitle`/`isIncome`), which is enough to
compile even before Task 7's real tuning lands.

1. Build and run the Monee app once (to install it and its extensions) on a device/simulator.
   Confirm the build succeeds.
2. From the Dashboard, tap the "+" menu → "Manual Entry" — confirm the form still opens
   titled "Add Transaction" and saves a new transaction as before (regression check for
   Task 4's edit-mode changes, deferred here since this is the first point a full build is
   possible).
3. In the Shortcuts app, build the Action Button shortcut described in
   `ScanReceiptTextIntent.swift`'s header comment, pointed at a screenshot of one of the two
   sample receipts (`IMG_2076.heic` / `IMG_1861.heic` in the repo root, or copies with the
   sensitive fields already blocked out).
4. Run the shortcut. Confirm: a "Logged" notification appears; opening the Monee app's
   Tracker shows a new transaction with a non-zero amount (title will just read "Receipt"
   until Task 7 lands — that's the expected stub value).
5. Tap the notification. Confirm: the app opens (or comes to the foreground) directly into
   an "Edit Transaction" sheet pre-filled with that transaction's data.
6. Share the same screenshot via the system share sheet, choosing "Monee" (the Share
   Extension). Confirm the same "Logged" notification and edit flow work identically.

- [ ] **Step 5: Commit**

```bash
git add Monee/AppTargets/ScanReceiptTextIntent.swift Monee/AppTargets/ShareExtension/ShareViewController.swift
git commit -m "feat: wire Action Button and Share Extension to ReceiptCaptureService"
```

---

### Task 7: `RegexParser` tuning (lowest priority — last)

**Files:**
- Modify: `Monee/Core/Database/Models/Transaction.swift` (add `.transfer` category case)
- Modify: `Monee/Core/Utilities/RegexParser.swift`
- Create: `scripts/verify_regex_parser.swift` (standalone check, no Xcode test target needed)

**Interfaces:**
- Produces: real (non-stub) logic for `ParsedReceiptData.suggestedTitle: String` and
  `ParsedReceiptData.isIncome: Bool` (Task 2 added these as stub-valued fields; this task
  replaces the stubs with real parsing logic — no compile-state change from this task, the
  project has been buildable since Task 6).
- Produces: `TransactionCategory.transfer` case.

- [ ] **Step 1: Add the `.transfer` category**

In `Monee/Core/Database/Models/Transaction.swift`, add a case to `TransactionCategory`
(after `.office`, before `.unassigned`):

```swift
enum TransactionCategory: String, Codable, CaseIterable {
    case income = "Income"
    case software = "Software & Subscriptions"
    case hardware = "Hardware & Equipment"
    case marketing = "Marketing & Ads"
    case travel = "Travel & Transport"
    case meals = "Meals & Entertainment"
    case office = "Office Supplies"
    case transfer = "Bank Transfer"
    case unassigned = "Unassigned"

    var iconName: String {
        switch self {
        case .income: return "banknote.fill"
        case .software: return "puzzlepiece.extension.fill"
        case .hardware: return "desktopcomputer"
        case .marketing: return "megaphone.fill"
        case .travel: return "airplane"
        case .meals: return "fork.knife"
        case .office: return "printer.fill"
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        case .unassigned: return "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .income: return .green
        case .software: return .indigo
        case .hardware: return .gray
        case .marketing: return .pink
        case .travel: return .teal
        case .meals: return .orange
        case .office: return .brown
        case .transfer: return .blue
        case .unassigned: return .secondary
        }
    }
}
```

- [ ] **Step 2: Rewrite `RegexParser.swift`**

Replace the full contents of `Monee/Core/Utilities/RegexParser.swift`:

```swift
//
//  RegexParser.swift
//  Monee
//
//  Core/Utilities/RegexParser.swift
//
//  IDR only, per product decision — Rupiah is, in practice, always a whole number, so "."
//  and "," are both just grouping separators, full stop. $-denominated receipts will NOT
//  parse — intentional scope narrowing.
//
//  Tuned against two real sample screenshots (a BCA bank transfer confirmation and a
//  blu/BI-FAST transfer confirmation) — see the comments below for what each fix addresses.
//

import Foundation

struct ParsedReceiptData {
    var amount: Double?
    var date: Date?
    var keyword: String?
    var category: TransactionCategory
    var suggestedTitle: String
    var isIncome: Bool
    var rawText: String

    var isComplete: Bool {
        amount != nil && date != nil
    }
}

enum RegexParser {

    static func parse(_ rawText: String) -> ParsedReceiptData {
        let amount = parseAmount(from: rawText)
        let date = parseDate(from: rawText)
        let (keyword, category) = parseKeyword(from: rawText)
        let isIncome = parseIsIncome(from: rawText)
        let suggestedTitle = parseSuggestedTitle(from: rawText, category: category)

        return ParsedReceiptData(
            amount: amount,
            date: date,
            keyword: keyword,
            category: category,
            suggestedTitle: suggestedTitle,
            isIncome: isIncome,
            rawText: rawText
        )
    }

    // MARK: - Amount Parsing (IDR only)

    static func parseAmount(from text: String) -> Double? {
        let totalKeywords = ["grand total", "total due", "amount due", "nominal", "total", "balance due", "amount", "jumlah"]
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for keyword in totalKeywords {
            guard let lineIndex = lines.firstIndex(where: { $0.lowercased().contains(keyword) }) else { continue }

            // Same line as the keyword (e.g. "Total: Rp45.000").
            if let value = rupiahValues(in: lines[lineIndex]).first {
                return value
            }

            // Common card-style layout: keyword label on its own line, value on the next
            // line (e.g. "Nominal" then "Rp 65.000,00" below it, as in the blu sample) —
            // check the next couple of lines before giving up on this keyword.
            for offset in 1...2 {
                let nextIndex = lineIndex + offset
                guard nextIndex < lines.count else { break }
                if let value = rupiahValues(in: lines[nextIndex]).first {
                    return value
                }
            }
        }

        return confidentRupiahValues(in: text).max()
    }

    /// Matches Rp/IDR-prefixed or bare digit groups: "Rp150.000", "IDR 45,000", "38000".
    private static func rupiahValues(in text: String) -> [Double] {
        let pattern = #"(?:Rp\.?|IDR)?\s?(\d{1,3}(?:[.,]\d{3})+|\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        return matches.compactMap { normalizeRupiahString(nsText.substring(with: $0.range)) }
    }

    /// Same as `rupiahValues`, but only values a human would recognize as money without a
    /// nearby label: an explicit Rp/IDR prefix, or thousands-grouping (e.g. "10.000"). Used
    /// only for the last-resort "guess the amount" fallback — without this restriction, a
    /// bare short number from a date or time (e.g. the year "2026" in the BCA sample) can
    /// outrank a genuinely small real amount (e.g. "Rp1.500") in a plain max() comparison.
    private static func confidentRupiahValues(in text: String) -> [Double] {
        let pattern = #"(?:Rp\.?|IDR)\s?\d{1,3}(?:[.,]\d{3})*|\d{1,3}(?:[.,]\d{3})+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        return matches.compactMap { normalizeRupiahString(nsText.substring(with: $0.range)) }
    }

    /// Strips "Rp"/"IDR" and every "." or "," grouping separator, parses the remainder
    /// as a whole-Rupiah amount.
    private static func normalizeRupiahString(_ raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: "Rp", with: "")
            .replacingOccurrences(of: "IDR", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    // MARK: - Date Parsing

    static func parseDate(from text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        let matches = detector.matches(in: text, range: range)
        let now = Date()
        let candidates = matches.compactMap { $0.date }.filter { $0 <= now.addingTimeInterval(86_400) }
        return candidates.max()
    }

    // MARK: - Keyword / Category Parsing

    private static let categoryKeywordMap: [TransactionCategory: [String]] = [
        .software: ["subscription", "saas", "adobe", "figma", "notion", "github", "openai", "app store"],
        .hardware: ["apple store", "best buy", "laptop", "monitor", "keyboard", "electronics"],
        .marketing: ["ads", "facebook ads", "google ads", "boost", "sponsor", "promotion"],
        .travel: ["uber", "grab", "gojek", "taxi", "airlines", "hotel", "flight", "airbnb"],
        .meals: ["restaurant", "cafe", "coffee", "starbucks", "mcdonald", "food", "grabfood", "gofood"],
        .office: ["office", "stationery", "staples", "supplies", "print"],
        .transfer: ["transfer", "bi-fast", "rtgs", "skn", "bca", "blu", "gopay", "ovo", "dana", "bank"]
    ]

    static func parseKeyword(from text: String) -> (keyword: String?, category: TransactionCategory) {
        let lowercased = text.lowercased()
        for (category, keywords) in categoryKeywordMap {
            for keyword in keywords {
                if lowercased.contains(keyword) {
                    return (keyword, category)
                }
            }
        }
        return (nil, .unassigned)
    }

    // MARK: - Direction (Income vs. Expense)

    /// Default is expense (false) when ambiguous — the safer default for cash-reserve math,
    /// since silently crediting fake income would inflate the reserve.
    private static let incomeKeywords = ["diterima", "menerima", "masuk", "top up", "topup", "received", "refund", "cash in"]

    static func parseIsIncome(from text: String) -> Bool {
        let lowercased = text.lowercased()
        return incomeKeywords.contains { lowercased.contains($0) }
    }

    // MARK: - Suggested Title

    /// Deliberately minimal: one pattern for the "ke <Name>" / "to <Name>" construction
    /// common in Indonesian transfer confirmations (e.g. "...ke SILVIA NG berhasil" in the
    /// blu sample), falling straight back to a generic label. No broader merchant-name
    /// extraction beyond this single pattern.
    static func parseSuggestedTitle(from text: String, category: TransactionCategory) -> String {
        let pattern = #"(?:\bke\b|\bto\b)\s+([A-Z][A-Za-z ]{1,30}?)(?:\s+berhasil\b|[.,\n]|$)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let name = text[range].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                return name
            }
        }

        return category == .unassigned ? "Receipt" : category.rawValue
    }
}
```

- [ ] **Step 3: Write the standalone verification script**

No XCTest target exists in this project. Since `RegexParser` and `TransactionCategory` only
depend on `Foundation` (no SwiftUI/SwiftData-specific behavior is exercised by parsing
logic), this can be verified with a plain `swift` invocation instead — no Xcode project
changes needed.

Create `scripts/verify_regex_parser.swift`:

```swift
// Standalone verification for RegexParser, run via:
//   swift scripts/verify_regex_parser.swift Monee/Core/Utilities/RegexParser.swift Monee/Core/Database/Models/Transaction.swift
// (Transaction.swift is included only for the TransactionCategory enum it defines; its
// @Model/SwiftUI pieces still compile standalone since Foundation + SwiftUI + SwiftData are
// all system frameworks available to the `swift` command on macOS.)

import Foundation

var failures = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name)")
        failures += 1
    }
}

// Real sample 1: BCA bank transfer confirmation screenshot. No "total"/"nominal"/"amount"/
// "jumlah" keyword appears anywhere — this exercises the confidentRupiahValues() fallback.
let bcaSample = """
Transfer Successful
02 Jul 2026 10:34:01
IDR 10,000.00
Beneficiary Name
Beneficiary Account
Transaction Type
Transfer to BCA Account
View Details
"""

// Real sample 2: blu/BI-FAST transfer confirmation screenshot. "Nominal" label and its
// value are on separate lines — this exercises the next-line lookahead in parseAmount().
let bluSample = """
Kamu Berhasil Mengirimkan Dana!
Transfer Rp 65.000 ke SILVIA NG berhasil
Transaksi Berhasil
20 Jun 2026 | 13:15:15 WIB
Nominal
Rp 65.000,00
SILVIA NG
BCA
Tipe Transaksi
BI-FAST
No. Ref blu
Detail
"""

let bca = RegexParser.parse(bcaSample)
check("BCA sample: amount == 10000", bca.amount == 10000)
check("BCA sample: category == .transfer", bca.category == .transfer)
check("BCA sample: isIncome == false", bca.isIncome == false)
check("BCA sample: suggestedTitle == \"BCA Account\"", bca.suggestedTitle == "BCA Account")

let blu = RegexParser.parse(bluSample)
check("blu sample: amount == 65000", blu.amount == 65000)
check("blu sample: category == .transfer", blu.category == .transfer)
check("blu sample: isIncome == false", blu.isIncome == false)
check("blu sample: suggestedTitle == \"SILVIA NG\"", blu.suggestedTitle == "SILVIA NG")

// Regression check for the fallback-ranking bug this task fixes: a small real amount must
// not lose to a bare year/date number.
let smallAmountSample = """
Payment Confirmation
01 Jan 2026
Rp1.500
"""
let small = RegexParser.parse(smallAmountSample)
check("small amount beats bare year: amount == 1500", small.amount == 1500)

print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
```

- [ ] **Step 4: Run the verification script**

```bash
swift scripts/verify_regex_parser.swift Monee/Core/Utilities/RegexParser.swift Monee/Core/Database/Models/Transaction.swift
```

Expected: every `check(...)` line prints `PASS:`, followed by `ALL CHECKS PASSED`, and the
command exits `0`. If `TransactionCategory.tint` (a `Color` from SwiftUI) fails to compile
standalone via the bare `swift` command, split it into a `.swift` file containing only the
`enum TransactionCategory` and `struct ParsedReceiptData`/`RegexParser` pieces (no `import
SwiftUI`/`import SwiftData`) for the purposes of running this script, or temporarily comment
out the `tint`/`@Model` parts in a scratch copy — do not change the real
`Transaction.swift`/`RegexParser.swift` to accommodate the script; the script accommodates
them.

- [ ] **Step 5: Full project build**

Open `Monee.xcodeproj` in Xcode and build the `Monee` scheme (<kbd>Cmd+B</kbd>). The project
has been buildable since Task 6 (this task only swaps stub values for real logic, no new
types), so this build should already succeed cleanly. Fix any remaining compile errors before
proceeding (there should be none if every prior task's code was applied as written).

- [ ] **Step 6: Commit**

```bash
git add Monee/Core/Database/Models/Transaction.swift Monee/Core/Utilities/RegexParser.swift scripts/verify_regex_parser.swift
git commit -m "feat: tune RegexParser against real sample data, add .transfer category"
```

---

## Post-plan follow-up (not part of this plan)

- Tap-to-edit on arbitrary Tracker list rows (not just OCR captures) is a natural follow-on
  enabled by Task 4's edit-mode addition, but is not built here.
- No broader merchant-name-extraction heuristics beyond the single `"ke <Name>"` pattern in
  Task 7 — deliberately deferred per user direction to keep this piece minimal.
