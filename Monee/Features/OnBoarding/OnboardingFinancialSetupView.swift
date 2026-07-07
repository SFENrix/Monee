//
//  OnboardingFinancialSetupView.swift
//  Monee
//
//  Third onboarding step, shown after OnboardingSetupView's "Get Started" tap.
//  Collects rough financial numbers (total money, monthly income, monthly
//  expense) so the Profile's Overview section has something to anchor to
//  before any real transactions exist. Same visual language as the prior
//  onboarding screens. Shares `ArchCurveShape` with OnboardingSetupView.swift.
//

import SwiftUI

struct OnboardingFinancialSetupView: View {
    /// Called once this step is done, with whatever numbers the user entered.
    /// Any field left blank is passed through as `nil`.
    var onFinish: (
        _ totalMoney: Double?,
        _ monthlyIncome: Double?,
        _ monthlyExpense: Double?
    ) -> Void = { _, _, _ in }

    @Environment(\.dismiss) private var dismiss

    @State private var totalMoneyText: String = ""
    @State private var monthlyIncomeText: String = ""
    @State private var monthlyExpenseText: String = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case totalMoney, monthlyIncome, monthlyExpense
    }

    var body: some View {
        ZStack(alignment: .top) {
            backgroundGradient
                .frame(height: 260)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                Spacer().frame(height: 250)

                sheetContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Color.white)
                    .clipShape(ArchCurveShape())
            }
            .ignoresSafeArea(edges: .bottom)
            .dismissKeyboardOnTap()

            Image("buntel")
                .resizable()
                .scaledToFit()
                .frame(width: 190, height: 190)
                .padding(.top, 70)
                .allowsHitTesting(false)

            VStack {
                HStack {
                    backButton
                    Spacer()
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.leading, 8)
            .zIndex(1)
        }
    }

    // MARK: - Back button

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black.opacity(0.7))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.7)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sheet content

    private var sheetContent: some View {
        VStack(spacing: 28) {
            VStack(spacing: 6) {
                Text("Almost there...")
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("A rough estimate is fine — you can always update this later")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 16) {
                fieldCard(label: "Total money") {
                    TextField("0", text: $totalMoneyText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 16))
                        .focused($focusedField, equals: .totalMoney)
                }

                fieldCard(label: "Monthly income") {
                    TextField("0", text: $monthlyIncomeText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 16))
                        .focused($focusedField, equals: .monthlyIncome)
                }

                fieldCard(label: "Monthly expense") {
                    TextField("0", text: $monthlyExpenseText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 16))
                        .focused($focusedField, equals: .monthlyExpense)
                }
            }

            Spacer(minLength: 0)

            Button {
                onFinish(
                    Double(totalMoneyText),
                    Double(monthlyIncomeText),
                    Double(monthlyExpenseText)
                )
                dismiss()
            } label: {
                Text("Finish")
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
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
    }

    private func fieldCard<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                content()
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemGray6).opacity(0.6))
        )
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            Color(red: 0.98, green: 0.96, blue: 0.92)

            Circle()
                .fill(Color(red: 0.96, green: 0.65, blue: 0.45).opacity(0.55))
                .frame(width: 300, height: 300)
                .blur(radius: 90)
                .offset(x: 120, y: -60)

            Circle()
                .fill(Color(red: 0.55, green: 0.80, blue: 0.70).opacity(0.55))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: -130, y: 40)
        }
    }
}

#Preview {
    OnboardingFinancialSetupView()
}
