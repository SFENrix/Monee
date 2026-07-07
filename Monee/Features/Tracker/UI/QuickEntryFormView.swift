//
//  QuickEntryFormView.swift
//  Monee
//
//  Focused input form for manual transaction entry — and, via `editing`, for fixing up an
//  already-saved OCR capture (reached from the notification tap-to-edit route).
//
//  UI restyled to match the "Add New Transaction" mock: custom header (back chevron + Done),
//  plain label/value rows, a pill-style Date control (native DatePicker under the hood, so
//  tapping it opens the system calendar picker), icon-button Statement toggle, a Categories
//  grid shown only for expenses, and a compact floating card instead of a full screen sheet.
//  Nothing downstream changed — every call is still through QuickEntryViewModel's public API.
//
//  Updated 07/07/26 — removed the separate Time row (date-only now, matching the latest
//  mock), and the Date pill now reads out the full month name (e.g. "June 12, 2026").
//
//  Fixed 07/07/26 — the card's VStack only hugged its own content height, so the white
//  rounded background + clipShape stopped partway down the sheet instead of filling the
//  full presentationDetents(.height(600)) area; the remaining space fell through to
//  presentationBackground(.clear) and showed the dimmed backdrop, making the card look
//  like it had shrunk. Added `.frame(maxHeight: .infinity, alignment: .top)` (with a
//  trailing Spacer so content stays pinned to the top) before the background/clipShape
//  so the card now always fills the sheet.
//

import SwiftUI
import SwiftData

struct QuickEntryFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = QuickEntryViewModel()

    var onSaved: (() -> Void)?

    /// Non-nil when opened to fix up an already-saved Transaction (notification tap-to-edit).
    var editing: Transaction?

    private var accentTeal: Color { Color(red: 0.29, green: 0.60, blue: 0.60) }

    private var expenseCategories: [TransactionCategory] {
        TransactionCategory.allCases.filter { $0 != .income }
    }

    private let categoryColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 0) {
            header

            totalRow
            Divider().padding(.leading, 20)

            HStack {
                Text("Date")
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)

                ZStack(alignment: .leading) {
                    DatePicker(
                        "Date",
                        selection: $viewModel.date,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(accentTeal)
                    .opacity(0.011) // keep native tap target/interaction, hide its default look

                    pillLabel(dateText)
                        .allowsHitTesting(false)
                }
                .padding(.leading, 12)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider().padding(.leading, 20)

            statementRow

            if !viewModel.isIncome {
                Divider().padding(.leading, 20)
                categoriesSection
            }

            if let error = viewModel.validationError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .padding(.horizontal, 12)
        .dismissKeyboardOnTap()
        .task {
            if let editing {
                viewModel.load(from: editing)
            } else {
                viewModel.isIncome = true
            }
        }
        .presentationDetents([.height(viewModel.isIncome ? 340 : 540)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(32)
        .presentationBackground(.clear)
        .background(RemoveSheetDimmingBackground())
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(.systemGray6)))
            }

            Spacer()

            Text(editing != nil ? "Edit Transaction" : "Add New Transaction")
                .font(.system(size: 17, weight: .semibold))

            Spacer()

            Button {
                if viewModel.save(using: modelContext) {
                    onSaved?()
                    dismiss()
                }
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(accentTeal))
            }
            .disabled(!viewModel.canSave)
            .opacity(viewModel.canSave ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Rows

    private var totalRow: some View {
        HStack(spacing: 8) {
            Text("Total")
                .font(.system(size: 17))
                .foregroundStyle(.primary)

            HStack(spacing: 4) {
//                Text("IDR")
//                    .foregroundStyle(.primary)
                TextField(
                    "IDR",
                    value: $viewModel.amount,
                    format: .number
                )
                .keyboardType(.decimalPad)
                .foregroundStyle(viewModel.amount == 0 ? .secondary : .primary)
            }
            .font(.system(size: 17))

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func pillLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minWidth: 120)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(red: 0.96, green: 0.96, blue: 0.97))
            )
    }

    private var statementRow: some View {
        HStack(spacing: 24) {
            Text("Statement")
                .font(.system(size: 17))
                .foregroundStyle(.primary)

            statementButton(
                title: "Income",
                systemImage: "square.and.arrow.down",
                isSelected: viewModel.isIncome
            ) {
                viewModel.isIncome = true
            }

            statementButton(
                title: "Expense",
                systemImage: "square.and.arrow.up",
                isSelected: !viewModel.isIncome
            ) {
                viewModel.isIncome = false
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func statementButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                Text(title)
                    .font(.system(size: 13))
            }
            .foregroundStyle(isSelected ? accentTeal : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Categories")
                .font(.system(size: 17))
                .foregroundStyle(.primary)
                .padding(.horizontal, 20)

            LazyVGrid(columns: categoryColumns, spacing: 12) {
                ForEach(expenseCategories, id: \.self) { cat in
                    categoryPill(cat)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 14)
    }

    private func categoryPill(_ cat: TransactionCategory) -> some View {
        let isSelected = viewModel.category == cat

        return Button {
            viewModel.category = cat
        } label: {
            Text(cat.rawValue)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    isSelected
                    ? .white
                    : Color(red: 0.22, green: 0.18, blue: 0.15)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    Capsule()
                        .fill(
                            isSelected
                            ? Color(red: 0.35, green: 0.63, blue: 0.63)
                            : Color(red: 0.95, green: 0.91, blue: 0.84)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Formatting
    private var dateText: String {
        viewModel.date.formatted(
            .dateTime
                .month(.wide)
                .day()
                .year()
        )
    }
}

// MARK: - Dimmed-backdrop removal

/// `.sheet` always drops in UIKit's system scrim behind the presented content,
/// and SwiftUI doesn't expose a public way to turn that off — `presentationBackground(.clear)`
/// only clears the *sheet's own* background, not the dimming view sitting behind it.
/// This drops an invisible marker view into the hierarchy and clears the background two
/// levels up from it (that ancestor is consistently the dimming view in the current UIKit
/// sheet implementation). Because it relies on that view-hierarchy shape rather than public
/// API, re-check this if a future iOS release changes how sheets are composed.
private struct RemoveSheetDimmingBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            // The scrim sits two levels above the hosting view in the current
            // UIKit sheet implementation — deliberately not walking further up
            // than that so we don't touch unrelated ancestor views.
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

#Preview {
    Color.gray
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            QuickEntryFormView()
                .modelContainer(SwiftDataService.makePreviewContainer())
        }
}
