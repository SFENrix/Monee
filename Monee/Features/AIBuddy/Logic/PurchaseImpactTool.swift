//
//  PurchaseImpactTool.swift
//  Monee
//
//  A FoundationModels Tool the on-device model calls when the user asks about a
//  specific purchase amount. All arithmetic and tier classification happen in
//  CashReserveCalculator.evaluatePurchase (real Swift code) — this tool exists so
//  the model never has to estimate that impact itself.
//

import Foundation
import FoundationModels

struct PurchaseImpactTool: Tool {
    let name = "evaluatePurchaseImpact"
    let description = """
    Given a specific purchase amount the user is considering (in Indonesian Rupiah), \
    computes the real post-purchase Spare Money and runway, and classifies the purchase \
    as safe, caution, or bad. Always call this before commenting on whether a specific \
    purchase amount is affordable — never estimate or calculate the impact yourself.
    """

    let currentSummary: CashReserveSummary

    @Generable
    struct Arguments {
        @Guide(description: """
        The purchase amount mentioned by the user, converted to a plain Indonesian Rupiah \
        number with no currency symbol, no thousands separators, and no abbreviation. \
        Examples of user phrasing and the value to produce: "17 million" -> 17000000, \
        "17 juta" or "17jt" -> 17000000, "Rp17.000.000" -> 17000000, "500 thousand" or \
        "500rb" -> 500000.
        """)
        var amount: Double
    }

    func call(arguments: Arguments) async throws -> PurchaseImpact {
        #if DEBUG
        print("[PurchaseImpactTool] received amount: \(arguments.amount)")
        #endif
        return await CashReserveCalculator.evaluatePurchase(amount: arguments.amount, currentSummary: currentSummary)
    }
}
