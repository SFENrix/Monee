# Spare Money, Emergency Funds & Summary Screen — Design

**Goal:** Replace the existing blended "Cash Reserve" math with a simpler, fully-traceable "Spare Money" figure that also accounts for a new user-managed "emergency fund" concept, and define the data/logic layer a forthcoming design-team-built "Summary" screen (monthly expense pie chart + emergency fund progress) will consume.

**Scope boundary:** The Summary screen's actual UI is being built separately by the design team. This spec defines everything beneath it — the data model, the math, and the AI integration — so that wiring the real screen in later is mechanical, not a redesign. Nothing in this spec proposes visual layout for the new screen.

## Background

Today, `CashReserveCalculator.summarize(transactions:fallbackMonthlyIncome:)` (`Monee/Core/Utilities/CashReserveCalculator.swift`) computes a "Current Reserve" that blends in a self-reported income estimate when logged income has fewer than 3 transactions, pro-rated over days of history. Confidence (`isDataSufficient`) requires ≥5 expenses **and** ≥7 days of history. `AIChatViewModel.buildFinancialContext` (`Monee/Features/AIBuddy/ViewModels/AIChatViewModel.swift`) feeds this into the AI as a "CASH RESERVE SUMMARY," and `AppleIntelligenceAdapter`'s coaching rules (`Monee/Features/AIBuddy/Logic/AppleIntelligenceAdapter.swift`) instruct the model to classify purchases against it (SAFE/NEEDS ATTENTION/BAD).

This design replaces that blended figure with **Spare Money** — a number fully traceable to logged transactions plus one new self-managed quantity (the emergency fund), never a blended guess.

## 1. Emergency Fund Store

A new running total on the existing `UserProfile` store (`Monee/Core/Utilities/UserProfile.swift`), following its existing UserDefaults-backed static-property pattern:

- `UserProfile.emergencyFundTotal: Double` — starts at 0 (default when unset). Increased only through an explicit, user-initiated "add to fund" action inside the app (UI TBD from design team). Never decreases automatically and never goes negative — this spec does not define a withdrawal flow; if the design team's screen needs one later, that's a follow-up spec.
- `UserProfile.emergencyFundTarget: Double?` — **computed, not stored.** `12 × estimatedMonthlyExpense` when `UserProfile.estimatedMonthlyExpense` is set, else `nil`. When `nil`, there is no target to show a percentage against — both the AI context and (whatever UI the design team builds) must treat this the same way the rest of the app treats "not enough data yet": encourage completing the expense estimate rather than displaying a nonsensical 0-target percentage.

No new SwiftData model, no schema change. This deliberately avoids the alternative of a special `TransactionCategory` case, which would require every current and future expense-summing call site (Tracker list totals, `ProfileView.averageMonthly`, the new pie chart, `CashReserveCalculator`, `AIChatViewModel`) to remember to filter it out — a running total on `UserProfile` can't leak into transaction sums because it was never a transaction.

## 2. Spare Money Math

`CashReserveCalculator.swift` changes in two ways simultaneously (this folds in the income-blending removal that was already discussed and never implemented, plus the new emergency-fund term):

- **Drop blending entirely.** `fallbackMonthlyIncome` parameter is removed. `trackedIncome` and `trackedExpenses` are plain sums over all logged transactions — no self-reported number ever enters this arithmetic.
- **Subtract the emergency fund.** `spareMoney = trackedIncome − trackedExpenses − UserProfile.emergencyFundTotal`.
- **Flatten the confidence gate.** Replace `isDataSufficient` (≥5 expenses AND ≥7 days span) with `hasEnoughData = transactionCount >= 5` (total transactions, income or expense, no date-span condition) — a single named constant `CashReserveCalculator.minimumTransactionsForConfidence = 5`, not a scattered literal.

`CashReserveSummary` fields change from `currentReserve`/`isDataSufficient`/`estimatedIncomeBlended` to `spareMoney`/`hasEnoughData` (the `estimatedIncomeBlended` field is deleted outright — there's nothing left to blend, so there's nothing to disclose). `avgDailyExpense`/`runwayDays`/`windowDays`/`expenseCount` keep their existing trailing-30-day-window behavior unchanged.

**Naming:** the Swift type names `CashReserveCalculator`/`CashReserveSummary` are kept as-is to minimize churn across the codebase (both are internal implementation names). Every user-facing and AI-facing surface — prompt text, any UI label — calls this number "Spare Money," never "reserve."

## 3. AI Buddy Integration

`AIChatViewModel.buildFinancialContext` changes to:

- Call `CashReserveCalculator.summarize(transactions:)` (no `fallbackMonthlyIncome` argument).
- `formatReserveSummary` (renamed in spirit, not necessarily in code, to reflect Spare Money) branches on `hasEnoughData` exactly like the existing "not enough data" gating pattern already used elsewhere in this file — below the threshold, the AI is told plainly to ask the user to log more transactions, never to guess.
- A new context block reports emergency fund status: current total, target (or "not set — expense estimate needed" if `nil`), and percent filled (0 when no target). This is self-reported/computed data, always labeled as such, following the same pattern as the existing profile-context block — never blended into `spareMoney`'s arithmetic (it's already subtracted there as its own term, so this block is purely informational framing for the AI, not a second use of the number).

`AppleIntelligenceAdapter`'s `coachingRules` string is updated:

- Replace "CASH RESERVE SUMMARY" / "current reserve" language with "SPARE MONEY SUMMARY" / "Spare Money" throughout, keeping the same SAFE / NEEDS ATTENTION / BAD purchase-classification instructions (now evaluated against Spare Money instead of the old blended reserve).
- Add instructions for the new emergency fund block: when the fund isn't yet at 100%, the AI **may** mention it — but only when contextually relevant (the user asks about spending, saving, or a purchase decision), not as a scheduled or every-response reminder. This is a judgment instruction added to the existing "core behaviors" list, the same way the existing purchase-challenging behavior is phrased — not a separate trigger mechanism, since there's no scheduling logic in this app to hook into (each AI call is already stateless/session-per-call, per the existing `AppleIntelligenceAdapter` design).

## 4. Summary Screen's Data Contract

The design team owns the actual screen; this section defines what it will read.

- **Expense-by-category pie chart, month-selectable.** A selected-month state (defaults to the current calendar month) drives a `Dictionary(grouping:)` over that month's expense transactions by `TransactionCategory`, summed per category — the same grouping technique `ProfileView.averageMonthly` already uses via `Calendar.dateComponents([.year, .month], from:)`, but filtering to one specific year+month instead of averaging across all of them. This produces the `[TransactionCategory: Double]` (or equivalent ordered pair list) the pie chart renders from.
- **Emergency fund progress:** current total, target (or nil), percent filled — the same three values computed in §1/§3, exposed for display.
- **Spare Money figure:** for display alongside the pie chart.

This spec does not define a new file for this data contract — the implementation plan will decide whether it's a small view-model-side helper or inlined into whatever view the design team delivers, once that UI exists.

## 5. Tab Placement

`RootTabView` (`Monee/App/ContentView.swift`) gains a fourth tab: **Tracker → Summary → Profile → Monee (AI Buddy)**. AI Buddy remains the last, `.search`-role tab as it is today.

## Out of Scope

- The Summary screen's actual visual design — deferred entirely to the design team; this spec's job is done once their screen can be wired to the data contract in §4.
- An emergency-fund withdrawal/decrease flow — not requested; `emergencyFundTotal` is additive-only in this spec.
- A ledger/history of individual emergency fund contributions — explicitly rejected in favor of a single running total, to keep this simple.
- Any change to the existing 30-day trailing-window `avgDailyExpense`/`runwayDays` calculation — untouched by this spec.
- Migrating any old `UserFinancialProfile`/pre-onboarding-integration data — not applicable; that migration boundary was already crossed in the prior onboarding-integration work.

## Verification

No XCTest target exists in this project (unchanged constraint from prior plans). Verification will be build + manual run in Simulator once implemented:
1. With <5 total transactions, AI Buddy states it doesn't have enough data — no Spare Money figure, no blended guess.
2. With ≥5 transactions and no emergency fund contribution, Spare Money equals `trackedIncome − trackedExpenses` exactly (verifiable by hand against Tracker).
3. After adding an emergency fund contribution (via whatever the design team's UI provides, or a temporary debug entry point until then), Spare Money drops by exactly that amount.
4. With no `estimatedMonthlyExpense` set, emergency fund target shows as "not set," not a 0%/0-target figure.
5. With `estimatedMonthlyExpense` set, target equals exactly `12 ×` that value.
6. Asking the AI a spending/saving question while the fund is under 100% surfaces a mention of it; asking an unrelated question (e.g. "what category did I spend most on?") does not force it in every time.
