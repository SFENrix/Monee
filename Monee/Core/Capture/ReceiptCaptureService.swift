//
//  ReceiptCaptureService.swift
//  Monee
//
//  Shared by the Action Button intent (main app target) and the Share Extension target.
//  Owns the "raw text in -> parsed fields out" decision, and the actual persistence, as
//  two separate steps: `stage` parses only (never touches the database), `save` persists
//  once the caller has confirmed (and possibly corrected) the category. This split exists
//  so both entry points can show a confirmation UI — an interactive App Intents snippet
//  for the Action Button, a plain SwiftUI view for the Share Extension — before anything
//  is written, instead of the old "parse and save in one step, fix it later" design.
//
//  Rule unchanged from before: if RegexParser finds an amount, staging succeeds and the
//  caller must ask the user to confirm/label it. If it doesn't find an amount, nothing is
//  ever saved — no staged/partial record.
//

import Foundation
import SwiftData

enum CaptureOutcome {
    case needsConfirmation(ParsedReceiptData)
    case amountNotFound
}

enum ReceiptCaptureService {
    /// Parses only — never inserts or saves anything. The caller (an AppIntent's
    /// perform(), or the Share Extension) is responsible for presenting a confirmation
    /// UI and calling `save` once the user has picked Income or Expense.
    static func stage(rawText: String) -> CaptureOutcome {
        let parsed = RegexParser.parse(rawText)
        guard parsed.amount != nil else {
            return .amountNotFound
        }
        return .needsConfirmation(parsed)
    }

    /// Persists a confirmed transaction and schedules the "logged" notification.
    /// Called only after the user has confirmed (and chosen a category for) a staged
    /// parse — never called directly from `stage`.
    @discardableResult
    static func save(
        title: String,
        amount: Double,
        date: Date,
        category: TransactionCategory,
        rawKeyword: String?
    ) -> Transaction {
        let transaction = Transaction(
            title: title,
            amount: amount,
            date: date,
            category: category,
            source: .ocr,
            rawKeyword: rawKeyword
        )

        let context = ModelContext(SwiftDataService.makeContainer())
        context.insert(transaction)
        try? context.save()

        NotificationService.scheduleCaptureNotification(for: transaction)
        return transaction
    }
}
