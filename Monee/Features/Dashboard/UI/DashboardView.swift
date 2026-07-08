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

import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var emergencyFundCurrent: Double = UserProfile.emergencyFundTotal
    @State private var selectedKind: Kind = .expense
    @State private var selectedMonth: Date = Date()
    @State private var showingAddFund = false
    @State private var showingWithdrawFund = false

    private enum Kind { case expense, income }

    var body: some View {
        VStack(spacing: 0) {
            emergencyFundHeader

            ScrollView {
                summaryCard
            }
            .background(Color(red: 0.98, green: 0.96, blue: 0.92))
        }
        .background(headerGradient.ignoresSafeArea(edges: .top))
        .sheet(isPresented: $showingAddFund) {
            AddEmergencyFundSheet(mode: .add, currentTotal: emergencyFundCurrent) { amountAdded, _ in
                let newTotal = emergencyFundCurrent + amountAdded
                UserProfile.emergencyFundTotal = newTotal
                emergencyFundCurrent = newTotal
            }
        }
        .sheet(isPresented: $showingWithdrawFund) {
            AddEmergencyFundSheet(mode: .withdraw, currentTotal: emergencyFundCurrent) { amountWithdrawn, _ in
                // Clamped defensively — the sheet already disables Done above the
                // available total, this just guards against it going negative.
                let newTotal = max(0, emergencyFundCurrent - amountWithdrawn)
                UserProfile.emergencyFundTotal = newTotal
                emergencyFundCurrent = newTotal
            }
        }
        .onAppear {
            // UserProfile is a plain UserDefaults store, not @Observable — re-sync
            // in case it changed elsewhere (e.g. Profile) since this view last appeared.
            emergencyFundCurrent = UserProfile.emergencyFundTotal
        }
    }

    // MARK: - Emergency fund header

    private var emergencyFundHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Emergency Savings")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                if let target = UserProfile.emergencyFundTarget {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.25))

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.96, green: 0.75, blue: 0.45),
                                            Color(red: 0.95, green: 0.65, blue: 0.35)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * progressFraction(target: target))

                            Text("\(emergencyFundCurrent.idrFormatted) / \(target.idrFormatted)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.black.opacity(0.75))
                                .padding(.leading, 14)
                        }
                    }
                    .frame(height: 32)
                } else {
                    Text("Set an Estimated Monthly Expense in Profile to calculate a target.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(height: 32)
                }

                Button {
                    showingWithdrawFund = true
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .disabled(emergencyFundCurrent <= 0)
                .opacity(emergencyFundCurrent <= 0 ? 0.5 : 1)

                Button {
                    showingAddFund = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color(red: 0.35, green: 0.72, blue: 0.78)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        // Pulled up close to the safe area — was 60pt, now sits right under
        // the status bar/notch instead of floating in the middle of the
        // teal strip.
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private func progressFraction(target: Double) -> CGFloat {
        guard target > 0 else { return 0 }
        return min(CGFloat(emergencyFundCurrent / target), 1)
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(spacing: 20) {
            monthSelector

            kindPicker

            donutChart

            legendList
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 32)
    }

    private var monthSelector: some View {
        HStack {
            Spacer()
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
    }

    /// Apple HIG segmented control — the standard way to switch between two
    /// mutually-exclusive views like Expense/Income.
    private var kindPicker: some View {
        Picker("Summary type", selection: $selectedKind) {
            Text("Expense").tag(Kind.expense)
            Text("Income").tag(Kind.income)
        }
        .pickerStyle(.segmented)
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
                iconSystemName: category.iconName,
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

    private var headerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.55, green: 0.72, blue: 0.68),
                Color(red: 0.92, green: 0.78, blue: 0.62)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Add/Withdraw Emergency Savings sheet

private struct AddEmergencyFundSheet: View {
    enum Mode {
        case add
        case withdraw

        var title: String {
            switch self {
            case .add: return "Add Emergency Savings"
            case .withdraw: return "Withdraw from Savings"
            }
        }

        var accentColor: Color {
            switch self {
            case .add: return Color(red: 0.35, green: 0.72, blue: 0.78)
            case .withdraw: return Color(red: 0.85, green: 0.45, blue: 0.40)
            }
        }
    }

    let mode: Mode
    /// Only enforced for `.withdraw` — can't take out more than is actually in the
    /// fund. Unused for `.add`, which has no upper bound.
    let currentTotal: Double
    /// (amount, date) — always positive; DashboardView applies the sign based on `mode`.
    var onDone: (Double, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var date = Date()

    private var enteredAmount: Double? {
        guard let value = Double(amountText), value > 0 else { return nil }
        if mode == .withdraw, value > currentTotal { return nil }
        return value
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(mode.title)
                    .font(.system(size: 17, weight: .bold))

                Spacer()

                Button("Done") {
                    if let amount = enteredAmount {
                        onDone(amount, date)
                    }
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(mode.accentColor))
                .disabled(enteredAmount == nil)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            VStack(spacing: 0) {
                HStack {
                    Text("Total")
                        .font(.system(size: 16))
                    Spacer()

                    TextField("IDR", text: $amountText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 16))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider().padding(.leading, 20)

                HStack {
                    Text("Date")
                        .font(.system(size: 16))
                    Spacer()
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }

            if mode == .withdraw {
                Text("Up to \(currentTotal.idrFormatted) available")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }
        }
        .dismissKeyboardOnTap()
        .presentationDetents([.height(mode == .withdraw ? 250 : 220)])
    }
}

#Preview {
    DashboardView()
        .modelContainer(SwiftDataService.makePreviewContainer(seeded: true))
        .environment(AppContainer.shared)
}
