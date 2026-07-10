//
//  ShareConfirmationView.swift
//  Monee
//
//  Plain SwiftUI confirmation shown inside the Share Extension before saving. Unlike
//  ReceiptConfirmationSnippetView (an App Intents snippet, where TextField/local @State
//  don't work), this runs as an ordinary hosted SwiftUI view inside the extension's own
//  process — no snippet restrictions apply here, so this is a closure-driven view like
//  any other SwiftUI screen.
//
//  Updated 08/07/26 — "Expense" now opens a Menu of TransactionCategory options instead
//  of saving straight to the OCR-guessed category. `onConfirm` carries the resolved
//  category directly (Income implies `.income`, no separate Bool needed) so
//  ShareViewController doesn't need its own income/expense branch anymore.
//
//  ⚠️ UI PLACEHOLDER — plain layout, functional only.
//

import SwiftUI

struct ShareConfirmationView: View {
    let parsed: ParsedReceiptData
    let onConfirm: (TransactionCategory) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(parsed.suggestedTitle)
                .font(.headline)

            Text((parsed.amount ?? 0).idrFormatted)
                .font(.largeTitle.bold())

            if let date = parsed.date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if parsed.category != .income {
                Text("Suggested category: \(parsed.category.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Menu {
                    ForEach(TransactionCategory.allCases.filter { $0 != .income }, id: \.self) { category in
                        Button {
                            onConfirm(category)
                        } label: {
                            Label(category.rawValue, systemImage: category.iconSystemName)
                        }
                    }
                } label: {
                    Text("Expense")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onConfirm(.income)
                } label: {
                    Text("Income")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }
}
