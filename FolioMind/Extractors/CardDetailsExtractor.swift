//
//  CardDetailsExtractor.swift
//  FolioMind
//
//  Heuristics to extract credit card details from OCR text and fields.
//

import Foundation

struct CardDetails {
    let pan: String?
    let expiry: String?
    let holder: String?
    let issuer: String?
}

enum CardDetailsExtractor {
    // MARK: - Public API

    static func extract(ocrText: String, fields: [Field]) -> CardDetails {
        // Try to extract from structured fields first
        let panFromFields = fieldValue(for: ["card_number", "card number", "pan"], in: fields)
        let expiryFromFields = fieldValue(for: ["expiry", "exp", "valid_thru"], in: fields)
        let holderFromFields = fieldValue(for: ["cardholder", "name"], in: fields)
        let issuerFromFields = fieldValue(for: ["issuer", "bank", "network"], in: fields)

        // Extract from OCR text as fallback
        let lines = parseLines(from: ocrText)
        let pan = panFromFields ?? extractPan(from: ocrText)
        let expiry = expiryFromFields ?? extractExpiry(from: ocrText)
        let holder = holderFromFields ?? extractHolderName(from: lines, pan: pan, expiry: expiry)
        let issuer = issuerFromFields ?? extractIssuer(from: lines, fullText: ocrText)

        return CardDetails(pan: pan, expiry: expiry, holder: holder, issuer: issuer)
    }

    // MARK: - Field Extraction

    private static func fieldValue(for keys: [String], in fields: [Field]) -> String? {
        fields.first { field in
            keys.contains(field.key.lowercased())
        }?.value
    }

    // MARK: - PAN Extraction

    private static func extractPan(from text: String) -> String? {
        // Search line by line to avoid concatenating numbers from different lines
        let lines = text.components(separatedBy: .newlines)
        let pattern = "(?:\\d[\\s-]?){13,19}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        var candidates: [String] = []
        for line in lines {
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: line.utf16.count))
            for match in matches {
                guard let range = Range(match.range, in: line) else { continue }
                let digits = String(line[range]).filter(\.isWholeNumber)
                if (13...19).contains(digits.count) {
                    candidates.append(digits)
                }
            }
        }

        // Prefer Luhn-valid PAN, fallback to longest
        return candidates.first(where: isLuhnValid) ?? candidates.max(by: { $0.count < $1.count })
    }

    // MARK: - Expiry Extraction

    private static func extractExpiry(from text: String) -> String? {
        // Strategy 1: Look for expiry near keywords like "Valid Thru", "Exp", etc.
        if let keywordExpiry = extractExpiryNearKeyword(from: text) {
            return keywordExpiry
        }

        // Strategy 2: Find standalone date patterns, excluding those embedded in other numbers
        return extractStandaloneExpiry(from: text)
    }

    private static func extractExpiryNearKeyword(from text: String) -> String? {
        // Try with separator first (most common)
        let patternWithSep = "(?i)(valid|exp|expiry|good\\s*thru)[^\\n]{0,20}(0[1-9]|1[0-2])[\\s/\\-](\\d{2}|\\d{4})"
        if let regex = try? NSRegularExpression(pattern: patternWithSep),
           let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)),
           match.numberOfRanges >= 4,
           let monthRange = Range(match.range(at: 2), in: text),
           let yearRange = Range(match.range(at: 3), in: text) {
            let month = String(text[monthRange])
            let year = String(text[yearRange])
            return normalizeExpiry("\(month)/\(year)")
        }

        // Try without separator (e.g., "Valid 0824")
        let patternNoSep = "(?i)(valid|exp|expiry|good\\s*thru)[^\\n]{0,20}(0[1-9]|1[0-2])(\\d{2})"
        if let regex = try? NSRegularExpression(pattern: patternNoSep),
           let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)),
           match.numberOfRanges >= 4,
           let monthRange = Range(match.range(at: 2), in: text),
           let yearRange = Range(match.range(at: 3), in: text) {
            let month = String(text[monthRange])
            let year = String(text[yearRange])
            return normalizeExpiry("\(month)\(year)")
        }

        return nil
    }

    private static func extractStandaloneExpiry(from text: String) -> String? {
        // Use negative lookbehind/lookahead to avoid matching parts of longer numbers
        let pattern = "(?<!\\d)(0[1-9]|1[0-2])[\\s/\\-](\\d{2})(?!\\d)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
        let candidates = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            return normalizeExpiry(String(text[range]))
        }

        // Prefer future dates
        return candidates.max { lhs, rhs in
            (expiryDate(from: lhs) ?? .distantPast) < (expiryDate(from: rhs) ?? .distantPast)
        }
    }

    // MARK: - Cardholder Name Extraction

    private static func extractHolderName(from lines: [String], pan: String?, expiry: String?) -> String? {
        let ignoreTokens = [
            "valid", "exp", "good thru",
            "visa", "mastercard", "american express", "amex", "discover",
            "bank", "www", "http", "https", "bofa", "global"
        ]

        // Find lines that could be names (no digits, not ignored tokens)
        let candidates = lines.enumerated().filter { _, line in
            let lower = line.lowercased()
            return !line.isEmpty
                && line.rangeOfCharacter(from: .decimalDigits) == nil
                && !ignoreTokens.contains(where: { lower.contains($0) })
        }

        // Prefer lines after PAN or expiry
        let panLineIndex = pan.flatMap { lineIndex(containing: $0, in: lines) } ?? -1
        let expiryLineIndex = expiry.flatMap { lineIndex(containing: $0, in: lines) } ?? -1
        let preferredIndex = (panLineIndex >= 0 ? panLineIndex : expiryLineIndex)

        if preferredIndex >= 0,
           let match = candidates.first(where: { idx, _ in idx > preferredIndex }) {
            return match.1
        }

        return candidates.first?.1
    }

    // MARK: - Issuer Extraction

    private static func extractIssuer(from lines: [String], fullText: String) -> String? {
        let knownIssuers = [
            "bank of america", "bofa", "boa",
            "chase", "wells fargo",
            "citibank", "citi",
            "capital one", "hsbc",
            "amex", "american express",
            "discover", "us bank",
            "td", "pnc", "barclays", "santander"
        ]

        // Check for known issuers in full text - prefer longer matches
        let lowerText = fullText.lowercased()
        let matches = knownIssuers.filter { lowerText.contains($0) }
        if let longestMatch = matches.max(by: { $0.count < $1.count }) {
            return longestMatch.capitalized
        }

        // Look for banking-related terms in lines
        let bankingTerms = ["bank", "card services", "financial"]
        if let line = lines.first(where: { line in
            let lower = line.lowercased()
            return bankingTerms.contains(where: { lower.contains($0) })
        }) {
            return line
        }

        return nil
    }

    // MARK: - Utilities

    private static func parseLines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizeExpiry(_ raw: String) -> String {
        let digits = raw.filter(\.isWholeNumber)
        guard digits.count == 4 || digits.count == 6 else { return raw }

        let month = String(digits.prefix(2))
        let yearDigits = digits.count == 4 ? digits.suffix(2) : digits.suffix(4)
        return "\(month)/\(yearDigits)"
    }

    private static func expiryDate(from normalized: String) -> Date? {
        let parts = normalized.split(separator: "/")
        guard parts.count == 2,
              let month = Int(parts[0]),
              let yearValue = Int(parts[1]) else {
            return nil
        }

        let year = yearValue < 100 ? 2000 + yearValue : yearValue

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        return Calendar(identifier: .gregorian).date(from: components)
    }

    private static func lineIndex(containing snippet: String, in lines: [String]) -> Int? {
        let normalizedSnippet = snippet.replacingOccurrences(of: " ", with: "")
        return lines.firstIndex { line in
            line.replacingOccurrences(of: " ", with: "").contains(normalizedSnippet)
        }
    }

    private static func isLuhnValid(_ digits: String) -> Bool {
        let reversed = digits.reversed().compactMap { Int(String($0)) }
        let sum = reversed.enumerated().reduce(0) { sum, pair in
            let (index, digit) = pair
            if index % 2 == 1 {
                let doubled = digit * 2
                return sum + (doubled > 9 ? doubled - 9 : doubled)
            } else {
                return sum + digit
            }
        }
        return sum % 10 == 0
    }
}
