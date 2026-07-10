//
//  RegexParser.swift
//  Monee
//
//  Core/Utilities/RegexParser.swift
//
//  IDR only, per product decision — Rupiah is, in practice, always a whole number, so "."
//  and "," are both just grouping separators, full stop. $-denominated receipts will NOT
//  parse — intentional scope narrowing.
//
//  Tuned against two real sample screenshots (a BCA bank transfer confirmation and a
//  blu/BI-FAST transfer confirmation) — see the comments below for what each fix addresses.
//

import Foundation

struct ParsedReceiptData {
    var amount: Double?
    var date: Date?
    var keyword: String?
    var category: TransactionCategory
    var suggestedTitle: String
    var isIncome: Bool
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
        let isIncome = parseIsIncome(from: rawText)
        let suggestedTitle = parseSuggestedTitle(from: rawText, category: category)

        return ParsedReceiptData(
            amount: amount,
            date: date,
            keyword: keyword,
            category: category,
            suggestedTitle: suggestedTitle,
            isIncome: isIncome,
            rawText: rawText
        )
    }

    // MARK: - Amount Parsing (IDR only)

    static func parseAmount(from text: String) -> Double? {
        let totalKeywords = ["grand total", "total due", "amount due", "nominal", "total", "balance due", "amount", "jumlah"]
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for keyword in totalKeywords {
            guard let lineIndex = lines.firstIndex(where: { $0.lowercased().contains(keyword) }) else { continue }

            // Same line as the keyword (e.g. "Total: Rp45.000").
            if let value = rupiahValues(in: lines[lineIndex]).first {
                return value
            }

            // Common card-style layout: keyword label on its own line, value on the next
            // line (e.g. "Nominal" then "Rp 65.000,00" below it, as in the blu sample) —
            // check the next couple of lines before giving up on this keyword.
            for offset in 1...2 {
                let nextIndex = lineIndex + offset
                guard nextIndex < lines.count else { break }
                if let value = rupiahValues(in: lines[nextIndex]).first {
                    return value
                }
            }
        }

        return confidentRupiahValues(in: text).max()
    }

    /// Matches Rp/IDR-prefixed or bare digit groups: "Rp150.000", "IDR 45,000", "38000".
    private static func rupiahValues(in text: String) -> [Double] {
        let pattern = #"(?:Rp\.?|IDR)?\s?(\d{1,3}(?:[.,]\d{3})+|\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        return matches.compactMap { normalizeRupiahString(nsText.substring(with: $0.range)) }
    }

    /// Same as `rupiahValues`, but only values a human would recognize as money without a
    /// nearby label: an explicit Rp/IDR prefix, or thousands-grouping (e.g. "10.000"). Used
    /// only for the last-resort "guess the amount" fallback — without this restriction, a
    /// bare short number from a date or time (e.g. the year "2026" in the BCA sample) can
    /// outrank a genuinely small real amount (e.g. "Rp1.500") in a plain max() comparison.
    private static func confidentRupiahValues(in text: String) -> [Double] {
        let pattern = #"(?:Rp\.?|IDR)\s?\d{1,3}(?:[.,]\d{3})*|\d{1,3}(?:[.,]\d{3})+"#
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
        .other: ["subscription", "saas", "adobe", "figma", "notion", "github", "openai", "app store"],
        .other: ["apple store", "best buy", "laptop", "monitor", "keyboard", "electronics"],
        .other: ["ads", "facebook ads", "google ads", "boost", "sponsor", "promotion"],
        .other: ["uber", "grab", "gojek", "taxi", "airlines", "hotel", "flight", "airbnb"],
        .food: ["restaurant", "cafe", "coffee", "starbucks", "mcdonald", "food", "grabfood", "gofood"],
//        .office: ["office", "stationery", "staples", "supplies", "print"],
//        .transfer: ["transfer", "bi-fast", "rtgs", "skn", "bca", "blu", "gopay", "ovo", "dana", "bank"]
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
        return (nil, .other)
    }

    // MARK: - Direction (Income vs. Expense)

    /// Default is expense (false) when ambiguous — the safer default for cash-reserve math,
    /// since silently crediting fake income would inflate the reserve.
    private static let incomeKeywords = ["diterima", "menerima", "masuk", "top up", "topup", "received", "refund", "cash in"]

    static func parseIsIncome(from text: String) -> Bool {
        let lowercased = text.lowercased()
        return incomeKeywords.contains { lowercased.contains($0) }
    }

    // MARK: - Suggested Title

    /// Deliberately minimal: one pattern for the "ke <Name>" / "to <Name>" construction
    /// common in Indonesian transfer confirmations (e.g. "...ke SILVIA NG berhasil" in the
    /// blu sample), falling straight back to a generic label. No broader merchant-name
    /// extraction beyond this single pattern.
    static func parseSuggestedTitle(from text: String, category: TransactionCategory) -> String {
        let pattern = #"(?:\bke\b|\bto\b)\s+([A-Z][A-Za-z ]{1,30}?)(?:\s+berhasil\b|[.,\n]|$)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let name = text[range].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                return name
            }
        }

        return category == .other ? "Receipt" : category.rawValue
    }
}
