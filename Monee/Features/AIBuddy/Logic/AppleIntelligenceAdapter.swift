//
//  AppleIntelligenceAdapter.swift
//  FreelanceFinance
//
//  Created by Rio Ferdinand on 30/06/26.
//  Updated 02/07/26 — replaced simulated delay with real on-device generation via
//  the FoundationModels framework. Requires iOS 26.0+ deployment target.
//

import Foundation
import FoundationModels

/// Errors specific to on-device generation, phrased for direct display to the user —
/// AIChatViewModel forwards `localizedDescription` straight into `errorMessage`.
enum AppleIntelligenceAdapterError: LocalizedError {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case contextTooLarge
    case guardrailViolation
    case unsupportedLanguage
    case generationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Turn on Apple Intelligence in Settings → Apple Intelligence & Siri to use the AI Buddy."
        case .modelNotReady:
            return "Apple Intelligence is still downloading its on-device model. Try again in a moment."
        case .contextTooLarge:
            return "That's a lot of transaction history — try a shorter or more specific question."
        case .guardrailViolation:
            return "I can't respond to that one. Try rephrasing your question."
        case .unsupportedLanguage:
            return "Set your device and Siri language to a supported language (Settings → General → Language & Region) to use the AI Buddy."
        case .generationFailed(let reason):
            return "Couldn't generate a response: \(reason)"
        }
    }
}

/// The primary engine for on-device AI processing using Apple's Foundation Models framework.
struct AppleIntelligenceAdapter: AIAdapterProtocol {
    
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

                        Once the user mentions a specific purchase amount and asks whether it's okay to buy,
                        call the evaluatePurchaseImpact tool with that amount before responding — never guess
                        the impact yourself. The tool returns the real post-purchase tier (safe, caution, or bad)
                        along with two already Rupiah-formatted strings: purchaseAmountFormatted (e.g.
                        "Rp17.000.000") for restating what the user wants to buy, and
                        postPurchaseSpareMoneyFormatted (e.g. "Rp1.190.000") for the remaining Spare Money.
                        Copy both strings into your response character-for-character — never retype, reformat,
                        or add/remove digits from either one, and never state the raw postPurchaseSpareMoney
                        number or your own transcription of the purchase amount instead. You are unreliable at
                        inserting thousands-separators correctly and past attempts have silently multiplied
                        figures by 10 or 100, or used commas instead of dots. State the tier plainly and back
                        it up within your own coaching voice — do not recompute or second-guess the tool's
                        result.

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
        
        // New session per call, on purpose, independently grounded by
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
    /// returns a fixed clarifying question rather than trusting an ungrounded answer.
    private func respondCheckingToolUse(session: LanguageModelSession, prompt: String) async throws -> String {
        let response = try await session.respond(to: prompt)

        #if DEBUG
        let entries = Array(session.transcript)
        print("[AIAdapter] first pass — mentionsAmount: \(promptMentionsAnAmount(prompt)), toolCalled: \(session.transcript.containsPurchaseToolCall), transcript entries: \(entries.count)")
        for entry in entries {
            print("[AIAdapter]   entry: \(entry)")
        }
        #endif

        guard promptMentionsAnAmount(prompt), !session.transcript.containsPurchaseToolCall else {
            return response.content
        }

        let nudgedPrompt = prompt + "\n\n(Reminder: you must call evaluatePurchaseImpact before answering this.)"
        let retryResponse = try await session.respond(to: nudgedPrompt)

        #if DEBUG
        print("[AIAdapter] retry pass — toolCalled: \(session.transcript.containsPurchaseToolCall), transcript entries: \(Array(session.transcript).count)")
        #endif

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
    
    func availabilityWarning() -> String? {
        do {
            try requireAvailability()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
    
    private func requireAvailability() throws {
        switch SystemLanguageModel.default.availability {
        case .available:
            return
        case .unavailable(.deviceNotEligible):
            throw AppleIntelligenceAdapterError.deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            throw AppleIntelligenceAdapterError.appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            throw AppleIntelligenceAdapterError.modelNotReady
        case .unavailable:
            throw AppleIntelligenceAdapterError.generationFailed("Apple Intelligence is unavailable right now.")
        }
    }
}
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
