//
//  QuickEntryViewModel.swift
//  Monee
//
//  Owns form state + validation + persistence for manual transaction entry, AND for editing
//  an already-existing Transaction (used by the notification tap-to-edit route in
//  NotificationDelegate -> ContentView). Deliberately has no knowledge of how it's presented
//  (sheet, deep link) — the view handles presentation, this just handles data.
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

    /// Non-nil while editing an existing Transaction — `save()` updates it in place instead
    /// of inserting a new one.
    private var editingTransaction: Transaction?

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (amount ?? 0) > 0
    }

    /// Loads an existing Transaction's fields for editing.
    ///
    /// `isIncome` MUST be set before `category` — `isIncome`'s didSet resets `category` to
    /// `.unassigned`/`.income` as a side effect, so `category` has to be the last write to
    /// actually stick (same gotcha already documented in ReceiptConfirmationView).
    func load(from transaction: Transaction) {
        editingTransaction = transaction
        title = transaction.title
        amount = transaction.amount
        date = transaction.date
        source = transaction.source
        rawKeyword = transaction.rawKeyword
        isIncome = transaction.isIncome
        category = transaction.category
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

        if let editingTransaction {
            editingTransaction.title = trimmedTitle
            editingTransaction.amount = amount
            editingTransaction.date = date
            editingTransaction.category = category
            editingTransaction.source = source
            editingTransaction.rawKeyword = rawKeyword
        } else {
            let transaction = Transaction(
                title: trimmedTitle,
                amount: amount,
                date: date,
                category: category,
                source: source,
                rawKeyword: rawKeyword
            )
            modelContext.insert(transaction)
        }

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
        editingTransaction = nil
    }
}
