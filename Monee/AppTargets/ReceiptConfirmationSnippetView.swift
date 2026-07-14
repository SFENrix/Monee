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
//  Updated 10/07/26 — snippets can't do @State-driven "pick then separately confirm"
//  (see note above — no live editing here), so "preselected but changeable" instead
//  means: the RegexParser-suggested category/Income button is visually highlighted,
//  but every button — including non-suggested ones — remains its own tappable,
//  immediately-final choice, same as before.
//
//  Updated 10/07/26 — every category/Income button now has an explicit
//  minHeight: 44 / minWidth: 44, per Apple HIG's minimum hit-target size.
//

import AppIntents
import SwiftUI

struct ReceiptConfirmationSnippetView: View {
    enum State {
        case error(String)
        case confirming(title: String, amount: Double, date: Date, category: TransactionCategory, isIncome: Bool, rawKeyword: String?)
    }

    let state: State

    var body: some View {
        switch state {
        case .error(let message):
            Text(message)
                .padding()

        case .confirming(let title, let amount, let date, let category, let isIncome, let rawKeyword):
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(amount.idrFormatted)
                        .font(.subheadline.bold())
                }
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(isIncome || category != .other
                     ? "Suggested: \(isIncome ? "Income" : category.rawValue) — tap a button below to log it"
                     : "Tap a button below to log it")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(TransactionCategory.allCases.filter { $0 != .income }, id: \.self) { expenseCategory in
                        let isSuggested = !isIncome && expenseCategory == category && category != .other
                        Button(intent: ConfirmReceiptAsExpenseIntent(
                            amount: amount,
                            date: date,
                            transactionTitle: title,
                            categoryRawValue: expenseCategory.rawValue,
                            rawKeyword: rawKeyword
                        )) {
                            Label(isSuggested ? "\(expenseCategory.rawValue)" : expenseCategory.rawValue, systemImage: expenseCategory.iconSystemName)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(isSuggested ? .accentColor : .secondary)
                    }
                }

                Button(intent: ConfirmReceiptAsIncomeIntent(
                    amount: amount,
                    date: date,
                    transactionTitle: title,
                    rawKeyword: rawKeyword
                )) {
                    Text(isIncome ? "Income (suggested)" : "Income")
                        .font(.footnote)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(isIncome ? .accentColor : .secondary)
            }
            .padding(10)
        }
    }
}
