//
//  CashReserveCalculator.swift
//  Monee
//
//  Deterministic financial math, kept entirely separate from the AI. LLMs — especially
//  compact on-device models — are unreliable at summing/averaging over transaction lists.
//  This computes the real numbers in Swift so the AI's job is to interpret and coach,
//  not to do arithmetic it might get wrong.
//
//  Spare Money = onboarding starting balance + tracked income - tracked expenses -
//  the user's emergency fund total. Deliberately does NOT blend in any self-reported
//  income estimate — that number lives in UserProfile and is handed to the AI as
//  separate qualitative context (see AIChatViewModel.formatSpareMoneySummary /
//  formatEmergencyFundContext). Blending used to happen here; it produced figures
//  that looked arbitrary to the user once few transactions were logged. This file
//  now answers exactly one question: what do the user's logged transactions (plus
//  their starting balance and emergency fund contributions) say is actually free to
//  spend, and is there enough logged history to trust the answer.
//

import Foundation
import FoundationModels

struct CashReserveSummary {
    let spareMoney: Double           // startingBalance + tracked income - tracked expenses - emergency fund total
    let avgDailyExpense: Double      // trailing window average (up to 30 days of history)
    let runwayDays: Double?          // spareMoney / avgDailyExpense; nil if no spend pace yet
    let windowDays: Int              // how many days avgDailyExpense is actually based on
    let expenseCount: Int
    let transactionCount: Int        // income + expenses combined — what the confidence gate checks
    /// True once the user has logged CashReserveCalculator.minimumTransactionsForConfidence
    /// or more transactions (of any kind). Below this, the AI should not state a Spare Money
    /// figure, runway, or spending verdict — just encourage logging more.
    let hasEnoughData: Bool
}

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
    var postPurchaseRunwayDays: Double? = nil
}

enum CashReserveCalculator {
    /// Below this many total logged transactions, the Spare Money/runway numbers are
    /// considered too thin to state to the user. A flat count, not a compound
    /// date+count rule — simpler to reason about and to explain in the UI.
    static let minimumTransactionsForConfidence = 5

    static func summarize(transactions: [Transaction], startingBalance: Double, emergencyFundTotal: Double) -> CashReserveSummary {
        let income = transactions.filter { $0.isIncome }
        let expenses = transactions.filter { !$0.isIncome }

        let totalIncome = income.reduce(0) { $0 + $1.amount }
        let totalExpenses = expenses.reduce(0) { $0 + $1.amount }
        let spareMoney = startingBalance + totalIncome - totalExpenses - emergencyFundTotal

        // Trailing-window burn rate — the more real history exists, the more this
        // smooths out one-off spikes instead of one big purchase skewing everything.
        let now = Date()
        let earliestExpenseDate = expenses.map(\.date).min() ?? now
        let daysOfHistory = max(1, Int(now.timeIntervalSince(earliestExpenseDate) / 86_400))
        let window = min(daysOfHistory, 30)
        let windowStart = now.addingTimeInterval(-Double(window) * 86_400)
        let recentTotal = expenses.filter { $0.date >= windowStart }.reduce(0) { $0 + $1.amount }
        let avgDailyExpense = window > 0 ? recentTotal / Double(window) : 0

        let runwayDays: Double? = avgDailyExpense > 0 ? spareMoney / avgDailyExpense : nil

        return CashReserveSummary(
            spareMoney: spareMoney,
            avgDailyExpense: avgDailyExpense,
            runwayDays: runwayDays,
            windowDays: window,
            expenseCount: expenses.count,
            transactionCount: transactions.count,
            hasEnoughData: transactions.count >= minimumTransactionsForConfidence
        )
    }
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
}
