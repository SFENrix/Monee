//
//  UserFinancialProfile.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//


//
//  UserFinancialProfile.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//
//  Deliberately NOT a SwiftData model or a full "profile" — it's one editable number,
//  used only as a fallback by the AI context builder when real income transaction
//  history is too sparse to trust. As real income transactions accumulate, this value
//  stops being used (see AIChatViewModel.buildFinancialContext). UserDefaults-backed
//  so it's readable from a plain class (AIChatViewModel), not just SwiftUI views.
//

import Foundation

enum UserFinancialProfile {
    private static let key = "estimatedMonthlyIncome"

    static var estimatedMonthlyIncome: Double? {
        get {
            let value = UserDefaults.standard.double(forKey: key)
            return value > 0 ? value : nil
        }
        set {
            if let newValue, newValue > 0 {
                UserDefaults.standard.set(newValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    static var hasEstimate: Bool { estimatedMonthlyIncome != nil }
}