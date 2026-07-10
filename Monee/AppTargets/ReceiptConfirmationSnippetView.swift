//
//  ReceiptConfirmationSnippetView.swift
//  Monee
//
//  The view ScanReceiptTextIntent.perform() returns via ShowsSnippetView. A single
//  concrete view type switching on an internal enum state — required because the
//  intent's `some IntentResult & ShowsSnippetView` return type needs one concrete type
//  across every branch (screenshot missing, no text found, no amount found, or the
//  happy-path confirmation), not a different View type per branch.
//
//  Buttons are intent-driven, not state-driven, per the snippet interactivity model:
//  TextField/local @State edits don't work inside a snippet, so there's no live editing
//  here — tapping a button immediately triggers the matching ConfirmReceipt...Intent,
//  which does the actual save and ends the flow.
//
//  Updated 08/07/26 — a Menu wrapping the expense categories (tap "Expense" to reveal
//  a submenu) rendered as a disabled/forbidden control on-device: snippets render a
//  restricted subset of SwiftUI, and Menu isn't in it — only flat, top-level
//  Button(intent:) controls are actually interactive here. Replaced with a flat grid
//  of one button per category (each its own pre-configured intent) instead of a
//  two-step reveal. ShareConfirmationView's Menu is unaffected — that one runs as an
//  ordinary hosted SwiftUI view in the Share Extension's own process, not a snippet.
//

import AppIntents
import SwiftUI

struct ReceiptConfirmationSnippetView: View {
    enum State {
        case error(String)
        case confirming(title: String, amount: Double, date: Date, category: TransactionCategory, rawKeyword: String?)
    }

    let state: State

    var body: some View {
        switch state {
        case .error(let message):
            Text(message)
                .padding()

        case .confirming(let title, let amount, let date, let category, let rawKeyword):
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                Text(amount.idrFormatted)
                    .font(.title2.bold())
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if category != .income {
                    Text("Suggested category: \(category.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Expense")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(TransactionCategory.allCases.filter { $0 != .income }, id: \.self) { expenseCategory in
                        Button(intent: ConfirmReceiptAsExpenseIntent(
                            amount: amount,
                            date: date,
                            transactionTitle: title,
                            categoryRawValue: expenseCategory.rawValue,
                            rawKeyword: rawKeyword
                        )) {
                            Label(expenseCategory.rawValue, systemImage: expenseCategory.iconSystemName)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                Button(intent: ConfirmReceiptAsIncomeIntent(
                    amount: amount,
                    date: date,
                    transactionTitle: title,
                    rawKeyword: rawKeyword
                )) {
                    Text("Income")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
    }
}
