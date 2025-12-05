//
//  FieldExtractor.swift
//  FolioMind
//
//  Intelligent field extraction from OCR text using pattern matching and heuristics.
//

import Foundation

enum FieldExtractor {
    /// Extract structured fields from OCR text
    static func extractFields(from ocrText: String) -> [Field] {
        var fields: [Field] = []

        // Extract phone numbers
        fields.append(contentsOf: extractPhoneNumbers(from: ocrText))

        // Extract emails
        fields.append(contentsOf: extractEmails(from: ocrText))

        // Extract URLs
        fields.append(contentsOf: extractURLs(from: ocrText))

        // Extract dates
        fields.append(contentsOf: extractDates(from: ocrText))

        // Extract addresses
        fields.append(contentsOf: extractAddresses(from: ocrText))

        // Extract amounts/currency
        fields.append(contentsOf: extractAmounts(from: ocrText))

        // Extract names (heuristic-based)
        fields.append(contentsOf: extractNames(from: ocrText))

        // Final deduplication pass across all field types
        return deduplicateFields(fields)
    }

    // MARK: - Phone Number Extraction

    static func extractPhoneNumbers(from text: String) -> [Field] {
        var fields: [Field] = []

        // Multiple phone number patterns
        let patterns = [
            // US formats: (123) 456-7890, 123-456-7890, 123.456.7890
            "\\(?\\d{3}\\)?[\\s.-]?\\d{3}[\\s.-]?\\d{4}",
            // International: +1 123 456 7890, +44 20 1234 5678
            "\\+\\d{1,3}[\\s.-]?\\(?\\d{1,4}\\)?[\\s.-]?\\d{1,4}[\\s.-]?\\d{1,9}",
            // Compact: 1234567890 (10+ digits)
            "\\b\\d{10,15}\\b"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
                for match in matches {
                    if let range = Range(match.range, in: text) {
                        let phoneNumber = String(text[range])

                        // Validate it looks like a phone number
                        let digits = phoneNumber.filter { $0.isNumber }
                        if digits.count >= 10 && digits.count <= 15 {
                            // Skip numbers that are likely group/policy identifiers
                            if hasBannedPhoneContext(in: text, range: range) {
                                continue
                            }

                            // Check context for confidence boost
                            let confidence = phoneContextConfidence(phoneNumber, in: text, range: range)

                            fields.append(Field(
                                key: "phone_number",
                                value: phoneNumber.trimmingCharacters(in: .whitespaces),
                                confidence: confidence,
                                source: .vision
                            ))
                        }
                    }
                }
            }
        }

        return deduplicateFields(fields)
    }

    private static func phoneContextConfidence(_ number: String, in text: String, range: Range<String.Index>) -> Double {
        // Look for keywords near the phone number
        let contextRange = max(0, text.distance(from: text.startIndex, to: range.lowerBound) - 50) ..<
                          min(text.count, text.distance(from: text.startIndex, to: range.upperBound) + 50)

        if let contextStart = text.index(text.startIndex, offsetBy: contextRange.lowerBound, limitedBy: text.endIndex),
           let contextEnd = text.index(text.startIndex, offsetBy: contextRange.upperBound, limitedBy: text.endIndex) {
            let context = String(text[contextStart..<contextEnd]).lowercased()

            let phoneKeywords = ["phone", "tel", "call", "mobile", "cell", "contact", "fax"]
            if phoneKeywords.contains(where: { context.contains($0) }) {
                return 0.9
            }
        }

        // Default confidence based on format
        if number.contains("(") || number.contains("+") {
            return 0.75
        }
        return 0.6
    }

    private static func hasBannedPhoneContext(in text: String, range: Range<String.Index>) -> Bool {
        let contextRange = max(0, text.distance(from: text.startIndex, to: range.lowerBound) - 30) ..<
                          min(text.count, text.distance(from: text.startIndex, to: range.upperBound) + 10)

        guard let contextStart = text.index(text.startIndex, offsetBy: contextRange.lowerBound, limitedBy: text.endIndex),
              let contextEnd = text.index(text.startIndex, offsetBy: contextRange.upperBound, limitedBy: text.endIndex) else {
            return false
        }

        let context = String(text[contextStart..<contextEnd]).lowercased()
        let banned = ["group", "grp", "policy", "claim", "payer", "den grp", "member id"]
        return banned.contains(where: { context.contains($0) })
    }

    // MARK: - Email Extraction

    static func extractEmails(from text: String) -> [Field] {
        var fields: [Field] = []

        let pattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    let email = String(text[range])
                    fields.append(Field(
                        key: "email",
                        value: email,
                        confidence: 0.9,
                        source: .vision
                    ))
                }
            }
        }

        return deduplicateFields(fields)
    }

    // MARK: - URL Extraction

    static func extractURLs(from text: String) -> [Field] {
        var fields: [Field] = []

        let patterns = [
            "https?://[\\w.-]+(?:\\.[a-zA-Z]{2,})+(?:/[^\\s]*)?",
            "www\\.[\\w.-]+(?:\\.[a-zA-Z]{2,})+(?:/[^\\s]*)?"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
                for match in matches {
                    if let range = Range(match.range, in: text) {
                        let url = String(text[range])
                        fields.append(Field(
                            key: "website",
                            value: url,
                            confidence: 0.85,
                            source: .vision
                        ))
                    }
                }
            }
        }

        return deduplicateFields(fields)
    }

    // MARK: - Date Extraction

    static func extractDates(from text: String) -> [Field] {
        var fields: [Field] = []

        let patterns = [
            // MM/DD/YYYY, MM-DD-YYYY
            "\\b(?:0?[1-9]|1[0-2])[/-](?:0?[1-9]|[12][0-9]|3[01])[/-](?:19|20)?\\d{2}\\b",
            // Month DD, YYYY
            "\\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|"
                + "Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\\s+\\d{1,2},?\\s+\\d{4}\\b",
            // DD Month YYYY
            "\\b\\d{1,2}\\s+(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|"
                + "Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\\s+\\d{4}\\b"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
                for match in matches {
                    if let range = Range(match.range, in: text) {
                        let date = String(text[range])

                        // Determine if it's a due date, effective date, etc.
                        let key = dateContextKey(date, in: text, range: range)

                        fields.append(Field(
                            key: key,
                            value: date,
                            confidence: 0.8,
                            source: .vision
                        ))
                    }
                }
            }
        }

        return deduplicateFields(fields)
    }

    private static func dateContextKey(_ date: String, in text: String, range: Range<String.Index>) -> String {
        let contextRange = max(0, text.distance(from: text.startIndex, to: range.lowerBound) - 30) ..<
                          min(text.count, text.distance(from: text.startIndex, to: range.upperBound) + 10)

        if let contextStart = text.index(text.startIndex, offsetBy: contextRange.lowerBound, limitedBy: text.endIndex),
           let contextEnd = text.index(text.startIndex, offsetBy: contextRange.upperBound, limitedBy: text.endIndex) {
            let context = String(text[contextStart..<contextEnd]).lowercased()

            if context.contains("due") || context.contains("payment") {
                return "due_date"
            } else if context.contains("effective") || context.contains("start") {
                return "effective_date"
            } else if context.contains("expir") || context.contains("valid") {
                return "expiry_date"
            } else if context.contains("birth") || context.contains("dob") {
                return "date_of_birth"
            }
        }

        return "date"
    }

    // MARK: - Address Extraction

    static func extractAddresses(from text: String) -> [Field] {
        var fields: [Field] = []

        // Multi-line address pattern: street, city, state zip
        let streetPattern =
            "\\d+\\s+[A-Za-z0-9\\s,.]+(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Lane|Ln|Drive|Dr|Court|Ct|Circle|Cir|Way)"
            + "[^\\n]*(?:\\n|,)[^\\n]+,\\s*[A-Z]{2}\\s+\\d{5}(?:-\\d{4})?"
        let poBoxPattern = "P\\s*O\\.?\\s*Box\\s+\\d+[\\s\\n,]+[A-Za-z\\s]+[\\s\\n,]+[A-Z]{2}\\s+\\d{5}(?:-\\d{4})?(?:\\s+\\d{4})?"

        let patterns = [streetPattern, poBoxPattern]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
                for match in matches {
                    if let range = Range(match.range, in: text) {
                        let address = String(text[range])
                            .replacingOccurrences(of: "\n", with: ", ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        fields.append(Field(
                            key: "address",
                            value: address,
                            confidence: 0.75,
                            source: .vision
                        ))
                    }
                }
            }
        }

        return deduplicateFields(fields)
    }

    // MARK: - Amount/Currency Extraction

    static func extractAmounts(from text: String) -> [Field] {
        var fields: [Field] = []

        let pattern = "\\$\\s*\\d{1,3}(?:,\\d{3})*(?:\\.\\d{2})?"

        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))
            for match in matches {
                if let range = Range(match.range, in: text) {
                    let amount = String(text[range])

                    // Determine context (balance, due, total, etc.)
                    let key = amountContextKey(amount, in: text, range: range)

                    fields.append(Field(
                        key: key,
                        value: amount,
                        confidence: 0.85,
                        source: .vision
                    ))
                }
            }
        }

        return deduplicateFields(fields)
    }

    private static func amountContextKey(_ amount: String, in text: String, range: Range<String.Index>) -> String {
        let contextRange = max(0, text.distance(from: text.startIndex, to: range.lowerBound) - 40) ..<
                          text.distance(from: text.startIndex, to: range.upperBound)

        if let contextStart = text.index(text.startIndex, offsetBy: contextRange.lowerBound, limitedBy: text.endIndex),
           let contextEnd = text.index(text.startIndex, offsetBy: contextRange.upperBound, limitedBy: text.endIndex) {
            let context = String(text[contextStart..<contextEnd]).lowercased()

            if context.contains("balance") {
                return "balance"
            } else if context.contains("due") || context.contains("payment") {
                return "amount_due"
            } else if context.contains("total") {
                return "total_amount"
            } else if context.contains("minimum") {
                return "minimum_payment"
            }
        }

        return "amount"
    }

    // MARK: - Name Extraction

    static func extractNames(from text: String) -> [Field] {
        var fields: [Field] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Heuristic: 2-4 capitalized words, no numbers, reasonable length
            guard trimmed.count >= 5 && trimmed.count <= 50 else { continue }
            guard trimmed.rangeOfCharacter(from: .decimalDigits) == nil else { continue }

            let words = trimmed.split(separator: " ").map(String.init)
            guard words.count >= 2 && words.count <= 4 else { continue }

            // Check if all words are title case
            let allTitleCase = words.allSatisfy { word in
                guard let first = word.first else { return false }
                return first.isUppercase && word.dropFirst().allSatisfy { $0.isLowercase || $0.isUppercase }
            }

            if allTitleCase {
                // Look for name context
                let nameKeywords = ["name", "member", "patient", "cardholder", "insured", "holder"]

                // Check if this line or nearby text suggests it's a name
                let linesContext = lines.joined(separator: " ").lowercased()
                let hasNameContext = nameKeywords.contains(where: { linesContext.contains($0) })

                if hasNameContext {
                    fields.append(Field(
                        key: "name",
                        value: trimmed,
                        confidence: 0.7,
                        source: .vision
                    ))
                }
            }
        }

        return deduplicateFields(fields)
    }

    // MARK: - Utilities

    private static func deduplicateFields(_ fields: [Field]) -> [Field] {
        var seen = Set<String>()
        var unique: [Field] = []

        for field in fields {
            // Normalize the value for comparison
            let normalizedValue: String
            if field.key.lowercased().contains("phone") {
                // For phone numbers, normalize by removing all non-digit characters except +
                normalizedValue = field.value.filter { $0.isNumber || $0 == "+" }
            } else {
                normalizedValue = field.value
            }

            let key = "\(field.key):\(normalizedValue)"
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(field)
            }
        }

        return unique
    }
}
