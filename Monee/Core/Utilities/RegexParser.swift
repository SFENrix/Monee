//
//  ParsedReceiptData.swift
//  Monee
//
//  Created by Rio Ferdinand on 02/07/26.
//


//
//  RegexParser.swift
//  Monee
//
//  Core/Utilities/RegexParser.swift
//

import Foundation

/// Result of parsing raw OCR text from a receipt.
/// This is a transient struct — ReceiptConfirmationView shows this to the user
/// for editing BEFORE it ever becomes a persisted `Transaction`.
struct ParsedReceiptData {
    var amount: Double?
    var date: Date?
    var keyword: String?
    var category: TransactionCategory
    var rawText: String

    /// Confirmation UI can use this to decide whether to highlight missing fields
    var isComplete: Bool {
        amount != nil && date != nil
    }
}

/// Local-only, on-device parsing engine. No network calls.
/// Intentionally rule-based (not ML/NLP) to stay fast, deterministic, and
/// dependency-free for the POC deadline. Expand the keyword map as we test
/// with real receipts — that's the highest-leverage tuning knob here.
enum RegexParser {

    // MARK: - Public Entry Point

    static func parse(_ rawText: String) -> ParsedReceiptData {
        let amount = parseAmount(from: rawText)
        let date = parseDate(from: rawText)
        let (keyword, category) = parseKeyword(from: rawText)

        return ParsedReceiptData(
            amount: amount,
            date: date,
            keyword: keyword,
            category: category,
            rawText: rawText
        )
    }

    // MARK: - Amount Parsing

    /// Looks for a currency-like number near a "total" keyword line first.
    /// Falls back to the largest currency-like number in the whole text
    /// (subtotal < tax < total is a decent heuristic when no keyword hits).
    static func parseAmount(from text: String) -> Double? {
        let totalKeywords = ["grand total", "total due", "amount due", "total", "balance due", "amount"]
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for keyword in totalKeywords {
            if let line = lines.first(where: { $0.lowercased().contains(keyword) }),
               let value = currencyValues(in: line).first {
                return value
            }
        }

        return currencyValues(in: text).max()
    }

    private static func currencyValues(in text: String) -> [Double] {
        // Matches: $12.99 / 12.99 / Rp12.000 / 1,234.56 / 12.000,50 (basic cases)
        let pattern = #"(?:Rp|IDR|\$|USD)?\s?(\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{2})?|\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        return matches.compactMap { match in
            normalizeCurrencyString(nsText.substring(with: match.range))
        }
    }

    /// Strips currency symbols/codes and normalizes "1.234,56" vs "1,234.56" style separators.
    private static func normalizeCurrencyString(_ raw: String) -> Double? {
        var cleaned = raw
            .replacingOccurrences(of: "Rp", with: "")
            .replacingOccurrences(of: "IDR", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "USD", with: "")
            .trimmingCharacters(in: .whitespaces)

        if cleaned.contains(","), cleaned.contains(".") {
            if let commaIdx = cleaned.lastIndex(of: ","), let dotIdx = cleaned.lastIndex(of: ".") {
                if commaIdx > dotIdx {
                    // European style: 1.234,56 -> 1234.56
                    cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                    cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
                } else {
                    // US style: 1,234.56 -> 1234.56
                    cleaned = cleaned.replacingOccurrences(of: ",", with: "")
                }
            }
        } else if cleaned.contains(",") {
            let parts = cleaned.components(separatedBy: ",")
            if parts.last?.count == 3 {
                cleaned = cleaned.replacingOccurrences(of: ",", with: "") // thousands sep
            } else {
                cleaned = cleaned.replacingOccurrences(of: ",", with: ".") // decimal sep
            }
        }

        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    // MARK: - Date Parsing

    /// Uses NSDataDetector (Apple's built-in, locale-aware date detector) instead of a
    /// hand-rolled regex. Far more reliable across formats than we can hand-write in 2 days.
    static func parseDate(from text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }

        let range = NSRange(location: 0, length: (text as NSString).length)
        let matches = detector.matches(in: text, range: range)

        // Filter out obvious false positives (phone numbers, loyalty IDs) by rejecting
        // anything more than a day in the future — receipts are never post-dated.
        let now = Date()
        let candidates = matches.compactMap { $0.date }.filter { $0 <= now.addingTimeInterval(86_400) }

        return candidates.max()
    }

    // MARK: - Keyword / Category Parsing

    /// Maps common merchant/line-item vocabulary to the existing TransactionCategory enum.
    /// First thing to expand once we test against real receipts.
    private static let categoryKeywordMap: [TransactionCategory: [String]] = [
        .software: ["subscription", "saas", "adobe", "figma", "notion", "github", "openai", "app store"],
        .hardware: ["apple store", "best buy", "laptop", "monitor", "keyboard", "electronics"],
        .marketing: ["ads", "facebook ads", "google ads", "boost", "sponsor", "promotion"],
        .travel: ["uber", "grab", "gojek", "taxi", "airlines", "hotel", "flight", "airbnb"],
        .meals: ["restaurant", "cafe", "coffee", "starbucks", "mcdonald", "food", "grabfood", "gofood"],
        .office: ["office", "stationery", "staples", "supplies", "print"]
    ]

    /// Returns the first matched raw keyword and its resolved category.
    /// Defaults to `.unassigned` — never blocks the flow, user confirms/edits manually.
    static func parseKeyword(from text: String) -> (keyword: String?, category: TransactionCategory) {
        let lowercased = text.lowercased()

        for (category, keywords) in categoryKeywordMap {
            for keyword in keywords {
                if lowercased.contains(keyword) {
                    return (keyword, category)
                }
            }
        }

        return (nil, .unassigned)
    }
}