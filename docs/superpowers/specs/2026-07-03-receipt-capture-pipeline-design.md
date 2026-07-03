# Receipt Capture Pipeline — Design Spec

**Date:** 2026-07-03
**Status:** Approved by user, pending final spec review

## 1. Context

The repo is mid-refactor on the receipt-capture pipeline (Action Button + Share Extension →
OCR/text extraction → parse → confirm → save). Several files reference types
(`PendingReceiptStore`, `NotificationService`, `NotificationCategory`, `NotificationAction`,
`NotificationUserInfoKey`) that were designed via code comments but never actually
implemented, so the app currently does not compile end-to-end. Investigation surfaced these
concrete issues:

- `PendingReceiptStore` / `NotificationService` and friends are referenced by
  `ScanReceiptTextIntent.swift`, `ShareViewController.swift`, `NotificationDelegate.swift`,
  and `ReceiptConfirmationView.swift`, but no file defines them.
- Two competing `UNUserNotificationCenterDelegate` implementations exist:
  `ContainerExtension.swift` (extension on `AppContainer`, references a `modelContainer`
  property that doesn't exist — dead code) and `NotificationDelegate.swift` (a standalone,
  more complete class). Nothing currently registers either as the actual delegate — there is
  no `AppDelegate` in this SwiftUI-only app.
- `AppGroup.swift`'s identifier (`group.com.rioferdinand.freelancefinance`) does not match
  the identifier in all three `.entitlements` files (`group.com.rioferdinand.monee`) — a
  runtime crash waiting to happen (`fatalError` in `AppGroup.containerURL`/`defaults`).
- `DeepLink.swift` dropped its `.pendingReceipt(id:)` case in a recent commit, but
  `NotificationDelegate.swift` still depends on that case for its "Edit" action.
- `ReceiptConfirmationView.swift` references `parsed.suggestedTitle` and `parsed.isIncome` —
  neither exists on `RegexParser`'s `ParsedReceiptData` — another compile error.
- `ShareExtension/Info.plist`'s `NSExtensionActivationRule` has
  `NSExtensionActivationSupportsText` set to an empty string instead of a boolean `true`.
- There is currently no way to edit an already-saved `Transaction` anywhere in the app;
  `QuickEntryViewModel.save()` only ever inserts new records.

Additionally, the user reconsidered the originally-scoped "pending receipt" architecture
(stage a capture, confirm via a rich actionable notification with Save/Edit/Dismiss, only
then write to SwiftData) as unnecessary complexity that works against the app's "frictionless
tracking" core value. The user provided two real OCR-relevant screenshots (a BCA bank
transfer confirmation and a blu/BI-FAST transfer confirmation) which drove concrete
`RegexParser` findings (§6).

## 2. Scope

Three tasks, in priority order:
1. Fix the Action Button text-extraction + confirmation feature; remove now-unnecessary
   files/code.
2. Get the Share Extension working, reusing the same text-extraction/save path.
3. Tune `RegexParser` for more accurate, adaptive extraction (lowest priority — see §6).

Out of scope: Threshold Savings / Jar system (still on hold per the product spec), any UI
restyling (all current UI is explicitly placeholder), AI Buddy changes.

## 3. Architecture Decision

**Chosen approach:** a single shared type, `ReceiptCaptureService`, owns the "text in →
Transaction saved or not" decision. Both the Action Button intent (`ScanReceiptTextIntent`,
main app target) and the Share Extension (`ShareViewController`, ShareExtension target) call
it. This was chosen over duplicating the logic in each entry point, which is how the current
half-broken state arose (the two flows already drifted — only `ShareViewController` handles
images) — and over routing through `AppContainer`, which isn't reachable from the Share
Extension process at all (separate target/process boundary).

**Core behavioral rule** (confirmed with user): the old "stage first, confirm via rich
actionable notification, then save" flow is retired. Instead:
- If `RegexParser` finds an amount → save a real `Transaction` immediately
  (`source: .ocr`), using fallback defaults for date (`Date()`) and category
  (`.unassigned` unless a category/direction keyword matched). Fire a simple, informational
  local notification confirming what was logged.
- If no amount is found → save nothing. No notification, no partial/staged record. The
  Action Button's Shortcut dialog response is the only feedback ("couldn't find an amount").
  This applies identically to Share Extension text shares and image shares (image OCR
  failure/empty result behaves the same as "no amount found" — nothing saved).

The notification exists purely so the user can fix a wrong parse — there is no "Save" action
(already saved) and no "Dismiss" action; a single tap opens an edit screen for that
transaction. Deleting a bad capture uses the Tracker list's existing swipe-to-delete.

## 4. Components

### 4.1 Cleanup
- Delete `Monee/App/ContainerExtension.swift` (dead code, superseded by `NotificationDelegate`).
- Un-stage the stray empty-file git index entry at `Monee/App/\` (`git rm --cached` — nothing
  exists on disk for it).
- `AppGroup.swift`: change `identifier` to `"group.com.rioferdinand.monee"` to match all three
  `.entitlements` files.
- `ShareExtension/Info.plist`: change `NSExtensionActivationSupportsText` from `<string></string>`
  to `<true/>`.

### 4.2 `ReceiptCaptureService` (new)
Location: `Monee/Core/Capture/ReceiptCaptureService.swift`. Target membership: main app +
ShareExtension (not WidgetExtension).

```
enum CaptureOutcome {
    case saved(Transaction)
    case amountNotFound
}

enum ReceiptCaptureService {
    static func capture(rawText: String) -> CaptureOutcome
}
```

Implementation: runs `RegexParser.parse(rawText)`. If `parsed.amount` is non-nil, builds a
`Transaction` (title from `parsed.suggestedTitle`, amount, `date: parsed.date ?? Date()`,
category: `parsed.isIncome ? .income : parsed.category` — same override pattern
`ReceiptConfirmationView` already uses for the manual-capture path, so `.income` and a
mismatched expense category can never coexist, `source: .ocr`, `rawKeyword: parsed.keyword`),
inserts via a fresh `ModelContext(SwiftDataService.makeContainer())`, saves, calls
`NotificationService.scheduleCaptureNotification(for:)`, returns `.saved(transaction)`.
Otherwise returns `.amountNotFound` with no side effects.

`ScanReceiptTextIntent.perform()` calls this directly with the Shortcut-captured text (no OCR
needed — Shortcuts' Live Text step already did that) and shapes its dialog response from the
outcome. `ShareViewController` calls `VisionOCRService.recognizeText(from:)` first for image
shares (or uses the shared text directly for text shares), then calls the same function.

### 4.3 `NotificationService` (new)
Location: `Monee/Core/Notifications/NotificationService.swift`.
- `configure()` — registers one `UNNotificationCategory` (`"TRANSACTION_LOGGED"`), no actions.
  Called defensively at the start of both entry points (background-launched code paths may
  skip normal app init).
- `scheduleCaptureNotification(for transaction: Transaction)` — builds
  `UNMutableNotificationContent` (title "Logged", body `"\(transaction.title) — \(transaction.amount.idrFormatted)"`),
  `userInfo["transactionID"] = transaction.id.uuidString`, `categoryIdentifier =
  "TRANSACTION_LOGGED"`, fires with a `nil` trigger (immediate).

### 4.4 Notification → edit routing
- `NotificationDelegate.swift`: simplifies to one responsibility. `didReceive response:`
  reads `transactionID` from `userInfo`, parses it as a `UUID`, sets
  `AppContainer.shared.pendingRoute = .editTransaction(id:)`, calls the completion handler.
  No more save/dismiss action branches.
- Becomes a `static let shared = NotificationDelegate()` singleton (required: `UNUserNotificationCenter.delegate`
  is a **weak** reference — an unretained instance would be deallocated immediately and
  silently stop receiving callbacks).
- `FreelanceFinanceApp.init()` sets `UNUserNotificationCenter.current().delegate =
  NotificationDelegate.shared`.
- `DeepLink.swift` gains `case editTransaction(id: UUID)` (replacing the removed
  `.pendingReceipt(id: String)`), URL shape `moneeapp://editTransaction?id=<uuid>`.
- `ContentView.handleRoute` gains a case: fetch the `Transaction` by id from the model
  context, present `QuickEntryFormView(editing: transaction)` as a sheet.

### 4.5 Edit capability
- `QuickEntryViewModel` gains an edit mode: an initializer/`load(from:)` that copies an
  existing `Transaction`'s fields into the published properties and retains a reference to
  it; `save(using:)` branches — if editing, mutate the existing transaction's properties in
  place and just `try modelContext.save()` (no insert); otherwise behaves as today (insert
  new).
- `ReceiptConfirmationView.swift` drops its `pendingEntryID` / `PendingReceiptStore` entry
  path entirely (that staging concept no longer exists) and goes back to being purely the
  manual-PhotosPicker-capture screen (`pendingImage` path only). This also removes the now
  provably-dead reference to a nonexistent `PendingReceiptStore.entry(id:)`.

### 4.6 RegexParser tuning (lowest priority — see §6 for rationale/ordering)
Concrete fixes, driven by the two real screenshots (BCA bank transfer, blu/BI-FAST transfer):
- Add `"nominal"` to `totalKeywords` (Indonesian for "amount" — present in one sample, absent
  from the current list entirely).
- `parseAmount`: when the matched keyword line itself has no Rupiah value, check the next
  1–2 lines too (both samples show label and value on separate lines, e.g. "Nominal" then
  "Rp 65.000,00" below it — current code only checks the keyword's own line).
- `parseAmount` fallback (`rupiahValues(in: text).max()`, used when no keyword line matches
  at all): restrict candidates to "currency-shaped" values only — grouped-by-3
  (`\d{1,3}(?:[.,]\d{3})+`) or Rp/IDR-prefixed. Currently a bare short number (e.g. the year
  "2026" from a date) can outrank a genuinely small real amount (e.g. Rp1.500) in the `.max()`
  comparison; excluding bare untagged short digit runs from this fallback pool fixes that.
- Add banking/transfer keywords (`"transfer"`, `"bi-fast"`, `"bca"`, `"blu"`, etc.) to
  `categoryKeywordMap`, mapped to a new `TransactionCategory.transfer` case (per user
  decision — SwiftData handles new raw-value enum cases without migration).
- Add income/expense direction detection: incoming-language keywords (`"diterima"`,
  `"masuk"`, `"top up"`, `"received"`, `"refund"`) flip `isIncome`; default is expense
  (`isIncome = false`) when ambiguous, since that's the safer default for cash-reserve math.
- Add `suggestedTitle: String` and `isIncome: Bool` to `ParsedReceiptData` — this also fixes
  `ReceiptConfirmationView`'s two existing compile errors (`parsed.suggestedTitle`,
  `parsed.isIncome`), which reference fields that don't exist today.
- `suggestedTitle` extraction: kept intentionally minimal — a single regex for the
  `"ke <Name>"` / `"to <Name>"` construction (matches "...ke SILVIA NG berhasil" from the
  blu sample), falling straight back to a generic label (category name, or "Transfer") if it
  doesn't match. No broader name-extraction heuristics beyond this one pattern.

## 5. Data Flow (happy path, Action Button)

1. User presses Action Button → Shortcut takes a screenshot → Live Text extracts on-screen
   text → runs `ScanReceiptTextIntent` with that text (`openAppWhenRun = false`).
2. `perform()` calls `NotificationService.configure()` defensively, then
   `ReceiptCaptureService.capture(rawText:)`.
3. If an amount is found: a `Transaction` is inserted and saved directly to the on-disk
   SwiftData store; a local notification fires immediately confirming what was logged;
   the intent's dialog response confirms the amount to Siri/Shortcuts.
4. User taps the notification → `NotificationDelegate` sets `pendingRoute =
   .editTransaction(id:)` → app launches/foregrounds → `ContentView` observes the route,
   switches to the relevant tab, fetches the `Transaction`, presents `QuickEntryFormView`
   pre-filled in edit mode.
5. If no amount was found in step 2: nothing is saved, no notification fires; the user only
   hears/sees the Shortcut's own "couldn't find an amount" response.

Share Extension flow (text or image) is identical from step 2 onward — the only difference is
how raw text is obtained (direct for text shares, via `VisionOCRService` for image shares).

## 6. Task Ordering / Effort Priority

Per explicit user direction: crucial correctness fixes come first, `RegexParser` tuning last,
since it's the least critical piece for a working end-to-end demo and shouldn't consume time
better spent on the pipeline itself. Rough order:
1. Cleanup + App Group / Info.plist fixes (§4.1) — unblocks everything else.
2. `ReceiptCaptureService` + `NotificationService` (§4.2, §4.3).
3. Notification → edit routing, `NotificationDelegate` singleton wiring (§4.4).
4. Edit capability in `QuickEntryViewModel`/`QuickEntryFormView` (§4.5).
5. Wire `ScanReceiptTextIntent` and `ShareViewController` to the new service (tasks 1 & 2 from
   the product spec).
6. `RegexParser` tuning (§4.6, task 3 from the product spec) — last.

## 7. Testing Notes

- No existing test target in this project (POC scope, 2-day sprint) — verification will be
  manual: build + run on-device/simulator, trigger the Action Button Shortcut and a Share
  Extension share with the two real sample screenshots, confirm a `Transaction` appears in
  the Tracker list with a sensible title/amount/category, confirm tapping the notification
  opens the edit sheet pre-filled correctly.
- `RegexParser` changes can be spot-checked against the two real sample texts extracted from
  the provided screenshots (BCA: "IDR 10,000.00" bank transfer; blu: "Rp 65.000,00"
  BI-FAST transfer) without needing a full OCR pass, since the raw text shape is already known
  from reading the images directly.

## 8. Explicitly Out of Scope / Deferred

- No new UI styling — all views remain functional-placeholder per existing convention.
- No broader merchant-name-extraction heuristics beyond the single `"ke <Name>"` pattern.
- No changes to the AI Buddy / `PromptBuilder` context-gathering.
- No Threshold Savings / Jar system work.
- Tap-to-edit on arbitrary Tracker list rows (not just OCR captures) is a natural follow-on
  enabled by §4.5's edit-mode addition, but is not required or built as part of this work.
