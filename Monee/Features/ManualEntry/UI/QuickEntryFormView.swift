//
//  QuickEntryFormView.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//


//
//  QuickEntryFormView.swift
//  FreelanceFinance
//
//  Created by Rio Ferdinand on 02/07/26.
//
//  Focused input form for manual transaction entry. Presented as a sheet from the
//  Dashboard today; built so it can equally be pushed full-screen from a deep link
//  (WidgetExtension/Intents/QuickEntryIntent.swift) later without changes.
//
//  ⚠️ UI PLACEHOLDER: plain Form/Picker styling, functional only. UI team — swap freely,
//  nothing downstream depends on how this looks, only on QuickEntryViewModel's public API.
//

import SwiftUI
import SwiftData

struct QuickEntryFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = QuickEntryViewModel()

    var onSaved: (() -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $viewModel.isIncome) {
                        Text("Expense").tag(false)
                        Text("Income").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Details") {
                    TextField("What was it for?", text: $viewModel.title)
                    TextField("Amount", value: $viewModel.amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
                }

                if !viewModel.isIncome {
                    Section("Category") {
                        Picker("Category", selection: $viewModel.category) {
                            ForEach(TransactionCategory.allCases.filter { $0 != .income }, id: \.self) { cat in
                                Label(cat.rawValue, systemImage: cat.iconName).tag(cat)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                if let error = viewModel.validationError {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(viewModel.isIncome ? "Add Income" : "Add Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if viewModel.save(using: modelContext) {
                            onSaved?()
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.canSave)
                }
            }
        }
    }
}

#Preview {
    QuickEntryFormView()
        .modelContainer(SwiftDataService.makePreviewContainer())
}
