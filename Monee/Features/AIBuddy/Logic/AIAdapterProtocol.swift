//
//  AIAdapterProtocol.swift
//  FreelanceFinance
//
//  Created by Rio Ferdinand on 30/06/26.
//


import Foundation

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

