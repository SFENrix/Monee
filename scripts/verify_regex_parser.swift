// Standalone verification for RegexParser, run via:
//   swift scripts/verify_regex_parser.swift Monee/Core/Utilities/RegexParser.swift Monee/Core/Database/Models/Transaction.swift
// (Transaction.swift is included only for the TransactionCategory enum it defines; its
// @Model/SwiftUI pieces still compile standalone since Foundation + SwiftUI + SwiftData are
// all system frameworks available to the `swift` command on macOS.)

import Foundation

var failures = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name)")
        failures += 1
    }
}

// Real sample 1: BCA bank transfer confirmation screenshot. No "total"/"nominal"/"amount"/
// "jumlah" keyword appears anywhere — this exercises the confidentRupiahValues() fallback.
let bcaSample = """
Transfer Successful
02 Jul 2026 10:34:01
IDR 10,000.00
Beneficiary Name
Beneficiary Account
Transaction Type
Transfer to BCA Account
View Details
"""

// Real sample 2: blu/BI-FAST transfer confirmation screenshot. "Nominal" label and its
// value are on separate lines — this exercises the next-line lookahead in parseAmount().
let bluSample = """
Kamu Berhasil Mengirimkan Dana!
Transfer Rp 65.000 ke SILVIA NG berhasil
Transaksi Berhasil
20 Jun 2026 | 13:15:15 WIB
Nominal
Rp 65.000,00
SILVIA NG
BCA
Tipe Transaksi
BI-FAST
No. Ref blu
Detail
"""

let bca = RegexParser.parse(bcaSample)
check("BCA sample: amount == 10000", bca.amount == 10000)
check("BCA sample: category == .transfer", bca.category == .transfer)
check("BCA sample: isIncome == false", bca.isIncome == false)
check("BCA sample: suggestedTitle == \"BCA Account\"", bca.suggestedTitle == "BCA Account")

let blu = RegexParser.parse(bluSample)
check("blu sample: amount == 65000", blu.amount == 65000)
check("blu sample: category == .transfer", blu.category == .transfer)
check("blu sample: isIncome == false", blu.isIncome == false)
check("blu sample: suggestedTitle == \"SILVIA NG\"", blu.suggestedTitle == "SILVIA NG")

// Regression check for the fallback-ranking bug this task fixes: a small real amount must
// not lose to a bare year/date number.
let smallAmountSample = """
Payment Confirmation
01 Jan 2026
Rp1.500
"""
let small = RegexParser.parse(smallAmountSample)
check("small amount beats bare year: amount == 1500", small.amount == 1500)

print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
