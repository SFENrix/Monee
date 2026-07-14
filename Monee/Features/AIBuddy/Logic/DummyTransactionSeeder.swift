//
//  DummyTransactionSeeder.swift
//  Monee
//
//  DEBUG-only sample data, pulled out of AIChatView so the view file isn't
//  carrying a growing block of test fixture data.
//

import Foundation
import SwiftData

#if DEBUG
enum DummyTransactionSeeder {
    static let transactionCount = 36

    /// Adds a fixed set of sample transactions spanning the last ~3 months (recurring
    /// monthly client income + bills, plus weekly-ish groceries/coffee/dining) — enough
    /// to clear CashReserveCalculator's confidence gate and produce a believable average
    /// daily spend, for testing AIBuddy's purchase-impact math without manual entry.
    static func seed(into modelContext: ModelContext) {
        let samples: [(daysAgo: Int, title: String, category: TransactionCategory, amount: Double)] = [
            // Month 3 (61–90 days ago)
            (88, "Client payment — Website project", .income, 7_000_000),
            (85, "Groceries", .food, 380_000),
            (82, "Electricity bill", .household, 420_000),
            (80, "Coffee shop (work)", .food, 70_000),
            (77, "Netflix + Spotify", .entertaiment, 200_000),
            (74, "Groceries", .food, 350_000),
            (70, "Internet bill", .household, 350_000),
            (67, "Dinner out", .food, 260_000),
            (64, "Phone credit", .other, 100_000),
            (61, "Groceries", .food, 390_000),

            // Month 2 (31–60 days ago)
            (58, "Client payment — Logo design", .income, 3_500_000),
            (55, "Groceries", .food, 360_000),
            (52, "Electricity bill", .household, 440_000),
            (50, "Coffee shop (work)", .food, 75_000),
            (47, "Movie night", .entertaiment, 150_000),
            (44, "Groceries", .food, 370_000),
            (40, "Internet bill", .household, 350_000),
            (37, "Dinner out", .food, 240_000),
            (34, "Phone credit", .other, 100_000),
            (31, "Groceries", .food, 400_000),

            // Month 1 (last 30 days)
            (28, "Client payment — Website project", .income, 8_000_000),
            (25, "Groceries", .food, 350_000),
            (23, "Electricity bill", .household, 450_000),
            (21, "Coffee shop (work)", .food, 75_000),
            (19, "Netflix + Spotify", .entertaiment, 200_000),
            (18, "Client payment — Logo design", .income, 3_000_000),
            (15, "Groceries", .food, 400_000),
            (13, "Internet bill", .household, 350_000),
            (11, "Dinner out", .food, 250_000),
            (9, "Phone credit", .other, 100_000),
            (7, "Groceries", .food, 380_000),
            (6, "Movie night", .entertaiment, 150_000),
            (4, "Client payment — Retainer", .income, 5_000_000),
            (3, "Household supplies", .household, 220_000),
            (2, "Coffee shop (work)", .food, 80_000),
            (1, "Groceries", .food, 300_000)
        ]

        for sample in samples {
            let date = Calendar.current.date(byAdding: .day, value: -sample.daysAgo, to: Date()) ?? Date()
            let transaction = Transaction(
                title: sample.title,
                amount: sample.amount,
                date: date,
                category: sample.category,
                source: .manual
            )
            modelContext.insert(transaction)
        }

        try? modelContext.save()
    }
}
#endif
