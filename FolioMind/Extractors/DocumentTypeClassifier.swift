//
//  DocumentTypeClassifier.swift
//  FolioMind
//
//  Heuristic classifier for document types based on OCR text and fields.
//  Improved with promotional detection and strengthened rules to prevent false positives.
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

        // CRITICAL: Check in this specific order
        // Promotional must be checked FIRST to prevent false positives

        // 1. Promotional (check EARLY to prevent false positives)
        let promotionalHit = isPromotional(text: haystack)

        // 2. High-specificity types (strong unique patterns)
        let insuranceHit = isInsuranceCard(text: haystack, fields: fieldKeys)
        let creditHit = isCreditCard(
            text: haystack,
            fieldValues: fieldValues,
            fieldKeys: fieldKeys
        )

        // 3. Transactional types (require structure)
        let receiptHit = isReceipt(
            text: haystack,
            fieldKeys: fieldKeys,
            isPromotional: promotionalHit
        )
        let billHit = isBillStatement(text: haystack)

        // 4. Generic types (weaker signals)
        let letterHit = isLetter(text: haystack, isPromotional: promotionalHit)

        // PRIORITY ORDER (order matters!)
        let result: DocumentType
        if promotionalHit {
            result = .promotional
        } else if insuranceHit {
            result = .insuranceCard
        } else if creditHit {
            result = .creditCard
        } else if receiptHit {
            result = .receipt
        } else if billHit {
            result = .billStatement
        } else if letterHit {
            result = .letter
        } else {
            result = defaultType
        }

        let signals = DecisionSignals(
            promotional: promotionalHit,
            credit: creditHit,
            insurance: insuranceHit,
            receipt: receiptHit,
            bill: billHit,
            letter: letterHit
        )

        logDecision(
            text: text,
            fieldKeys: fieldKeys,
            fieldValues: fieldValues,
            signals: signals,
            result: result
        )

        return result
    }

    // MARK: - Promotional Detection (NEW)

    /// Detects promotional/marketing content (offers, coupons, advertisements)
    /// Requires 2+ different signal types to avoid false positives
    private static func isPromotional(text: String) -> Bool {
        // Future-conditional verbs (offer contingent on action)
        let incentiveVerbs = [
            "get $", "earn", "save $", "receive", "win",
            "claim", "redeem"
        ]

        // Future/conditional grammar
        let conditionals = [
            "when you", "if you", "after you",
            "you'll", "we'll", "you will", "you can"
        ]

        // Promotional terminology
        let promoTerms = [
            "promo code", "promotional code", "offer code",
            "offer", "promotion", "deal",
            "bonus", "reward", "free", "gift"
        ]

        // Urgency/scarcity
        let urgency = [
            "limited time", "expires", "ends", "by ",
            "hurry", "act now", "don't miss", "last chance"
        ]

        // Call-to-action
        let ctas = [
            "sign up", "enroll", "apply now", "join now",
            "visit", "call now", "click here", "register"
        ]

        // Count distinct signal types
        var signalTypes = 0
        if incentiveVerbs.contains(where: { text.contains($0) }) { signalTypes += 1 }
        if conditionals.contains(where: { text.contains($0) }) { signalTypes += 1 }
        if promoTerms.contains(where: { text.contains($0) }) { signalTypes += 1 }
        if urgency.contains(where: { text.contains($0) }) { signalTypes += 1 }
        if ctas.contains(where: { text.contains($0) }) { signalTypes += 1 }

        // Require at least 2 different promotional signal types
        return signalTypes >= 2
    }

    // MARK: - Receipt Detection (STRENGTHENED)

    /// Detects receipts (proof of purchase transactions)
    /// Strengthened to require transaction structure and prevent promotional misclassification
    private static func isReceipt(
        text: String,
        fieldKeys: [String],
        isPromotional: Bool
    ) -> Bool {
        // ANTI-PATTERN: If promotional, cannot be receipt
        if isPromotional {
            return false
        }

        // STRONG TRANSACTION INDICATORS

        // Transaction identifiers
        let transactionPatterns = [
            "receipt #", "receipt#", "receipt number", "receipt no",
            "transaction #", "transaction number", "transaction id",
            "order #", "order number", "order id",
            "confirmation #"
        ]
        let hasTransactionId = transactionPatterns.contains { text.contains($0) }

        // Payment methods
        let cardTypes = ["visa", "mastercard", "amex", "american express",
                        "discover", "maestro", "jcb", "diners"]
        let paymentIndicators = [
            "auth code", "authorization", "approval code",
            "paid with", "payment method", "card type"
        ]
        let hasCardPayment = cardTypes.contains { text.contains($0) } ||
                            paymentIndicators.contains { text.contains($0) }

        // Cash payment indicators
        let cashIndicators = [
            "cash", "change:", "change due", "tendered",
            "amount paid", "paid in cash", "cash tendered"
        ]
        let hasCashPayment = cashIndicators.contains { text.contains($0) }

        let hasPaymentMethod = hasCardPayment || hasCashPayment

        // Merchant context
        let merchantIndicators = [
            "store #", "cashier", "terminal", "register",
            "server:", "table:", "pump:", "merchant id"
        ]
        let hasMerchantContext = merchantIndicators.contains { text.contains($0) }

        // CLASSIFICATION RULES (tiered by confidence)

        // Rule 1: STRONG - Transaction ID + Payment Method
        if hasTransactionId && hasPaymentMethod {
            return true
        }

        // Rule 2: MEDIUM - Merchant context + Payment Method
        if hasMerchantContext && hasPaymentMethod {
            return true
        }

        // Rule 3: WEAK - Requires multiple signals
        let receiptKeywords = [
            "receipt", "thank you for shopping",
            "customer copy", "merchant copy"
        ]
        let hasReceiptWord = receiptKeywords.contains { text.contains($0) }

        let paymentCompleteWords = [
            "tendered", "change:", "change due"
        ]
        let hasPaymentComplete = paymentCompleteWords.contains { text.contains($0) }

        let amountCount = countAmounts(in: text)
        let hasMultipleAmounts = amountCount >= 3

        if hasReceiptWord && hasPaymentComplete && hasMultipleAmounts {
            return true
        }

        // Default: Not confident it's a receipt
        return false
    }

    // MARK: - Insurance Card Detection (STRENGTHENED)

    /// Detects insurance cards (health, dental, vision)
    /// Strengthened to require multiple signals and filter out EOB/summaries
    private static func isInsuranceCard(text: String, fields: [String]) -> Bool {
        // ANTI-PATTERNS (check first)
        let antiPatterns = [
            "this is not an insurance card",
            "summary of benefits", "coverage summary",
            "explanation of benefits", "eob",
            "claim statement", "billing statement"
        ]
        if antiPatterns.contains(where: { text.contains($0) }) {
            return false
        }

        // SIGNAL CATEGORIES

        // Card-specific identifiers
        let cardIndicators = [
            "member id", "member number", "subscriber id",
            "policy number", "policy #", "certificate number"
        ]
        let hasCardIndicator = cardIndicators.contains { text.contains($0) }

        // Insurance-specific terminology
        let insuranceTerms = [
            "copay", "co-pay", "deductible",
            "rx bin", "rxbin", "rx grp", "rxgrp", "rx pcn",
            "payer id", "provider network"
        ]
        let hasInsuranceTerm = insuranceTerms.contains { text.contains($0) }

        // Network/plan types
        let networkTerms = [
            "ppo", "hmo", "epo", "pos",
            "dental plan", "vision plan", "health plan"
        ]
        let hasNetworkTerm = networkTerms.contains { text.contains($0) }

        // Insurance company names (strong signal)
        let insurers = [
            "blue cross", "blue shield", "premera", "regence",
            "aetna", "cigna", "united healthcare", "kaiser",
            "anthem", "humana", "delta dental", "vsp"
        ]
        let hasInsurerName = insurers.contains { text.contains($0) }

        // CLASSIFICATION RULES

        // Rule 1: RX info is very specific to insurance cards
        if text.contains("rx bin") || text.contains("rxbin") {
            return true
        }

        // Rule 2: Insurer name + card indicator
        if hasInsurerName && hasCardIndicator {
            return true
        }

        // Rule 3: Require COMBINATION (at least 2 different signal types)
        let signalCount = [
            hasCardIndicator,
            hasInsuranceTerm,
            hasNetworkTerm
        ].filter { $0 }.count

        return signalCount >= 2
    }

    // MARK: - Credit Card Detection (IMPROVED)

    /// Detects physical payment cards (credit/debit)
    /// Improved to filter out gift cards and membership cards
    private static func isCreditCard(
        text: String,
        fieldValues: [String],
        fieldKeys: [String]
    ) -> Bool {
        // PAN candidates
        let valueCandidates = fieldValues.flatMap { panCandidates(in: $0) }
        let textCandidates = panCandidates(in: text)
        let allCandidates = (textCandidates + valueCandidates)

        let hasValidPan = allCandidates.contains { isLikelyPAN($0) }
        let hasLongNumber = allCandidates.contains { (13...19).contains($0.count) }

        // Card context indicators
        let issuerNames = [
            "visa", "mastercard", "american express", "amex",
            "discover", "unionpay", "maestro", "diners", "jcb"
        ]
        let hasIssuerName = issuerNames.contains { text.contains($0) }

        let cardTypeKeywords = [
            "credit card", "debit card", "payment card",
            "debit", "credit", "valid thru", "exp", "expires"
        ]
        let hasCardTypeKeyword = cardTypeKeywords.contains { text.contains($0) }

        let hasExpiry = hasExpiryPattern(in: text) ||
                       fieldValues.contains { hasExpiryPattern(in: $0) }

        // Field key patterns (more specific)
        let cardFieldKeys = fieldKeys.filter { key in
            (key.contains("card") && key.contains("number")) ||
            key.contains("pan") ||
            (key.contains("credit") && key.contains("card")) ||
            (key.contains("debit") && key.contains("card"))
        }
        let hasCardField = !cardFieldKeys.isEmpty

        // ANTI-PATTERNS (not a payment card)
        let nonPaymentCardTerms = [
            "gift card", "member card", "membership card",
            "rewards card", "loyalty card", "id card"
        ]
        let isNonPaymentCard = nonPaymentCardTerms.contains { text.contains($0) }

        if isNonPaymentCard && !hasIssuerName {
            return false  // Gift/membership cards excluded unless issuer name present
        }

        // CLASSIFICATION RULES

        let hasStrongContext = hasIssuerName || hasExpiry || hasCardField

        // Rule 1: Luhn-valid PAN + strong context
        if hasValidPan && hasStrongContext {
            return true
        }

        // Rule 2: Long number + issuer name + expiry
        if hasLongNumber && hasIssuerName && hasExpiry {
            return true
        }

        return false
    }

    // MARK: - Bill Statement Detection (STRENGTHENED)

    /// Detects bill statements (utilities, medical, credit card statements)
    /// Strengthened to require combination of signals
    private static func isBillStatement(text: String) -> Bool {
        // Strong billing-specific terms
        let billingTerms = [
            "billing statement", "statement of account",
            "billing period", "statement date",
            "service period"
        ]
        let hasBillingTerm = billingTerms.contains { text.contains($0) }

        // Payment request language
        let paymentDue = [
            "amount due", "total due", "balance due",
            "minimum payment", "payment due date",
            "please pay", "remit payment"
        ]
        let hasPaymentDue = paymentDue.contains { text.contains($0) }

        // Account management
        let accountTerms = [
            "account number", "account #",
            "previous balance", "current charges",
            "account summary", "new balance"
        ]
        let hasAccountTerm = accountTerms.contains { text.contains($0) }

        // Service-specific (utilities, medical, etc.)
        let serviceTerms = [
            "utility bill", "electric service", "gas service",
            "water service", "internet service",
            "usage", "kwh", "therms", "gallons",
            "medical bill", "hospital bill", "patient statement"
        ]
        let hasServiceTerm = serviceTerms.contains { text.contains($0) }

        // Invoice patterns
        let invoiceTerms = [
            "invoice number", "invoice #", "invoice date"
        ]
        let hasInvoice = invoiceTerms.contains { text.contains($0) }

        // CLASSIFICATION RULES

        // Rule 1: Very specific billing terminology
        if hasBillingTerm {
            return true
        }

        // Rule 2: Invoice + payment request
        if hasInvoice && hasPaymentDue {
            return true
        }

        // Rule 3: Service-specific + payment request
        if hasServiceTerm && hasPaymentDue {
            return true
        }

        // Rule 4: Account management + payment request
        if hasAccountTerm && hasPaymentDue {
            return true
        }

        // Single "amount due" NOT enough
        return false
    }

    // MARK: - Letter Detection (IMPROVED)

    /// Detects personal/business correspondence
    /// Improved to defer to promotional when marketing content detected
    private static func isLetter(text: String, isPromotional: Bool) -> Bool {
        // If already identified as promotional, don't classify as letter
        if isPromotional {
            return false
        }

        // Salutations
        let salutations = [
            "dear ", "to whom it may concern",
            "hello ", "hi ", "greetings"
        ]
        let hasSalutation = salutations.contains { text.contains($0) }

        // Closings
        let closings = [
            "sincerely", "regards", "best regards",
            "yours truly", "respectfully", "cordially",
            "with appreciation", "warm regards"
        ]
        let hasClosing = closings.contains { text.contains($0) }

        // Require BOTH salutation and closing for letter format
        return hasSalutation && hasClosing
    }

    // MARK: - Helper Functions

    private static func countAmounts(in text: String) -> Int {
        let pattern = "\\$?\\s?\\d{1,3}(?:,\\d{3})*(?:\\.\\d{2})?"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        return regex?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)).count ?? 0
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

    // MARK: - Logging

    private struct DecisionSignals {
        let promotional: Bool
        let credit: Bool
        let insurance: Bool
        let receipt: Bool
        let bill: Bool
        let letter: Bool
    }

    private static func logDecision(
        text: String,
        fieldKeys: [String],
        fieldValues: [String],
        signals: DecisionSignals,
        result: DocumentType
    ) {
#if DEBUG
        guard debugLoggingEnabled else { return }
        let candidates = panCandidates(in: text) + fieldValues.flatMap { panCandidates(in: $0) }
        let luhnValids = candidates.filter { isLikelyPAN($0) }
        let summary = """
        [Classifier] result=\(result.rawValue)
          promotional=\(signals.promotional)
          insurance=\(signals.insurance)
          credit=\(signals.credit)
          receipt=\(signals.receipt)
          bill=\(signals.bill)
          letter=\(signals.letter)
          fieldKeys=\(fieldKeys.prefix(5))
          luhnValid=\(luhnValids.count) candidates=\(candidates.count)
          expiryMatch=\(hasExpiryPattern(in: text))
          textPreview=\(text.prefix(100))...
        """
        print(summary)
#endif
    }
}
