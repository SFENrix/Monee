//
//  IncomeEstimateSheet.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//


//
//  IncomeEstimateSheet.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//
//  One-time, skippable nudge — not a blocking onboarding flow. Fires once from
//  AIChatView the first time it's opened with no estimate set. Placed under AIBuddy
//  for now since that's the only place it's triggered from; UI team may want to move
//  this into a general Settings surface later if one gets built.
//
//  ⚠️ UI PLACEHOLDER — plain Form styling, functional only.
//

import SwiftUI

struct IncomeEstimateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var appContainer
    @State private var amountText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Roughly, how much do you make in a typical month? This helps your AI Buddy give grounded advice before you've logged much history. You can skip this or change it anytime.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Estimated Monthly Income") {
                    TextField("e.g. 3000", text: $amountText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("Quick Estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { finish() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value = Double(amountText), value > 0 {
                            UserFinancialProfile.estimatedMonthlyIncome = value
                        }
                        finish()
                    }
                }
            }
        }
    }

    private func finish() {
        appContainer.isUserOnboarded = true
        dismiss()
    }
}

#Preview {
    IncomeEstimateSheet()
        .environment(AppContainer.shared)
}