//
//  UserProfile.swift
//  Monee
//
//  Single source of truth for onboarding-collected, self-reported profile data,
//  plus the user-managed emergency fund total. None of these numbers are ever
//  mixed into CashReserveCalculator's income/expense arithmetic directly — the
//  fund total is subtracted as its own explicit term (see CashReserveCalculator
//  .summarize), and the profile estimates are handed to the AI as separate,
//  always-labeled qualitative context (see AIChatViewModel.formatEmergencyFundContext
//  and formatSpareMoneySummary). UserDefaults-backed so it's readable from a plain
//  class (AIChatViewModel), not just SwiftUI views.
//

import Foundation

/// Rough life/family situation captured during onboarding — used to give the AI
/// context on tone (stricter vs. more forgiving about spending) and to give
/// Profile's Overview section something to anchor to before real transactions exist.
enum OnboardingStatus: String, CaseIterable, Identifiable, Codable {
    case single = "Single"
    case married = "Married"
    case withChild = "With child"

    var id: String { rawValue }
}

enum UserProfile {
    private static let nameKey = "userProfile.name"
    private static let statusKey = "userProfile.status"
    private static let estimatedMonthlyIncomeKey = "userProfile.estimatedMonthlyIncome"
    private static let estimatedMonthlyExpenseKey = "userProfile.estimatedMonthlyExpense"
    private static let emergencyFundTotalKey = "userProfile.emergencyFundTotal"
    private static let hasCompletedOnboardingKey = "userProfile.hasCompletedOnboarding"

    static var name: String? {
        get {
            let value = UserDefaults.standard.string(forKey: nameKey)
            return (value?.isEmpty ?? true) ? nil : value
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: nameKey)
            } else {
                UserDefaults.standard.removeObject(forKey: nameKey)
            }
        }
    }

    static var status: OnboardingStatus? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: statusKey) else { return nil }
            return OnboardingStatus(rawValue: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: statusKey)
            } else {
                UserDefaults.standard.removeObject(forKey: statusKey)
            }
        }
    }

    static var estimatedMonthlyIncome: Double? {
        get {
            let value = UserDefaults.standard.double(forKey: estimatedMonthlyIncomeKey)
            return value > 0 ? value : nil
        }
        set {
            if let newValue, newValue > 0 {
                UserDefaults.standard.set(newValue, forKey: estimatedMonthlyIncomeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: estimatedMonthlyIncomeKey)
            }
        }
    }

    static var estimatedMonthlyExpense: Double? {
        get {
            let value = UserDefaults.standard.double(forKey: estimatedMonthlyExpenseKey)
            return value > 0 ? value : nil
        }
        set {
            if let newValue, newValue > 0 {
                UserDefaults.standard.set(newValue, forKey: estimatedMonthlyExpenseKey)
            } else {
                UserDefaults.standard.removeObject(forKey: estimatedMonthlyExpenseKey)
            }
        }
    }

    /// Additions-only running total the user has manually set aside as an emergency
    /// fund — never mixed into CashReserveCalculator's income/expense sums directly,
    /// but subtracted from them as its own term (see CashReserveCalculator.summarize).
    /// Clamped to non-negative; this app has no withdrawal flow yet.
    static var emergencyFundTotal: Double {
        get { UserDefaults.standard.double(forKey: emergencyFundTotalKey) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: emergencyFundTotalKey) }
    }

    /// 12x the user's estimated monthly expense. `nil` until that estimate exists —
    /// there's nothing meaningful to show a fill percentage against otherwise.
    static var emergencyFundTarget: Double? {
        guard let expense = estimatedMonthlyExpense else { return nil }
        return expense * 12
    }

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasCompletedOnboardingKey) }
    }
}
