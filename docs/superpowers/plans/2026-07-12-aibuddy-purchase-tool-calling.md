# AIBuddy Purchase Verdict — Tool Calling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop AIBuddy from hallucinating purchase-impact numbers by moving the subtraction and tier decision (SAFE/CAUTION/BAD) into Swift, and using Foundation Models Tool calling so the model calls real code to get those numbers instead of guessing them.

**Architecture:** `CashReserveCalculator` gains a pure `evaluatePurchase` function. A new `PurchaseImpactTool` wraps it and is registered on the `LanguageModelSession` in `AppleIntelligenceAdapter`. The model extracts the purchase amount from the user's text, calls the tool, gets back real numbers, and narrates them in free text — same `String` return type as today, no changes to `ChatMessage` or the chat UI.

**Tech Stack:** Swift, SwiftUI, SwiftData, Apple FoundationModels framework (iOS 26+), XCTest.

## Global Constraints

- Deployment target iOS 26.0+ (already required by `AppleIntelligenceAdapter`'s existing use of `FoundationModels`).
- All amounts are Indonesian Rupiah (IDR) — never other currencies, per existing coaching rules.
- `AIAdapterProtocol.generateAdvice`'s return type stays `String` — no changes to `ChatMessage.content` (`Monee/Core/Database/Models/ChatMessage.swift`) or any AIBuddy UI file.
- Purchase tier thresholds: SAFE = post-purchase runway ≥ 14 days; CAUTION = 1–13 days; BAD = post-purchase Spare Money ≤ 0.
- No unit tests exist anywhere else in this project — this plan adds the first, minimal test target on purpose (Task 1), scoped only to `CashReserveCalculator`.
- This plan deviates from `docs/superpowers/specs/2026-07-11-aibuddy-purchase-tool-calling-design.md` in one place: the final chat response stays free text (no `generating: PurchaseAdvice.self` structural constraint on the whole response), because `generateAdvice` is the single entry point for every chat message, not just purchase questions — forcing a tier+reasoning shape would break unrelated questions. The tool call alone already grounds the numbers in real Swift math, which is what fixes the reported bug.

---

## Task 1: Add a Unit Test Target, and `evaluatePurchase` to `CashReserveCalculator`

**Files:**
- Modify: `Monee/Core/Utilities/CashReserveCalculator.swift`
- Create (via Xcode UI, not a code step): `MoneeTests` test target
- Test: `MoneeTests/CashReserveCalculatorTests.swift`

**Interfaces:**
- Produces: `PurchaseTier` (enum: `.safe`, `.caution`, `.bad`), `PurchaseImpact` (struct: `tier: PurchaseTier`, `postPurchaseSpareMoney: Double`, `postPurchaseRunwayDays: Double?`), `CashReserveCalculator.evaluatePurchase(amount: Double, currentSummary: CashReserveSummary) -> PurchaseImpact`. Task 2 (`PurchaseImpactTool`) calls this function directly.

- [ ] **Step 1: Add the test target in Xcode**

This is a one-time UI action, not code:
1. Open `Monee.xcodeproj` in Xcode.
2. Menu bar → File → New → Target...
3. Choose "Unit Testing Bundle" (under the iOS tab), click Next.
4. Product Name: `MoneeTests`. "Team" and "Organization Identifier" can stay as Xcode defaults. Under "Target to be Tested," choose `Monee`.
5. Click Finish. Xcode creates a `MoneeTests/` group with a starter `MoneeTests.swift` file — you can delete that starter file's contents in the next step, or delete the file entirely once `CashReserveCalculatorTests.swift` exists.
6. Verify: Xcode's scheme selector (top bar, next to the play/stop buttons) should now show a "Test" option when you hold Cmd and press U, or via Product → Test (Cmd+U). Run it once now — it'll pass trivially on the starter file — just to confirm the target is wired up before writing real tests.

- [ ] **Step 2: Write the failing test**

Create `MoneeTests/CashReserveCalculatorTests.swift`:

```swift
import XCTest
@testable import Monee

final class CashReserveCalculatorTests: XCTestCase {

    private func makeSummary(spareMoney: Double, avgDailyExpense: Double) -> CashReserveSummary {
        CashReserveSummary(
            spareMoney: spareMoney,
            avgDailyExpense: avgDailyExpense,
            runwayDays: avgDailyExpense > 0 ? spareMoney / avgDailyExpense : nil,
            windowDays: 30,
            expenseCount: 10,
            transactionCount: 10,
            hasEnoughData: true
        )
    }

    func testSafeWhenPostPurchaseRunwayIsComfortable() {
        let summary = makeSummary(spareMoney: 10_000_000, avgDailyExpense: 100_000)
        let result = CashReserveCalculator.evaluatePurchase(amount: 1_000_000, currentSummary: summary)

        XCTAssertEqual(result.tier, .safe)
        XCTAssertEqual(result.postPurchaseSpareMoney, 9_000_000)
        XCTAssertEqual(result.postPurchaseRunwayDays, 90)
    }

    func testSafeAtExactlyFourteenDayBoundary() {
        let summary = makeSummary(spareMoney: 1_500_000, avgDailyExpense: 100_000)
        let result = CashReserveCalculator.evaluatePurchase(amount: 100_000, currentSummary: summary)

        XCTAssertEqual(result.postPurchaseRunwayDays, 14)
        XCTAssertEqual(result.tier, .safe)
    }

    func testCautionWhenRunwayDropsBelowFourteenDaysButStaysPositive() {
        let summary = makeSummary(spareMoney: 2_000_000, avgDailyExpense: 200_000)
        let result = CashReserveCalculator.evaluatePurchase(amount: 1_000_000, currentSummary: summary)

        XCTAssertEqual(result.postPurchaseSpareMoney, 1_000_000)
        XCTAssertEqual(result.postPurchaseRunwayDays, 5)
        XCTAssertEqual(result.tier, .caution)
    }

    func testBadWhenPurchaseTakesSpareMoneyNegative() {
        let summary = makeSummary(spareMoney: 1_000_000, avgDailyExpense: 200_000)
        let result = CashReserveCalculator.evaluatePurchase(amount: 1_500_000, currentSummary: summary)

        XCTAssertEqual(result.postPurchaseSpareMoney, -500_000)
        XCTAssertEqual(result.tier, .bad)
    }

    func testSafeWhenNoSpendPaceEstablishedYetAndMoneyStaysPositive() {
        let summary = makeSummary(spareMoney: 5_000_000, avgDailyExpense: 0)
        let result = CashReserveCalculator.evaluatePurchase(amount: 1_000_000, currentSummary: summary)

        XCTAssertNil(result.postPurchaseRunwayDays)
        XCTAssertEqual(result.tier, .safe)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `xcodebuild test -project Monee.xcodeproj -scheme Monee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoneeTests/CashReserveCalculatorTests`

Expected: Build FAILS — `evaluatePurchase`, `PurchaseTier`, and `PurchaseImpact` don't exist yet. (If the exact simulator name `iPhone 16` isn't available on your machine, run `xcrun simctl list devices available` and substitute any available iOS simulator name.)

- [ ] **Step 4: Implement `evaluatePurchase`**

In `Monee/Core/Utilities/CashReserveCalculator.swift`, add `import FoundationModels` to the existing `import Foundation` line, and add this below the existing `CashReserveSummary` struct (before `enum CashReserveCalculator`):

```swift
/// Result of comparing a specific purchase amount against the current Spare Money
/// summary. `@Generable` so it can be returned directly from a FoundationModels
/// Tool call (see PurchaseImpactTool) — the model reads these fields structurally,
/// it never has to parse or recompute them from prose.
@Generable
enum PurchaseTier: String {
    case safe
    case caution
    case bad
}

@Generable
struct PurchaseImpact {
    var tier: PurchaseTier
    var postPurchaseSpareMoney: Double
    var postPurchaseRunwayDays: Double?
}
```

Then add this function inside `enum CashReserveCalculator`, after `summarize`:

```swift
/// Deterministic purchase-impact classification — the piece that used to be left
/// to the AI's own arithmetic (source of the original hallucinated-figure bug).
/// Thresholds: SAFE >= 14 days post-purchase runway, CAUTION 1-13 days,
/// BAD when the purchase would take Spare Money to zero or below.
static func evaluatePurchase(amount: Double, currentSummary: CashReserveSummary) -> PurchaseImpact {
    let postPurchaseSpareMoney = currentSummary.spareMoney - amount
    let postPurchaseRunwayDays: Double? = currentSummary.avgDailyExpense > 0
        ? postPurchaseSpareMoney / currentSummary.avgDailyExpense
        : nil

    let tier: PurchaseTier
    if postPurchaseSpareMoney <= 0 {
        tier = .bad
    } else if let runway = postPurchaseRunwayDays, runway < 14 {
        tier = .caution
    } else {
        tier = .safe
    }

    return PurchaseImpact(
        tier: tier,
        postPurchaseSpareMoney: postPurchaseSpareMoney,
        postPurchaseRunwayDays: postPurchaseRunwayDays
    )
}
```

**Verify while implementing:** if Xcode's compiler rejects `@Generable` on `PurchaseImpact` because of the `var` stored properties or the `Double?` field, open Quick Help (Option-click) on `Generable` to check current requirements — this macro is on a newer framework and its exact constraints are worth confirming directly against the SDK installed on your machine rather than trusting this plan blindly.

- [ ] **Step 5: Run the test to verify it passes**

Run: `xcodebuild test -project Monee.xcodeproj -scheme Monee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoneeTests/CashReserveCalculatorTests`

Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```bash
git add Monee/Core/Utilities/CashReserveCalculator.swift MoneeTests/
git commit -m "Add PurchaseTier/PurchaseImpact and evaluatePurchase to CashReserveCalculator"
```

---

## Task 2: `PurchaseImpactTool`

**Files:**
- Create: `Monee/Features/AIBuddy/Logic/PurchaseImpactTool.swift`

**Interfaces:**
- Consumes: `CashReserveCalculator.evaluatePurchase(amount:currentSummary:) -> PurchaseImpact`, `CashReserveSummary` (both from Task 1).
- Produces: `PurchaseImpactTool` (a `Tool` conforming to FoundationModels' `Tool` protocol), constructed as `PurchaseImpactTool(currentSummary: CashReserveSummary)`. Task 3 registers this on the `LanguageModelSession`.

This task has no automated test — `Tool` conformance is exercised by the on-device model at runtime (Task 3's manual verification step), not something XCTest can drive without invoking real on-device generation.

- [ ] **Step 1: Write the tool**

Create `Monee/Features/AIBuddy/Logic/PurchaseImpactTool.swift`:

```swift
//
//  PurchaseImpactTool.swift
//  Monee
//
//  A FoundationModels Tool the on-device model calls when the user asks about a
//  specific purchase amount. All arithmetic and tier classification happen in
//  CashReserveCalculator.evaluatePurchase (real Swift code) — this tool exists so
//  the model never has to estimate that impact itself.
//

import Foundation
import FoundationModels

struct PurchaseImpactTool: Tool {
    let name = "evaluatePurchaseImpact"
    let description = """
    Given a specific purchase amount the user is considering (in Indonesian Rupiah), \
    computes the real post-purchase Spare Money and runway, and classifies the purchase \
    as safe, caution, or bad. Always call this before commenting on whether a specific \
    purchase amount is affordable — never estimate or calculate the impact yourself.
    """

    let currentSummary: CashReserveSummary

    @Generable
    struct Arguments {
        @Guide(description: "The purchase amount mentioned by the user, in Indonesian Rupiah, as a plain number with no currency symbol or thousands separators")
        var amount: Double
    }

    func call(arguments: Arguments) async throws -> PurchaseImpact {
        CashReserveCalculator.evaluatePurchase(amount: arguments.amount, currentSummary: currentSummary)
    }
}
```

**Verify while implementing:** this is the part of the plan built on the least-certain API surface. Two things to check against Xcode's Quick Help / autocomplete once you add this file, since `FoundationModels` is a newer framework and small signature details may have shifted from what's written here:
1. `Tool`'s exact requirements — Option-click `Tool` to confirm the protocol still expects `name`, `description`, an `Arguments: ConvertibleFromGeneratedContent` associated type via a `@Generable` nested struct, and `func call(arguments:) async throws -> Output` where `Output: PromptRepresentable`.
2. Whether `PurchaseImpact` (a `@Generable` struct) satisfies `PromptRepresentable` automatically — it should, since `Generable` types conform to it, but if the compiler disagrees, that's the constraint to look up.

If either differs from what's above, adjust this file only — it doesn't change Task 1's tests or Task 3's call site, since both depend only on `PurchaseImpactTool`'s existence and `CashReserveCalculator.evaluatePurchase`, not on `Tool`'s internal conformance details.

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: BUILD SUCCEEDED. (`PurchaseImpactTool` isn't referenced anywhere yet, so this only confirms the file itself is valid — Task 3 wires it in.)

- [ ] **Step 3: Commit**

```bash
git add Monee/Features/AIBuddy/Logic/PurchaseImpactTool.swift
git commit -m "Add PurchaseImpactTool wrapping CashReserveCalculator.evaluatePurchase"
```

---

## Task 3: Wire the Tool into `AppleIntelligenceAdapter`, Update the Protocol and Call Site

**Files:**
- Modify: `Monee/Features/AIBuddy/Logic/AIAdapterProtocol.swift`
- Modify: `Monee/Features/AIBuddy/Logic/AppleIntelligenceAdapter.swift`
- Modify: `Monee/Features/AIBuddy/ViewModels/AIChatViewModel.swift`

**Interfaces:**
- Consumes: `PurchaseImpactTool` (Task 2), `CashReserveSummary` (Task 1, already produced today by `CashReserveCalculator.summarize` inside `AIChatViewModel.buildFinancialContext`).
- Produces: `AIAdapterProtocol.generateAdvice(systemContext:userPrompt:currentSummary:) async throws -> String` — the new signature every caller and implementer must match.

No new automated test here — this is glue code between real chat flow and the model; correctness is verified by the manual on-device pass in Task 4.

- [ ] **Step 1: Update the protocol signature**

In `Monee/Features/AIBuddy/Logic/AIAdapterProtocol.swift`, replace the `generateAdvice` declaration:

```swift
protocol AIAdapterProtocol {
    /// Generates financial advice based on local data and the user's input.
    /// - Parameters:
    ///   - systemContext: The serialized SwiftData (Transactions) defining the user's financial reality.
    ///   - userPrompt: The question or message submitted by the user.
    ///   - currentSummary: The pre-calculated Spare Money summary — handed through so
    ///     adapters that support tool calling (e.g. AppleIntelligenceAdapter) can ground
    ///     purchase-impact questions in real numbers instead of estimating them.
    /// - Returns: The AI's response text.
    func generateAdvice(systemContext: String, userPrompt: String, currentSummary: CashReserveSummary) async throws -> String

    /// Optional pre-flight check, run once when the chat screen appears. Return `nil` if
    /// the adapter is ready to generate; return a short user-facing reason if not.
    /// Adapters with no such concept (e.g. a network-based one) can just return nil.
    func availabilityWarning() -> String?
}
```

- [ ] **Step 2: Update the coaching rules and method signature in `AppleIntelligenceAdapter`**

In `Monee/Features/AIBuddy/Logic/AppleIntelligenceAdapter.swift`, replace the whole `generateAdvice` function (currently lines 47–120) with:

```swift
func generateAdvice(systemContext: String, userPrompt: String, currentSummary: CashReserveSummary) async throws -> String {
    try requireAvailability()

    // The Coaching Rules — becomes the session's persistent instructions.
    let coachingRules = """
                    You are 'Finance Buddy', a strict but empathetic financial coach for a self-employed user.

                    All amounts you are given, and all amounts you state back, are in Indonesian Rupiah (IDR) —
                    never dollars or any other currency. Numbers are already formatted as Rupiah (e.g. "Rp150.000")
                    in the data below; keep that formatting when you reference them.

                    YOUR CORE BEHAVIORS:
                    - Do not just give permission to spend money. Always challenge the user's spending habits gently.
                    - Ask proactive follow-up questions to force the user to justify their purchases (e.g., "Do you really need this right now?", "How will this purchase generate income for your freelance business?").
                    - Keep your answers concise, conversational, and easy to read. Do not output long essays.

                    YOU WILL BE GIVEN a SPARE MONEY SUMMARY with pre-calculated numbers (Spare Money —
                    tracked income minus tracked expenses minus the user's emergency fund total, average daily
                    spend, and runway). These are computed correctly in code — use them exactly as given,
                    never redo the arithmetic yourself. If it says there isn't enough data yet, do NOT invent
                    or estimate a Spare Money figure, runway, or spending verdict — just tell the user plainly
                    to log more transactions first.

                    Once it gives you real numbers, if the user mentions a specific purchase amount and asks
                    whether it's okay, you MUST call the evaluatePurchaseImpact tool with that amount before
                    responding — never estimate, calculate, or guess the impact yourself. The tool returns the
                    real post-purchase numbers and a tier: safe, caution, or bad. State that tier plainly and
                    back it with the numbers the tool returned, in your own coaching voice — do not recompute
                    or second-guess the tier.

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

    // New session per call, on purpose — each message is independently grounded by
    // the injected transaction context rather than relying on model-side memory.
    let session = LanguageModelSession(
        tools: [PurchaseImpactTool(currentSummary: currentSummary)],
        instructions: coachingRules
    )

    let fullPrompt = """
    User's Recent Transactions:
    \(systemContext)

    User Question:
    \(userPrompt)
    """

    do {
        return try await respondCheckingToolUse(session: session, prompt: fullPrompt)
    } catch let error as LanguageModelSession.GenerationError {
        switch error {
        case .exceededContextWindowSize:
            throw AppleIntelligenceAdapterError.contextTooLarge
        case .guardrailViolation:
            throw AppleIntelligenceAdapterError.guardrailViolation
        case .unsupportedLanguageOrLocale:
            throw AppleIntelligenceAdapterError.unsupportedLanguage
        default:
            throw AppleIntelligenceAdapterError.generationFailed(error.localizedDescription)
        }
    } catch {
        throw AppleIntelligenceAdapterError.generationFailed(error.localizedDescription)
    }
}

/// Responds, then checks whether a purchase-shaped prompt actually triggered the
/// tool. If the model skipped it, retries once with a nudge. If it skips again,
/// returns a fixed clarifying question rather than trusting an ungrounded answer —
/// see the design spec's Section 3 for why this exists.
private func respondCheckingToolUse(session: LanguageModelSession, prompt: String) async throws -> String {
    let response = try await session.respond(to: prompt)

    guard promptMentionsAnAmount(prompt), !session.transcript.containsPurchaseToolCall else {
        return response.content
    }

    let nudgedPrompt = prompt + "\n\n(Reminder: you must call evaluatePurchaseImpact before answering this.)"
    let retryResponse = try await session.respond(to: nudgedPrompt)

    if session.transcript.containsPurchaseToolCall {
        return retryResponse.content
    }

    return "I want to give you a real answer on that — can you tell me the exact amount, like \"Rp1.000.000\"?"
}

/// Cheap heuristic gate for the retry check above — not a substitute for the
/// model's own extraction, just decides whether it's worth checking the transcript
/// at all. A prompt with no digits can't be a purchase-amount question.
private func promptMentionsAnAmount(_ prompt: String) -> Bool {
    prompt.contains(where: \.isNumber)
}
```

Also add this small helper on `Transcript` in the same file (below the `AppleIntelligenceAdapter` struct's closing brace):

```swift
private extension Transcript {
    /// True if any entry in this transcript is a call to PurchaseImpactTool.
    var containsPurchaseToolCall: Bool {
        contains { entry in
            if case .toolCalls(let calls) = entry {
                return calls.contains { $0.toolName == "evaluatePurchaseImpact" }
            }
            return false
        }
    }
}
```

**Verify while implementing:** `Transcript.Entry`'s `.toolCalls` case and its element's tool-name property are the second least-certain piece of this plan. Option-click `Transcript` and `Transcript.ToolCalls` in Xcode to confirm the case name and property name (it may be `toolName`, `name`, or reached through a nested call struct) — adjust `containsPurchaseToolCall` to match what you find. Nothing else in this task depends on its internals, only on it returning a `Bool`.

- [ ] **Step 3: Update the call site in `AIChatViewModel`**

In `Monee/Features/AIBuddy/ViewModels/AIChatViewModel.swift`, `sendMessage` currently does:

```swift
let transactionContext = try buildFinancialContext(using: modelContext)

let response = try await aiAdapter.generateAdvice(
    systemContext: transactionContext,
    userPrompt: trimmed
)
```

`buildFinancialContext` already computes a `CashReserveSummary` internally (via `CashReserveCalculator.summarize`) but only returns the formatted `String`. Change `buildFinancialContext` to return both, and update the call site:

Replace the `buildFinancialContext` signature (currently `private func buildFinancialContext(using context: ModelContext) throws -> String`) and its final `return` statement:

```swift
private func buildFinancialContext(using context: ModelContext) throws -> (text: String, summary: CashReserveSummary) {
    let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
    let all = try context.fetch(descriptor)

    let expenses = all.filter { !$0.isIncome }
    let incomeTxns = all.filter { $0.isIncome }

    var sections: [String] = []

    // Pre-calculated — never let the AI redo this math itself.
    let summary = CashReserveCalculator.summarize(
        transactions: all,
        startingBalance: UserProfile.startingBalance,
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

    return (text: sections.joined(separator: "\n\n"), summary: summary)
}
```

Then update `sendMessage`'s call site (replace the two statements shown above):

```swift
let context = try buildFinancialContext(using: modelContext)

let response = try await aiAdapter.generateAdvice(
    systemContext: context.text,
    userPrompt: trimmed,
    currentSummary: context.summary
)
```

- [ ] **Step 4: Build to verify everything compiles**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: BUILD SUCCEEDED. If it fails on the `Transcript` helper from Step 2, revisit the "Verify while implementing" note there before continuing.

- [ ] **Step 5: Run the Task 1 tests again to confirm nothing broke**

Run: `xcodebuild test -project Monee.xcodeproj -scheme Monee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:MoneeTests/CashReserveCalculatorTests`

Expected: PASS, 5 tests (unchanged from Task 1 — this task didn't touch `CashReserveCalculator`).

- [ ] **Step 6: Commit**

```bash
git add Monee/Features/AIBuddy/Logic/AIAdapterProtocol.swift Monee/Features/AIBuddy/Logic/AppleIntelligenceAdapter.swift Monee/Features/AIBuddy/ViewModels/AIChatViewModel.swift
git commit -m "Wire PurchaseImpactTool into AppleIntelligenceAdapter's session"
```

---

## Task 4: Remove Dead Code, Manually Verify On-Device

**Files:**
- Delete: `Monee/Features/AIBuddy/Logic/PromptBuilder.swift`

**Interfaces:** None — this task only removes unused code and performs manual verification of Tasks 2–3's runtime behavior, which XCTest can't drive (it requires real on-device Apple Intelligence generation).

- [ ] **Step 1: Confirm `PromptBuilder` really is unused**

Run: `grep -rn "PromptBuilder" Monee/ --include="*.swift"`

Expected: only matches inside `PromptBuilder.swift` itself (its own type/file name in comments). If anything outside that file references it, stop and investigate before deleting.

- [ ] **Step 2: Delete the file**

```bash
git rm Monee/Features/AIBuddy/Logic/PromptBuilder.swift
```

- [ ] **Step 3: Build to confirm nothing depended on it**

Run: `xcodebuild -project Monee.xcodeproj -scheme Monee -destination 'platform=iOS Simulator,name=iPhone 16' build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit the deletion**

```bash
git commit -m "Remove unused PromptBuilder.swift, superseded by AIChatViewModel.buildFinancialContext"
```

- [ ] **Step 5: Manual on-device verification**

This step can't be automated — it needs the real on-device model on a physical device or simulator with Apple Intelligence enabled. Run the app (Cmd+R), open AI Buddy, log enough transactions to clear the 5-transaction confidence gate (`CashReserveCalculator.minimumTransactionsForConfidence`), then send each of these prompts, checking the response quotes numbers consistent with what you logged (not invented figures like the original "30 million" bug):

1. "I want to buy something for 1 juta, is that fine?" (Indonesian phrasing for 1,000,000)
2. "Can I spend Rp500.000 on this?"
3. "Should I buy a laptop for 5000000?"
4. "What's my biggest expense category this month?" (not a purchase question — confirms general chat still works normally and doesn't get derailed by the new tool)

For prompts 1–3, if a response ever comes back with a number that doesn't match `spareMoney - amount` from what you logged, that's a regression — re-check the `Transcript` property names from Task 3 Step 2's verification note, since a silently-mismatched property name would make `containsPurchaseToolCall` always return `false` (harmless — it just means the retry/fallback path triggers more often than needed) or the wrong tool matching entirely.

No commit for this step — it's verification only, not a code change.

---

## Self-Review Notes

- **Spec coverage:** Section 1 (tier classification) → Task 1. Section 2 (tool + Generable types, no dedicated file) → Task 2. Section 3 (adapter changes, transcript check + retry + fallback) → Task 3, with the one documented deviation (free-text final response, not `generating: PurchaseAdvice.self`) called out in Global Constraints. Section 4 (cleanup) → Task 4. Section 5 (testing) → Task 1's test target + Task 4's manual verification list. Out-of-scope items (general baseline tier, verdict UI, multi-turn memory) are untouched, as intended.
- **Type consistency checked:** `PurchaseTier`/`PurchaseImpact` (Task 1) → consumed identically in `PurchaseImpactTool.call` (Task 2) → `CashReserveSummary` (Task 1, unchanged) flows from `AIChatViewModel.buildFinancialContext` (Task 3) into `PurchaseImpactTool(currentSummary:)` (Task 2) and `AIAdapterProtocol.generateAdvice(currentSummary:)` (Task 3) consistently.
