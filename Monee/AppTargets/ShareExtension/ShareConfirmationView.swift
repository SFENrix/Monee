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
//  ⚠️ UI PLACEHOLDER — plain layout, functional only.
//

import SwiftUI

struct ShareConfirmationView: View {
    let parsed: ParsedReceiptData
    let onConfirm: (Bool) -> Void

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

            HStack(spacing: 16) {
                Button {
                    onConfirm(false)
                } label: {
                    Text("Expense")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onConfirm(true)
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
