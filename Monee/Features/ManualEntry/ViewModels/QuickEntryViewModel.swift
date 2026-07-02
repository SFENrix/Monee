//
//  QuickEntryViewModel.swift
//  FreelanceFinance
//
//  Created by Rio Ferdinand on 02/07/26.
//
//  Owns form state + validation + persistence for manual transaction entry.
//  Deliberately has no knowledge of how it's presented (sheet, full push, deep link from
//  QuickEntryIntent later) — the view handles presentation, this just handles data.
//  Updated 02/07/26 — added `source`/`rawKeyword` so ReceiptConfirmationView can reuse this
//  exact save path for OCR-sourced transactions instead of duplicating validation logic.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class QuickEntryViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var amount: Double?
    @Published var category: TransactionCategory = .unassigned
    @Published var date: Date = .now
    @Published var validationError: String?

    /// Drives the Income/Expense segmented control. Setting this reassigns `category`
    /// so the two can never disagree — no separate "type" field needed.
    @Published var isIncome: Bool = false {
        didSet { category = isIncome ? .income : .unassigned }
    }

    /// Defaults to manual entry; ReceiptConfirmationView sets this to `.ocr` after prefilling.
    @Published var source: TransactionSource = .manual
    @Published var rawKeyword: String?

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (amount ?? 0) > 0
    }

    @discardableResult
    func save(using modelContext: ModelContext) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            validationError = "Give this transaction a short description."
            return false
        }
        guard let amount, amount > 0 else {
            validationError = "Enter an amount greater than zero."
            return false
        }

        let transaction = Transaction(
            title: trimmedTitle,
            amount: amount,
            date: date,
            category: category,
            source: source,
            rawKeyword: rawKeyword
        )
        modelContext.insert(transaction)

        do {
            try modelContext.save()
            reset()
            return true
        } catch {
            validationError = "Couldn't save: \(error.localizedDescription)"
            return false
        }
    }

    func reset() {
        title = ""
        amount = nil
        category = .unassigned
        date = .now
        validationError = nil
        source = .manual
        rawKeyword = nil
        isIncome = false
    }
}
