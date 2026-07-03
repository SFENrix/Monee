//
//  PromptBuilder.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//


//
//  PromptBuilder.swift
//  FreelanceFinance
//
//  Created by Rio Ferdinand on 02/07/26.
//
//  Formats SwiftData (Transactions + recent ChatMessages) into the system context string
//  handed to whichever AIAdapterProtocol implementation is active. Kept adapter-agnostic
//  on purpose — Apple Intelligence and a future OpenAI fallback both consume the same shape.
//

import Foundation

enum PromptBuilder {

    /// Combines financial context and recent conversation history into one block of text.
    /// - Parameters:
    ///   - transactions: The user's transactions, most recent first.
    ///   - recentMessages: Messages already in the current session, oldest first.
    static func buildSystemContext(transactions: [Transaction], recentMessages: [ChatMessage]) -> String {
        var sections: [String] = ["FINANCIAL CONTEXT:\n\(serializeTransactions(transactions))"]

        let history = serializeHistory(recentMessages)
        if !history.isEmpty {
            sections.append("CONVERSATION SO FAR:\n\(history)")
        }

        return sections.joined(separator: "\n\n")
    }

    private static func serializeTransactions(_ transactions: [Transaction]) -> String {
        guard !transactions.isEmpty else {
            return "No recent transactions found. The user's financial slate is clean."
        }

        // Cap at 50 so we don't blow past the on-device model's context window.
        return transactions.prefix(50).map { txn in
            "- \(txn.date.formatted(date: .abbreviated, time: .omitted)): \(txn.title) (\(txn.category.rawValue), \(txn.amount.idrFormatted))"
            // was: ...($\(String(format: "%.2f", txn.amount)))
        }.joined(separator: "\n")
    }

    private static func serializeHistory(_ messages: [ChatMessage]) -> String {
        guard !messages.isEmpty else { return "" }

        // Last 10 turns is plenty of context for coaching-style advice without bloating the prompt.
        return messages.suffix(10).map { message in
            let speaker = message.role == .user ? "User" : "Buddy"
            return "\(speaker): \(message.content)"
        }.joined(separator: "\n")
    }
}
