//
//  TrackerView.swift
//  FreelanceFinance
//
//  Transaction tracker: running total, month/year navigation, add-transaction modal,
//  and a list of transactions grouped by month/year.
//
//  Assumes an existing SwiftData `Transaction` model with:
//    var date: Date
//    var title: String
//    var amount: Double
//    var isIncome: Bool
//  Adjust field names below if yours differ.
//

import SwiftUI
import SwiftData

struct TrackerView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]

    @State private var visibleMonth: Date = .now
    @State private var showingMonthPicker = false
    @State private var showingQuickAdd = false
    @State private var showingScanReceipt = false
    @State private var editingTransaction: Transaction?

    var body: some View {
        ZStack(alignment: .top) {
            headerBackground
                .frame(height: 220)
                .ignoresSafeArea(edges: .top)
            
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 54)
                    .padding(.bottom, 36)
                
                VStack(spacing: 0) {
                    monthControls
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                    
                    transactionList
                }
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(.systemBackground))
                )
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingMonthPicker) {
            MonthYearPickerSheet(selection: $visibleMonth)
                .presentationDetents([.height(280)])
                .presentationCornerRadius(28)
        }
        .sheet(isPresented: $showingQuickAdd) {
            QuickEntryFormView(onSaved: {
                // @Query already updates `transactions` automatically on save,
                // so nothing extra is needed here unless you want e.g. to jump
                // the list to the newly added transaction's month.
            })
        }
        .sheet(isPresented: $showingScanReceipt) {
            ReceiptConfirmationView()
        }
        .sheet(item: $editingTransaction) { transaction in
            QuickEntryFormView(editing: transaction)
        }
        .onChange(of: appContainer.pendingRoute) { _, newRoute in
            handleRoute(newRoute)
        }
        .onAppear {
            handleRoute(appContainer.pendingRoute)
        }
    }

    /// Routes a deep link (Widget's Quick Entry tap, or tapping the "Logged" notification
    /// after an Action Button / Share Extension capture) to the right sheet.
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

    // MARK: - Header
    
    private var totalCollected: Double {
        transactions.reduce(0) { $0 + ($1.isIncome ? $1.amount : -$1.amount) }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Money Collected")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            
            // showSign only when negative: formatCurrency always shows abs(amount), so
            // passing showSign: false unconditionally (as before) hid the sign entirely —
            // a negative running balance (more expenses than income) displayed as a
            // plain, ever-growing positive number, making expenses look like they
            // increased "Money Collected" and income look like it decreased it.
            Text(formatCurrency(totalCollected, showSign: totalCollected < 0, isIncome: false))
                .font(.system(size: 34, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var headerBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.62, green: 0.78, blue: 0.97),
                    Color(red: 0.80, green: 0.89, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            DiagonalStripes()
        }
    }
    
    // MARK: - Month controls
    
    private var monthControls: some View {
        HStack {
            Button {
                showingMonthPicker = true
            } label: {
                Text(visibleMonth.formatted(.dateTime.month(.abbreviated).year()))
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color(.tertiarySystemBackground))
                            .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            
            Spacer()
            Menu {
                Button {
                    showingQuickAdd = true
                } label: {
                    Label("Manual Entry", systemImage: "square.and.pencil")
                }
                Button {
                    showingScanReceipt = true
                } label: {
                    Label("Scan Receipt", systemImage: "doc.viewfinder")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            
        }
    }
    
    // MARK: - Transaction list
    
    private struct MonthGroup: Identifiable {
        let id = UUID()
        let monthDate: Date
        let transactions: [Transaction]
    }
    
    private var groupedByMonth: [MonthGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: transactions) { txn in
            calendar.dateInterval(of: .month, for: txn.date)?.start ?? txn.date
        }
        return groups
            .map { MonthGroup(monthDate: $0.key, transactions: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.monthDate > $1.monthDate }
    }
    
    private var transactionList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if transactions.isEmpty {
                        emptyState
                    } else {
                        ForEach(groupedByMonth) { group in
                            monthSection(group)
                                .id(group.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 100)
                
            }
            .onChange(of: visibleMonth) { _, newValue in
                scrollToMonth(newValue, proxy: proxy)
            }
        }
    }
    
    /// Scrolls to the section matching the selected month/year. If there's no
    /// exact match (no transactions logged that month), scrolls to whichever
    /// section is closest instead of doing nothing.
    private func scrollToMonth(_ date: Date, proxy: ScrollViewProxy) {
        guard !groupedByMonth.isEmpty else { return }
        
        let calendar = Calendar.current
        let targetComponents = calendar.dateComponents([.year, .month], from: date)
        guard let targetYear = targetComponents.year, let targetMonth = targetComponents.month else { return }
        let targetIndex = targetYear * 12 + targetMonth
        
        func monthIndex(_ date: Date) -> Int {
            let comps = calendar.dateComponents([.year, .month], from: date)
            return (comps.year ?? 0) * 12 + (comps.month ?? 0)
        }
        
        let closest = groupedByMonth.min { a, b in
            abs(monthIndex(a.monthDate) - targetIndex) < abs(monthIndex(b.monthDate) - targetIndex)
        }
        
        if let closest {
            withAnimation {
                proxy.scrollTo(closest.id, anchor: .top)
            }
        }
    }
    
    private func monthSection(_ group: MonthGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.monthDate.formatted(.dateTime.month(.wide)))
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Text(group.monthDate.formatted(.dateTime.year()))
                    .font(.system(size: 20, weight: .bold))
            }
            
            VStack(spacing: 0) {
                ForEach(Array(group.transactions.enumerated()), id: \.element.id) { index, txn in
                    SwipeableTransactionRow(
                        transaction: txn,
                        onEdit: { editingTransaction = txn },
                        onDelete: { modelContext.delete(txn) }
                    )
                    if index < group.transactions.count - 1 {
                        Divider()
                            .overlay(Color.blue.opacity(0.15))
                            .padding(.leading, 56)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.blue.opacity(0.07))
            )
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No transactions yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Diagonal stripe decoration

private struct DiagonalStripes: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let spacing: CGFloat = 26
                let width = geo.size.width
                let height = geo.size.height
                var x: CGFloat = -height
                while x < width {
                    path.move(to: CGPoint(x: x, y: height))
                    path.addLine(to: CGPoint(x: x + height, y: 0))
                    x += spacing
                }
            }
            .stroke(Color.white.opacity(0.18), lineWidth: 5)
        }
        .clipped()
    }
}

// MARK: - Transaction Row

private struct TransactionRow: View {
    let transaction: Transaction
    
    private var day: String {
        transaction.date.formatted(.dateTime.day(.twoDigits))
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Text(day)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
            
            Text(transaction.title)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
            
            Spacer()
            
            Text(formatCurrency(transaction.amount, showSign: true, isIncome: transaction.isIncome))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(transaction.isIncome ? .green : .red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

// MARK: - Swipeable Transaction Row

/// Wraps `TransactionRow` with a swipe-to-reveal Edit/Delete pair, matching the
/// left-swipe pattern from Mail/Messages. Built as a custom drag gesture (rather than
/// converting the list to a native `List` with `.swipeActions`) to keep the existing
/// custom ScrollView/LazyVStack layout and row styling exactly as designed.
private struct SwipeableTransactionRow: View {
    let transaction: Transaction
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isOpen = false

    private let actionWidth: CGFloat = 160

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 0) {
                Button {
                    onEdit()
                    close()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "pencil")
                        Text("Edit").font(.caption2)
                    }
                    .frame(width: actionWidth / 2, height: 30)
                    .frame(maxHeight: .infinity)
                    .foregroundStyle(.white)
                    .background(Color.blue)
                }
                .buttonStyle(.plain)

                Button {
                    close()
                    onDelete()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Delete").font(.caption2)
                    }
                    .frame(width: actionWidth / 2, height: 30)
                    .frame(maxHeight: .infinity)
                    .foregroundStyle(.white)
                    .background(Color.red)
                }
                .buttonStyle(.plain)
            }

            TransactionRow(transaction: transaction)
                .background(
                    // Color.blue.opacity(0.07) alone is ~93% transparent — it visually
                    // matches the month card's own tint, but doesn't opaquely mask the
                    // Edit/Delete buttons underneath. Layering it over an opaque base
                    // keeps the same look while actually hiding the actions at rest.
                    ZStack {
                        Color(.systemBackground)
                        Color.blue.opacity(0.09)
                            
                    }
                )
                .contentShape(Rectangle())
                .offset(x: offset)
                .onTapGesture {
                    if isOpen { close() }
                }
                .gesture(
                    // minimumDistance raised from the default 10 to 24, and gated on
                    // horizontal movement clearly dominating vertical — a vertical scroll
                    // flick starting on a row was engaging this recognizer (and fighting
                    // the ScrollView's own pan gesture for every touch) before the system
                    // settled on "this is a scroll," which is what made scrolling feel
                    // sluggish across many on-screen rows.
                    DragGesture(minimumDistance: 24)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let base: CGFloat = isOpen ? -actionWidth : 0
                            let proposed = base + value.translation.width
                            offset = min(0, max(-actionWidth, proposed))
                        }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                if offset < -actionWidth / 2 {
                                    offset = -actionWidth
                                    isOpen = true
                                } else {
                                    offset = 0
                                    isOpen = false
                                }
                            }
                        }
                )
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            offset = 0
            isOpen = false
        }
    }
}

// MARK: - Month/Year picker sheet

private struct MonthYearPickerSheet: View {
    @Binding var selection: Date
    @Environment(\.dismiss) private var dismiss
    
    @State private var month: Int
    @State private var year: Int
    
    private let months = Calendar.current.monthSymbols
    private let years: [Int] = Array(1900...10000)
    
    init(selection: Binding<Date>) {
        _selection = selection
        let calendar = Calendar.current
        _month = State(initialValue: calendar.component(.month, from: selection.wrappedValue) - 1)
        _year = State(initialValue: calendar.component(.year, from: selection.wrappedValue))
    }
    
    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Month", selection: $month) {
                    ForEach(0..<months.count, id: \.self) { index in
                        Text(months[index]).tag(index)
                    }
                }
                .pickerStyle(.wheel)
                
                Picker("Year", selection: $year) {
                    ForEach(years, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .pickerStyle(.wheel)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .padding(.horizontal, 16)
            .navigationTitle("Select Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var components = DateComponents()
                        components.year = year
                        components.month = month + 1
                        components.day = 1
                        if let date = Calendar.current.date(from: components) {
                            selection = date
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Currency formatting

private func formatCurrency(_ amount: Double, showSign: Bool, isIncome: Bool = true) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = "."
    formatter.decimalSeparator = ","
    formatter.maximumFractionDigits = 0
    
    let magnitude = abs(amount)
    let numberString = formatter.string(from: NSNumber(value: magnitude)) ?? "\(Int(magnitude))"
    
    guard showSign else {
        return "Rp\(numberString)"
    }
    let sign = isIncome ? "+" : "-"
    return "\(sign)Rp\(numberString)"
}

#Preview {
    TrackerView()
        .modelContainer(SwiftDataService.makePreviewContainer(seeded: true))
        .environment(AppContainer.shared)
}
