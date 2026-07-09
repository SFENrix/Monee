//
//  Transaction.swift
//  Monee
//
//  Created by Rio Ferdinand on 01/07/26.
//  Updated 02/07/26 — added `title` (fixes AIChatViewModel referencing a property that
//  didn't exist), wired up `category` on the model (was defined but never used), added `source`.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: Preset categories (GANTI ISINYA NANTI, YANG PENTING BISA DEMO DULU)

enum TransactionCategory: String, Codable, CaseIterable {
    case income = "Income"
    case food = "Food"
    case household = "Household"
    case entertaiment = "Entertaiment"
    case other = "Other"
   
}

/// Where a transaction's data came from — lets the UI (and later, confidence scoring)
/// distinguish "user typed this" from "OCR guessed this and the user confirmed it".
enum TransactionSource: String, Codable {
    case manual   // via QuickEntryFormView
    case ocr      // via VisionOCRService + RegexParser, confirmed by the user
}

@Model
final class Transaction {
    var id: UUID
    /// Short label, e.g. "Adobe Creative Cloud" or "Grab to client meeting".
    /// For OCR transactions this is the merchant name; for manual entries, whatever the user types.
    var title: String
    // Parsed Total Amount
    var amount: Double
    // Parsed Date
    var date: Date
    var category: TransactionCategory
    var source: TransactionSource
    /// Raw keyword the Regex parser matched on — kept for debugging OCR accuracy. Nil for manual entries.
    var rawKeyword: String?
    /// Convenience — income vs. expense is derived from category rather than a
    /// separate field, so `.hardware` + income can never happen as an inconsistent state.
    var isIncome: Bool { category == .income }

    init(
        title: String,
        amount: Double,
        date: Date = Date(),
        category: TransactionCategory = .other,
//        category: TransactionCategory = .unassigned,
        source: TransactionSource = .manual,
        rawKeyword: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.amount = amount
        self.date = date
        self.category = category
        self.source = source
        self.rawKeyword = rawKeyword
    }
}
