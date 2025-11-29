//
//  DocumentTypeClassifier.swift
//  FolioMind
//
//  Simple heuristic classifier for document types based on OCR text and fields.
//

import Foundation

struct DocumentTypeClassifier {
    static var debugLoggingEnabled: Bool = true

    static func classify(
        ocrText: String,
        fields: [Field],
        hinted: DocumentType?,
        defaultType: DocumentType = .generic
    ) -> DocumentType {
        let text = ocrText.lowercased()
        let fieldKeys = fields.map { $0.key.lowercased() }
        let fieldValues = fields.map { $0.value.lowercased() }
        let haystack = (text + " " + fieldValues.joined(separator: " ")).lowercased()

        let creditHit = isCreditCard(text: haystack, fieldValues: fieldValues, fieldKeys: fieldKeys)
        let insuranceHit = isInsuranceCard(text: haystack, fields: fieldKeys)
        let billHit = isBillStatement(text: haystack)
        let letterHit = isLetter(text: haystack)

        let result: DocumentType
        if insuranceHit { result = .insuranceCard }
        else if creditHit { result = .creditCard }
        else if billHit { result = .billStatement }
        else if letterHit { result = .letter }
        else { result = defaultType }

        logDecision(
            text: text,
            fieldKeys: fieldKeys,
            fieldValues: fieldValues,
            creditHit: creditHit,
            insuranceHit: insuranceHit,
            billHit: billHit,
            letterHit: letterHit,
            result: result
        )

        return result
    }

    private static func isCreditCard(text: String, fieldValues: [String], fieldKeys: [String]) -> Bool {
        let patterns = ["visa", "mastercard", "american express", "amex", "discover", "unionpay", "maestro", "diners", "jcb", "valid thru", "exp", "exp date", "good thru", "debit", "credit"]
        let hasKeyword = patterns.contains { text.contains($0) }

        let valueCandidates = fieldValues.flatMap { panCandidates(in: $0) }
        let textCandidates = panCandidates(in: text)
        let allCandidates = (textCandidates + valueCandidates)

        let hasValidPan = allCandidates.contains { isLikelyPAN($0) }
        let hasLongNumber = allCandidates.contains { (13...19).contains($0.count) }
        let hasExpiry = hasExpiryPattern(in: text) || fieldValues.contains { hasExpiryPattern(in: $0) }
        let cardKey = fieldKeys.contains { $0.contains("card") || $0.contains("pan") }
        let hasCardContext = hasKeyword || hasExpiry || cardKey

        // Require card context to avoid misclassifying long IDs as card numbers
        if hasValidPan && hasCardContext { return true }
        if hasCardContext && hasLongNumber { return true }
        return false
    }

    private static func isInsuranceCard(text: String, fields: [String]) -> Bool {
        let patterns = [
            "insurance", "member id", "policy", "group", "payer", "provider",
            "rxbin", "rxgrp", "rx bin", "rx pcn", "dental", "ppo", "hmo", "vision", "den grp"
        ]
        let fieldHints = ["member_name", "policy_number", "group_number", "rx_bin", "rx_grp", "payer_number", "plan_name"]
        let hasKeyword = patterns.contains { text.contains($0) }
        let hasField = fields.contains { fieldHints.contains($0) }
        return hasKeyword || hasField
    }

    private static func isBillStatement(text: String) -> Bool {
        let patterns = ["amount due", "total due", "balance due", "statement date", "billing period", "invoice", "account number", "due date"]
        return patterns.contains { text.contains($0) }
    }

    private static func isLetter(text: String) -> Bool {
        let patterns = ["dear ", "to whom it may concern", "sincerely", "regards"]
        return patterns.contains { text.contains($0) }
    }

    private static func panCandidates(in text: String) -> [String] {
        // Capture digit sequences allowing spaces or dashes, then strip separators.
        let pattern = "(?:\\d[\\s-]?){13,19}"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let matches = regex?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) ?? []
        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let raw = String(text[range])
            let digitsOnly = raw.filter(\.isWholeNumber)
            return digitsOnly
        }
    }

    private static func isLikelyPAN(_ digits: String) -> Bool {
        let cleaned = digits.filter(\.isWholeNumber)
        guard (13...19).contains(cleaned.count) else { return false }
        return luhnValid(cleaned)
    }

    private static func hasExpiryPattern(in text: String) -> Bool {
        let pattern = "(0[1-9]|1[0-2])[\\s/\\-]?(\\d{2}|\\d{4})"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func luhnValid(_ digits: String) -> Bool {
        var sum = 0
        let reversed = digits.reversed().map { Int(String($0)) ?? 0 }
        for (index, value) in reversed.enumerated() {
            if index % 2 == 1 {
                let doubled = value * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += value
            }
        }
        return sum % 10 == 0
    }

    private static func logDecision(
        text: String,
        fieldKeys: [String],
        fieldValues: [String],
        creditHit: Bool,
        insuranceHit: Bool,
        billHit: Bool,
        letterHit: Bool,
        result: DocumentType
    ) {
#if DEBUG
        guard debugLoggingEnabled else { return }
        let candidates = panCandidates(in: text) + fieldValues.flatMap { panCandidates(in: $0) }
        let luhnValids = candidates.filter { isLikelyPAN($0) }
        let summary = """
        [Classifier] result=\(result.rawValue) \
        credit=\(creditHit) insurance=\(insuranceHit) bill=\(billHit) letter=\(letterHit) \
        luhnValid=\(luhnValids) candidates=\(candidates) expiryMatch=\(hasExpiryPattern(in: text))
        fieldKeys=\(fieldKeys)
        """
        print(summary)
#endif
    }
}
