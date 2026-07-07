//
//  ConfirmReceiptIntents.swift
//  Monee
//
//  The two intents ReceiptConfirmationSnippetView's buttons trigger. Each one carries
//  the parsed fields as plain parameters (TextField isn't available inside a snippet, so
//  there's no live-editing here — just picking Income vs. Expense) and performs the
//  actual save, ending the interactive flow with a final dialog rather than another
//  snippet. TransactionCategory can't be an @Parameter type directly, so the expense
//  path carries it as its rawValue and reconstructs it in perform().
//

import AppIntents
import Foundation

struct ConfirmReceiptAsIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Receipt as Income"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Date")
    var date: Date

    @Parameter(title: "Title")
    var transactionTitle: String

    @Parameter(title: "Raw Keyword")
    var rawKeyword: String?

    init() {}

    init(amount: Double, date: Date, transactionTitle: String, rawKeyword: String?) {
        self.amount = amount
        self.date = date
        self.transactionTitle = transactionTitle
        self.rawKeyword = rawKeyword
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let transaction = ReceiptCaptureService.save(
            title: transactionTitle,
            amount: amount,
            date: date,
            category: .income,
            rawKeyword: rawKeyword
        )
        return .result(dialog: "Logged \(transaction.amount.idrFormatted) as income.")
    }
}

struct ConfirmReceiptAsExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Receipt as Expense"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Date")
    var date: Date

    @Parameter(title: "Title")
    var transactionTitle: String

    @Parameter(title: "Category")
    var categoryRawValue: String

    @Parameter(title: "Raw Keyword")
    var rawKeyword: String?

    init() {}

    init(amount: Double, date: Date, transactionTitle: String, categoryRawValue: String, rawKeyword: String?) {
        self.amount = amount
        self.date = date
        self.transactionTitle = transactionTitle
        self.categoryRawValue = categoryRawValue
        self.rawKeyword = rawKeyword
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let category = TransactionCategory(rawValue: categoryRawValue) ?? .unassigned
        let transaction = ReceiptCaptureService.save(
            title: transactionTitle,
            amount: amount,
            date: date,
            category: category,
            rawKeyword: rawKeyword
        )
        return .result(dialog: "Logged \(transaction.amount.idrFormatted) as an expense.")
    }
}
