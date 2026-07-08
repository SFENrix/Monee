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


    /// Builds the financial context handed to the AI. Two independent pieces:
    /// (1) the deterministic Spare Money summary, computed only from logged
    /// transactions and the user's own emergency fund total — no self-reported
    /// number is ever mixed into this arithmetic; (2) the user's emergency fund
    /// status, always shown but always labeled as self-managed/qualitative,
    /// never treated as a second use of the number already subtracted in (1).
    private func buildFinancialContext(using context: ModelContext) throws -> String {
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

        return sections.joined(separator: "\n\n")
    }

    /// The AI is only allowed to state a Spare Money/runway figure or a spending
    /// verdict once there's enough logged history to trust it — below the threshold,
    /// it should just encourage the user to log more, not guess with a thin sample.
    private func formatSpareMoneySummary(_ summary: CashReserveSummary) -> String {
        guard summary.hasEnoughData else {
            let remaining = CashReserveCalculator.minimumTransactionsForConfidence - summary.transactionCount
            return """
            SPARE MONEY SUMMARY: Not enough data yet — only \(summary.transactionCount) transaction(s) logged. \
            Log \(remaining) more (backdated entries are fine) before stating a Spare Money figure, runway, or \
            spending verdict. Do not compute or guess a number — tell the user plainly to log more transactions \
            first so future advice is reliable.
            """
        }

        var lines = [
            "SPARE MONEY SUMMARY (pre-calculated in code — use these exact numbers, do not recompute):",
            "- Spare Money: \(summary.spareMoney.idrFormatted)",
            "- Average daily spend (last \(summary.windowDays) day\(summary.windowDays == 1 ? "" : "s")): \(summary.avgDailyExpense.idrFormatted)"
        ]
        if let runway = summary.runwayDays {
            lines.append("- Estimated runway at current pace: \(String(format: "%.0f", runway)) days")
        } else {
            lines.append("- Runway: not calculable yet (no spending pace established)")
        }
        return lines.joined(separator: "\n")
    }

    /// Self-managed by the user (added manually, additions-only), already subtracted
    /// out of Spare Money above — this block is purely qualitative status for the AI
    /// to reference when relevant (see AppleIntelligenceAdapter's coaching rules),
    /// never a second use of the number in arithmetic.
    private func formatEmergencyFundContext() -> String {
        let total = UserProfile.emergencyFundTotal
        guard let target = UserProfile.emergencyFundTarget else {
            return """
            EMERGENCY FUND: No target set yet — the user hasn't provided an estimated monthly expense, \
            which the target (12x that estimate) depends on. If relevant, encourage them to complete that \
            estimate in Profile so their emergency fund progress can be tracked.
            """
        }
        let percent = min(100, Int((total / target) * 100))
        return """
        EMERGENCY FUND (self-managed by the user, already subtracted out of Spare Money above — \
        this is qualitative status only, not a second use of that number):
        - Current: \(total.idrFormatted)
        - Target (12x estimated monthly expense): \(target.idrFormatted)
        - Percent filled: \(percent)%
        """
    }
    
}
