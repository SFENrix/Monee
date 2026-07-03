//
//  ReceiptCaptureService.swift
//  Monee
//
//  Shared by the Action Button intent (main app target) and the Share Extension target.
//  Owns the single "raw text in -> Transaction saved or not" decision so both entry points
//  can't drift out of sync on what counts as a usable capture.
//
//  Rule: if RegexParser finds an amount, save immediately as a real Transaction. If it
//  doesn't, save nothing — no staged/partial record. This replaces the old "stage first,
//  confirm via an actionable notification, then save" design.
//

import Foundation
import SwiftData

enum CaptureOutcome {
    case saved(Transaction)
    case amountNotFound
}

enum ReceiptCaptureService {
    static func capture(rawText: String) -> CaptureOutcome {
        let parsed = RegexParser.parse(rawText)

        guard let amount = parsed.amount else {
            return .amountNotFound
        }

        let category: TransactionCategory = parsed.isIncome ? .income : parsed.category
        let transaction = Transaction(
            title: parsed.suggestedTitle,
            amount: amount,
            date: parsed.date ?? Date(),
            category: category,
            source: .ocr,
            rawKeyword: parsed.keyword
        )

        let context = ModelContext(SwiftDataService.makeContainer())
        context.insert(transaction)
        try? context.save()

        NotificationService.scheduleCaptureNotification(for: transaction)
        return .saved(transaction)
    }
}
