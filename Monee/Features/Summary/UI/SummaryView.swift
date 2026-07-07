//
//  SummaryView.swift
//  Monee
//
//  Fourth tab: month-selectable expense-by-category pie chart, emergency fund
//  progress, and a manual add-to-fund input. The design team will restyle this
//  screen later — this implements the real data contract now (month filtering,
//  Spare Money math, emergency fund total/target) so the underlying logic can be
//  tested ahead of that visual pass.
//
//  ⚠️ UI PLACEHOLDER: everything here is functional-only styling. UI team —
//  restyle freely; the @Query, CashReserveCalculator, and UserProfile calls are
//  the only real contracts this depends on.
//

import SwiftUI
import SwiftData
import Charts

struct SummaryView: View {
    @Query private var transactions: [Transaction]

    @State private var selectedMonth: Date = Date()
    @State private var emergencyFundTotal: Double = UserProfile.emergencyFundTotal
    @State private var addFundText: String = ""

    private var spareMoneySummary: CashReserveSummary {
        CashReserveCalculator.summarize(transactions: transactions, emergencyFundTotal: emergencyFundTotal)
    }

    private var categoryTotals: [(category: TransactionCategory, total: Double)] {
        let calendar = Calendar.current
        let monthExpenses = transactions.filter { txn in
            !txn.isIncome && calendar.isDate(txn.date, equalTo: selectedMonth, toGranularity: .month)
        }
        let grouped = Dictionary(grouping: monthExpenses, by: { $0.category })
        return grouped
            .map { (category: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Month") {
                    DatePicker(
                        "Month",
                        selection: $selectedMonth,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                }

                Section("Spare Money") {
                    LabeledContent("Spare Money") {
                        Text(spareMoneySummary.spareMoney.idrFormatted)
                    }
                    if !spareMoneySummary.hasEnoughData {
                        Text("Not enough data yet — log \(CashReserveCalculator.minimumTransactionsForConfidence - spareMoneySummary.transactionCount) more transaction(s) for a reliable figure.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Expenses by Category") {
                    if categoryTotals.isEmpty {
                        Text("No expenses logged for this month.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(categoryTotals, id: \.category) { item in
                            SectorMark(
                                angle: .value("Amount", item.total),
                                innerRadius: .ratio(0.5),
                                angularInset: 1.5
                            )
                            .foregroundStyle(item.category.tint)
                            .cornerRadius(4)
                        }
                        .frame(height: 220)

                        ForEach(categoryTotals, id: \.category) { item in
                            LabeledContent(item.category.rawValue) {
                                Text(item.total.idrFormatted)
                            }
                        }
                    }
                }

                Section("Emergency Fund") {
                    if let target = UserProfile.emergencyFundTarget {
                        ProgressView(value: min(emergencyFundTotal, target), total: target) {
                            Text("\(Int(min(100, (emergencyFundTotal / target) * 100)))% filled")
                        }
                        LabeledContent("Current") {
                            Text(emergencyFundTotal.idrFormatted)
                        }
                        LabeledContent("Target (12x estimated monthly expense)") {
                            Text(target.idrFormatted)
                        }
                    } else {
                        Text("Set an Estimated Monthly Expense in Profile to calculate a target.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        TextField("Add amount", text: $addFundText)
                            .keyboardType(.decimalPad)
                        Button("Add") {
                            addToFund()
                        }
                        .disabled(Double(addFundText) == nil || Double(addFundText) == 0)
                    }
                }
            }
            .navigationTitle("Summary")
            .dismissKeyboardOnTap()
        }
    }

    private func addToFund() {
        guard let amount = Double(addFundText), amount > 0 else { return }
        let newTotal = emergencyFundTotal + amount
        UserProfile.emergencyFundTotal = newTotal
        emergencyFundTotal = newTotal
        addFundText = ""
    }
}

#Preview {
    SummaryView()
        .modelContainer(SwiftDataService.makePreviewContainer(seeded: true))
}
