//
//  RegexParser.swift
//  Monee
//
//  Core/Utilities/RegexParser.swift
//
//  Updated 02/07/26 — narrowed to IDR only, per product decision. This removes the
//  USD/decimal ambiguity that caused two separate parsing bugs earlier — Rupiah is,
//  in practice, always a whole number, so "." and "," are now both just grouping
//  separators, full stop. $-denominated receipts (e.g. an international SaaS invoice
//  billed in USD) will NOT parse — intentional scope narrowing. User enters the
//  converted IDR amount manually in that case.
//

import Foundation

struct ParsedReceiptData {
    var amount: Double?
    var date: Date?
    var keyword: String?
    var category: TransactionCategory
    /// Stub for now — Task 7 replaces this with a real "ke <Name>" extraction pattern.
    var suggestedTitle: String = "Receipt"
    /// Stub for now — Task 7 replaces this with real income/expense direction detection.
    var isIncome: Bool = false
    var rawText: String

    var isComplete: Bool {
        amount != nil && date != nil
    }
}

enum RegexParser {

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

    // MARK: - Amount Parsing (IDR only)

    static func parseAmount(from text: String) -> Double? {
        let totalKeywords = ["grand total", "total due", "amount due", "total", "balance due", "amount", "jumlah"]
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for keyword in totalKeywords {
            if let line = lines.first(where: { $0.lowercased().contains(keyword) }),
               let value = rupiahValues(in: line).first {
                return value
            }
        }

        return rupiahValues(in: text).max()
    }

    /// Matches Rp/IDR-prefixed or bare digit groups: "Rp150.000", "IDR 45,000", "38000".
    private static func rupiahValues(in text: String) -> [Double] {
        let pattern = #"(?:Rp\.?|IDR)?\s?(\d{1,3}(?:[.,]\d{3})+|\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        return matches.compactMap { normalizeRupiahString(nsText.substring(with: $0.range)) }
    }

    /// Strips "Rp"/"IDR" and every "." or "," grouping separator, parses the remainder
    /// as a whole-Rupiah amount.
    private static func normalizeRupiahString(_ raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: "Rp", with: "")
            .replacingOccurrences(of: "IDR", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)

        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    // MARK: - Date Parsing

    static func parseDate(from text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        let matches = detector.matches(in: text, range: range)
        let now = Date()
        let candidates = matches.compactMap { $0.date }.filter { $0 <= now.addingTimeInterval(86_400) }
        return candidates.max()
    }

    // MARK: - Keyword / Category Parsing

    private static let categoryKeywordMap: [TransactionCategory: [String]] = [
        .software: ["subscription", "saas", "adobe", "figma", "notion", "github", "openai", "app store"],
        .hardware: ["apple store", "best buy", "laptop", "monitor", "keyboard", "electronics"],
        .marketing: ["ads", "facebook ads", "google ads", "boost", "sponsor", "promotion"],
        .travel: ["uber", "grab", "gojek", "taxi", "airlines", "hotel", "flight", "airbnb"],
        .meals: ["restaurant", "cafe", "coffee", "starbucks", "mcdonald", "food", "grabfood", "gofood"],
        .office: ["office", "stationery", "staples", "supplies", "print"]
    ]

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
