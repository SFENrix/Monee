# Onboarding Integration Design

**Goal:** Wire the already-built 3-screen onboarding chain (`OnboardingView` → `OnboardingSetupView` → `OnboardingFinancialSetupView`) into the app so it's shown once, full-screen and non-dismissable, on first launch; delete the old `IncomeEstimateSheet` it supersedes; and have the collected data (name, status, starting balance, estimated monthly income/expense) flow into `ProfileView` and the AI's financial context.

## Current State

- `OnboardingView` (welcome/mascot) → `OnboardingSetupView` (name + status, its own `OnboardingStatus` enum: Single/Married/With child) → `OnboardingFinancialSetupView` (total money/monthly income/monthly expense). All three exist with real design-team UI and correctly bubble data up via `onFinish` closures, but nothing presents `OnboardingView` anywhere — the chain is dead code today.
- `IncomeEstimateSheet` is the old one-field (`estimatedMonthlyIncome` only) nudge, triggered lazily from `AIChatView.task` the first time it opens with `!appContainer.isUserOnboarded && !UserFinancialProfile.hasEstimate`. It sets `appContainer.isUserOnboarded = true` on dismiss (skip or save).
- `UserFinancialProfile` (`Core/Utilities`) is a single-field UserDefaults wrapper (`estimatedMonthlyIncome`), read by `AIChatViewModel.buildFinancialContext` as `fallbackMonthlyIncome` into `CashReserveCalculator.summarize`, which blends it into the reserve figure when logged income has fewer than 3 transactions, pro-rated over 30 days of history. This blending math is unchanged by this design.
- `ProfileView` has hardcoded `@State private var name = "Gwen Alyssa"` and its own 4-case `RelationshipStatus` enum (Single/In a Relationship/Married/It's Complicated), neither persisted — both reset on every launch.
- `AppContainer.isUserOnboarded: Bool` (in-memory, `@Observable`) already exists and is read/written by the old flow; reused here.

## Changes

### 1. `Monee/Core/Utilities/UserProfile.swift` (new, replaces `UserFinancialProfile.swift`)

UserDefaults-backed enum, the single source of truth for onboarding-collected data:

- `static var name: String?`
- `static var status: OnboardingStatus?`
- `static var estimatedMonthlyIncome: Double?`
- `static var estimatedMonthlyExpense: Double?`
- `static var hasCompletedOnboarding: Bool`

`OnboardingStatus` (currently a private-file enum in `OnboardingSetupView.swift`: `.single`, `.married`, `.withChild`) moves into this file as the shared status enum used by both onboarding and Profile. `UserFinancialProfile.swift` is deleted; all three call sites (`AIChatViewModel`, `IncomeEstimateSheet` — deleted anyway) are repointed.

### 2. Onboarding chain wiring

No changes to `OnboardingFinancialSetupView` or the visual bodies of the other two screens. Only the completion path changes:

- `OnboardingSetupView.onFinish(name, status, totalMoney, monthlyIncome, monthlyExpense)` — currently a no-op default closure — gets a real implementation supplied by whoever hosts the chain (see below), which:
  1. Writes `UserProfile.name`, `.status`, `.estimatedMonthlyIncome`, `.estimatedMonthlyExpense`.
  2. If `totalMoney` is present and `> 0`, inserts `Transaction(title: "Starting Balance", amount: totalMoney, date: Date(), category: .income, source: .manual)` via `modelContext` and saves — recorded as an ordinary transaction so `CashReserveCalculator` never needs a special baseline case.
  3. Sets `UserProfile.hasCompletedOnboarding = true` and `appContainer.isUserOnboarded = true`.
- `OnboardingView.onGetStarted` pushes to `OnboardingSetupView` (currently a no-op default closure taking no params).
- These three screens need one host that owns the `NavigationStack`/push sequencing and has access to `\.modelContext` and `AppContainer`. This host is a thin wrapper — not a rewrite of the existing screens — e.g. `OnboardingView` itself gains a `NavigationStack` wrapping its body with a `navigationDestination`-driven push to `OnboardingSetupView`, or a small new container view. Exact mechanism is an implementation-plan-level decision (both screens already support programmatic composition via their closures); the constraint is: don't touch the visual body of any of the three screens beyond adding the navigation container needed to chain them.

### 3. Trigger point — `Monee/App/ContentView.swift` (`RootTabView`)

```swift
struct RootTabView: View {
    @State private var selectedTab: AppTab = .aiChat
    @Environment(AppContainer.self) private var appContainer

    var body: some View {
        TabView(selection: $selectedTab) { /* unchanged */ }
            .task {
                appContainer.isUserOnboarded = UserProfile.hasCompletedOnboarding
            }
            .fullScreenCover(isPresented: Binding(
                get: { !appContainer.isUserOnboarded },
                set: { _ in }
            )) {
                OnboardingView(/* wired onGetStarted chain */)
            }
    }
}
```

Non-dismissable (no `set` mutation path, matches the old sheet's blocking intent but as a required flow instead of skippable).

### 4. Remove `IncomeEstimateSheet`

- Delete `Monee/Features/AIBuddy/UI/IncomeEstimateSheet.swift`.
- In `AIChatView.swift`: remove `@State private var showingIncomeEstimate`, the `.sheet(isPresented: $showingIncomeEstimate) { IncomeEstimateSheet() }` block, and the `if !appContainer.isUserOnboarded && !UserFinancialProfile.hasEstimate { showingIncomeEstimate = true }` check inside `.task`.
- Replace the hardcoded `var userFirstName: String = "there"` with a computed property: `var userFirstName: String { UserProfile.name ?? "there" }`.

### 5. `ProfileView` changes

- Delete the local `enum RelationshipStatus` (lines 297–304) and its use in `statusCard`/`StatusPickerView`; both retarget to the shared `OnboardingStatus`.
- `@State private var name: String = "Gwen Alyssa"` → `@State private var name: String = UserProfile.name ?? ""`, with `.onChange(of: name) { UserProfile.name = $0 }` (mirrors existing `EditProfileView` save flow — no change to `EditProfileView` itself).
- `@State private var status: RelationshipStatus = .single` → `@State private var status: OnboardingStatus = UserProfile.status ?? .single`, with `.onChange(of: status) { UserProfile.status = $0 }`.
- New "Your Estimates" section below `overviewSection` (or above it — exact placement is a plan-level UI decision), with two editable rows for Estimated Monthly Income / Estimated Monthly Expense, styled consistently with the existing `OverviewCard`/`infoRow` visual language, each backed directly by `UserProfile.estimatedMonthlyIncome` / `.estimatedMonthlyExpense`. This is distinct from the existing computed "Average Income"/"Average Expenses" cards (which stay as-is, driven by real transactions) — the new rows are the self-reported onboarding targets, editable independently.

### 6. `AIChatViewModel` / `CashReserveCalculator`

No math changes. `buildFinancialContext`'s call `CashReserveCalculator.summarize(transactions: all, fallbackMonthlyIncome: UserFinancialProfile.estimatedMonthlyIncome)` → `fallbackMonthlyIncome: UserProfile.estimatedMonthlyIncome`. Same for the `else if let estimate = UserFinancialProfile.estimatedMonthlyIncome` branch in the income-section formatting.

## Out of Scope

- Any change to `CashReserveCalculator`'s blending/confidence logic (explored in a prior, now-stale plan doc; explicitly not revisited here).
- Any change to the visual design of the three onboarding screens beyond the navigation container needed to chain them.
- Migrating the old `UserFinancialProfile` UserDefaults key (`"estimatedMonthlyIncome"`) forward — fresh start, matches prior precedent in this codebase.
- Making "Total money" / income / expense fields required to finish onboarding — `OnboardingFinancialSetupView` already treats blank fields as `nil` and this design doesn't add validation beyond what exists (name/status ARE effectively required since `OnboardingSetupView` collects them before advancing, but nothing currently blocks proceeding with an empty name — not changed here).

## Verification

Manual (no XCTest target exists in this project):
1. Fresh Simulator / after deleting `UserProfile`'s UserDefaults keys: launch app → onboarding chain appears full-screen, cannot be swiped away, walks through all 3 screens.
2. Complete with Name "Test", Status "Married", Total money 2000000, Monthly income 5000000, Monthly expense 3000000 → onboarding dismisses, Tracker tab shows a "Starting Balance" transaction for Rp2.000.000.
3. Profile tab shows Name "Test", Status "Married", Estimated Monthly Income/Expense rows populated; edit an estimate row, force-quit, relaunch — value persists.
4. AI Buddy: ask a question relying on income — response reflects the new estimate; force-quit and relaunch app — onboarding does NOT reappear.
5. `IncomeEstimateSheet.swift` no longer exists in the project; build succeeds with no references to `UserFinancialProfile` or the old `RelationshipStatus`.
