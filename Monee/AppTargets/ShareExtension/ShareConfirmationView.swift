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
//  Updated 10/07/26 — replaced the "tap a category to save immediately" Menu with a
//  real category picker: every category (Income included) is a selectable chip, the
//  one RegexParser guessed is preselected, and nothing saves until "Confirm" is
//  tapped. Runs as an ordinary hosted SwiftUI view in the Share Extension's own
//  process (not a snippet), so @State-driven selection works fine here.
//
//  Updated 10/07/26 — every tappable control (category chips + Confirm) now has an
//  explicit minHeight: 44 / minWidth: 44, per Apple HIG's minimum hit-target size —
//  `.bordered`/`.borderedProminent`'s default padding doesn't reliably reach 44pt on
//  its own at this font size.
//
//  Updated 10/07/26 — Income moved out of the category grid to its own row below,
//  after the 4 expense categories, to match ReceiptConfirmationSnippetView's
//  ordering (both confirmation UIs now show expenses first, Income last).
//
//  ⚠️ UI PLACEHOLDER — plain layout, functional only.
//

import SwiftUI

struct ShareConfirmationView: View {
    let parsed: ParsedReceiptData
    let onConfirm: (TransactionCategory) -> Void

    @State private var selectedCategory: TransactionCategory

    init(parsed: ParsedReceiptData, onConfirm: @escaping (TransactionCategory) -> Void) {
        self.parsed = parsed
        self.onConfirm = onConfirm
        _selectedCategory = State(initialValue: parsed.isIncome ? .income : parsed.category)
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

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

            Text("Category")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(TransactionCategory.allCases.filter { $0 != .income }, id: \.self) { category in
                    categoryChip(category)
                }
            }

            categoryChip(.income)

            Button {
                onConfirm(selectedCategory)
            } label: {
                Text("Confirm")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    private func categoryChip(_ category: TransactionCategory) -> some View {
        Button {
            selectedCategory = category
        } label: {
            Label(category.rawValue, systemImage: category.iconSystemName)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(selectedCategory == category ? .accentColor : .secondary)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(selectedCategory == category ? 0.15 : 0))
        )
    }
}
