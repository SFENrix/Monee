//
//  ProfileView.swift
//  Monee
//
//  Profile tab: avatar header, editable status row, and an overview section showing
//  average monthly income/expenses computed from logged transactions.
//
//  Restyled 07/07/26 — matched to the new mock: a blurred mint/peach mesh page
//  background (same family as the onboarding art), a rounded gradient "cover photo"
//  behind the header with the avatar overlapping its bottom edge, Name promoted
//  to its own editable card (mirroring Status), and Overview cards tinted mint/peach
//  instead of plain white. UI ONLY — no logic, bindings, or data flow changes.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query private var transactions: [Transaction]

    @State private var name: String = UserProfile.name ?? ""
    @State private var status: OnboardingStatus = UserProfile.status ?? .single
    @State private var estimatedIncomeText: String = UserProfile.estimatedMonthlyIncome.map { String(Int($0)) } ?? ""
    @State private var estimatedExpenseText: String = UserProfile.estimatedMonthlyExpense.map { String(Int($0)) } ?? ""
    @State private var showingEditProfile = false

    private let mintTint = Color(red: 0.55, green: 0.80, blue: 0.70)
    private let peachTint = Color(red: 0.96, green: 0.65, blue: 0.45)

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundMesh

                ScrollView {
                    VStack(spacing: 20) {
                        profileHeader

                        nameCard
                        statusCard

                        estimatesSection

                        overviewSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView(name: $name)
            }
        }
        .onChange(of: name) { _, newValue in UserProfile.name = newValue }
        .onChange(of: status) { _, newValue in UserProfile.status = newValue }
    }

    // MARK: - Background

    private var backgroundMesh: some View {
        ZStack {
            Color(red: 0.98, green: 0.96, blue: 0.92)

            Circle()
                .fill(mintTint.opacity(0.35))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: -140, y: -280)

            Circle()
                .fill(peachTint.opacity(0.32))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: 130, y: -120)

            Circle()
                .fill(mintTint.opacity(0.28))
                .frame(width: 280, height: 280)
                .blur(radius: 100)
                .offset(x: -60, y: 420)
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var profileHeader: some View {
        ZStack(alignment: .bottom) {
            coverGradient

            AvatarView(name: name)
                .frame(width: 96, height: 96)
                .background(
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: 106, height: 106)
                )
                .offset(y: 48)
        }
        .padding(.bottom, 48) // reserves space for the avatar overlapping below the cover
    }

    private var coverGradient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.90, green: 0.95, blue: 0.90),
                    Color(red: 0.99, green: 0.87, blue: 0.75)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(mintTint.opacity(0.55))
                .frame(width: 180, height: 180)
                .blur(radius: 55)
                .offset(x: -100, y: -40)
            Circle()
                .fill(peachTint.opacity(0.55))
                .frame(width: 200, height: 200)
                .blur(radius: 65)
                .offset(x: 110, y: 30)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    // MARK: - Name / Status cards

    private var nameCard: some View {
        Button {
            showingEditProfile = true
        } label: {
            infoRow(label: "Name", value: name)
        }
        .buttonStyle(.plain)
    }

    private var statusCard: some View {
        NavigationLink {
            StatusPickerView(status: $status)
        } label: {
            infoRow(label: "Status", value: status.rawValue)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Estimates

    private var estimatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Estimates")
                .font(.title3.bold())
                .padding(.leading, 4)

            VStack(spacing: 12) {
                estimateRow(title: "Estimated Monthly Income", text: $estimatedIncomeText) {
                    UserProfile.estimatedMonthlyIncome = Double($0)
                }
                estimateRow(title: "Estimated Monthly Expense", text: $estimatedExpenseText) {
                    UserProfile.estimatedMonthlyExpense = Double($0)
                }
            }
        }
    }

    private func estimateRow(title: String, text: Binding<String>, onCommit: @escaping (String) -> Void) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .onChange(of: text.wrappedValue) { _, newValue in onCommit(newValue) }
                .frame(width: 120)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            Image(systemName: "pencil")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }

    // MARK: - Overview

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.title3.bold())
                .padding(.leading, 4)

            HStack(spacing: 12) {
                OverviewCard(
                    title: "Average Income",
                    amount: averageMonthly(isIncome: true),
                    isPositive: true,
                    tint: mintTint
                )
                OverviewCard(
                    title: "Average Expenses",
                    amount: averageMonthly(isIncome: false),
                    isPositive: false,
                    tint: peachTint
                )
            }
        }
    }

    /// Average of monthly totals across only the months that actually have
    /// transactions of that type — months with no data don't drag the average down.
    private func averageMonthly(isIncome: Bool) -> Double {
        let calendar = Calendar.current
        let filtered = transactions.filter { $0.isIncome == isIncome }
        guard !filtered.isEmpty else { return 0 }

        let grouped = Dictionary(grouping: filtered) {
            calendar.dateComponents([.year, .month], from: $0.date)
        }
        let monthlyTotals = grouped.values.map { txns in
            txns.reduce(0) { $0 + $1.amount }
        }
        return monthlyTotals.reduce(0, +) / Double(monthlyTotals.count)
    }
}

// MARK: - Overview card

private struct OverviewCard: View {
    let title: String
    let amount: Double
    let isPositive: Bool
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(formatCurrency(amount))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            HStack {
                Spacer()
                Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isPositive ? .green : .red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(.systemBackground), tint.opacity(0.30)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
}

private func formatCurrency(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = "."
    formatter.decimalSeparator = ","
    formatter.maximumFractionDigits = 0
    let numberString = formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
    return "Rp\(numberString)"
}

// MARK: - Avatar

private struct AvatarView: View {
    let name: String

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.93, green: 0.45, blue: 0.65),
                        Color(red: 0.97, green: 0.65, blue: 0.80)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(initials)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

private struct StatusPickerView: View {
    @Binding var status: OnboardingStatus
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(OnboardingStatus.allCases) { option in
            Button {
                status = option
                dismiss()
            } label: {
                HStack {
                    Text(option.rawValue)
                        .foregroundStyle(.primary)
                    Spacer()
                    if option == status {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .navigationTitle("Status")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Edit profile

private struct EditProfileView: View {
    @Binding var name: String
    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Your name", text: $draftName)
                        .textContentType(.name)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            name = trimmed
                        }
                        dismiss()
                    }
                }
            }
            .onAppear { draftName = name }
        }
    }
}

#Preview {
    ProfileView()
        .modelContainer(SwiftDataService.makePreviewContainer(seeded: true))
}
