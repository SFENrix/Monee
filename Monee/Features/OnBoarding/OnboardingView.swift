//
//  OnboardingView.swift
//  Monee
//
//  Welcome / onboarding screen introducing the app's mascot "Buntel" over a soft
//  pastel mesh background, with a white rounded sheet holding the copy and CTA.
//
//  Updated 07/07/26 — swapped the hand-drawn SwiftUI mascot for the real
//  "buntel" image asset (Assets.xcassets → buntel).
//
//  Updated 07/07/26 — now owns the full onboarding chain: pushes to
//  OnboardingSetupView on "Get Started", and writes the final collected data
//  (name, status, starting balance, estimated income/expense) to UserProfile
//  when OnboardingFinancialSetupView (the last step) finishes. Starting balance
//  is recorded as an ordinary "Starting Balance" Transaction rather than a
//  special baseline field, so CashReserveCalculator never needs a second code path.
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppContainer.self) private var appContainer

    var body: some View {
        NavigationStack {
            welcomeScreen
        }
    }

    private var welcomeScreen: some View {
        ZStack {
            meshBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                Image("buntel")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 190, height: 190)
                    .padding(.bottom, 28)

                VStack(spacing: 8) {
                    Text("Hi, I'm Buntel!")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.black.opacity(0.85))

                    Text("Let's get things ready before you start")
                        .font(.system(size: 16))
                        .foregroundStyle(.black.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 36)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)

            VStack {
                Spacer()
                bottomSheet
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: OnboardingRoute.self) { route in
            switch route {
            case .setup:
                OnboardingSetupView(onFinish: finishOnboarding)
            }
        }
    }

    // MARK: - Bottom sheet

    private var bottomSheet: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.black.opacity(0.08))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            NavigationLink(value: OnboardingRoute.setup) {
                Text("Get Started")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.38, green: 0.78, blue: 0.80),
                                        Color(red: 0.30, green: 0.68, blue: 0.72)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .background(
            TopCurveShape()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 20, x: 0, y: -6)
        )
        .frame(height: 300)
    }

    // MARK: - Background

    private var meshBackground: some View {
        ZStack {
            Color(red: 0.98, green: 0.96, blue: 0.92)

            Circle()
                .fill(Color(red: 0.96, green: 0.65, blue: 0.45).opacity(0.55))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: 110, y: -260)

            Circle()
                .fill(Color(red: 0.55, green: 0.80, blue: 0.70).opacity(0.55))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -140, y: -60)

            Circle()
                .fill(Color(red: 0.98, green: 0.87, blue: 0.72).opacity(0.6))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: 0, y: 120)
        }
    }

    // MARK: - Completion

    /// Called once OnboardingFinancialSetupView (the last of the three chained
    /// screens) finishes. Persists everything collected across the whole chain
    /// and flips the flags that dismiss the fullScreenCover in RootTabView.
    private func finishOnboarding(
        name: String,
        status: OnboardingStatus?,
        totalMoney: Double?,
        monthlyIncome: Double?,
        monthlyExpense: Double?
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        UserProfile.name = trimmedName.isEmpty ? nil : trimmedName
        UserProfile.status = status
        UserProfile.estimatedMonthlyIncome = monthlyIncome
        UserProfile.estimatedMonthlyExpense = monthlyExpense

        if let totalMoney, totalMoney > 0 {
            let transaction = Transaction(
                title: "Starting Balance",
                amount: totalMoney,
                date: Date(),
                category: .income,
                source: .manual
            )
            modelContext.insert(transaction)
            try? modelContext.save()
        }

        UserProfile.hasCompletedOnboarding = true
        appContainer.isUserOnboarded = true
    }
}

/// Onboarding's own navigation route — a single case today, but a real enum (not
/// a Bool flag) so the chain can gain intermediate steps later without RootTabView
/// or the fullScreenCover presentation needing to change.
private enum OnboardingRoute: Hashable {
    case setup
}

// MARK: - Bottom sheet shape

/// A rounded rectangle whose top edge is a gentle wave rather than a
/// straight line, matching the soft curve where the white sheet meets
/// the gradient background.
private struct TopCurveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let waveHeight: CGFloat = 55

        path.move(to: CGPoint(x: rect.minX, y: waveHeight))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: 0),
            control1: CGPoint(x: rect.width * 0.35, y: waveHeight + 35),
            control2: CGPoint(x: rect.width * 0.65, y: -25)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview {
    OnboardingView()
        .environment(AppContainer.shared)
        .modelContainer(SwiftDataService.makePreviewContainer())
}
