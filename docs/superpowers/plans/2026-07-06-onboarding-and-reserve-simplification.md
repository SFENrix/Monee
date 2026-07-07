# Onboarding & Cash Reserve Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the time-decayed income-estimate blending in `CashReserveCalculator` with a flat transaction-count gate, and add a real onboarding flow (Name, Status, Current Balance, Estimated Monthly Income, Estimated Monthly Expense) whose values are given to the AI as separate qualitative context — never mixed into the deterministic reserve arithmetic.

**Architecture:** One consolidated UserDefaults-backed `UserProfile` store replaces the narrower `UserFinancialProfile`. `CashReserveCalculator` becomes a pure `income − expenses` calculation over logged transactions plus a boolean confidence gate (`transactionCount >= 5`) — no more fallback blending. A new full-screen `OnboardingView`, shown once from the app root, collects the five profile fields and — if the user enters a starting balance — inserts it as an ordinary `Transaction` (title "Starting Balance") rather than a special-cased number, so the reserve math never needs a second code path. `AIChatViewModel` builds two separate context blocks for the AI: deterministic reserve facts (gated by the count threshold) and self-reported profile context (always shown, always labeled as a target/estimate, never arithmetic).

**Tech Stack:** SwiftUI, SwiftData, Apple FoundationModels (on-device LLM), UserDefaults.

## Global Constraints

- IDR (Indonesian Rupiah) only, no other currencies — matches existing `idrFormatted` / `RegexParser` scope.
- No XCTest target exists anywhere in this project (verified: zero `XCTest` references in `project.pbxproj`, no `*Tests*` directories). Every task below verifies via **build + manual run in Simulator**, not automated tests. Do not create a new test target as part of this feature — out of scope.
- `RelationshipStatus` changes from its current 4 dating-app-style cases (`single`, `inRelationship`, `married`, `itsComplicated`) to 3 finance-context cases (`single`, `married`, `marriedWithKids`) — decided in conversation with the user (status exists to tell the AI whether to be stricter or more forgiving about spending, not to describe a relationship). This enum is not yet persisted anywhere (currently a `@State` default in `ProfileView` that resets every launch), so this is a safe rename with no migration needed.
- Transaction-count confidence threshold is **5** (explicit user decision, "room for changes" — keep it as a single named constant, not scattered literals).
- The old `estimatedMonthlyIncome` value in `UserDefaults` (key `"estimatedMonthlyIncome"`, written by the old `IncomeEstimateSheet`) is **not migrated** — explicit user decision to start fresh. The new onboarding flow always re-collects it.
- Starting balance is recorded as a real `Transaction` (title `"Starting Balance"`, category `.income`, dated at onboarding completion) — not a special baseline field in `CashReserveSummary`. This was a deliberate simplification the user asked about and confirmed.

---

## File Structure

| File | Change |
|---|---|
| `Monee/Core/Utilities/UserFinancialProfile.swift` | **Delete** — replaced by `UserProfile.swift` |
| `Monee/Core/Utilities/UserProfile.swift` | **Create** — consolidated UserDefaults-backed profile store: `name`, `status`, `estimatedMonthlyIncome`, `estimatedMonthlyExpense`, `hasCompletedOnboarding`. Hosts the `RelationshipStatus` enum. |
| `Monee/Core/Utilities/CashReserveCalculator.swift` | **Modify** — remove blending/fallback logic; `currentReserve` becomes plain `income − expenses`; add `minimumTransactionsForConfidence` constant and `hasEnoughData` field. |
| `Monee/Features/AIBuddy/ViewModels/AIChatViewModel.swift` | **Modify** — `buildFinancialContext` drops the `fallbackMonthlyIncome` argument; `formatReserveSummary` branches on `hasEnoughData`; new `formatProfileContext` emits the self-reported profile block separately. |
| `Monee/Features/AIBuddy/Logic/AppleIntelligenceAdapter.swift` | **Modify** — coaching-rules prompt updated: reference the new "not enough data" gating language, and instruct the model to use `status` for strict/forgiving tone and to encourage saving beyond estimated income / warn against exceeding estimated expense. |
| `Monee/Features/AIBuddy/UI/IncomeEstimateSheet.swift` | **Delete** — superseded by the new onboarding screen. |
| `Monee/Features/Onboarding/UI/OnboardingView.swift` | **Create** — new full-screen onboarding form (Name, Status, Current Balance, Estimated Monthly Income, Estimated Monthly Expense). |
| `Monee/Features/AIBuddy/UI/AIChatView.swift` | **Modify** — remove the old lazy income-estimate-sheet trigger (`showingIncomeEstimate`, its `.sheet`, and the `.task` gate); replace hardcoded `userFirstName` with `UserProfile.name`. |
| `Monee/App/ContentView.swift` (`RootTabView`) | **Modify** — add a `.fullScreenCover` gated on `!UserProfile.hasCompletedOnboarding`, showing `OnboardingView`. |
| `Monee/Features/Profile/UI/ProfileView.swift` | **Modify** — read/write `name` and `status` through `UserProfile` instead of local `@State`; add editable rows for Estimated Monthly Income / Estimated Monthly Expense; remove the now-duplicate local `RelationshipStatus` definition (import the one from `UserProfile.swift`). |

---

### Task 1: Consolidated `UserProfile` store

**Files:**
- Create: `Monee/Core/Utilities/UserProfile.swift`
- Delete: `Monee/Core/Utilities/UserFinancialProfile.swift`

**Interfaces:**
- Produces: `enum UserProfile` with `static var name: String?`, `static var status: RelationshipStatus?`, `static var estimatedMonthlyIncome: Double?`, `static var estimatedMonthlyExpense: Double?`, `static var hasCompletedOnboarding: Bool` (all UserDefaults-backed, get/set).
- Produces: `enum RelationshipStatus: String, CaseIterable, Identifiable` with cases `.single = "Single"`, `.married = "Married"`, `.marriedWithKids = "Married with Kids"`, and `var id: String { rawValue }`.

- [ ] **Step 1: Write `UserProfile.swift`**

```swift
//
//  UserProfile.swift
//  Monee
//
//  Single source of truth for onboarding-collected, self-reported profile data.
//  Deliberately NOT SwiftData — these are advisory numbers the AI uses as qualitative
//  context (targets/estimates), never mixed into CashReserveCalculator's arithmetic.
//  UserDefaults-backed so it's readable from a plain class (AIChatViewModel), not just
//  SwiftUI views.
//

import Foundation

enum RelationshipStatus: String, CaseIterable, Identifiable, Codable {
    case single = "Single"
    case married = "Married"
    case marriedWithKids = "Married with Kids"

    var id: String { rawValue }
}

enum UserProfile {
    private static let nameKey = "userProfile.name"
    private static let statusKey = "userProfile.status"
    private static let estimatedMonthlyIncomeKey = "userProfile.estimatedMonthlyIncome"
    private static let estimatedMonthlyExpenseKey = "userProfile.estimatedMonthlyExpense"
    private static let hasCompletedOnboardingKey = "userProfile.hasCompletedOnboarding"

    static var name: String? {
        get {
            let value = UserDefaults.standard.string(forKey: nameKey)
            return (value?.isEmpty ?? true) ? nil : value
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: nameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: nameKey)
            }
        }
    }

    static var status: RelationshipStatus? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: statusKey) else { return nil }
            return RelationshipStatus(rawValue: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: statusKey)
            } else {
                UserDefaults.standard.removeObject(forKey: statusKey)
            }
        }
    }

    static var estimatedMonthlyIncome: Double? {
        get {
            let value = UserDefaults.standard.double(forKey: estimatedMonthlyIncomeKey)
            return value > 0 ? value : nil
        }
        set {
            if let newValue, newValue > 0 {
                UserDefaults.standard.set(newValue, forKey: estimatedMonthlyIncomeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: estimatedMonthlyIncomeKey)
            }
        }
    }

    static var estimatedMonthlyExpense: Double? {
        get {
            let value = UserDefaults.standard.double(forKey: estimatedMonthlyExpenseKey)
            return value > 0 ? value : nil
        }
        set {
            if let newValue, newValue > 0 {
                UserDefaults.standard.set(newValue, forKey: estimatedMonthlyExpenseKey)
            } else {
                UserDefaults.standard.removeObject(forKey: estimatedMonthlyExpenseKey)
            }
        }
    }

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasCompletedOnboardingKey) }
    }
}
```

- [ ] **Step 2: Delete the old file**

```bash
git rm Monee/Core/Utilities/UserFinancialProfile.swift
```

- [ ] **Step 3: Build to confirm no references to the deleted type remain**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: Build FAILS at this point — `UserFinancialProfile` and old `RelationshipStatus` cases are still referenced from `AIChatView.swift`, `AIChatViewModel.swift`, `IncomeEstimateSheet.swift`, `ProfileView.swift`. That's expected; those call sites are fixed in later tasks. Confirm the *only* errors are "cannot find type 'UserFinancialProfile'" / missing `.itsComplicated` etc. — not something unrelated.

- [ ] **Step 4: Commit**

```bash
git add Monee/Core/Utilities/UserProfile.swift
git commit -m "feat: add consolidated UserProfile store, replacing UserFinancialProfile"
```

---

### Task 2: Simplify `CashReserveCalculator` — remove blending, add confidence gate

**Files:**
- Modify: `Monee/Core/Utilities/CashReserveCalculator.swift`

**Interfaces:**
- Consumes: `Transaction` (existing model, `amount: Double`, `date: Date`, `isIncome: Bool`).
- Produces: `CashReserveCalculator.summarize(transactions: [Transaction]) -> CashReserveSummary` (no more `fallbackMonthlyIncome` parameter). `CashReserveSummary` gains `transactionCount: Int` and `hasEnoughData: Bool`; loses `estimatedIncomeBlended` and `isDataSufficient` (renamed/replaced by `hasEnoughData`). Produces `CashReserveCalculator.minimumTransactionsForConfidence: Int = 5`.

- [ ] **Step 1: Rewrite the file**

```swift
//
//  CashReserveCalculator.swift
//  Monee
//
//  Deterministic financial math, kept entirely separate from the AI. LLMs — especially
//  compact on-device models — are unreliable at summing/averaging over transaction lists.
//  This computes the real numbers in Swift so the AI's job is to interpret and coach,
//  not to do arithmetic it might get wrong.
//
//  Deliberately does NOT blend in any self-reported estimate — that number lives in
//  UserProfile and is handed to the AI as separate qualitative context (see
//  AIChatViewModel.formatProfileContext). Mixing it into this arithmetic was the old
//  design; it produced reserve figures that looked arbitrary to the user once few
//  transactions were logged. This file now answers exactly one question: what do the
//  user's logged transactions say, and is there enough of them to trust the answer.
//

import Foundation

struct CashReserveSummary {
    let currentReserve: Double       // income logged - expenses logged, all time
    let avgDailyExpense: Double      // trailing window average (up to 30 days of history)
    let runwayDays: Double?          // currentReserve / avgDailyExpense; nil if no spend pace yet
    let windowDays: Int              // how many days avgDailyExpense is actually based on
    let expenseCount: Int
    let transactionCount: Int        // income + expenses combined — what the confidence gate checks
    /// True once the user has logged CashReserveCalculator.minimumTransactionsForConfidence
    /// or more transactions (of any kind). Below this, the AI should not state a reserve
    /// figure, runway, or spending verdict — just encourage logging more.
    let hasEnoughData: Bool
}

enum CashReserveCalculator {
    /// Below this many total logged transactions, the reserve/runway numbers are
    /// considered too thin to state to the user. A flat count, not a compound
    /// date+count rule — simpler to reason about and to explain in the UI.
    static let minimumTransactionsForConfidence = 5

    static func summarize(transactions: [Transaction]) -> CashReserveSummary {
        let income = transactions.filter { $0.isIncome }
        let expenses = transactions.filter { !$0.isIncome }

        let totalIncome = income.reduce(0) { $0 + $1.amount }
        let totalExpenses = expenses.reduce(0) { $0 + $1.amount }
        let currentReserve = totalIncome - totalExpenses

        // Trailing-window burn rate — the more real history exists, the more this
        // smooths out one-off spikes instead of one big purchase skewing everything.
        let now = Date()
        let earliestExpenseDate = expenses.map(\.date).min() ?? now
        let daysOfHistory = max(1, Int(now.timeIntervalSince(earliestExpenseDate) / 86_400))
        let window = min(daysOfHistory, 30)
        let windowStart = now.addingTimeInterval(-Double(window) * 86_400)
        let recentTotal = expenses.filter { $0.date >= windowStart }.reduce(0) { $0 + $1.amount }
        let avgDailyExpense = window > 0 ? recentTotal / Double(window) : 0

        let runwayDays: Double? = avgDailyExpense > 0 ? currentReserve / avgDailyExpense : nil

        return CashReserveSummary(
            currentReserve: currentReserve,
            avgDailyExpense: avgDailyExpense,
            runwayDays: runwayDays,
            windowDays: window,
            expenseCount: expenses.count,
            transactionCount: transactions.count,
            hasEnoughData: transactions.count >= minimumTransactionsForConfidence
        )
    }
}
```

- [ ] **Step 2: Build to confirm this file compiles standalone (callers fixed in Task 3)**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: Errors only at `AIChatViewModel.swift`'s call to `CashReserveCalculator.summarize(transactions:fallbackMonthlyIncome:)` (wrong argument label / extra arg) and its use of `.estimatedIncomeBlended` / `.isDataSufficient`. No errors inside `CashReserveCalculator.swift` itself.

- [ ] **Step 3: Commit**

```bash
git add Monee/Core/Utilities/CashReserveCalculator.swift
git commit -m "refactor: drop income-estimate blending from CashReserveCalculator, add flat confidence gate"
```

---

### Task 3: `AIChatViewModel` — gated reserve summary + separate profile context

**Files:**
- Modify: `Monee/Features/AIBuddy/ViewModels/AIChatViewModel.swift`

**Interfaces:**
- Consumes: `CashReserveCalculator.summarize(transactions: [Transaction]) -> CashReserveSummary` and `CashReserveCalculator.minimumTransactionsForConfidence` (Task 2). Consumes `UserProfile.name/.status/.estimatedMonthlyIncome/.estimatedMonthlyExpense` (Task 1).
- Produces: `buildFinancialContext(using:)` unchanged signature; internal `formatReserveSummary(_:)` now branches on `hasEnoughData`; new internal `formatProfileContext() -> String`.

- [ ] **Step 1: Replace `buildFinancialContext` and the two formatting helpers**

Replace lines 123–199 of `AIChatViewModel.swift` (the current `buildFinancialContext`, `formatReserveSummary`) with:

```swift
    /// Builds the financial context handed to the AI. Two independent pieces:
    /// (1) the deterministic reserve summary, computed only from logged transactions
    /// and gated behind a minimum transaction count — no self-reported number is ever
    /// mixed into this arithmetic; (2) the user's self-reported profile context (name,
    /// status, estimated income/expense), always shown but always labeled as a target
    /// or estimate, used by the AI qualitatively (tone, encouragement), never as fact.
    private func buildFinancialContext(using context: ModelContext) throws -> String {
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let all = try context.fetch(descriptor)

        let expenses = all.filter { !$0.isIncome }
        let incomeTxns = all.filter { $0.isIncome }

        var sections: [String] = []

        let summary = CashReserveCalculator.summarize(transactions: all)
        sections.append(formatReserveSummary(summary))
        sections.append(formatProfileContext())

        if expenses.isEmpty {
            sections.append("EXPENSES: No expenses logged yet.")
        } else {
            let shown = expenses.prefix(15)
            let lines = shown.map { txn in
                "- \(txn.date.formatted(date: .abbreviated, time: .omitted)): \(txn.title) (\(txn.amount.idrFormatted))"
            }.joined(separator: "\n")
            sections.append("EXPENSES (\(expenses.count) logged total, showing \(shown.count) most recent):\n\(lines)")
        }

        if incomeTxns.isEmpty {
            sections.append("INCOME: No income transactions logged yet.")
        } else {
            let shown = incomeTxns.prefix(10)
            let lines = shown.map { txn in
                "- \(txn.date.formatted(date: .abbreviated, time: .omitted)): \(txn.title) (\(txn.amount.idrFormatted))"
            }.joined(separator: "\n")
            sections.append("INCOME (\(incomeTxns.count) logged total, showing \(shown.count) most recent):\n\(lines)")
        }

        return sections.joined(separator: "\n\n")
    }

    /// The AI is only allowed to state a reserve/runway figure or a spending verdict
    /// once there's enough logged history to trust it — below the threshold, it should
    /// just encourage the user to log more, not guess with a thin sample.
    private func formatReserveSummary(_ summary: CashReserveSummary) -> String {
        guard summary.hasEnoughData else {
            let remaining = CashReserveCalculator.minimumTransactionsForConfidence - summary.transactionCount
            return """
            CASH RESERVE SUMMARY: Not enough data yet — only \(summary.transactionCount) transaction(s) logged. \
            Log \(remaining) more (backdated entries are fine) before stating a reserve figure, runway, or \
            spending verdict. Do not compute or guess a number — tell the user plainly to log more transactions \
            first so future advice is reliable.
            """
        }

        var lines = [
            "CASH RESERVE SUMMARY (pre-calculated in code — use these exact numbers, do not recompute):",
            "- Current reserve: \(summary.currentReserve.idrFormatted)",
            "- Average daily spend (last \(summary.windowDays) day\(summary.windowDays == 1 ? "" : "s")): \(summary.avgDailyExpense.idrFormatted)"
        ]
        if let runway = summary.runwayDays {
            lines.append("- Estimated runway at current pace: \(String(format: "%.0f", runway)) days")
        } else {
            lines.append("- Runway: not calculable yet (no spending pace established)")
        }
        return lines.joined(separator: "\n")
    }

    /// Self-reported at onboarding, never touched by CashReserveCalculator. Given to the
    /// AI purely for qualitative framing: encourage saving/growing savings beyond the
    /// income estimate, and warn against spending past the expense estimate — as targets
    /// to react to, not numbers to add into the reserve.
    private func formatProfileContext() -> String {
        var lines = ["USER PROFILE (self-reported, NOT logged transactions — use for tone and targets only):"]

        if let name = UserProfile.name {
            lines.append("- Name: \(name)")
        }
        if let status = UserProfile.status {
            lines.append("- Household status: \(status.rawValue)")
        }
        if let income = UserProfile.estimatedMonthlyIncome {
            lines.append("- Estimated monthly income (target, self-reported): \(income.idrFormatted)")
        }
        if let expense = UserProfile.estimatedMonthlyExpense {
            lines.append("- Estimated monthly expense budget (target, self-reported): \(expense.idrFormatted)")
        }
        if lines.count == 1 {
            lines.append("- No profile data available.")
        }
        return lines.joined(separator: "\n")
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: Errors now only in `AIChatView.swift` (references `showingIncomeEstimate`, `IncomeEstimateSheet`, hardcoded `userFirstName`) and `IncomeEstimateSheet.swift` itself (references deleted `UserFinancialProfile`). `AIChatViewModel.swift` and `CashReserveCalculator.swift` compile clean.

- [ ] **Step 3: Commit**

```bash
git add Monee/Features/AIBuddy/ViewModels/AIChatViewModel.swift
git commit -m "feat: gate AI reserve figure on transaction count, add separate profile context block"
```

---

### Task 4: Onboarding screen

**Files:**
- Create: `Monee/Features/Onboarding/UI/OnboardingView.swift`
- Delete: `Monee/Features/AIBuddy/UI/IncomeEstimateSheet.swift`

**Interfaces:**
- Consumes: `UserProfile` (Task 1) for writing `name`, `status`, `estimatedMonthlyIncome`, `estimatedMonthlyExpense`, `hasCompletedOnboarding`. Consumes `Transaction(title:amount:date:category:source:)` (existing model) and `ModelContext.insert`/`.save()` for the starting-balance transaction. Consumes `RelationshipStatus` (Task 1).
- Produces: `struct OnboardingView: View`, taking no required init parameters (reads `\.modelContext` and `AppContainer.self` from the environment), calling `AppContainer.shared.isUserOnboarded = true` on completion so `RootTabView` (Task 6) dismisses it without a relaunch.

- [ ] **Step 1: Delete the old sheet**

```bash
git rm Monee/Features/AIBuddy/UI/IncomeEstimateSheet.swift
```

- [ ] **Step 2: Write `OnboardingView.swift`**

```swift
//
//  OnboardingView.swift
//  Monee
//
//  Blocking, one-time flow shown from RootTabView before hasCompletedOnboarding is
//  true. Collects the profile fields the AI Buddy uses as qualitative context — Name,
//  Status, Current Balance, Estimated Monthly Income, Estimated Monthly Expense. None
//  of these numbers are mixed into CashReserveCalculator's arithmetic: Current Balance
//  is instead recorded as an ordinary "Starting Balance" Transaction, so the reserve
//  math never needs a special baseline case.
//
//  Name / Status / Estimated Income / Estimated Expense are required to finish.
//  Current Balance is optional (skippable, defaults to not creating a transaction at
//  all) — it exists for users who don't want to backdate their transaction history.
//
//  ⚠️ UI PLACEHOLDER — plain Form styling, functional only.
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    @State private var name: String = ""
    @State private var status: RelationshipStatus = .single
    @State private var currentBalanceText: String = ""
    @State private var estimatedIncomeText: String = ""
    @State private var estimatedExpenseText: String = ""

    private var canFinish: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Double(estimatedIncomeText) ?? 0 > 0
            && Double(estimatedExpenseText) ?? 0 > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A few details help your AI Buddy give grounded advice from day one.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Name") {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                }

                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(RelationshipStatus.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Current Balance (optional)") {
                    TextField("e.g. 2000000", text: $currentBalanceText)
                        .keyboardType(.decimalPad)
                    Text("If you don't want to log backdated transactions, enter what you have right now — it'll be recorded as a starting transaction.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Estimated Monthly Income") {
                    TextField("e.g. 5000000", text: $estimatedIncomeText)
                        .keyboardType(.decimalPad)
                }

                Section("Estimated Monthly Expense") {
                    TextField("e.g. 3000000", text: $estimatedExpenseText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Welcome to Monee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { finish() }
                        .disabled(!canFinish)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func finish() {
        UserProfile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        UserProfile.status = status
        UserProfile.estimatedMonthlyIncome = Double(estimatedIncomeText)
        UserProfile.estimatedMonthlyExpense = Double(estimatedExpenseText)

        if let startingBalance = Double(currentBalanceText), startingBalance > 0 {
            let transaction = Transaction(
                title: "Starting Balance",
                amount: startingBalance,
                date: Date(),
                category: .income,
                source: .manual
            )
            modelContext.insert(transaction)
            try? modelContext.save()
        }

        UserProfile.hasCompletedOnboarding = true
        appContainer.isUserOnboarded = true
    }
}

#Preview {
    OnboardingView()
        .environment(AppContainer.shared)
        .modelContainer(SwiftDataService.makePreviewContainer())
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: Errors remaining only in `AIChatView.swift` (Task 5) and `ProfileView.swift` (Task 7, still defining its own `RelationshipStatus`/using local `@State`). `OnboardingView.swift` compiles clean.

- [ ] **Step 4: Commit**

```bash
git add Monee/Features/Onboarding/UI/OnboardingView.swift
git rm Monee/Features/AIBuddy/UI/IncomeEstimateSheet.swift 2>/dev/null || true
git commit -m "feat: add full onboarding screen collecting profile + starting balance"
```

---

### Task 5: Wire `AIChatView` off the old income-estimate trigger

**Files:**
- Modify: `Monee/Features/AIBuddy/UI/AIChatView.swift`

**Interfaces:**
- Consumes: `UserProfile.name` (Task 1).

- [ ] **Step 1: Remove the old onboarding trigger and hardcoded name**

In `AIChatView.swift`:
- Delete the `@State private var showingIncomeEstimate = false` line (line 33).
- Delete the `.sheet(isPresented: $showingIncomeEstimate) { IncomeEstimateSheet() }` block (lines 82–84).
- Replace the `.task` block:

```swift
        .task {
            viewModel.bootstrap(modelContext: modelContext)
        }
```

- Replace the `userFirstName` property:

```swift
    var userFirstName: String { UserProfile.name ?? "there" }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: Errors remaining only in `ProfileView.swift` (Task 7). `AIChatView.swift` compiles clean.

- [ ] **Step 3: Commit**

```bash
git add Monee/Features/AIBuddy/UI/AIChatView.swift
git commit -m "refactor: drop lazy income-estimate sheet trigger from AIChatView, use UserProfile.name"
```

---

### Task 6: Show onboarding from the app root

**Files:**
- Modify: `Monee/App/ContentView.swift`

**Interfaces:**
- Consumes: `OnboardingView` (Task 4), `UserProfile.hasCompletedOnboarding` (Task 1), `AppContainer.isUserOnboarded` (existing).

- [ ] **Step 1: Add the full-screen cover**

Replace `RootTabView`'s body in `ContentView.swift`:

```swift
struct RootTabView: View {
    @State private var selectedTab: AppTab = .aiChat
    @Environment(AppContainer.self) private var appContainer

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Tracker", systemImage: "wallet.bifold.fill", value: AppTab.tracker) {
                TrackerView()
            }

            Tab("Profile", systemImage: "person.fill", value: AppTab.profile) {
                ProfileView()
            }

            Tab(value: AppTab.aiChat, role: .search) {
                AIChatView()
            } label: {
                Label("Monee", systemImage: "face.smiling")
            }
        }
        .task {
            appContainer.isUserOnboarded = UserProfile.hasCompletedOnboarding
        }
        .fullScreenCover(isPresented: Binding(
            get: { !appContainer.isUserOnboarded },
            set: { _ in }
        )) {
            OnboardingView()
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: Errors remaining only in `ProfileView.swift` (Task 7).

- [ ] **Step 3: Commit**

```bash
git add Monee/App/ContentView.swift
git commit -m "feat: show onboarding full-screen from app root until UserProfile.hasCompletedOnboarding"
```

---

### Task 7: `ProfileView` — persist through `UserProfile`, add estimate rows

**Files:**
- Modify: `Monee/Features/Profile/UI/ProfileView.swift`

**Interfaces:**
- Consumes: `UserProfile.name/.status/.estimatedMonthlyIncome/.estimatedMonthlyExpense` (Task 1), shared `RelationshipStatus` (Task 1, no longer defined locally).

- [ ] **Step 1: Replace local `@State` with `UserProfile`-backed state, remove the local enum, add estimate rows**

Replace lines 12–43 of `ProfileView.swift` (the `struct ProfileView` declaration through the end of `body`) with:

```swift
struct ProfileView: View {
    @Query private var transactions: [Transaction]

    @State private var name: String = UserProfile.name ?? ""
    @State private var status: RelationshipStatus = UserProfile.status ?? .single
    @State private var estimatedIncomeText: String = UserProfile.estimatedMonthlyIncome.map { String(Int($0)) } ?? ""
    @State private var estimatedExpenseText: String = UserProfile.estimatedMonthlyExpense.map { String(Int($0)) } ?? ""
    @State private var showingEditProfile = false

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient

                ScrollView {
                    VStack(spacing: 20) {
                        profileHeader

                        statusRow

                        estimatesSection

                        overviewSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView(name: $name)
            }
        }
        .onChange(of: name) { _, newValue in UserProfile.name = newValue }
        .onChange(of: status) { _, newValue in UserProfile.status = newValue }
    }

    // MARK: - Estimates

    private var estimatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Estimates")
                .font(.title3.bold())
                .padding(.leading, 4)

            VStack(spacing: 12) {
                estimateRow(title: "Estimated Monthly Income", text: $estimatedIncomeText) {
                    UserProfile.estimatedMonthlyIncome = Double($0)
                }
                estimateRow(title: "Estimated Monthly Expense", text: $estimatedExpenseText) {
                    UserProfile.estimatedMonthlyExpense = Double($0)
                }
            }
        }
    }

    private func estimateRow(title: String, text: Binding<String>, onCommit: @escaping (String) -> Void) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .onChange(of: text.wrappedValue) { _, newValue in onCommit(newValue) }
                .frame(width: 120)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
```

- [ ] **Step 2: Remove the duplicate `RelationshipStatus` enum**

Delete lines 227–234 of the original file (the `enum RelationshipStatus` block) — it now lives in `UserProfile.swift`.

- [ ] **Step 3: Build**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: BUILD SUCCEEDED — this was the last file with outstanding errors.

- [ ] **Step 4: Commit**

```bash
git add Monee/Features/Profile/UI/ProfileView.swift
git commit -m "feat: persist ProfileView name/status through UserProfile, add editable income/expense estimates"
```

---

### Task 8: End-to-end manual verification

**Files:** none (verification only)

- [ ] **Step 1: Run the app in Simulator**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'platform=iOS Simulator,name=iPhone 16' build` then launch via Xcode or `xcrun simctl launch booted <bundle-id>`.
Expected: On first launch (fresh Simulator or after `defaults delete <bundle-id>` / deleting the app), the onboarding screen appears full-screen and cannot be swiped away.

- [ ] **Step 2: Complete onboarding with a starting balance**

Enter Name "Test User", Status "Married with Kids", Current Balance `2000000`, Estimated Monthly Income `5000000`, Estimated Monthly Expense `3000000`. Tap Finish.
Expected: Onboarding dismisses, app shows the tab bar. Open the Tracker tab — a "Starting Balance" transaction dated today for Rp2.000.000 appears.

- [ ] **Step 3: Verify the reserve gate with few transactions**

Open AI Buddy, ask "what's my cash reserve?".
Expected: Reply says it doesn't have enough data yet and to log more transactions (1 transaction logged — the starting balance — so it should ask for 4 more) — it must NOT state a reserve number.

- [ ] **Step 4: Verify the reserve appears once past the threshold, and profile context is used qualitatively**

Log 4 more transactions (any mix of income/expense) via Tracker's add-transaction flow, so total = 5. Ask AI Buddy the same question, then ask "should I save more?".
Expected: First answer now states a real reserve figure equal to `startingBalance + loggedIncome − loggedExpenses` (verify the arithmetic by hand against what's in Tracker). Second answer references the estimated income/expense as targets (e.g. encourages saving beyond the Rp5.000.000 income estimate or flags spending against the Rp3.000.000 expense budget) without claiming those numbers came from logged transactions.

- [ ] **Step 5: Verify Profile tab persistence**

Go to Profile tab, change Status to "Single", force-quit the app, relaunch.
Expected: Status still reads "Single" (previously it reset to "Single" on every launch regardless — confirm it now actually persists the *chosen* value across relaunches, not just coincidentally showing the default).

---

## Self-Review

**Spec coverage:**
- Estimated monthly expense field added → Task 1, 4, 7. ✅
- Onboarding screen (Name, Status, Current Balance, Estimated Income, Estimated Expense) → Task 4. ✅
- Current balance recorded as a transaction instead of a special calc case → Task 4, Step 2. ✅
- Fields are context-only, never in the reserve calculation → Task 2 (calculator no longer accepts any estimate), Task 3 (`formatProfileContext` kept separate from `formatReserveSummary`). ✅
- Flat 5-transaction threshold gating the AI's reserve/runway statements → Task 2 (`minimumTransactionsForConfidence`), Task 3 (`formatReserveSummary` branch). ✅
- AI encourages saving beyond income estimate / warns against exceeding expense estimate → Task 3 (`formatProfileContext` labels), Task 9 below (prompt update) — **gap found and added as Task 9**.
- Status determines strict vs. forgiving tone → same gap, folded into Task 9.

**Placeholder scan:** No "TBD"/"handle appropriately" language found in the tasks above; all code blocks are complete.

**Type consistency:** `CashReserveSummary` fields (`hasEnoughData`, `transactionCount`) used identically in Task 2 (produced) and Task 3 (consumed). `UserProfile` static members used identically across Tasks 3, 4, 5, 6, 7. `RelationshipStatus` cases (`.single`, `.married`, `.marriedWithKids`) consistent across Tasks 1, 4, 7.

Adding the missing task found during self-review:

---

### Task 9: Update AI coaching-rules prompt for status tone + estimate framing

**Files:**
- Modify: `Monee/Features/AIBuddy/Logic/AppleIntelligenceAdapter.swift`

**Interfaces:**
- Consumes: nothing new — the profile context text (Task 3) is already interpolated into `fullPrompt`; this task only changes the static `coachingRules` instructions string so the model knows how to use it.

- [ ] **Step 1: Update `coachingRules`**

In `generateAdvice`, replace the `coachingRules` string (lines 51–75) with:

```swift
        let coachingRules = """
                        You are 'Freelancer Finance Buddy', a strict but empathetic financial coach for a self-employed user.

                        All amounts you are given, and all amounts you state back, are in Indonesian Rupiah (IDR) —
                        never dollars or any other currency. Numbers are already formatted as Rupiah (e.g. "Rp150.000")
                        in the data below; keep that formatting when you reference them.

                        YOUR CORE BEHAVIORS:
                        - Do not just give permission to spend money. Always challenge the user's spending habits gently.
                        - Ask proactive follow-up questions to force the user to justify their purchases (e.g., "Do you really need this right now?", "How will this purchase generate income for your freelance business?").
                        - Keep your answers concise, conversational, and easy to read. Do not output long essays.

                        YOU WILL BE GIVEN a CASH RESERVE SUMMARY, computed in code from real logged transactions.
                        If it says there isn't enough data yet, do NOT invent or estimate a reserve figure, runway,
                        or spending verdict — just tell the user plainly to log more transactions first. Once it
                        gives you real numbers, use them exactly as given, never redo the arithmetic yourself.
                        When the user mentions a specific purchase amount and you DO have a real reserve figure,
                        classify it plainly as one of:
                        - SAFE: leaves runway comfortably above ~14 days and doesn't meaningfully dent the reserve
                        - NEEDS ATTENTION: drops runway below ~14 days, or eats a large share of the reserve
                        - BAD: would take the reserve negative, or the reserve is already thin

                        YOU WILL ALSO BE GIVEN a USER PROFILE block — self-reported, not logged transactions.
                        Use it only qualitatively, never as arithmetic input to the reserve:
                        - Household status sets how strict vs. forgiving to be: "Single" — be more relaxed about
                          discretionary spending. "Married" — be moderately stricter, weigh shared household needs.
                          "Married with Kids" — be the strictest, prioritize stability and essential spending.
                        - If an estimated monthly income target is given, encourage the user to save and grow
                          their savings beyond that figure over time — treat it as a target to beat, not a fact
                          about their current reserve.
                        - If an estimated monthly expense budget is given, warn the user plainly when their
                          logged spending this month is approaching or exceeding it.
                        - Always make clear these profile numbers are self-reported targets, distinct from the
                          real, logged-transaction-based reserve figure — never present them as if they were
                          measured from actual transactions.

                        You will also be given recent expense and income transactions for qualitative color —
                        use these to explain patterns, not to recalculate totals.
                """
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manually re-verify Task 8 Step 4's second answer** ("should I save more?") — confirm the tone shifts if you change Status in Profile between "Single" and "Married with Kids" and ask again.

- [ ] **Step 4: Commit**

```bash
git add Monee/Features/AIBuddy/Logic/AppleIntelligenceAdapter.swift
git commit -m "feat: teach AI coaching prompt to use household status for tone and estimates as savings/spending targets"
```
