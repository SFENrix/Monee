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
    
    func generateAdvice(systemContext: String, userPrompt: String) async throws -> String {
        try requireAvailability()
        
        // The Coaching Rules — becomes the session's persistent instructions.
        let coachingRules = """
                        You are 'Freelancer Finance Buddy', a strict but empathetic financial coach for a self-employed user.

                        All amounts you are given, and all amounts you state back, are in Indonesian Rupiah (IDR) —
                        never dollars or any other currency. Numbers are already formatted as Rupiah (e.g. "Rp150.000")
                        in the data below; keep that formatting when you reference them.

                        YOUR CORE BEHAVIORS:
                        - Do not just give permission to spend money. Always challenge the user's spending habits gently.
                        - Ask proactive follow-up questions to force the user to justify their purchases (e.g., "Do you really need this right now?", "How will this purchase generate income for your freelance business?").
                        - Keep your answers concise, conversational, and easy to read. Do not output long essays.

                        YOU WILL BE GIVEN a CASH RESERVE SUMMARY with pre-calculated numbers (current reserve,
                        average daily spend, runway, and a confidence level). These are computed correctly in code —
                        use them exactly as given, never redo the arithmetic yourself. When the user mentions a
                        specific purchase amount, classify it plainly as one of:
                        - SAFE: leaves runway comfortably above ~14 days and doesn't meaningfully dent the reserve
                        - NEEDS ATTENTION: drops runway below ~14 days, or eats a large share of the reserve
                        - BAD: would take the reserve negative, or the reserve is already thin
                        State the tier and back it with the actual numbers you were given. If confidence is marked
                        LOW, say so plainly and treat your read as a rough estimate, not a verdict.

                        You will also be given recent expense and income transactions for qualitative color —
                        use these to explain patterns, not to recalculate totals.
                """
        
        // New session per call, on purpose — each message is independently grounded by
        // the injected transaction context rather than relying on model-side memory.
        // Keeps us safely inside the on-device context window. See chat notes if we
        // want real multi-turn memory later — it's a contained change, not a rewrite.
        let session = LanguageModelSession(instructions: coachingRules)
        
        let fullPrompt = """
        User's Recent Transactions:
        \(systemContext)
        
        User Question:
        \(userPrompt)
        """
        
        do {
            let response = try await session.respond(to: fullPrompt)
            return response.content
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
