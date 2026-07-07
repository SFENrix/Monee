//
//  DashboardView.swift
//  Monee
//
//  Created by Gwen Marvella Yeanlynn on 07/07/26.
//

//
//  DashboardView.swift
//  FreelanceFinance
//
//  Emergency-savings tracker + Expense/Income summary donut chart, following
//  the same visual language as TrackerView/ProfileView (teal header strip,
//  cream sheet with rounded top).
//
//  DATA NOTE: your `Transaction` model (date, title, amount, isIncome) has no
//  `category` field, so the chart/legend map each transaction's `title` into
//  one of four fixed categories (Entertainment, Household, Food, Other) via
//  simple keyword matching. If you add a real `category` field to
//  `Transaction` later, swap `category(for:)` below to read it directly
//  instead of guessing from the title.
//

import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    /// Target for the emergency fund. Wire this to your real settings/model
    /// (e.g. the `totalMoney` collected during onboarding) if you'd rather
    /// not use AppStorage.
    @AppStorage("emergencyFundTarget") private var emergencyFundTarget: Double = 10_000_000
    @AppStorage("emergencyFundCurrent") private var emergencyFundCurrent: Double = 3_050_000

    @State private var selectedKind: Kind = .expense
    @State private var selectedMonth: Date = Date()
    @State private var showingAddFund = false

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
            AddEmergencyFundSheet { amountAdded, _ in
                emergencyFundCurrent += amountAdded
            }
        }
    }

    // MARK: - Emergency fund header

    private var emergencyFundHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Emergency Savings")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
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
                            .frame(width: geo.size.width * progressFraction)

                        Text("\(formatRupiahPlain(emergencyFundCurrent)) / \(formatRupiahPlain(emergencyFundTarget))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.black.opacity(0.75))
                            .padding(.leading, 14)
                    }
                }
                .frame(height: 32)

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

    private var progressFraction: CGFloat {
        guard emergencyFundTarget > 0 else { return 0 }
        return min(CGFloat(emergencyFundCurrent / emergencyFundTarget), 1)
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
                Text(formatRupiahPlain(total))
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

                    Text(formatRupiahPlain(item.amount))
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

    /// The four fixed categories shown in the legend, with the icon + color
    /// pulled straight from the reference UI: Entertainment (orange /
    /// confetti), Household (green / house), Food (teal / fork & knife),
    /// Other (coral / ellipsis).
    private enum Category: String, CaseIterable {
        case entertainment = "Entertainment"
        case household = "Household"
        case food = "Food"
        case other = "Other"

        var iconSystemName: String {
            switch self {
            case .entertainment: return "party.popper.fill"
            case .household: return "house.fill"
            case .food: return "fork.knife"
            case .other: return "ellipsis"
            }
        }

        var color: Color {
            switch self {
            case .entertainment: return Color(red: 0.93, green: 0.62, blue: 0.32)
            case .household: return Color(red: 0.47, green: 0.68, blue: 0.48)
            case .food: return Color(red: 0.33, green: 0.66, blue: 0.78)
            case .other: return Color(red: 0.84, green: 0.44, blue: 0.40)
            }
        }
    }

    /// Maps a transaction's free-text `title` to one of the four fixed
    /// categories via keyword matching. Swap this out for a real
    /// `txn.category` lookup once that field exists on `Transaction`.
    private func category(for title: String) -> Category {
        let lower = title.lowercased()

        if lower.contains("entertain") || lower.contains("movie") || lower.contains("cinema")
            || lower.contains("game") || lower.contains("concert") || lower.contains("netflix")
            || lower.contains("spotify") {
            return .entertainment
        }

        if lower.contains("house") || lower.contains("rent") || lower.contains("util")
            || lower.contains("electric") || lower.contains("water") || lower.contains("internet")
            || lower.contains("wifi") {
            return .household
        }

        if lower.contains("food") || lower.contains("restaurant") || lower.contains("grocer")
            || lower.contains("eat") || lower.contains("coffee") || lower.contains("lunch")
            || lower.contains("dinner") || lower.contains("snack") {
            return .food
        }

        return .other
    }

    private var categoryTotals: [CategoryTotal] {
        let grouped = Dictionary(grouping: filteredTransactions) { category(for: $0.title) }

        return Category.allCases.compactMap { cat -> CategoryTotal? in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return CategoryTotal(
                id: cat.rawValue,
                label: cat.rawValue,
                iconSystemName: cat.iconSystemName,
                color: cat.color,
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

// MARK: - Add Emergency Savings sheet

private struct AddEmergencyFundSheet: View {
    /// (amountAdded, date)
    var onDone: (Double, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var date = Date()

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

                Text("Add Emergency Savings")
                    .font(.system(size: 17, weight: .bold))

                Spacer()

                Button("Done") {
                    if let amount = Double(amountText) {
                        onDone(amount, date)
                    }
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(red: 0.35, green: 0.72, blue: 0.78)))
                .disabled(Double(amountText) == nil)
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
        }
        .presentationDetents([.height(220)])
    }
}

// MARK: - Formatting

private func formatRupiahPlain(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = "."
    formatter.maximumFractionDigits = 0
    let number = formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    return "Rp\(number)"
}

#Preview {
    DashboardView()
        .modelContainer(SwiftDataService.makePreviewContainer(seeded: true))
        .environment(AppContainer.shared)
}
