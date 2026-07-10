//
//  DashboardView.swift
//  Monee
//
//  Created by Gwen Marvella Yeanlynn on 07/07/26.
//
//  Emergency-savings tracker + Expense/Income summary donut chart, following
//  the same visual language as TrackerView/ProfileView (teal header strip,
//  cream sheet with rounded top).
//
//  Rewired 08/07/26 — replaced the original @AppStorage("emergencyFundTarget"/
//  "emergencyFundCurrent") pair (hardcoded defaults, disconnected from the rest
//  of the app) with UserProfile.emergencyFundTotal/.emergencyFundTarget, the
//  same store CashReserveCalculator and the AI Buddy's context already read —
//  so what this screen shows, what "Add" writes, and what the AI reasons about
//  are one number, not three independent ones. Also replaced the keyword-based
//  title-matching category guesser (written before Transaction had a real
//  `category` field) with the actual TransactionCategory enum. This also
//  retires the separate placeholder `SummaryView`/"Summary" tab that briefly
//  duplicated this screen — one dashboard, correctly wired.
//
//  Updated 08/07/26 — added a withdraw flow alongside the existing add flow, and
//  wired both to Tracker's "Money Collected": moving money into/out of the fund is
//  deliberately NOT logged as a Transaction (that would double-subtract against
//  CashReserveCalculator's Spare Money, which already subtracts emergencyFundTotal
//  as its own term). Instead TrackerView reads UserProfile.emergencyFundTotal
//  directly and nets it out of the running balance — see TrackerView.totalCollected.
//
//  Updated 10/07/26 — Emergency Fund now has its own dedicated screen (SavingsView,
//  the "Savings" tab), so it's been removed entirely from this Summary screen —
//  emergencyFundHeader, the add/withdraw sheets, and their state are all gone.
//  In its place, the Expense/Income segmented control moved up to sit where the
//  emergency fund header used to be (straddling the teal/cream boundary), and the
//  month selector — previously above the picker — now sits below it, at the top
//  of the cream card, matching the new hi-fi.
//

import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var selectedKind: Kind = .expense
    @State private var selectedMonth: Date = Date()

    @State private var showingAverageInfo = false

    private enum Kind { case expense, income }

    var body: some View {
        VStack(spacing: 0) {
            kindPicker
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)

            ScrollView {
                summaryCard
            }
            .background(Color(red: 0.98, green: 0.96, blue: 0.92))
        }
        .background(headerGradient.ignoresSafeArea(edges: .top))
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(spacing: 20) {
            summaryHeaderRow

            donutChart

            legendList
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 32)
        
    }

    /// Average expense/income sits on its own row, with the month pill on a
    /// separate row below (right-aligned) — matches the hi-fi where these are
    /// stacked rather than side by side.
    private var summaryHeaderRow: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(selectedKind == .expense ? "Average Expense" : "Average Income")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    Button {
                        showingAverageInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingAverageInfo, arrowEdge: .top) {
                        averageInfoBubble
                            .presentationCompactAdaptation(.popover)
                    }
                }

                if let average = averagePerDay {
                    Text(average.idrFormatted)
                        .font(.system(size: 26, weight: .bold))
                } else {
                    Text("No data yet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                monthPill
            }
        }
    }

    private var monthPill: some View {
        Menu {
            ForEach(lastTwelveMonths, id: \.self) { month in
                Button(monthYearString(month)) { selectedMonth = month }
            }
        } label: {
            Text(monthYearString(selectedMonth))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(.systemGray5)))
        }
    }

    /// Average \(selectedKind) per day, over the days in the selected month that
    /// actually have a logged transaction of that kind — nil (→ placeholder)
    /// rather than 0 when there's nothing logged yet, so an empty month doesn't
    /// masquerade as "you averaged Rp0."
    private var averagePerDay: Double? {
        guard !filteredTransactions.isEmpty else { return nil }
        let calendar = Calendar.current
        let distinctDays = Set(filteredTransactions.map { calendar.startOfDay(for: $0.date) })
        guard !distinctDays.isEmpty else { return nil }
        return total / Double(distinctDays.count)
    }

    /// Apple HIG segmented control — the standard way to switch between two
    /// mutually-exclusive views like Expense/Income. Moved up to sit where the
    /// emergency fund header used to be, straddling the teal/cream boundary.
    /// The segmented control's native track is translucent, so sitting directly
    /// on the teal gradient was letting it bleed through as a greenish tint —
    /// an explicit gray Capsule behind it keeps the track a consistent gray
    /// regardless of what's underneath.
    private var kindPicker: some View {
        Picker("Summary type", selection: $selectedKind) {
            Text("Expense").tag(Kind.expense)
            Text("Income").tag(Kind.income)
        }
        .pickerStyle(.segmented)
        .background(
            Capsule().fill(Color(.systemGray4))
        )
    }

    private var donutChart: some View {
        ZStack {
            if categoryTotals.isEmpty {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 40)
                    .frame(width: 260, height: 260)
            } else {
                Chart(categoryTotals) { item in
                    SectorMark(
                        angle: .value("Amount", item.amount),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .foregroundStyle(item.color)
                    .cornerRadius(2)
                }
                .frame(height: 260)
                .chartLegend(.hidden)
            }

            VStack(spacing: 4) {
                Text("Total")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text(total.idrFormatted)
                    .font(.system(size: 20, weight: .bold))
            }
        }
        .padding(.top, 8)
    }

    private var legendList: some View {
        VStack(spacing: 0) {
            if categoryTotals.isEmpty {
                Text("No \(selectedKind == .expense ? "expenses" : "income") logged this month")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            }

            ForEach(categoryTotals) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.iconSystemName)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(item.color))

                    Text(item.label)
                        .font(.system(size: 16))

                    Spacer()

                    Text(item.amount.idrFormatted)
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)

                if item.id != categoryTotals.last?.id {
                    Divider()
                }
            }
        }
        .padding(.top, 8)
    }

    /// Content of the tooltip popover — bolds "3 months" to match the hi-fi.
    /// NOTE: "3 months" is currently just copy, not a computed window — this
    /// screen still averages per-day within the single selected month
    /// (`averagePerDay`). If you want the average itself to actually be a
    /// rolling 3-month figure, that's a separate change to that calculation.
    private var averageInfoBubble: some View {
        (
            Text("Based on your average spending over the last ")
                + Text("3 months").fontWeight(.bold)
        )
        .font(.system(size: 15))
        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: 280)
    }

    // MARK: - Data

    private struct CategoryTotal: Identifiable {
        let id: String
        let label: String
        let iconSystemName: String
        let color: Color
        let amount: Double
    }

    private var filteredTransactions: [Transaction] {
        let calendar = Calendar.current
        return transactions.filter { txn in
            let matchesKind = selectedKind == .expense ? !txn.isIncome : txn.isIncome
            let matchesMonth = calendar.isDate(txn.date, equalTo: selectedMonth, toGranularity: .month)
            return matchesKind && matchesMonth
        }
    }

    /// Grouped by the real TransactionCategory (icon/color come straight from
    /// that enum, so this always matches how Tracker/QuickEntryFormView label
    /// the same categories elsewhere in the app) — no more keyword guessing.
    private var categoryTotals: [CategoryTotal] {
        let grouped = Dictionary(grouping: filteredTransactions, by: { $0.category })

        return grouped.map { category, items in
            CategoryTotal(
                id: category.rawValue,
                label: category.rawValue,
                iconSystemName: category.iconSystemName,
                color: category.tint,
                amount: items.reduce(0) { $0 + $1.amount }
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private var total: Double {
        filteredTransactions.reduce(0) { $0 + $1.amount }
    }

    private var lastTwelveMonths: [Date] {
        let calendar = Calendar.current
        return (0..<12).compactMap {
            calendar.date(byAdding: .month, value: -$0, to: Date())
        }
    }

    private func monthYearString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM, yyyy"
        return formatter.string(from: date)
    }

    /// Same teal/green gradient as TrackerView's header, for visual consistency
    /// across tabs (was a lighter, differently-toned peach/mint diagonal before).
    private var headerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.11, green: 0.27, blue: 0.28),
                Color(red: 0.20, green: 0.38, blue: 0.35),
                Color(red: 0.32, green: 0.47, blue: 0.41),
                Color(red: 0.44, green: 0.56, blue: 0.47)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#Preview {
    DashboardView()
        .modelContainer(SwiftDataService.makePreviewContainer(seeded: true))
        .environment(AppContainer.shared)
}
