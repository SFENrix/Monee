# AIBuddy Purchase Verdict — Tool Calling & Guided Generation — Design

**Goal:** Stop AIBuddy from hallucinating purchase-impact numbers by moving all arithmetic and tier classification (SAFE / CAUTION / BAD) into Swift, and using Apple's Foundation Models Tool calling + Guided Generation so the model only ever narrates a verdict it's handed, never computes or invents one.

**Scope boundary:** This round covers the purchase-impact flow only (user asks "can I buy X for Y?"). The general "how's my financial situation?" question (no purchase amount) already reads correct numbers from the existing Spare Money summary and is not being changed here — a documented follow-up, not part of this spec.

## Background

`AppleIntelligenceAdapter.generateAdvice` (`Monee/Features/AIBuddy/Logic/AppleIntelligenceAdapter.swift`) currently injects a pre-calculated Spare Money summary (via `CashReserveCalculator`) as static context, then instructs the model in prose to classify any purchase amount the user mentions into SAFE / NEEDS ATTENTION / BAD by comparing it against that summary. Confirmed bug: this asks the model to perform subtraction/comparison on a number it parsed out of free text — exactly the kind of arithmetic on-device Foundation Models are documented to be unreliable at. Observed failure: starting balance 10,000,000, income 5,000,000, expense 4,000,000, user asks about a 1,000,000 purchase — the model's response included a fabricated "30 million" spare figure with no basis in the injected context.

`CashReserveCalculator.swift` already establishes the pattern this design extends: deterministic math lives in Swift, the AI's job is to interpret and coach, never to compute. This design applies that same principle to purchase-specific comparisons, which today are the one place it's been left to the model.

`PromptBuilder.swift` (`Monee/Features/AIBuddy/Logic/PromptBuilder.swift`) is dead code — nothing calls it; `AIChatViewModel.buildFinancialContext` superseded it. Removed as part of this pass since it sits in the same folder being touched and would otherwise read as a second, competing context-builder to anyone new to the code.

## 1. Purchase Tier Classification — `CashReserveCalculator`

New pure function alongside the existing `summarize`, reusing its output rather than re-fetching transactions:

```swift
enum PurchaseTier: String { case safe, caution, bad }

struct PurchaseImpact {
    let tier: PurchaseTier
    let postPurchaseSpareMoney: Double
    let postPurchaseRunwayDays: Double?
}

static func evaluatePurchase(amount: Double, currentSummary: CashReserveSummary) -> PurchaseImpact
```

Thresholds (runway-only, deliberately simple over the alternative of also gating on % of Spare Money consumed — one clear number is easier to reason about and to tune later than a compound rule):

- **SAFE** — post-purchase runway ≥ 14 days
- **CAUTION** — post-purchase runway 1–13 days
- **BAD** — post-purchase runway ≤ 0 (Spare Money goes negative)

`postPurchaseSpareMoney = currentSummary.spareMoney - amount`; `postPurchaseRunwayDays` recomputed against `currentSummary.avgDailyExpense` the same way `runwayDays` is today (nil if no spend pace established).

## 2. `PurchaseImpactTool` — New File

`Monee/Features/AIBuddy/Logic/PurchaseImpactTool.swift`. A single new file containing both the tool and its output type — no dedicated file for the `@Generable` type, since it has exactly one call site (Apple's own sample code colocates small `@Generable` output contracts with the call site that produces them; a type only earns its own file once it's reused across multiple tools/adapters, which isn't the case here).

- `PurchaseImpactTool: Tool` — constructed with the current `CashReserveSummary` (computed once per message, same as today).
- Its argument schema captures the purchase amount the model extracts from the user's text.
- `call(arguments:)` runs `CashReserveCalculator.evaluatePurchase(amount:currentSummary:)` — real Swift math, zero model involvement — and returns the result as the tool's output.
- `PurchaseAdvice` (the final `@Generable` shape the model produces after getting the tool's result back) also lives in this file:

```swift
@Generable
struct PurchaseAdvice {
    var tier: PurchaseTier
    @Guide(description: "One or two sentences, coaching tone, no numbers restated beyond what's natural")
    var reasoning: String
}
```

Guided Generation constrains the final response to these two fields — the model narrates within a fixed shape, it cannot wander into inventing its own figure the way free-text generation could.

## 3. `AppleIntelligenceAdapter` Changes

- `generateAdvice` gains a `currentSummary: CashReserveSummary` parameter (needed to construct the tool). `AIAdapterProtocol.generateAdvice` signature updates to match — its one implementer, `AppleIntelligenceAdapter`, and its one caller, `AIChatViewModel.sendMessage`, both update accordingly. `AIChatViewModel` already computes this summary in `buildFinancialContext`; it's passed through rather than recomputed.
- `LanguageModelSession` construction adds `tools: [PurchaseImpactTool(summary: currentSummary)]`.
- `coachingRules` changes: the existing inline "classify plainly as one of: SAFE / NEEDS ATTENTION / BAD..." paragraph is deleted — that logic now lives in `CashReserveCalculator.evaluatePurchase`, not in prose the model has to remember and apply correctly every time. Replaced with a shorter instruction: when the user mentions a specific purchase amount, call `PurchaseImpactTool` to get the real verdict, then explain it — never estimate or compute the verdict directly.
- New private helper, e.g. `respondWithPurchaseAdvice(session:prompt:) async throws -> String`, isolating the respond → verify-tool-was-called → retry-once-if-not → flatten-to-string sequence out of `generateAdvice`, keeping the latter readable:
  1. Call `session.respond(to:)`.
  2. Inspect `session.transcript` for a `PurchaseImpactTool` call entry.
  3. If the user's message looked purchase-shaped (a numeric amount was present) but no tool call occurred, retry once with a nudged instruction appended to the prompt.
  4. If the retry also shows no tool call, return a fixed fallback string asking the user to state the amount plainly — never let an ungrounded verdict through on a second attempt either.
  5. On success, flatten the resulting `PurchaseAdvice` into the same kind of plain-text string the chat UI already expects (e.g. a short sentence stating the tier in words, followed by the reasoning) — `AIAdapterProtocol.generateAdvice` keeps its existing `String` return type, `ChatMessage.content` (`Monee/Core/Database/Models/ChatMessage.swift`) and the chat UI are untouched by this change.

Existing error handling (`contextTooLarge`, `guardrailViolation`, `modelNotReady`, etc., via the existing `catch let error as LanguageModelSession.GenerationError` block) is unchanged — tool calling surfaces the same error types, no new `AppleIntelligenceAdapterError` cases needed.

## 4. Cleanup (same pass, same folder)

- Delete `PromptBuilder.swift` — confirmed unused (`grep` shows no call sites outside its own file and one comment reference).
- No other structural changes to `Features/AIBuddy/` — `AIChatView.swift`, `chatBubbles.swift`, `chatInputBar.swift`, `MessageText.swift` are all unaffected since the adapter's public contract (`String` in, `String` out) doesn't change.

## 5. Testing

Not unit-testable end-to-end (model tool-invocation and phrasing aren't deterministic). What is:

- `CashReserveCalculator.evaluatePurchase` — pure function, fully unit-testable: given a fixed `CashReserveSummary` and amount, assert the correct tier and post-purchase figures. This is where real test coverage concentrates, since it's also where the original compliance/correctness risk lived.
- `PurchaseImpactTool.call(arguments:)` — thin wrapper, testable directly with fixed arguments, bypassing the model.
- The model-invocation path (does the tool actually get called, does the retry work) isn't unit-testable — needs a short, maintained list of manual test prompts (varied purchase phrasings, including Indonesian-language ones like "sejuta" / "1jt") run on-device against `session.transcript` output whenever the coaching rules change.

## Out of Scope

- General "how's my situation?" baseline tier (no purchase amount) — follow-up spec.
- Any UI change to represent the verdict visually (badge, color) — explicitly deferred; verdict stays inside the plain-text chat bubble for now.
- Multi-turn / persistent session memory — each AIBuddy call remains a fresh session per message, unchanged from today.
