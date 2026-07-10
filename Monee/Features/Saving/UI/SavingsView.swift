//
//  SavingsView.swift
//  FreelanceFinance
//
//  Dedicated Emergency Savings screen — a fuller-detail counterpart to the compact
//  emergency-fund strip that used to live at the top of DashboardView/Summary.
//
//  DATA NOTE: follows the same UserProfile-backed pattern the rest of the app has
//  settled on (see AIChatViewModel.formatEmergencyFundContext / ContentView's merge
//  notes): `UserProfile.emergencyFundTotal` (Double, settable — the amount actually
//  saved so far) and `UserProfile.emergencyFundTarget` (Double?, read-only — 12x the
//  user's estimated monthly expense, nil until that estimate is set in Profile). If
//  your actual UserProfile API names/signatures differ, adjust the two `UserProfile.*`
//  references below and in AddFundsSheet's onDone — everything else is self-contained.
//
//  UserProfile is a plain UserDefaults-backed store, not @Observable, so — same as
//  TrackerView/DashboardView already do — the values are copied into local @State
//  and re-synced onAppear rather than read live, so this view doesn't go stale if
//  the user edits their income estimate on Profile and switches back here.
//

import SwiftUI

struct SavingsView: View {
    @State private var currentSaving: Double = UserProfile.emergencyFundTotal
    @State private var target: Double? = UserProfile.emergencyFundTarget
    @State private var showingAddFund = false
    @State private var showingInfo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerBackground
                    .frame(height: 280)
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0,
                            bottomLeadingRadius: 32,
                            bottomTrailingRadius: 32,
                            topTrailingRadius: 0,
                            style: .continuous
                        )
                    )
                    .overlay(alignment: .top) {
                        VStack(spacing: 40) {
                            headerContent
                            savingGoalsCard
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 90)
                    }

                VStack(alignment: .leading, spacing: 16) {
                    sectionTitle
                    progressCard
                    encouragementCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(red: 0.98, green: 0.94, blue: 0.87).ignoresSafeArea())
        .sheet(isPresented: $showingAddFund) {
            AddFundsSheet { amountAdded in
                UserProfile.emergencyFundTotal += amountAdded
                currentSaving = UserProfile.emergencyFundTotal
            }
        }
        .alert("Emergency Savings", isPresented: $showingInfo) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("Your emergency fund goal is set to 12x your estimated monthly expenses. Add to it anytime — it's kept separate from your everyday balance.")
        }
        .onAppear {
            currentSaving = UserProfile.emergencyFundTotal
            target = UserProfile.emergencyFundTarget
        }
    }

    // MARK: - Header

    private var headerContent: some View {
        VStack(spacing: 10) {
            Text("Current Saving")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.85))

            Text(formatRupiah(currentSaving))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            Button {
                showingAddFund = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color(red: 0.35, green: 0.72, blue: 0.78)))
            }
            .buttonStyle(.plain)
        }
    }

    private var savingGoalsCard: some View {
        HStack {
            Text("Saving Goals")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            Spacer()

            Text(target.map(formatRupiah) ?? "Not set yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
    }

    /// Smooth teal/green gradient, matching TrackerView's header for visual
    /// consistency between the Tracker and Savings tabs.
    private var headerBackground: some View {
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

    // MARK: - Section title

    private var sectionTitle: some View {
        HStack(spacing: 6) {
            Text("Emergency Savings")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)

            Button {
                showingInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Progress card

    private var progressFraction: Double {
        guard let target, target > 0 else { return 0 }
        return min(currentSaving / target, 1)
    }

    private var remaining: Double {
        guard let target else { return 0 }
        return max(target - currentSaving, 0)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Progress")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(progressFraction * 100))%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.35))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color(red: 0.85, green: 0.95, blue: 0.85))
                    )
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(red: 0.95, green: 0.90, blue: 0.80))

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
                }
            }
            .frame(height: 14)

            if target != nil {
                Text("\(formatRupiah(remaining)) left to save to reach your goal!")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 0.90, green: 0.55, blue: 0.25))
            } else {
                Text("Set an estimated monthly expense in Profile to calculate your goal.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
        )
    }

    // MARK: - Encouragement card

    /// Simple tiered message so the copy actually reflects where the user is,
    /// rather than always saying the same thing regardless of progress.
    private var encouragementMessage: (title: String, body: String) {
        switch progressFraction {
        case ..<0.01:
            return ("Let's get started!", "Every little bit counts — add your first contribution whenever you're ready.")
        case ..<0.5:
            return ("Keep going!", "You're doing great! Stay consistent and reach your goal sooner.")
        case ..<1.0:
            return ("Almost there!", "You're over halfway — a few more contributions and you'll hit your goal.")
        default:
            return ("Goal reached! 🎉", "Your emergency fund is fully stocked. Nice work staying consistent.")
        }
    }

    private var encouragementCard: some View {
        let message = encouragementMessage
        return HStack(alignment: .top, spacing: 14) {
            Image("buntel")
                .renderingMode(.original)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .font(.system(size: 16, weight: .bold))
                Text(message.body)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
        )
    }

    // MARK: - Formatting

    private func formatRupiah(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.maximumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "Rp\(number)"
    }
}

// MARK: - Add Funds sheet

private struct AddFundsSheet: View {
    var onDone: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""

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

                Text("Add to Savings")
                    .font(.system(size: 17, weight: .bold))

                Spacer()

                Button("Done") {
                    if let amount = Double(amountText), amount > 0 {
                        onDone(amount)
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

            HStack {
                Text("Amount")
                    .font(.system(size: 16))
                Spacer()
                Text("IDR")
                    .foregroundStyle(.secondary)
                TextField("0", text: $amountText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 16))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .presentationDetents([.height(160)])
    }
}

#Preview {
    SavingsView()
        .environment(AppContainer.shared)
}
