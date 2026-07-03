//
//  ContentView.swift
//  FreelanceFinance
//
//  ⚠️ UI PLACEHOLDER: Dashboard layout, "+" menu — functional-only. UI team, restyle freely.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }

            AIChatView()
                .tabItem { Label("AI Buddy", systemImage: "bubble.left.and.bubble.right.fill") }
        }
    }
}

// MARK: - Dashboard

private struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var showingQuickAdd = false
    @State private var showingScanReceipt = false
    @State private var editingTransaction: Transaction?

    private var totalSpent: Double {
        transactions.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }
    }

    private var totalIncome: Double {
        transactions.filter { $0.isIncome }.reduce(0) { $0 + $1.amount }
    }

    private var reserveSummary: CashReserveSummary {
        CashReserveCalculator.summarize(
            transactions: transactions,
            fallbackMonthlyIncome: UserFinancialProfile.estimatedMonthlyIncome
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SummaryCard(totalSpent: totalSpent, totalIncome: totalIncome, count: transactions.count)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    ReserveCard(summary: reserveSummary)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if transactions.isEmpty {
                    ContentUnavailableView(
                        "No Transactions Yet",
                        systemImage: "tray",
                        description: Text("Tap + to log your first expense.")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    Section("Recent") {
                        ForEach(transactions) { transaction in
                            TransactionRow(transaction: transaction)
                        }
                        .onDelete(perform: deleteTransactions)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Monee")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // ⚠️ UI PLACEHOLDER — a Menu is the quickest way to expose two entry
                    // points without crowding the toolbar. Restyle freely.
                    Menu {
                        Button {
                            showingQuickAdd = true
                        } label: {
                            Label("Manual Entry", systemImage: "square.and.pencil")
                        }
                        Button {
                            showingScanReceipt = true
                        } label: {
                            Label("Scan Receipt", systemImage: "doc.text.viewfinder")
                        }
                    } label: {
                        Label("Add Transaction", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingQuickAdd) {
                QuickEntryFormView()
            }
            .sheet(isPresented: $showingScanReceipt) {
                ReceiptConfirmationView()
            }
            .sheet(item: $editingTransaction) { transaction in
                QuickEntryFormView(editing: transaction)
            }
        }
        .onChange(of: appContainer.pendingRoute) { _, newRoute in
            handleRoute(newRoute)
        }
        .onAppear {
            handleRoute(appContainer.pendingRoute)
        }
    }

    private func deleteTransactions(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(transactions[index])
        }
    }

    private func handleRoute(_ route: DeepLink?) {
        guard let route else { return }
        switch route {
        case .quickEntry:
            showingQuickAdd = true
        case .editTransaction(let id):
            editingTransaction = transactions.first(where: { $0.id == id })
        }
        appContainer.pendingRoute = nil
    }
}

// MARK: - Summary Card

private struct SummaryCard: View {
    let totalSpent: Double
    let totalIncome: Double
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Total Spent")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(totalSpent, format: .idr)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.green)
                Text("Income logged: \(totalIncome, format: .idr)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(count) transaction\(count == 1 ? "" : "s") logged")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Reserve Card

private struct ReserveCard: View {
    let summary: CashReserveSummary

    private var runwayText: String {
        guard let runway = summary.runwayDays else { return "Not enough data to estimate runway yet" }
        let days = Int(runway.rounded())
        if days < 0 { return "Reserve is already negative" }
        return "\(days) day\(days == 1 ? "" : "s") of runway at current pace"
    }

    private var tint: Color {
        guard let runway = summary.runwayDays else { return .secondary }
        if runway < 0 { return .red }
        if runway < 14 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "gauge.with.needle.fill")
                    .foregroundStyle(tint)
                Text("Cash Reserve")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if !summary.isDataSufficient {
                    Text("LOW CONFIDENCE")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
            }
            Text(summary.currentReserve, format: .idr)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(summary.currentReserve < 0 ? .red : .primary)
            Text(runwayText)
                .font(.caption)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Transaction Row

private struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.category.iconName)
                .font(.title3)
                .foregroundStyle(transaction.category.tint)
                .frame(width: 32, height: 32)
                .background(transaction.category.tint.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.title)
                    .font(.body)
                Text(transaction.date, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text((transaction.isIncome ? "+" : "-") + transaction.amount.formatted(.idr))
                .font(.body.monospacedDigit())
                .foregroundStyle(transaction.isIncome ? .green : .primary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ContentView()
        .modelContainer(SwiftDataService.makePreviewContainer(seeded: true))
        .environment(AppContainer.shared)
}
