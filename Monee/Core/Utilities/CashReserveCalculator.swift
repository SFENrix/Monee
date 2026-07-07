//
//  CashReserveSummary.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//


//
//  CashReserveCalculator.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//
//  Deterministic financial math, kept entirely separate from the AI. LLMs — especially
//  compact on-device models — are unreliable at summing/averaging over transaction lists.
//  This computes the real numbers in Swift so the AI's job is to interpret and coach,
//  not to do arithmetic it might get wrong.
//

import Foundation

struct CashReserveSummary {
    let currentReserve: Double       // income logged - expenses logged, all time (may include
                                      // a blended income estimate — see estimatedIncomeBlended)
    let avgDailyExpense: Double      // trailing window average (up to 30 days of history)
    let runwayDays: Double?          // currentReserve / avgDailyExpense; nil if no spend pace yet
    let windowDays: Int              // how many days avgDailyExpense is actually based on
    let expenseCount: Int
    let isDataSufficient: Bool       // fewer than 5 expenses or <7 days span = low confidence
    /// Portion of `currentReserve` that comes from the user's self-reported income estimate
    /// rather than logged transactions — 0 when there's enough real income history to not
    /// need it. This is exactly the amount by which this reserve figure can diverge from a
    /// plain sum of logged transactions (e.g. the Tracker's running balance) — surfaced so
    /// callers (the AI Buddy) can say plainly when and why the two numbers don't match.
    let estimatedIncomeBlended: Double
}

enum CashReserveCalculator {
    static func summarize(transactions: [Transaction], fallbackMonthlyIncome: Double?) -> CashReserveSummary {
        let income = transactions.filter { $0.isIncome }
        let expenses = transactions.filter { !$0.isIncome }

        let loggedIncome = income.reduce(0) { $0 + $1.amount }
        let totalExpenses = expenses.reduce(0) { $0 + $1.amount }

        // Real income data is thin early on — blend in the self-reported estimate so
        // month-one reserve isn't wildly understated. Pro-rated so a day-one user isn't
        // credited a full month of income they haven't logged yet.
        let effectiveIncome: Double
        if income.count >= 3 {
            effectiveIncome = loggedIncome
        } else if let fallback = fallbackMonthlyIncome {
            let daysTracked = transactions.map(\.date).min()
                .map { Date().timeIntervalSince($0) / 86_400 } ?? 0
            let fraction = min(max(daysTracked / 30.0, 0), 1)
            effectiveIncome = loggedIncome + (fallback * fraction)
        } else {
            effectiveIncome = loggedIncome
        }

        let currentReserve = effectiveIncome - totalExpenses

        // Trailing-window burn rate — the more real history exists, the more this
        // smooths out one-off spikes instead of one big purchase skewing everything.
        let now = Date()
        let earliestExpenseDate = expenses.map(\.date).min() ?? now
        let daysOfHistory = max(1, Int(now.timeIntervalSince(earliestExpenseDate) / 86_400))
        let window = min(daysOfHistory, 30)
        let windowStart = now.addingTimeInterval(-Double(window) * 86_400)
        let recentTotal = expenses.filter { $0.date >= windowStart }.reduce(0) { $0 + $1.amount }
        let avgDailyExpense = window > 0 ? recentTotal / Double(window) : 0

        let runwayDays: Double? = avgDailyExpense > 0 ? currentReserve / avgDailyExpense : nil
        let isDataSufficient = expenses.count >= 5 && daysOfHistory >= 7

        return CashReserveSummary(
            currentReserve: currentReserve,
            avgDailyExpense: avgDailyExpense,
            runwayDays: runwayDays,
            windowDays: window,
            expenseCount: expenses.count,
            isDataSufficient: isDataSufficient,
            estimatedIncomeBlended: effectiveIncome - loggedIncome
        )
    }
}