# Spare Money, Emergency Fund & Summary Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the blended "Cash Reserve" math with a fully-traceable "Spare Money" figure (`tracked income − tracked expenses − emergency fund`), add a user-managed emergency fund concept the AI references qualitatively, and ship a functional placeholder Summary screen (month-selectable expense pie chart + emergency fund progress + add-to-fund input) so the new math and AI responses can be tested end-to-end now, ahead of the design team's final visual pass.

**Architecture:** `UserProfile` gains a UserDefaults-backed `emergencyFundTotal` (additions-only running total) and a computed `emergencyFundTarget` (12× estimated monthly expense, `nil` until that estimate exists). `CashReserveCalculator` drops its income-blending fallback entirely, subtracts `emergencyFundTotal` as a third term, and flattens its confidence gate to a single transaction-count threshold. `AIChatViewModel` feeds the AI two independent context blocks — the gated Spare Money summary, and a separate, always-shown emergency fund status block — never blending the two. `AppleIntelligenceAdapter`'s coaching-rules prompt is updated to talk about "Spare Money" instead of "reserve" and to mention the emergency fund only when contextually relevant, not on a fixed schedule. A new `SummaryView` (plain, unstyled controls, following this codebase's existing "UI PLACEHOLDER" convention) becomes a fourth tab, reading `Transaction` data via `@Query` and rendering an expense-by-category pie chart with SwiftUI Charts' `SectorMark`.

**Tech Stack:** SwiftUI, SwiftData, SwiftUI Charts (`import Charts`, built into the SDK — no new dependency), Apple FoundationModels, UserDefaults.

## Global Constraints

- IDR (Indonesian Rupiah) only — matches existing `idrFormatted` / `.idr` format style scope. No other currencies.
- No XCTest target exists anywhere in this project (verified in prior plans: zero `XCTest` references in `project.pbxproj`, no `*Tests*` directories). Every task below verifies via **build + manual run in Simulator**, not automated tests. Do not create a new test target.
- Build command: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40` — this machine's `xcode-select` points at Command Line Tools, not full Xcode, so `DEVELOPER_DIR` must be set explicitly on every invocation.
- `emergencyFundTotal` is additions-only in this plan — no withdrawal/decrease flow. Never let it go negative (the setter clamps with `max(0, newValue)`).
- `emergencyFundTarget = 12 × estimatedMonthlyExpense`, and is `nil` (not 0 or a crash) when `UserProfile.estimatedMonthlyExpense` is `nil`.
- The Swift type names `CashReserveCalculator` / `CashReserveSummary` stay as-is — only their fields and math change. Every user-facing or AI-facing string calls the number "Spare Money," never "reserve."
- The AI's emergency-fund mention is contextual (folded into the model's own judgment), never a scheduled or every-response reminder — this is a prompt-instruction change, not new trigger/scheduling code.
- Summary screen's pie chart is **month-selectable**, defaulting to the current calendar month, covering expense transactions only (not income), grouped by `TransactionCategory`.
- This is a placeholder screen: plain controls, no restyling investment, but fully functional — not a throwaway. Follow the existing `⚠️ UI PLACEHOLDER` comment convention used elsewhere in this codebase (e.g. the original `IncomeEstimateSheet`).

---

## File Structure

| File | Change |
|---|---|
| `Monee/Core/Utilities/UserProfile.swift` | **Modify** — add `emergencyFundTotal: Double` (stored, clamped ≥0) and `emergencyFundTarget: Double?` (computed, 12× estimated monthly expense) |
| `Monee/Core/Utilities/CashReserveCalculator.swift` | **Modify** — remove income-blending fallback; `summarize` takes `emergencyFundTotal: Double` instead of `fallbackMonthlyIncome: Double?`; `CashReserveSummary.currentReserve`/`isDataSufficient`/`estimatedIncomeBlended` become `spareMoney`/`hasEnoughData` (blended field deleted) |
| `Monee/Features/AIBuddy/ViewModels/AIChatViewModel.swift` | **Modify** — `buildFinancialContext` calls the new `summarize` signature; `formatReserveSummary` renamed `formatSpareMoneySummary`, branches on `hasEnoughData`; new `formatEmergencyFundContext()` |
| `Monee/Features/AIBuddy/Logic/AppleIntelligenceAdapter.swift` | **Modify** — `coachingRules` string: "SPARE MONEY SUMMARY" language, emergency fund contextual-mention instruction |
| `Monee/Features/Summary/UI/SummaryView.swift` | **Create** — placeholder screen: month picker, expense-by-category pie chart (`Charts`), emergency fund progress, add-to-fund input |
| `Monee/App/ContentView.swift` (`RootTabView`) | **Modify** — add a fourth "Summary" tab between Tracker and Profile |

---

### Task 1: `UserProfile` emergency fund fields

**Files:**
- Modify: `Monee/Core/Utilities/UserProfile.swift`

**Interfaces:**
- Produces: `UserProfile.emergencyFundTotal: Double` (get/set, UserDefaults-backed, clamped to `>= 0`, defaults to `0` when unset). Produces: `UserProfile.emergencyFundTarget: Double?` (computed, `12 * estimatedMonthlyExpense`, `nil` when `estimatedMonthlyExpense` is `nil`). Consumed by: `CashReserveCalculator` call sites in `AIChatViewModel` (Task 3) and `SummaryView` (Task 5).

- [ ] **Step 1: Add the new properties**

In `Monee/Core/Utilities/UserProfile.swift`, add a new key constant alongside the existing ones:

```swift
    private static let emergencyFundTotalKey = "userProfile.emergencyFundTotal"
```

Add these two new static properties, right after `estimatedMonthlyExpense` and before `hasCompletedOnboarding`:

```swift
    /// Additions-only running total the user has manually set aside as an emergency
    /// fund — never mixed into CashReserveCalculator's income/expense sums directly,
    /// but subtracted from them as its own term (see CashReserveCalculator.summarize).
    /// Clamped to non-negative; this app has no withdrawal flow yet.
    static var emergencyFundTotal: Double {
        get { UserDefaults.standard.double(forKey: emergencyFundTotalKey) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: emergencyFundTotalKey) }
    }

    /// 12x the user's estimated monthly expense. `nil` until that estimate exists —
    /// there's nothing meaningful to show a fill percentage against otherwise.
    static var emergencyFundTarget: Double? {
        guard let expense = estimatedMonthlyExpense else { return nil }
        return expense * 12
    }
```

- [ ] **Step 2: Update the file's header comment**

The existing header comment says "never mixed into CashReserveCalculator's arithmetic beyond the existing fallback-blend behavior" — that fallback-blend behavior is removed in Task 2, so replace the full header comment block at the top of the file:

```swift
//
//  UserProfile.swift
//  Monee
//
//  Single source of truth for onboarding-collected, self-reported profile data,
//  plus the user-managed emergency fund total. None of these numbers are ever
//  mixed into CashReserveCalculator's income/expense arithmetic directly — the
//  fund total is subtracted as its own explicit term (see CashReserveCalculator
//  .summarize), and the profile estimates are handed to the AI as separate,
//  always-labeled qualitative context (see AIChatViewModel.formatEmergencyFundContext
//  and formatSpareMoneySummary). UserDefaults-backed so it's readable from a plain
//  class (AIChatViewModel), not just SwiftUI views.
//
```

- [ ] **Step 3: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: BUILD SUCCEEDED — this task only adds new properties, nothing yet calls them.

- [ ] **Step 4: Commit**

```bash
git add Monee/Core/Utilities/UserProfile.swift
git commit -m "feat: add emergencyFundTotal and computed emergencyFundTarget to UserProfile"
```

---

### Task 2: `CashReserveCalculator` becomes the Spare Money calculation

**Files:**
- Modify: `Monee/Core/Utilities/CashReserveCalculator.swift`

**Interfaces:**
- Consumes: `Transaction` (existing model, `amount: Double`, `date: Date`, `isIncome: Bool`).
- Produces: `CashReserveCalculator.summarize(transactions: [Transaction], emergencyFundTotal: Double) -> CashReserveSummary`. Produces: `CashReserveCalculator.minimumTransactionsForConfidence: Int = 5`. Produces: `CashReserveSummary` with fields `spareMoney: Double`, `avgDailyExpense: Double`, `runwayDays: Double?`, `windowDays: Int`, `expenseCount: Int`, `transactionCount: Int`, `hasEnoughData: Bool`. Consumed by: `AIChatViewModel` (Task 3), `SummaryView` (Task 5).

- [ ] **Step 1: Rewrite the file**

Replace the full contents of `Monee/Core/Utilities/CashReserveCalculator.swift`:

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
//  Spare Money = tracked income - tracked expenses - the user's emergency fund total.
//  Deliberately does NOT blend in any self-reported income estimate — that number lives
//  in UserProfile and is handed to the AI as separate qualitative context (see
//  AIChatViewModel.formatSpareMoneySummary / formatEmergencyFundContext). Blending used
//  to happen here; it produced figures that looked arbitrary to the user once few
//  transactions were logged. This file now answers exactly one question: what do the
//  user's logged transactions (and their own emergency fund contributions) say is
//  actually free to spend, and is there enough logged history to trust the answer.
//

import Foundation

struct CashReserveSummary {
    let spareMoney: Double           // tracked income - tracked expenses - emergency fund total
    let avgDailyExpense: Double      // trailing window average (up to 30 days of history)
    let runwayDays: Double?          // spareMoney / avgDailyExpense; nil if no spend pace yet
    let windowDays: Int              // how many days avgDailyExpense is actually based on
    let expenseCount: Int
    let transactionCount: Int        // income + expenses combined — what the confidence gate checks
    /// True once the user has logged CashReserveCalculator.minimumTransactionsForConfidence
    /// or more transactions (of any kind). Below this, the AI should not state a Spare Money
    /// figure, runway, or spending verdict — just encourage logging more.
    let hasEnoughData: Bool
}

enum CashReserveCalculator {
    /// Below this many total logged transactions, the Spare Money/runway numbers are
    /// considered too thin to state to the user. A flat count, not a compound
    /// date+count rule — simpler to reason about and to explain in the UI.
    static let minimumTransactionsForConfidence = 5

    static func summarize(transactions: [Transaction], emergencyFundTotal: Double) -> CashReserveSummary {
        let income = transactions.filter { $0.isIncome }
        let expenses = transactions.filter { !$0.isIncome }

        let totalIncome = income.reduce(0) { $0 + $1.amount }
        let totalExpenses = expenses.reduce(0) { $0 + $1.amount }
        let spareMoney = totalIncome - totalExpenses - emergencyFundTotal

        // Trailing-window burn rate — the more real history exists, the more this
        // smooths out one-off spikes instead of one big purchase skewing everything.
        let now = Date()
        let earliestExpenseDate = expenses.map(\.date).min() ?? now
        let daysOfHistory = max(1, Int(now.timeIntervalSince(earliestExpenseDate) / 86_400))
        let window = min(daysOfHistory, 30)
        let windowStart = now.addingTimeInterval(-Double(window) * 86_400)
        let recentTotal = expenses.filter { $0.date >= windowStart }.reduce(0) { $0 + $1.amount }
        let avgDailyExpense = window > 0 ? recentTotal / Double(window) : 0

        let runwayDays: Double? = avgDailyExpense > 0 ? spareMoney / avgDailyExpense : nil

        return CashReserveSummary(
            spareMoney: spareMoney,
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

- [ ] **Step 2: Build to confirm expected (pre-existing) errors only**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: Errors only in `AIChatViewModel.swift` (fixed in Task 3) — it still calls the old `summarize(transactions:fallbackMonthlyIncome:)` signature and references `.currentReserve`/`.isDataSufficient`/`.estimatedIncomeBlended`, all now gone. No errors inside `CashReserveCalculator.swift` itself.

- [ ] **Step 3: Commit**

```bash
git add Monee/Core/Utilities/CashReserveCalculator.swift
git commit -m "refactor: drop income blending from CashReserveCalculator, compute Spare Money with emergency fund subtracted"
```

---

### Task 3: `AIChatViewModel` — Spare Money summary + emergency fund context

**Files:**
- Modify: `Monee/Features/AIBuddy/ViewModels/AIChatViewModel.swift`

**Interfaces:**
- Consumes: `CashReserveCalculator.summarize(transactions:emergencyFundTotal:) -> CashReserveSummary` and `CashReserveCalculator.minimumTransactionsForConfidence` (Task 2). Consumes: `UserProfile.emergencyFundTotal`, `UserProfile.emergencyFundTarget`, `UserProfile.estimatedMonthlyIncome` (Task 1 + existing).
- Produces: `buildFinancialContext(using:)` unchanged signature. Produces: `formatSpareMoneySummary(_:) -> String` (replaces `formatReserveSummary`). Produces: `formatEmergencyFundContext() -> String` (new).

- [ ] **Step 1: Replace `buildFinancialContext` and `formatReserveSummary`**

Replace lines 117-199 of `AIChatViewModel.swift` (from the `beginSession` closing brace's following blank line through the end of `formatReserveSummary`, i.e. everything from the `/// Builds the financial context...` doc comment through the closing brace of the old `formatReserveSummary`) with:

```swift
    /// Builds the financial context handed to the AI. Two independent pieces:
    /// (1) the deterministic Spare Money summary, computed only from logged
    /// transactions and the user's own emergency fund total — no self-reported
    /// number is ever mixed into this arithmetic; (2) the user's emergency fund
    /// status, always shown but always labeled as self-managed/qualitative,
    /// never treated as a second use of the number already subtracted in (1).
    private func buildFinancialContext(using context: ModelContext) throws -> String {
        let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let all = try context.fetch(descriptor)

        let expenses = all.filter { !$0.isIncome }
        let incomeTxns = all.filter { $0.isIncome }

        var sections: [String] = []

        // Pre-calculated — never let the AI redo this math itself.
        let summary = CashReserveCalculator.summarize(
            transactions: all,
            emergencyFundTotal: UserProfile.emergencyFundTotal
        )
        sections.append(formatSpareMoneySummary(summary))
        sections.append(formatEmergencyFundContext())

        if expenses.isEmpty {
            sections.append("EXPENSES: No expenses logged yet.")
        } else {
            let shown = expenses.prefix(15)
            let lines = shown.map { txn in
                "- \(txn.date.formatted(date: .abbreviated, time: .omitted)): \(txn.title) (\(txn.amount.idrFormatted))"
            }.joined(separator: "\n")
            sections.append("EXPENSES (\(expenses.count) logged total, showing \(shown.count) most recent):\n\(lines)")
        }

        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86_400)
        let recentIncomeCount = incomeTxns.filter { $0.date > thirtyDaysAgo }.count

        if recentIncomeCount >= 3 {
            let shown = incomeTxns.prefix(10)
            let lines = shown.map { txn in
                "- \(txn.date.formatted(date: .abbreviated, time: .omitted)): \(txn.title) (\(txn.amount.idrFormatted))"
            }.joined(separator: "\n")
            sections.append("INCOME (\(incomeTxns.count) logged total, showing \(shown.count) most recent):\n\(lines)")
        } else if let estimate = UserProfile.estimatedMonthlyIncome {
            sections.append("""
            INCOME: Only \(recentIncomeCount) income transaction(s) logged in the last 30 days — not enough to trust. \
            The user SELF-REPORTED an estimated monthly income of \(estimate.idrFormatted) during setup. \
            Treat this as a rough, possibly outdated guess, not observed fact — say so plainly if you rely on it.
            """)
        } else {
            sections.append("INCOME: No income data available — no transactions logged and no estimate provided. Do not assume any income figure; ask the user directly if you need one.")
        }

        return sections.joined(separator: "\n\n")
    }

    /// The AI is only allowed to state a Spare Money/runway figure or a spending
    /// verdict once there's enough logged history to trust it — below the threshold,
    /// it should just encourage the user to log more, not guess with a thin sample.
    private func formatSpareMoneySummary(_ summary: CashReserveSummary) -> String {
        guard summary.hasEnoughData else {
            let remaining = CashReserveCalculator.minimumTransactionsForConfidence - summary.transactionCount
            return """
            SPARE MONEY SUMMARY: Not enough data yet — only \(summary.transactionCount) transaction(s) logged. \
            Log \(remaining) more (backdated entries are fine) before stating a Spare Money figure, runway, or \
            spending verdict. Do not compute or guess a number — tell the user plainly to log more transactions \
            first so future advice is reliable.
            """
        }

        var lines = [
            "SPARE MONEY SUMMARY (pre-calculated in code — use these exact numbers, do not recompute):",
            "- Spare Money: \(summary.spareMoney.idrFormatted)",
            "- Average daily spend (last \(summary.windowDays) day\(summary.windowDays == 1 ? "" : "s")): \(summary.avgDailyExpense.idrFormatted)"
        ]
        if let runway = summary.runwayDays {
            lines.append("- Estimated runway at current pace: \(String(format: "%.0f", runway)) days")
        } else {
            lines.append("- Runway: not calculable yet (no spending pace established)")
        }
        return lines.joined(separator: "\n")
    }

    /// Self-managed by the user (added manually, additions-only), already subtracted
    /// out of Spare Money above — this block is purely qualitative status for the AI
    /// to reference when relevant (see AppleIntelligenceAdapter's coaching rules),
    /// never a second use of the number in arithmetic.
    private func formatEmergencyFundContext() -> String {
        let total = UserProfile.emergencyFundTotal
        guard let target = UserProfile.emergencyFundTarget else {
            return """
            EMERGENCY FUND: No target set yet — the user hasn't provided an estimated monthly expense, \
            which the target (12x that estimate) depends on. If relevant, encourage them to complete that \
            estimate in Profile so their emergency fund progress can be tracked.
            """
        }
        let percent = min(100, Int((total / target) * 100))
        return """
        EMERGENCY FUND (self-managed by the user, already subtracted out of Spare Money above — \
        this is qualitative status only, not a second use of that number):
        - Current: \(total.idrFormatted)
        - Target (12x estimated monthly expense): \(target.idrFormatted)
        - Percent filled: \(percent)%
        """
    }
```

- [ ] **Step 2: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: BUILD SUCCEEDED — no other file references the old `formatReserveSummary`, `.currentReserve`, `.isDataSufficient`, or `.estimatedIncomeBlended`.

- [ ] **Step 3: Commit**

```bash
git add Monee/Features/AIBuddy/ViewModels/AIChatViewModel.swift
git commit -m "feat: replace blended reserve summary with Spare Money + separate emergency fund context in AIChatViewModel"
```

---

### Task 4: Update AI coaching-rules prompt for Spare Money + contextual emergency fund mentions

**Files:**
- Modify: `Monee/Features/AIBuddy/Logic/AppleIntelligenceAdapter.swift`

**Interfaces:**
- Consumes: nothing new — the Spare Money and emergency fund context text (Task 3) is already interpolated into `fullPrompt` via `systemContext`; this task only changes the static `coachingRules` string so the model knows how to use it.

- [ ] **Step 1: Replace the `coachingRules` string**

In `generateAdvice` (`Monee/Features/AIBuddy/Logic/AppleIntelligenceAdapter.swift`), replace the `coachingRules` string (currently lines 51-75) with:

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

                        YOU WILL BE GIVEN a SPARE MONEY SUMMARY with pre-calculated numbers (Spare Money —
                        tracked income minus tracked expenses minus the user's emergency fund — average daily
                        spend, and runway). These are computed correctly in code — use them exactly as given,
                        never redo the arithmetic yourself. If it says there isn't enough data yet, do NOT invent
                        or estimate a Spare Money figure, runway, or spending verdict — just tell the user plainly
                        to log more transactions first. Once it gives you real numbers, when the user mentions a
                        specific purchase amount, classify it plainly as one of:
                        - SAFE: leaves runway comfortably above ~14 days and doesn't meaningfully dent Spare Money
                        - NEEDS ATTENTION: drops runway below ~14 days, or eats a large share of Spare Money
                        - BAD: would take Spare Money negative, or it's already thin
                        State the tier and back it with the actual numbers you were given.

                        YOU WILL ALSO BE GIVEN an EMERGENCY FUND block — self-managed by the user, already
                        subtracted out of Spare Money, given to you purely as qualitative status. Bring it up
                        only when it's actually relevant to what the user is asking — a spending decision, a
                        savings question, or them asking about their financial standing — not as a scheduled or
                        every-response reminder. When it IS relevant and the fund isn't yet at 100%, you can
                        encourage them with something like "Don't forget to add to your emergency fund — once
                        it fills up you'll have more spare money to allocate!" but don't force this into
                        unrelated answers (e.g. a question purely about which category they spent most on this
                        month doesn't need an emergency fund mention).

                        You will also be given recent expense and income transactions for qualitative color —
                        use these to explain patterns, not to recalculate totals.
                """
```

- [ ] **Step 2: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Monee/Features/AIBuddy/Logic/AppleIntelligenceAdapter.swift
git commit -m "feat: teach AI coaching prompt to talk about Spare Money and mention emergency fund contextually"
```

---

### Task 5: Placeholder `SummaryView`

**Files:**
- Create: `Monee/Features/Summary/UI/SummaryView.swift`

**Interfaces:**
- Consumes: `Transaction` (existing `@Model`, queried via `@Query`), `TransactionCategory` (existing, has `.tint: Color`), `CashReserveCalculator.summarize(transactions:emergencyFundTotal:) -> CashReserveSummary` (Task 2), `UserProfile.emergencyFundTotal`/`.emergencyFundTarget` (Task 1), `FloatingPointFormatStyle<Double>.Currency.idr` (existing, `Monee/Core/Utilities/CurrencyFormat.swift`).
- Produces: `struct SummaryView: View`, no required init parameters (reads `@Query` and `UserProfile` directly). Consumed by `RootTabView` (Task 6).

- [ ] **Step 1: Write `SummaryView.swift`**

```swift
//
//  SummaryView.swift
//  Monee
//
//  Fourth tab: month-selectable expense-by-category pie chart, emergency fund
//  progress, and a manual add-to-fund input. The design team will restyle this
//  screen later — this implements the real data contract now (month filtering,
//  Spare Money math, emergency fund total/target) so the underlying logic can be
//  tested ahead of that visual pass.
//
//  ⚠️ UI PLACEHOLDER: everything here is functional-only styling. UI team —
//  restyle freely; the @Query, CashReserveCalculator, and UserProfile calls are
//  the only real contracts this depends on.
//

import SwiftUI
import SwiftData
import Charts

struct SummaryView: View {
    @Query private var transactions: [Transaction]

    @State private var selectedMonth: Date = Date()
    @State private var emergencyFundTotal: Double = UserProfile.emergencyFundTotal
    @State private var addFundText: String = ""

    private var spareMoneySummary: CashReserveSummary {
        CashReserveCalculator.summarize(transactions: transactions, emergencyFundTotal: emergencyFundTotal)
    }

    private var categoryTotals: [(category: TransactionCategory, total: Double)] {
        let calendar = Calendar.current
        let monthExpenses = transactions.filter { txn in
            !txn.isIncome && calendar.isDate(txn.date, equalTo: selectedMonth, toGranularity: .month)
        }
        let grouped = Dictionary(grouping: monthExpenses, by: { $0.category })
        return grouped
            .map { (category: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Month") {
                    DatePicker(
                        "Month",
                        selection: $selectedMonth,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                }

                Section("Spare Money") {
                    LabeledContent("Spare Money") {
                        Text(spareMoneySummary.spareMoney, format: .idr)
                    }
                    if !spareMoneySummary.hasEnoughData {
                        Text("Not enough data yet — log \(CashReserveCalculator.minimumTransactionsForConfidence - spareMoneySummary.transactionCount) more transaction(s) for a reliable figure.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Expenses by Category") {
                    if categoryTotals.isEmpty {
                        Text("No expenses logged for this month.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(categoryTotals, id: \.category) { item in
                            SectorMark(
                                angle: .value("Amount", item.total),
                                innerRadius: .ratio(0.5),
                                angularInset: 1.5
                            )
                            .foregroundStyle(item.category.tint)
                            .cornerRadius(4)
                        }
                        .frame(height: 220)

                        ForEach(categoryTotals, id: \.category) { item in
                            LabeledContent(item.category.rawValue) {
                                Text(item.total, format: .idr)
                            }
                        }
                    }
                }

                Section("Emergency Fund") {
                    if let target = UserProfile.emergencyFundTarget {
                        ProgressView(value: min(emergencyFundTotal, target), total: target) {
                            Text("\(Int(min(100, (emergencyFundTotal / target) * 100)))% filled")
                        }
                        LabeledContent("Current") {
                            Text(emergencyFundTotal, format: .idr)
                        }
                        LabeledContent("Target (12x estimated monthly expense)") {
                            Text(target, format: .idr)
                        }
                    } else {
                        Text("Set an Estimated Monthly Expense in Profile to calculate a target.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        TextField("Add amount", text: $addFundText)
                            .keyboardType(.decimalPad)
                        Button("Add") {
                            addToFund()
                        }
                        .disabled(Double(addFundText) == nil || Double(addFundText) == 0)
                    }
                }
            }
            .navigationTitle("Summary")
            .dismissKeyboardOnTap()
        }
    }

    private func addToFund() {
        guard let amount = Double(addFundText), amount > 0 else { return }
        let newTotal = emergencyFundTotal + amount
        UserProfile.emergencyFundTotal = newTotal
        emergencyFundTotal = newTotal
        addFundText = ""
    }
}

#Preview {
    SummaryView()
        .modelContainer(SwiftDataService.makePreviewContainer(seeded: true))
}
```

- [ ] **Step 2: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Monee/Features/Summary/UI/SummaryView.swift
git commit -m "feat: add placeholder Summary screen with monthly expense pie chart and emergency fund progress"
```

---

### Task 6: Wire the Summary tab into `RootTabView`

**Files:**
- Modify: `Monee/App/ContentView.swift`

**Interfaces:**
- Consumes: `SummaryView()` (Task 5, no-arg init).

- [ ] **Step 1: Add the tab**

Replace the full contents of `Monee/App/ContentView.swift`:

```swift
//
//  ContentView.swift
//  FreelanceFinance
//
//  App root: four-tab shell (Tracker / Summary / Profile / AI Buddy). The old
//  single-screen Dashboard this file used to hold was retired once TrackerView +
//  ProfileView (real, design-provided views) replaced it.
//
//  Updated 07/07/26 — added a non-dismissable fullScreenCover showing OnboardingView
//  until UserProfile.hasCompletedOnboarding is true, synced into AppContainer on launch
//  so the same in-memory flag OnboardingView already flips on completion works without
//  a relaunch.
//
//  Updated 07/07/26 — added the Summary tab (placeholder UI) between Tracker and
//  Profile, surfacing the new Spare Money + emergency fund + expense pie chart.
//

import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case tracker
    case summary
    case profile
    case aiChat
}

struct RootTabView: View {
    @State private var selectedTab: AppTab = .aiChat
    @Environment(AppContainer.self) private var appContainer

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Tracker", systemImage: "wallet.bifold.fill", value: AppTab.tracker) {
                TrackerView()
            }

            Tab("Summary", systemImage: "chart.pie.fill", value: AppTab.summary) {
                SummaryView()
            }

            Tab("Profile", systemImage: "person.fill", value: AppTab.profile) {
                ProfileView()
            }


            Tab(value: AppTab.aiChat, role: .search) {
                AIChatView()
            } label: {
                Label("Monee",systemImage: "face.smiling")
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

#Preview {
    RootTabView()
        .modelContainer(SwiftDataService.makePreviewContainer(seeded: true))
        .environment(AppContainer.shared)
}
```

- [ ] **Step 2: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Monee/App/ContentView.swift
git commit -m "feat: add Summary tab to RootTabView between Tracker and Profile"
```

---

### Task 7: Manual verification — Spare Money math, emergency fund, AI responses, Summary screen

**Files:** none (verification only)

- [ ] **Step 1: Build and launch in Simulator**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'platform=iOS Simulator,name=iPhone 16' build`, then launch via Xcode.
Expected: App launches to the tab bar (already onboarded from prior work), now showing four tabs: Tracker, Summary, Profile, Monee.

- [ ] **Step 2: Verify the "not enough data" gate**

With fewer than 5 total transactions logged, open AI Buddy and ask "what's my spare money?"
Expected: The AI states it doesn't have enough data yet and asks for more transactions — it must NOT state a Spare Money figure.

- [ ] **Step 3: Verify Spare Money arithmetic once past the threshold**

Log transactions (via Tracker's add-transaction flow) until at least 5 total exist, noting the total income and total expense amounts entered. Ask AI Buddy "what's my spare money?" again.
Expected: The stated Spare Money figure equals `totalIncome - totalExpenses - 0` (emergency fund still empty) — verify the arithmetic by hand.

- [ ] **Step 4: Verify emergency fund subtraction**

Open the Summary tab. In the Emergency Fund section, add an amount (e.g. `500000`) via the "Add amount" field and tap "Add".
Expected: The Emergency Fund section's "Current" value updates to `500000`, and the progress bar reflects it against the target (or shows the "set an estimate" message if no `estimatedMonthlyExpense` exists yet). Ask AI Buddy "what's my spare money?" again.
Expected: The new Spare Money figure is exactly `500000` lower than in Step 3.

- [ ] **Step 5: Verify emergency fund target math**

In Profile, confirm (or set) an Estimated Monthly Expense value, e.g. `3000000`. Return to the Summary tab.
Expected: The Emergency Fund target reads exactly `36000000` (12 × 3.000.000), and the percent-filled bar matches `emergencyFundTotal / target`.

- [ ] **Step 6: Verify the monthly pie chart**

In the Summary tab, with expenses logged in the current month across at least two different categories, confirm the pie chart renders a slice per category and the list below it shows matching totals per category. Change the month picker to a month with no logged expenses.
Expected: The chart section shows "No expenses logged for this month" instead of an empty or broken chart.

- [ ] **Step 7: Verify contextual (not scheduled) emergency fund mentions**

With the emergency fund below 100% filled, ask AI Buddy an unrelated question like "what category did I spend the most on this month?"
Expected: The AI answers the category question without forcing an emergency fund reminder into every response. Then ask "should I buy something for Rp200.000 right now?"
Expected: The AI's answer may reasonably reference the emergency fund (e.g. encouraging contributing to it) since this is a spending-decision question — confirming the prompt's contextual instruction is being followed, not ignored entirely.

No commit for this task — verification only, no files changed.

---

## Self-Review

**Spec coverage:**
- `UserProfile.emergencyFundTotal` (additions-only, clamped ≥0) and `emergencyFundTarget` (12× estimated monthly expense, nil-safe) → Task 1. ✅
- `CashReserveCalculator` drops blending, subtracts emergency fund, flattens confidence gate to `transactionCount >= 5` → Task 2. ✅
- `CashReserveCalculator`/`CashReserveSummary` names kept, only fields/math changed → Task 2 (verified: enum/struct names unchanged). ✅
- AI context: Spare Money summary (gated) + separate always-shown emergency fund block, never blended → Task 3 (`formatSpareMoneySummary` + `formatEmergencyFundContext`, called independently in `buildFinancialContext`). ✅
- AI prompt: "Spare Money" language throughout, emergency fund mentioned contextually not on a schedule → Task 4. ✅
- Summary screen: month-selectable pie chart (expenses only, grouped by category), emergency fund progress, add-to-fund input, placeholder-labeled → Task 5. ✅
- Fourth tab wired in, Tracker → Summary → Profile → Monee order → Task 6. ✅
- End-to-end manual verification of math, gating, contextual AI behavior, and the Summary screen (no XCTest target) → Task 7. ✅

**Placeholder scan:** No "TBD"/"handle appropriately" language in any task; all code blocks are complete and copy-pasteable.

**Type consistency:** `CashReserveSummary` fields (`spareMoney`, `hasEnoughData`, `transactionCount`) used identically in Task 2 (produced) and Tasks 3, 5 (consumed). `CashReserveCalculator.summarize(transactions:emergencyFundTotal:)` signature used identically in Task 2 (defined), Task 3 (`AIChatViewModel`), Task 5 (`SummaryView`). `UserProfile.emergencyFundTotal`/`.emergencyFundTarget` used identically across Tasks 1, 3, 5. `SummaryView()` no-arg init used identically in Task 5 (defined) and Task 6 (consumed).
