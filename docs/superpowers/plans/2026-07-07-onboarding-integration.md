# Onboarding Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the already-built 3-screen onboarding chain (`OnboardingView` → `OnboardingSetupView` → `OnboardingFinancialSetupView`) into the app as a required first-launch flow, delete the old `IncomeEstimateSheet`, and flow the collected data (name, status, starting balance, estimated income/expense) into `ProfileView` and the AI's financial context.

**Architecture:** A new consolidated `UserProfile` UserDefaults store (replacing the single-field `UserFinancialProfile`) becomes the single source of truth for onboarding-collected data, including the shared `OnboardingStatus` enum (moved out of `OnboardingSetupView.swift`). `RootTabView` gates a non-dismissable `.fullScreenCover` on `UserProfile.hasCompletedOnboarding`. The three existing onboarding screens are wired together via one small host view that owns navigation and writes to `UserProfile` (and inserts a "Starting Balance" `Transaction`) on completion — their visual bodies are untouched. `ProfileView` and `AIChatViewModel`/`AIChatView` are repointed from their old hardcoded/single-field state onto `UserProfile`.

**Tech Stack:** SwiftUI, SwiftData, UserDefaults, `@Observable` (AppContainer).

## Global Constraints

- No XCTest target exists anywhere in this project (verified: zero `XCTest` references in `project.pbxproj`, no `*Tests*` directories). Every task below verifies via **build + manual run in Simulator**, not automated tests. Do not create a new test target as part of this work.
- Build command used throughout: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
- IDR (Indonesian Rupiah) only — matches existing `idrFormatted` / `RegexParser` scope. No new currency handling.
- Do not touch `CashReserveCalculator`'s blending/confidence-gate math — only its `fallbackMonthlyIncome` data source changes (from `UserFinancialProfile` to `UserProfile`).
- Do not change the visual body of `OnboardingView`, `OnboardingSetupView`, or `OnboardingFinancialSetupView` beyond what's needed to chain them together (per spec `docs/superpowers/specs/2026-07-07-onboarding-integration-design.md`, "Out of Scope").
- `OnboardingStatus` cases are `.single = "Single"`, `.married = "Married"`, `.withChild = "With child"` (existing, from `OnboardingSetupView.swift:214-220`) — this is the enum that wins over `ProfileView`'s old 4-case `RelationshipStatus` (explicit user decision).
- Starting balance is recorded as a real `Transaction` (title `"Starting Balance"`, category `.income`, source `.manual`, dated at onboarding completion) — not a special baseline field (explicit user decision).

---

## File Structure

| File | Change |
|---|---|
| `Monee/Core/Utilities/UserFinancialProfile.swift` | **Delete** — replaced by `UserProfile.swift` |
| `Monee/Core/Utilities/UserProfile.swift` | **Create** — consolidated UserDefaults-backed store + shared `OnboardingStatus` enum |
| `Monee/Features/OnBoarding/OnboardingSetUpView.swift` | **Modify** — remove the private `OnboardingStatus` enum (moves to `UserProfile.swift`); everything else unchanged |
| `Monee/Features/OnBoarding/OnboardingView.swift` | **Modify** — add a `NavigationStack` + push to `OnboardingSetupView`, wired to write to `UserProfile` on final completion |
| `Monee/Features/AIBuddy/UI/IncomeEstimateSheet.swift` | **Delete** — superseded by the onboarding chain |
| `Monee/Features/AIBuddy/UI/AIChatView.swift` | **Modify** — remove the old income-estimate trigger/sheet/state; `userFirstName` becomes computed from `UserProfile.name` |
| `Monee/Features/AIBuddy/ViewModels/AIChatViewModel.swift` | **Modify** — repoint `fallbackMonthlyIncome` source from `UserFinancialProfile` to `UserProfile` |
| `Monee/App/ContentView.swift` (`RootTabView`) | **Modify** — add `.fullScreenCover` gated on `!appContainer.isUserOnboarded`, synced from `UserProfile.hasCompletedOnboarding` on `.task` |
| `Monee/Features/Profile/UI/ProfileView.swift` | **Modify** — delete local `RelationshipStatus`, read/write `name`/`status` through `UserProfile`, add editable Estimated Monthly Income/Expense rows |

---

### Task 1: Consolidated `UserProfile` store with shared `OnboardingStatus`

**Files:**
- Create: `Monee/Core/Utilities/UserProfile.swift`
- Delete: `Monee/Core/Utilities/UserFinancialProfile.swift`
- Modify: `Monee/Features/OnBoarding/OnboardingSetUpView.swift` (remove lines 212-220, the private `OnboardingStatus` enum)

**Interfaces:**
- Produces: `enum OnboardingStatus: String, CaseIterable, Identifiable` with cases `.single = "Single"`, `.married = "Married"`, `.withChild = "With child"`, `var id: String { rawValue }`. Used by `OnboardingSetupView` (Task 1), `ProfileView` (Task 7).
- Produces: `enum UserProfile` with `static var name: String?`, `static var status: OnboardingStatus?`, `static var estimatedMonthlyIncome: Double?`, `static var estimatedMonthlyExpense: Double?`, `static var hasCompletedOnboarding: Bool` — all get/set, UserDefaults-backed. Used by `OnboardingView` (Task 2), `AIChatView`/`AIChatViewModel` (Tasks 3-4), `ContentView` (Task 5), `ProfileView` (Task 7).

- [ ] **Step 1: Write `UserProfile.swift`**

```swift
//
//  UserProfile.swift
//  Monee
//
//  Single source of truth for onboarding-collected, self-reported profile data.
//  Deliberately NOT SwiftData — these are advisory numbers the AI uses as qualitative
//  context (targets/estimates), never mixed into CashReserveCalculator's arithmetic
//  beyond the existing fallback-blend behavior. UserDefaults-backed so it's readable
//  from a plain class (AIChatViewModel), not just SwiftUI views.
//

import Foundation

/// Rough life/family situation captured during onboarding — used to give the AI
/// context on tone (stricter vs. more forgiving about spending) and to give
/// Profile's Overview section something to anchor to before real transactions exist.
enum OnboardingStatus: String, CaseIterable, Identifiable, Codable {
    case single = "Single"
    case married = "Married"
    case withChild = "With child"

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

    static var status: OnboardingStatus? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: statusKey) else { return nil }
            return OnboardingStatus(rawValue: raw)
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

- [ ] **Step 3: Remove the now-duplicate `OnboardingStatus` from `OnboardingSetUpView.swift`**

Open `Monee/Features/OnBoarding/OnboardingSetUpView.swift` and delete lines 211-220 (the comment block + `enum OnboardingStatus { ... }` at the bottom of the file, right before the `ArchCurveShape` struct). Leave everything else in the file untouched — `ArchCurveShape` and the `#Preview` block stay.

- [ ] **Step 4: Build to confirm expected (pre-existing) errors only**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: Build FAILS. Errors should ONLY be: "cannot find type 'UserFinancialProfile'" in `AIChatViewModel.swift` and `IncomeEstimateSheet.swift`. `OnboardingStatus` should resolve fine everywhere (it's now in `UserProfile.swift`, same module). If you see any other error, stop and investigate before continuing.

- [ ] **Step 5: Commit**

```bash
git add Monee/Core/Utilities/UserProfile.swift Monee/Features/OnBoarding/OnboardingSetUpView.swift
git commit -m "feat: add consolidated UserProfile store with shared OnboardingStatus enum"
```

---

### Task 2: Chain the onboarding screens together

**Files:**
- Modify: `Monee/Features/OnBoarding/OnboardingView.swift`

**Interfaces:**
- Consumes: `UserProfile` (Task 1), `OnboardingSetupView(onFinish:)` (existing, signature `(_ name: String, _ status: OnboardingStatus?, _ totalMoney: Double?, _ monthlyIncome: Double?, _ monthlyExpense: Double?) -> Void`), `Transaction.init(title:amount:date:category:source:)` (existing), `AppContainer` (existing, `@Observable`, has `isUserOnboarded: Bool`).
- Produces: `struct OnboardingView: View` — now takes no required init parameters (drops the old `onGetStarted` closure param entirely; it owns the full flow internally via `@Environment(\.modelContext)` and `@Environment(AppContainer.self)`). This is what `RootTabView` (Task 5) presents.

- [ ] **Step 1: Rewrite `OnboardingView.swift` to own navigation to `OnboardingSetupView`**

Replace the full contents of `Monee/Features/OnBoarding/OnboardingView.swift`:

```swift
//
//  OnboardingView.swift
//  Monee
//
//  Welcome / onboarding screen introducing the app's mascot "Buntel" over a soft
//  pastel mesh background, with a white rounded sheet holding the copy and CTA.
//
//  Updated 07/07/26 — swapped the hand-drawn SwiftUI mascot for the real
//  "buntel" image asset (Assets.xcassets → buntel).
//
//  Updated 07/07/26 — now owns the full onboarding chain: pushes to
//  OnboardingSetupView on "Get Started", and writes the final collected data
//  (name, status, starting balance, estimated income/expense) to UserProfile
//  when OnboardingFinancialSetupView (the last step) finishes. Starting balance
//  is recorded as an ordinary "Starting Balance" Transaction rather than a
//  special baseline field, so CashReserveCalculator never needs a second code path.
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    var body: some View {
        NavigationStack {
            welcomeScreen
        }
    }

    private var welcomeScreen: some View {
        ZStack {
            meshBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Image("buntel")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 190, height: 190)
                    .padding(.bottom, 28)

                VStack(spacing: 8) {
                    Text("Hi, I'm Buntel!")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.black.opacity(0.85))

                    Text("Let's get things ready before you start")
                        .font(.system(size: 16))
                        .foregroundStyle(.black.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 36)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)

            VStack {
                Spacer()
                bottomSheet
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: OnboardingRoute.self) { route in
            switch route {
            case .setup:
                OnboardingSetupView(onFinish: finishOnboarding)
            }
        }
    }

    // MARK: - Bottom sheet

    private var bottomSheet: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.black.opacity(0.08))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            NavigationLink(value: OnboardingRoute.setup) {
                Text("Get Started")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.38, green: 0.78, blue: 0.80),
                                        Color(red: 0.30, green: 0.68, blue: 0.72)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .background(
            TopCurveShape()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 20, x: 0, y: -6)
        )
        .frame(height: 300)
    }

    // MARK: - Background

    private var meshBackground: some View {
        ZStack {
            Color(red: 0.98, green: 0.96, blue: 0.92)

            Circle()
                .fill(Color(red: 0.96, green: 0.65, blue: 0.45).opacity(0.55))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: 110, y: -260)

            Circle()
                .fill(Color(red: 0.55, green: 0.80, blue: 0.70).opacity(0.55))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -140, y: -60)

            Circle()
                .fill(Color(red: 0.98, green: 0.87, blue: 0.72).opacity(0.6))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: 0, y: 120)
        }
    }

    // MARK: - Completion

    /// Called once OnboardingFinancialSetupView (the last of the three chained
    /// screens) finishes. Persists everything collected across the whole chain
    /// and flips the flags that dismiss the fullScreenCover in RootTabView.
    private func finishOnboarding(
        name: String,
        status: OnboardingStatus?,
        totalMoney: Double?,
        monthlyIncome: Double?,
        monthlyExpense: Double?
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        UserProfile.name = trimmedName.isEmpty ? nil : trimmedName
        UserProfile.status = status
        UserProfile.estimatedMonthlyIncome = monthlyIncome
        UserProfile.estimatedMonthlyExpense = monthlyExpense

        if let totalMoney, totalMoney > 0 {
            let transaction = Transaction(
                title: "Starting Balance",
                amount: totalMoney,
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

/// Onboarding's own navigation route — a single case today, but a real enum (not
/// a Bool flag) so the chain can gain intermediate steps later without RootTabView
/// or the fullScreenCover presentation needing to change.
private enum OnboardingRoute: Hashable {
    case setup
}

// MARK: - Bottom sheet shape

/// A rounded rectangle whose top edge is a gentle wave rather than a
/// straight line, matching the soft curve where the white sheet meets
/// the gradient background.
private struct TopCurveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let waveHeight: CGFloat = 55

        path.move(to: CGPoint(x: rect.minX, y: waveHeight))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: 0),
            control1: CGPoint(x: rect.width * 0.35, y: waveHeight + 35),
            control2: CGPoint(x: rect.width * 0.65, y: -25)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    OnboardingView()
        .environment(AppContainer.shared)
        .modelContainer(SwiftDataService.makePreviewContainer())
}
```

- [ ] **Step 2: Build to confirm expected (pre-existing) errors only**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: Errors only in `AIChatViewModel.swift` and `IncomeEstimateSheet.swift` (both reference deleted `UserFinancialProfile`, fixed in Tasks 3-4). `OnboardingView.swift` and `OnboardingSetUpView.swift` compile clean.

- [ ] **Step 3: Commit**

```bash
git add Monee/Features/OnBoarding/OnboardingView.swift
git commit -m "feat: chain OnboardingView into OnboardingSetupView, write collected data to UserProfile on finish"
```

---

### Task 3: Remove `IncomeEstimateSheet` and its trigger from `AIChatView`

**Files:**
- Delete: `Monee/Features/AIBuddy/UI/IncomeEstimateSheet.swift`
- Modify: `Monee/Features/AIBuddy/UI/AIChatView.swift`

**Interfaces:**
- Consumes: `UserProfile.name` (Task 1).

- [ ] **Step 1: Delete the old sheet**

```bash
git rm Monee/Features/AIBuddy/UI/IncomeEstimateSheet.swift
```

- [ ] **Step 2: Remove the trigger state, sheet, and hardcoded name in `AIChatView.swift`**

Delete the `userFirstName` stored property (line 33) and the comment above it (lines 30-32):

```swift
    /// TODO: no user-name field exists anywhere yet (UserFinancialProfile only stores
    /// an income estimate). Hardcoded for now — wire to a real name once onboarding
    /// captures one, or drop the personalized greeting.
    var userFirstName: String = "there"
```

Replace with a computed property in the same location:

```swift
    var userFirstName: String { UserProfile.name ?? "there" }
```

Delete line 37, `@State private var showingIncomeEstimate = false`.

Delete the sheet block (lines 86-88):

```swift
        .sheet(isPresented: $showingIncomeEstimate) {
            IncomeEstimateSheet()
        }
```

Replace the `.task` block (lines 89-94):

```swift
        .task {
            viewModel.bootstrap(modelContext: modelContext)
            if !appContainer.isUserOnboarded && !UserFinancialProfile.hasEstimate {
                showingIncomeEstimate = true
            }
        }
```

with:

```swift
        .task {
            viewModel.bootstrap(modelContext: modelContext)
        }
```

- [ ] **Step 3: Build to confirm expected (pre-existing) errors only**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: Errors only in `AIChatViewModel.swift` (fixed in Task 4). `AIChatView.swift` compiles clean.

- [ ] **Step 4: Commit**

```bash
git add Monee/Features/AIBuddy/UI/AIChatView.swift
git commit -m "refactor: drop lazy income-estimate sheet trigger from AIChatView, use UserProfile.name"
```

---

### Task 4: Repoint `AIChatViewModel`'s fallback income source

**Files:**
- Modify: `Monee/Features/AIBuddy/ViewModels/AIChatViewModel.swift`

**Interfaces:**
- Consumes: `UserProfile.estimatedMonthlyIncome` (Task 1).

- [ ] **Step 1: Replace both `UserFinancialProfile.estimatedMonthlyIncome` references**

In `Monee/Features/AIBuddy/ViewModels/AIChatViewModel.swift`, line 135, inside `buildFinancialContext`:

```swift
            let summary = CashReserveCalculator.summarize(
                transactions: all,
                fallbackMonthlyIncome: UserFinancialProfile.estimatedMonthlyIncome
            )
```

becomes:

```swift
            let summary = CashReserveCalculator.summarize(
                transactions: all,
                fallbackMonthlyIncome: UserProfile.estimatedMonthlyIncome
            )
```

And line 158:

```swift
            } else if let estimate = UserFinancialProfile.estimatedMonthlyIncome {
```

becomes:

```swift
            } else if let estimate = UserProfile.estimatedMonthlyIncome {
```

No other lines in this file change — `CashReserveCalculator`'s signature and blending math are untouched.

- [ ] **Step 2: Build**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: BUILD SUCCEEDED — this was the last file referencing the deleted `UserFinancialProfile`.

- [ ] **Step 3: Commit**

```bash
git add Monee/Features/AIBuddy/ViewModels/AIChatViewModel.swift
git commit -m "refactor: repoint AIChatViewModel's fallback income source from UserFinancialProfile to UserProfile"
```

---

### Task 5: Show onboarding from the app root

**Files:**
- Modify: `Monee/App/ContentView.swift`

**Interfaces:**
- Consumes: `OnboardingView()` (Task 2, no-arg init), `UserProfile.hasCompletedOnboarding` (Task 1), `AppContainer.isUserOnboarded` (existing).

- [ ] **Step 1: Add the full-screen cover to `RootTabView`**

Replace the full contents of `Monee/App/ContentView.swift`:

```swift
//
//  ContentView.swift
//  FreelanceFinance
//
//  App root: three-tab shell (Tracker / Profile / AI Buddy). The old single-screen
//  Dashboard this file used to hold was retired once TrackerView + ProfileView (real,
//  design-provided views) replaced it.
//
//  Updated 07/07/26 — added a non-dismissable fullScreenCover showing OnboardingView
//  until UserProfile.hasCompletedOnboarding is true, synced into AppContainer on launch
//  so the same in-memory flag OnboardingView already flips on completion works without
//  a relaunch.
//

import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case tracker
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

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Monee/App/ContentView.swift
git commit -m "feat: show onboarding full-screen from app root until UserProfile.hasCompletedOnboarding"
```

---

### Task 6: Manual verification — onboarding chain end to end

**Files:** none (verification only)

- [ ] **Step 1: Reset onboarding state and launch in Simulator**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'platform=iOS Simulator,name=iPhone 16' build`, then either erase the Simulator's content (Device → Erase All Content and Settings) or delete the app from a booted Simulator so `UserDefaults` starts clean, then launch via Xcode.
Expected: The welcome onboarding screen ("Hi, I'm Buntel!") appears full-screen immediately and there is no way to swipe it away or see the tab bar behind it.

- [ ] **Step 2: Walk the full chain**

Tap "Get Started" → fill Name "Test User", pick Status "With child" → tap "Get Started" again → on the financial screen enter Total money `2000000`, Monthly income `5000000`, Monthly expense `3000000` → tap "Finish".
Expected: The whole onboarding flow dismisses and the tab bar (Tracker/Profile/Monee) appears, landing on the AI Buddy tab.

- [ ] **Step 3: Verify the Starting Balance transaction**

Open the Tracker tab.
Expected: A "Starting Balance" transaction dated today for Rp2.000.000 appears in the list.

- [ ] **Step 4: Verify Profile reflects onboarding data**

Open the Profile tab.
Expected: Name reads "Test User", Status reads "With child". (Estimated Monthly Income/Expense rows are added in Task 7 — not yet visible after this task alone; that's expected at this point in the plan.)

- [ ] **Step 5: Verify onboarding does not reappear**

Force-quit the app and relaunch.
Expected: The app opens straight to the tab bar — onboarding does not show again.

- [ ] **Step 6: Verify AI Buddy greeting uses the real name**

Open the Monee (AI Buddy) tab with no chat history.
Expected: Empty-state greeting reads "Hi Test User!" instead of "Hi there!".

No commit for this task — verification only, no files changed.

---

### Task 7: `ProfileView` — persist through `UserProfile`, add estimate rows

**Files:**
- Modify: `Monee/Features/Profile/UI/ProfileView.swift`

**Interfaces:**
- Consumes: `UserProfile.name/.status/.estimatedMonthlyIncome/.estimatedMonthlyExpense` (Task 1), `OnboardingStatus` (Task 1, replaces the local `RelationshipStatus`).
- Produces: no new public interface — `ProfileView` remains a leaf view.

- [ ] **Step 1: Replace the `@State` declarations and wire persistence**

In `Monee/Features/Profile/UI/ProfileView.swift`, replace lines 18-53 (the `struct ProfileView` declaration through the end of `body`):

```swift
struct ProfileView: View {
    @Query private var transactions: [Transaction]

    @State private var name: String = UserProfile.name ?? ""
    @State private var status: OnboardingStatus = UserProfile.status ?? .single
    @State private var estimatedIncomeText: String = UserProfile.estimatedMonthlyIncome.map { String(Int($0)) } ?? ""
    @State private var estimatedExpenseText: String = UserProfile.estimatedMonthlyExpense.map { String(Int($0)) } ?? ""
    @State private var showingEditProfile = false

    private let mintTint = Color(red: 0.55, green: 0.80, blue: 0.70)
    private let peachTint = Color(red: 0.96, green: 0.65, blue: 0.45)

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundMesh

                ScrollView {
                    VStack(spacing: 20) {
                        profileHeader

                        nameCard
                        statusCard

                        estimatesSection

                        overviewSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView(name: $name)
            }
        }
        .onChange(of: name) { _, newValue in UserProfile.name = newValue }
        .onChange(of: status) { _, newValue in UserProfile.status = newValue }
    }
```

Note: this keeps `mintTint`/`peachTint` and everything from `backgroundMesh` down (Steps 2-3 below) exactly as they already are in the file — only the state declarations and `body` changed.

- [ ] **Step 2: Add the estimates section, right after `statusCard` in the file**

Insert this new section immediately after the existing `statusCard` computed property (which stays unchanged) and before `infoRow`:

```swift
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

- [ ] **Step 3: Retarget `statusCard`/`StatusPickerView` to `OnboardingStatus` and delete the local `RelationshipStatus` enum**

Find and delete this block near the bottom of the file (originally lines 296-304):

```swift
enum RelationshipStatus: String, CaseIterable, Identifiable {
    case single = "Single"
    case inRelationship = "In a Relationship"
    case married = "Married"
    case itsComplicated = "It's Complicated"

    var id: String { rawValue }
}
```

Then update `StatusPickerView`'s `@Binding` type (originally line 307):

```swift
private struct StatusPickerView: View {
    @Binding var status: RelationshipStatus
```

becomes:

```swift
private struct StatusPickerView: View {
    @Binding var status: OnboardingStatus
```

`List(RelationshipStatus.allCases)` (originally line 311) becomes `List(OnboardingStatus.allCases)`. No other lines in `StatusPickerView` change.

- [ ] **Step 4: Build**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -40`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Monee/Features/Profile/UI/ProfileView.swift
git commit -m "feat: persist ProfileView name/status through UserProfile, add editable income/expense estimates"
```

---

### Task 8: Manual verification — Profile estimates + persistence

**Files:** none (verification only)

- [ ] **Step 1: Confirm the new estimates section renders**

Launch the app (already onboarded from Task 6), open Profile.
Expected: A "Your Estimates" section appears between Status and Overview, showing "Estimated Monthly Income" as Rp5.000.000-equivalent value (raw `5000000`) and "Estimated Monthly Expense" as `3000000`, editable.

- [ ] **Step 2: Edit an estimate and verify persistence**

Change Estimated Monthly Income to `6000000`. Force-quit the app, relaunch, open Profile again.
Expected: Estimated Monthly Income still reads `6000000` — confirms the `onCommit` write path and `UserProfile` round-trip both work.

- [ ] **Step 3: Verify Status persists through the new enum**

Change Status to "Single" via the status picker. Force-quit, relaunch, open Profile.
Expected: Status reads "Single" — confirms `OnboardingStatus` (not the deleted `RelationshipStatus`) round-trips correctly through `UserProfile`.

- [ ] **Step 4: Verify AI Buddy picks up the updated income estimate**

Open AI Buddy, start a new chat, ask a question that would reference income (e.g. "how much can I spend today?") with fewer than 3 real income transactions logged.
Expected: The AI's answer is consistent with the Rp6.000.000 estimate (from Step 2), not the original onboarding value of Rp5.000.000 — confirms `AIChatViewModel` reads live from `UserProfile`, not a stale cached value.

No commit for this task — verification only, no files changed.

---

## Self-Review

**Spec coverage:**
- Consolidated `UserProfile` store (name/status/income/expense/hasCompletedOnboarding) → Task 1. ✅
- Shared `OnboardingStatus` replacing both the private onboarding enum and Profile's `RelationshipStatus` → Task 1 (moves it), Task 7 (Profile retargeted). ✅
- Onboarding chain wired end-to-end (`OnboardingView` → `OnboardingSetupView` → `OnboardingFinancialSetupView`) with no visual changes to the three screens → Task 2 (only navigation plumbing + `finishOnboarding` added to `OnboardingView`; the other two files are never modified). ✅
- Starting balance recorded as a `Transaction`, not a special field → Task 2 (`finishOnboarding`). ✅
- Full-screen, non-dismissable trigger from app root, gated on `UserProfile.hasCompletedOnboarding` → Task 5. ✅
- `IncomeEstimateSheet` deleted, its trigger removed from `AIChatView`, `userFirstName` now real → Task 3. ✅
- `CashReserveCalculator` math untouched, only `fallbackMonthlyIncome` source repointed → Task 4. ✅
- Profile shows editable Estimated Monthly Income/Expense rows, distinct from the existing computed Average cards → Task 7 (`estimatesSection`, `overviewSection` unchanged). ✅
- End-to-end manual verification (no XCTest target) → Tasks 6 and 8. ✅

**Placeholder scan:** No "TBD"/"handle appropriately" language in any task; all code blocks are complete. (Task 2's note about the stray placeholder line is an explicit warning to the implementer about what NOT to include, not an unresolved placeholder of its own — the final code block above it is complete and correct.)

**Type consistency:** `OnboardingStatus` cases (`.single`, `.married`, `.withChild`) used identically in Task 1 (defined), Task 2 (`finishOnboarding` parameter, matches `OnboardingSetupView.onFinish`'s existing signature), Task 7 (`ProfileView`/`StatusPickerView`). `UserProfile` static members used identically across Tasks 2, 3, 4, 5, 7. `OnboardingSetupView.onFinish` and `OnboardingFinancialSetupView.onFinish` closure signatures are unchanged from their current implementation (verified against the existing file contents) — Task 2 only supplies a real closure where a no-op default existed before.
