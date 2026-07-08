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
//  here — tapping Income immediately triggers ConfirmReceiptAsIncomeIntent, which does
//  the actual save and ends the flow. "Expense" is a Menu instead of a single Button —
//  each category is its own pre-configured Button(intent:), so picking a category still
//  fits the "every interactive control carries its own complete intent" snippet model;
//  there's no dynamic @State step in between tapping Expense and picking a category.
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

                HStack(spacing: 12) {
                    Menu {
                        ForEach(TransactionCategory.allCases.filter { $0 != .income }, id: \.self) { expenseCategory in
                            Button(intent: ConfirmReceiptAsExpenseIntent(
                                amount: amount,
                                date: date,
                                transactionTitle: title,
                                categoryRawValue: expenseCategory.rawValue,
                                rawKeyword: rawKeyword
                            )) {
                                Label(expenseCategory.rawValue, systemImage: expenseCategory.iconName)
                            }
                        }
                    } label: {
                        Text("Expense")
                    }

                    Button(intent: ConfirmReceiptAsIncomeIntent(
                        amount: amount,
                        date: date,
                        transactionTitle: title,
                        rawKeyword: rawKeyword
                    )) {
                        Text("Income")
                    }
                }
            }
            .padding()
        }
    }
}
