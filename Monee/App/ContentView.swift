//
//  ContentView.swift
//  FreelanceFinance
//
//  Created by Rio Ferdinand on 27/06/26.
//  Rewritten 02/07/26 — replaced the default Xcode SwiftData template (`Item`) with the
//  real Dashboard, wired to the actual Transaction model.
//  Updated 02/07/26 — AI Buddy tab now points at the real AIChatView instead of a placeholder.
//  Updated 02/07/26 — Add button now presents the real QuickEntryFormView.
//  Updated 02/07/26 — Dashboard reacts to AppContainer.pendingRoute (Widget/Share Extension
//  deep links) via handleRoute(_:).
//  Updated 02/07/26 — Total Spent/Income split now that Transaction supports income.
//  Updated 02/07/26 — pendingReceipt route now actually loads the App Group image and
//  presents ReceiptConfirmationView, instead of just printing.
//  Updated 02/07/26 — added ReserveCard showing CashReserveCalculator output on Dashboard.
//
//  ⚠️ UI PLACEHOLDER: Dashboard layout (list, summary cards, row styling) is functional-only.
//  UI team — restyle freely; nothing else in the app depends on how this looks.
//

import SwiftUI
import SwiftData
import UIKit

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
    @State private var showingReceiptScan = false
    @State private var pendingReceiptImage: UIImage?

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
                    Button {
                        showingQuickAdd = true
                    } label: {
                        Label("Add Transaction", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingQuickAdd) {
                QuickEntryFormView()
            }
            .sheet(isPresented: $showingReceiptScan) {
                ReceiptConfirmationView(pendingImage: pendingReceiptImage)
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
        case .pendingReceipt:
            loadPendingReceipt()
        }
        appContainer.pendingRoute = nil
    }

    /// Reads the image ShareViewController dropped in the App Group container, hands it
    /// to ReceiptConfirmationView, then clears the pending flag/file immediately — once
    /// the image is in memory there's no reason to re-trigger this on next launch, even
    /// if the user cancels the scan instead of saving.
    private func loadPendingReceipt() {
        guard AppGroup.defaults.bool(forKey: AppGroupKey.hasPendingReceipt),
              let data = try? Data(contentsOf: AppGroup.pendingReceiptImageURL),
              let image = UIImage(data: data) else {
            return
        }

        AppGroup.defaults.set(false, forKey: AppGroupKey.hasPendingReceipt)
        try? FileManager.default.removeItem(at: AppGroup.pendingReceiptImageURL)

        pendingReceiptImage = image
        showingReceiptScan = true
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
            Text(totalSpent, format: .currency(code: "USD"))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.green)
                Text("Income logged: \(totalIncome, format: .currency(code: "USD"))")
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
            Text(summary.currentReserve, format: .currency(code: "USD"))
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

            Text((transaction.isIncome ? "+" : "-") + transaction.amount.formatted(.currency(code: "USD")))
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
