//
//  CashReserveCalculatorTests.swift
//  Monee
//
//  Created by Rio Ferdinand on 12/07/26.
//


import XCTest
@testable import Monee

final class CashReserveCalculatorTests: XCTestCase {

    private func makeSummary(spareMoney: Double, avgDailyExpense: Double) -> CashReserveSummary {
        CashReserveSummary(
            spareMoney: spareMoney,
            avgDailyExpense: avgDailyExpense,
            runwayDays: avgDailyExpense > 0 ? spareMoney / avgDailyExpense : nil,
            windowDays: 30,
            expenseCount: 10,
            transactionCount: 10,
            hasEnoughData: true
        )
    }

    func testSafeWhenPostPurchaseRunwayIsComfortable() {
        let summary = makeSummary(spareMoney: 10_000_000, avgDailyExpense: 100_000)
        let result = CashReserveCalculator.evaluatePurchase(amount: 1_000_000, currentSummary: summary)

        XCTAssertEqual(result.tier, .safe)
        XCTAssertEqual(result.postPurchaseSpareMoney, 9_000_000)
        XCTAssertEqual(result.postPurchaseRunwayDays, 90)
    }

    func testSafeAtExactlyFourteenDayBoundary() {
        let summary = makeSummary(spareMoney: 1_500_000, avgDailyExpense: 100_000)
        let result = CashReserveCalculator.evaluatePurchase(amount: 100_000, currentSummary: summary)

        XCTAssertEqual(result.postPurchaseRunwayDays, 14)
        XCTAssertEqual(result.tier, .safe)
    }

    func testCautionWhenRunwayDropsBelowFourteenDaysButStaysPositive() {
        let summary = makeSummary(spareMoney: 2_000_000, avgDailyExpense: 200_000)
        let result = CashReserveCalculator.evaluatePurchase(amount: 1_000_000, currentSummary: summary)

        XCTAssertEqual(result.postPurchaseSpareMoney, 1_000_000)
        XCTAssertEqual(result.postPurchaseRunwayDays, 5)
        XCTAssertEqual(result.tier, .caution)
    }

    func testBadWhenPurchaseTakesSpareMoneyNegative() {
        let summary = makeSummary(spareMoney: 1_000_000, avgDailyExpense: 200_000)
        let result = CashReserveCalculator.evaluatePurchase(amount: 1_500_000, currentSummary: summary)

        XCTAssertEqual(result.postPurchaseSpareMoney, -500_000)
        XCTAssertEqual(result.tier, .bad)
    }

    func testSafeWhenNoSpendPaceEstablishedYetAndMoneyStaysPositive() {
        let summary = makeSummary(spareMoney: 5_000_000, avgDailyExpense: 0)
        let result = CashReserveCalculator.evaluatePurchase(amount: 1_000_000, currentSummary: summary)

        XCTAssertNil(result.postPurchaseRunwayDays)
        XCTAssertEqual(result.tier, .safe)
    }
}