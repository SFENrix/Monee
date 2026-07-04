//
//  ProfileView.swift
//  Monee
//
//  Profile tab: avatar header, editable status row, and an overview section showing
//  average monthly income/expenses computed from logged transactions.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query private var transactions: [Transaction]

    @State private var name: String = "Gwen Alyssa"
    @State private var status: RelationshipStatus = .single
    @State private var showingEditProfile = false

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient

                ScrollView {
                    VStack(spacing: 20) {
                        profileHeader

                        statusRow

                        overviewSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView(name: $name)
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color.blue.opacity(0.25)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: 10) {
            AvatarView(name: name)
                .frame(width: 96, height: 96)
                .padding(.top, 24)

            Text(name)
                .font(.title2.bold())

            Button {
                showingEditProfile = true
            } label: {
                Text("Edit Name")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(.systemGray5).opacity(0.5)))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Status row

    private var statusRow: some View {
        NavigationLink {
            StatusPickerView(status: $status)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Status")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(status.rawValue)
                        .font(.body)
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
        .buttonStyle(.plain)
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
                    isPositive: true
                )
                OverviewCard(
                    title: "Average Expenses",
                    amount: averageMonthly(isIncome: false),
                    isPositive: false
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
                .fill(Color(.systemBackground))
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
                    colors: [Color.blue.opacity(0.9), Color.blue.opacity(0.5)],
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

// MARK: - Relationship status

enum RelationshipStatus: String, CaseIterable, Identifiable {
    case single = "Single"
    case inRelationship = "In a Relationship"
    case married = "Married"
    case itsComplicated = "It's Complicated"

    var id: String { rawValue }
}

private struct StatusPickerView: View {
    @Binding var status: RelationshipStatus
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(RelationshipStatus.allCases) { option in
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

