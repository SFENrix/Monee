//
//  AIChatViewModel.swift
//  FreelanceFinance
//
//  Updated 02/07/26 — rebuilt to match AIChatView's contract: exposes `messages` and
//  `currentSessionTitle` directly instead of leaving the view to reach into ChatSession,
//  and separates `startNewSession()` (local reset, called by the toolbar button) from
//  the private session-creation path (only runs once the user actually sends something —
//  no empty ChatSession rows left behind if they tap "new chat" and change their mind).
//

import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
class AIChatViewModel: ObservableObject {

    private let aiAdapter: AIAdapterProtocol

    @Published var messages: [ChatMessage] = []
    @Published var isThinking: Bool = false
    @Published var errorMessage: String? = nil

    private var currentSession: ChatSession?

    var currentSessionTitle: String {
        currentSession?.title ?? "New Chat"
    }

    init(aiAdapter: AIAdapterProtocol = AppleIntelligenceAdapter()) {
        self.aiAdapter = aiAdapter
    }

    /// Runs once when AIChatView appears. Surfaces an availability warning up front
    /// (e.g. Apple Intelligence off, wrong language) instead of waiting for the first
    /// failed send.
    func bootstrap(modelContext: ModelContext) {
        errorMessage = aiAdapter.availabilityWarning()
    }

    /// Clears the active thread locally. Doesn't touch the database — a real
    /// ChatSession is only created once the user actually sends a message, so
    /// tapping "new chat" and changing your mind doesn't leave an empty row behind.
    func startNewSession() {
        currentSession = nil
        messages = []
        errorMessage = aiAdapter.availabilityWarning()
    }

    /// Loads a previously saved thread from history.
    func loadSession(_ session: ChatSession, modelContext: ModelContext) {
        currentSession = session
        errorMessage = aiAdapter.availabilityWarning()

        let sessionID = session.id
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        do {
            messages = try modelContext.fetch(descriptor)
        } catch {
            errorMessage = "Couldn't load that chat: \(error.localizedDescription)"
            messages = []
        }
    }

    /// Processes the user's message, fetches RAG context, and saves the turn.
    func sendMessage(_ text: String, modelContext: ModelContext) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isThinking = true
        errorMessage = nil

        let session = currentSession ?? beginSession(seedTitle: trimmed, modelContext: modelContext)

        let userMessage = ChatMessage(sessionID: session.id, role: .user, content: trimmed)
        modelContext.insert(userMessage)
        messages.append(userMessage)

        do {
            let transactionContext = try buildFinancialContext(using: modelContext)

            let response = try await aiAdapter.generateAdvice(
                systemContext: transactionContext,
                userPrompt: trimmed
            )

            let assistantMessage = ChatMessage(sessionID: session.id, role: .assistant, content: response)
            modelContext.insert(assistantMessage)
            messages.append(assistantMessage)

            session.updatedAt = Date()
            try modelContext.save()

        } catch {
            errorMessage = error.localizedDescription
        }

        isThinking = false
    }

    /// Actually creates and persists a new ChatSession — only called from sendMessage,
    /// the first time a thread needs one.
    private func beginSession(seedTitle: String, modelContext: ModelContext) -> ChatSession {
        let title = String(seedTitle.prefix(40))
        let session = ChatSession(title: title.isEmpty ? "New Chat" : title)
        modelContext.insert(session)
        currentSession = session
        return session
    }

 
    /// Builds the financial context handed to the AI. Expenses are ALWAYS real data,
        /// however sparse — never fabricated, since a guessed baseline can mislead the
        /// model into false confidence. Income falls back to the user's self-reported
        /// estimate only when real income transactions are too thin to trust, and that
        /// fallback is explicitly labeled as a guess so the AI can hedge accordingly.
    private func buildFinancialContext(using context: ModelContext) throws -> String {
            let descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            let all = try context.fetch(descriptor)

            let expenses = all.filter { !$0.isIncome }
            let incomeTxns = all.filter { $0.isIncome }

            var sections: [String] = []

            // Pre-calculated — never let the AI redo this math itself.
            let summary = CashReserveCalculator.summarize(
                transactions: all,
                fallbackMonthlyIncome: UserProfile.estimatedMonthlyIncome
            )
            sections.append(formatReserveSummary(summary))

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

            return sections.joined(separator: "\n\n")
        }

        private func formatReserveSummary(_ summary: CashReserveSummary) -> String {
            var lines = [
                "CASH RESERVE SUMMARY (pre-calculated in code — use these exact numbers, do not recompute):",
                "- Current reserve: \(summary.currentReserve.idrFormatted)",
                "- Average daily spend (last \(summary.windowDays) day\(summary.windowDays == 1 ? "" : "s")): \(summary.avgDailyExpense.idrFormatted)"
            ]
            if let runway = summary.runwayDays {
                lines.append("- Estimated runway at current pace: \(String(format: "%.0f", runway)) days")
            } else {
                lines.append("- Runway: not calculable yet (no spending pace established)")
            }
            lines.append(summary.isDataSufficient
                ? "- Confidence: HIGH — based on \(summary.expenseCount) logged expenses."
                : "- Confidence: LOW — only \(summary.expenseCount) expenses logged. Treat conclusions as rough and say so.")

            // This is exactly why this reserve figure can differ from the plain running
            // balance shown in the Tracker tab — the user has no other way to see this
            // blend happening, so the AI needs to say so explicitly rather than silently
            // citing a number that won't match what they see on screen.
            if summary.estimatedIncomeBlended > 0 {
                lines.append("""
                - IMPORTANT: \(summary.estimatedIncomeBlended.idrFormatted) of this reserve is from the user's \
                self-reported income estimate, not logged transactions — you don't have enough logged income yet. \
                This is why this number is higher than the running balance shown in their Tracker tab. \
                Mention this plainly if you state the reserve figure, so it doesn't look like a mismatch or error.
                """)
            }
            return lines.joined(separator: "\n")
        }
    
}
