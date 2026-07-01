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
    /// - Returns: The AI's response text.
    func generateAdvice(systemContext: String, userPrompt: String) async throws -> String
}