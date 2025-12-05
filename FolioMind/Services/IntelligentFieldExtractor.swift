//
//  IntelligentFieldExtractor.swift
//  FolioMind
//
//  Uses on-device intelligence and LLMs to extract structured fields from OCR text.
//  Provides document-type-specific prompts and extraction logic.
//

import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Protocol for LLM-based field extraction backends
protocol LLMService {
    func extract(prompt: String, text: String) async throws -> String
    func cleanText(_ rawText: String) async throws -> String
}

/// Intelligent field extractor that uses on-device AI and LLMs
@MainActor
final class IntelligentFieldExtractor {
    private let llmService: LLMService?
    private let useNaturalLanguage: Bool

    init(llmService: LLMService? = nil, useNaturalLanguage: Bool = true) {
        self.llmService = llmService
        self.useNaturalLanguage = useNaturalLanguage
    }

    /// Extract fields intelligently based on document type
    func extractFields(from text: String, docType: DocumentType) async throws -> [Field] {
        var fields: [Field] = []

        // Use Natural Language framework for entity recognition
        if useNaturalLanguage {
            fields.append(contentsOf: extractUsingNaturalLanguage(from: text))
        }

        // Use LLM for structured extraction if available
        if let llmService = llmService {
            let llmFields = try await extractUsingLLM(
                from: text,
                docType: docType,
                service: llmService
            )
            fields.append(contentsOf: llmFields)
        }

        // Apply document-type-specific extraction
        fields.append(contentsOf: extractDocumentSpecificFields(from: text, docType: docType))

        let merged = deduplicateAndMerge(fields, docType: docType)
        return mapToSchema(merged, docType: docType)
    }

    // MARK: - Natural Language Framework Extraction

    private func extractUsingNaturalLanguage(from text: String) -> [Field] {
        var fields: [Field] = []

        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = text

        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        let tags: [NLTag] = [.personalName, .placeName, .organizationName]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            if let tag = tag, tags.contains(tag) {
                let token = String(text[tokenRange])

                switch tag {
                case .personalName:
                    fields.append(Field(
                        key: "name",
                        value: token,
                        confidence: 0.85,
                        source: .vision
                    ))

                case .organizationName:
                    fields.append(Field(
                        key: "organization",
                        value: token,
                        confidence: 0.8,
                        source: .vision
                    ))

                case .placeName:
                    fields.append(Field(
                        key: "location",
                        value: token,
                        confidence: 0.75,
                        source: .vision
                    ))

                default:
                    break
                }
            }
            return true
        }

        return fields
    }

    // MARK: - LLM-Based Extraction

    private func extractUsingLLM(
        from text: String,
        docType: DocumentType,
        service: LLMService
    ) async throws -> [Field] {
        // For generic documents, use comprehensive extraction prompt
        // For specific document types, use targeted prompts
        let response: String
        if docType == .generic {
            response = try await extractWithComprehensivePrompt(from: text, service: service)
        } else {
            let prompt = buildPrompt(for: docType)
            response = try await service.extract(prompt: prompt, text: text)
        }
        return parseStructuredResponse(response, docType: docType)
    }
    
    /// Extracts fields using a comprehensive prompt suitable for any document type
    private func extractWithComprehensivePrompt(
        from text: String,
        service: LLMService
    ) async throws -> String {
        let prompt = """
        You are an information extraction engine for arbitrary real-world documents
        (e.g. insurance cards, billing statements, property tax notices, utility bills,
        receipts, bank statements, government letters, etc.).

        TASK
        - Read the document text.
        - Infer what type of document it is.
        - Normalize the content.
        - Extract as many relevant fields as you can.
        - Return a single JSON object that follows the schema below.

        OUTPUT RULES
        - Output **only** a JSON object, no extra text or explanations.
        - Use double quotes for all keys and string values.
        - Omit any field you cannot confidently determine.
        - Do NOT invent values or guess IDs, dates, or amounts.
        - Use English for all field values, even if the source text is in another language.

        DOCUMENT TYPE
        - Infer a high-level type:
          - "credit_card", "debit_card", "insurance_card",
            "billing_statement", "bank_statement", "receipt",
            "utility_bill", "property_tax", "tax_document",
            "government_notice", "id_document", "other"
        - Put this in "document_type".
        - Optionally add a short free-text "document_subtype" if helpful.

        NORMALIZATION RULES
        - Card numbers:
          - Return **only the last 4 digits** in "card_number".
          - Mask the rest with "X" if needed, e.g. "XXXX-XXXX-XXXX-1234".
        - Dates:
          - Prefer ISO format: "YYYY-MM-DD" if full date is known.
          - If only month/year is known, use "YYYY-MM".
          - If only year is known, use "YYYY".
        - Money amounts:
          - Return as strings with two decimal places, e.g. "123.45".
          - Include currency symbol if present in the original text (e.g. "$123.45").
        - Phone numbers:
          - Normalize to a standard readable format when possible,
            e.g. "(800) 123-4567" or "+1-800-123-4567".
        - Addresses:
          - Keep as a single line or a small set of lines, but remove obvious line breaks
            that split a street address awkwardly.

        POSSIBLE FIELDS (use only what applies)

        Meta & general
        - "document_type": one of the values listed above
        - "document_subtype": "short free-text subtype (optional)"
        - "title": "document title or subject"
        - "primary_date": "main date for this document (normalized)"
        - "all_dates": ["other dates mentioned, normalized if possible"]
        - "names": ["any person names mentioned"]
        - "organizations": ["any organization, company, or government names"]
        - "reference_numbers": ["any IDs or reference numbers"]
        - "key_information": "short summary of the most important details"

        Parties & contact
        - "account_holder_name": "primary person/entity responsible for the account"
        - "recipient_name": "to whom this document is addressed"
        - "sender_name": "who issued this document"
        - "billing_address": "billing address if present"
        - "service_address": "service location if present"
        - "mailing_address": "mailing address if different"
        - "phone_number": "main customer service or contact phone"
        - "email": "contact email if present"

        Financial summary (generic)
        - "account_number": "account or loan number"
        - "statement_date": "statement or notice date"
        - "billing_period": "billing period date range"
        - "due_date": "payment due date"
        - "amount_due": "total amount due"
        - "minimum_payment": "minimum payment amount"
        - "previous_balance": "previous balance"
        - "new_charges": "new charges"
        - "payments_received": "payments applied"
        - "fees": "any fees if explicitly listed"
        - "taxes": "any taxes if explicitly listed"
        - "currency": "currency code or symbol if clearly indicated"
        - "line_items": [
            {
              "description": "item/charge description",
              "date": "item date if available",
              "amount": "item amount"
            }
          ]

        Card-specific (credit/debit)
        - "cardholder": "name on card"
        - "card_number": "card number (last 4 digits only)"
        - "expiry_date": "expiration date (normalized)"
        - "issuer": "card issuer / bank name"
        - "card_type": "visa | mastercard | amex | discover | other"

        Insurance-specific
        - "member_name": "insured member name(s) - if multiple family members are listed,
          provide comma-separated names (e.g. 'JOHN DOE, JANE DOE, JIMMY DOE')"
        - "member_id": "member / subscriber ID"
        - "group_number": "group number"
        - "payer_number": "payer number / payer ID (common on dental cards)"
        - "policy_number": "policy number"
        - "plan_name": "insurance plan name"
        - "insurance_company": "insurance provider / company name"
        - "effective_date": "coverage effective date"
        - "copay": "copay amounts if shown"
        - "rx_bin": "prescription BIN"
        - "rx_pcn": "prescription PCN"

        Property / tax-specific
        - "property_address": "property location"
        - "parcel_number": "parcel / lot / tax ID"
        - "property_id": "other property identifier"
        - "tax_year": "tax year"
        - "assessed_value": "assessed property value"
        - "taxable_value": "taxable value"
        - "tax_amount": "total tax amount"
        - "installments": [
            {
              "due_date": "installment due date",
              "amount": "installment amount"
            }
          ]

        Utilities / services (electricity, water, gas, internet, etc.)
        - "service_type": "electricity | water | gas | internet | phone | other"
        - "meter_number": "meter or service ID"
        - "usage_period": "usage period date range"
        - "usage_amount": "usage quantity (e.g. kWh, gallons, GB) if given"

        Free-form fallback
        - "amounts": ["any monetary amounts mentioned"]
        - "other_fields": {
            "key": "value",
            "key2": "value2"
          }

        RULES FOR FIELD SELECTION
        - Only include fields that clearly apply to this document.
        - If there are multiple plausible values for one field, choose the one that best matches
          how real documents are usually structured (e.g. the main amount due, the primary date).
        - If you are unsure, omit the field instead of guessing.

        Now extract and return a single JSON object for this document.
        """
        let response = try await service.extract(prompt: prompt, text: text)
        return response
    }

    private func buildPrompt(for docType: DocumentType) -> String {
        switch docType {
        case .creditCard:
            return """
            Extract the following fields from this credit card document. Return in JSON format:
            {
              "cardholder": "name on card",
              "card_number": "card number (last 4 digits only)",
              "expiry_date": "expiration date",
              "issuer": "card issuer/bank name",
              "card_type": "visa/mastercard/amex/etc"
            }
            Only include fields you can confidently extract. Use null for missing fields.
            """

        case .insuranceCard:
            return """
            Extract the following fields from this insurance card. Return in JSON format:
            {
              "member_name": "insured member name(s) - if multiple family members listed,
              provide comma-separated (e.g. 'JOHN DOE, JANE DOE, JIMMY DOE')",
              "member_id": "member/subscriber ID",
              "group_number": "group number",
              "payer_number": "payer number/payer ID (common on dental cards)",
              "policy_number": "policy number",
              "plan_name": "insurance plan name (e.g. 'Dental PPO', 'Enhanced Dental PPO')",
              "insurance_company": "insurance provider/company name",
              "effective_date": "coverage effective date",
              "copay": "copay amounts if shown",
              "phone_number": "customer service phone",
              "rx_bin": "prescription BIN",
              "rx_pcn": "prescription PCN"
            }
            Only include fields you can confidently extract. Use null for missing fields.
            IMPORTANT:
            - If you see multiple member names (often numbered like '01 NAME1', '02 NAME2'),
              include ALL of them as comma-separated values in member_name.
            - For plan_name, extract the specific plan type (like "Dental PPO" or "Enhanced Dental PPO"),
              not generic service names.
            """

        case .billStatement:
            return """
            Extract the following fields from this bill/statement. Return in JSON format:
            {
              "account_number": "account number",
              "statement_date": "statement date",
              "due_date": "payment due date",
              "amount_due": "total amount due",
              "minimum_payment": "minimum payment amount",
              "previous_balance": "previous balance",
              "new_charges": "new charges",
              "merchant": "company/merchant name",
              "billing_period": "billing period dates"
            }
            Only include fields you can confidently extract. Use null for missing fields.
            """

        case .idCard:
            return """
            Extract the following fields from this ID card. Return in JSON format:
            {
              "name": "person's full name",
              "id_number": "ID/license number",
              "date_of_birth": "date of birth",
              "issue_date": "issue date",
              "expiry_date": "expiration date",
              "address": "address",
              "issuing_authority": "issuing state/country/authority",
              "class": "license class if driver's license",
              "height": "height",
              "sex": "sex/gender"
            }
            Only include fields you can confidently extract. Use null for missing fields.
            """

        case .letter:
            return """
            Extract the following fields from this letter. Return in JSON format:
            {
              "sender": "sender name/organization",
              "sender_address": "sender address",
              "recipient": "recipient name",
              "recipient_address": "recipient address",
              "date": "letter date",
              "subject": "letter subject/re line",
              "reference_number": "any reference/case numbers",
              "key_dates": "important dates mentioned",
              "action_required": "any actions required from recipient"
            }
            Only include fields you can confidently extract. Use null for missing fields.
            """

        case .receipt:
            return """
            Extract the following fields from this receipt. Return in JSON format:
            {
              "merchant": "merchant/store name",
              "date": "transaction date",
              "time": "transaction time",
              "total": "total amount",
              "subtotal": "subtotal before tax",
              "tax": "tax amount",
              "payment_method": "payment method (cash/card)",
              "last_four": "last 4 of card if applicable",
              "transaction_id": "transaction/receipt number",
              "items": "list of items purchased"
            }
            Only include fields you can confidently extract. Use null for missing fields.
            """

        case .promotional:
            return """
            Extract the following fields from this promotional/marketing document. Return in JSON format:
            {
              "offer_description": "description of the offer or promotion",
              "promo_code": "promotional code if any",
              "offer_amount": "monetary value of offer (e.g. '$50 bonus')",
              "requirements": "what the recipient needs to do to qualify",
              "expiration_date": "when the offer expires",
              "company": "company making the offer",
              "phone_number": "contact phone number",
              "website": "website or URL to use the offer",
              "terms": "key terms and conditions"
            }
            Only include fields you can confidently extract. Use null for missing fields.
            """

        case .generic:
            return """
            Extract key information from this document. Return in JSON format:
            {
              "title": "document title or subject",
              "date": "any dates found",
              "names": "any person names",
              "organizations": "any organization names",
              "amounts": "any monetary amounts",
              "reference_numbers": "any IDs or reference numbers",
              "key_information": "other important details"
            }
            Only include fields you can confidently extract. Use null for missing fields.
            """
        }
    }

    private func parseStructuredResponse(_ response: String, docType: DocumentType) -> [Field] {
        var fields: [Field] = []

        // Try to parse JSON response
        let data = Data(response.utf8)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fields
        }

        for (key, value) in json {
            // Handle different value types
            let stringValue: String

            if let str = value as? String {
                // Direct string value
                guard !str.isEmpty && str != "null" else { continue }
                stringValue = str
            } else if let array = value as? [Any] {
                // Array - convert to comma-separated string for simple arrays
                // or JSON string for complex nested structures
                guard !array.isEmpty else { continue }

                // Check if it's an array of strings
                if let stringArray = array as? [String] {
                    stringValue = stringArray.joined(separator: ", ")
                } else if let jsonData = try? JSONSerialization.data(withJSONObject: array, options: [.prettyPrinted]),
                          let jsonString = String(data: jsonData, encoding: .utf8) {
                    // Complex array (objects, nested structures) - store as JSON
                    stringValue = jsonString
                } else {
                    continue
                }
            } else if let dict = value as? [String: Any] {
                // Nested object - convert to JSON string
                guard let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
                      let jsonString = String(data: jsonData, encoding: .utf8) else {
                    continue
                }
                stringValue = jsonString
            } else if let number = value as? NSNumber {
                // Handle numbers
                stringValue = number.stringValue
            } else {
                // Skip null or unsupported types
                continue
            }

            fields.append(Field(
                key: key,
                value: stringValue,
                confidence: 0.9, // High confidence from LLM
                source: .openai // Or .gemini depending on service
            ))
        }

        return fields
    }

    // MARK: - Document-Specific Extraction

    private func extractDocumentSpecificFields(from text: String, docType: DocumentType) -> [Field] {
        switch docType {
        case .creditCard:
            return extractCreditCardFields(from: text)
        case .insuranceCard:
            return extractInsuranceFields(from: text)
        case .billStatement:
            return extractBillFields(from: text)
        case .idCard:
            return extractIDFields(from: text)
        case .letter:
            return extractLetterFields(from: text)
        case .receipt:
            return extractReceiptFields(from: text)
        case .promotional:
            return extractPromotionalFields(from: text)
        case .generic:
            return []
        }
    }

    private func extractCreditCardFields(from text: String) -> [Field] {
        var fields: [Field] = []

        let lowercased = text.lowercased()

        // Extract card network separately from issuing bank to avoid duplicates
        let networks = ["visa", "mastercard", "unionpay", "maestro", "diners", "jcb"]
        if let network = networks.first(where: { lowercased.contains($0) }) {
            fields.append(Field(
                key: "card_type",
                value: network.capitalized,
                confidence: 0.8,
                source: .vision
            ))
        }

        // Extract issuing bank/brand (include co-branded issuers like Amex/Discover)
        let issuers = [
            "american express", "amex",
            "discover",
            "chase", "citi", "capital one", "bank of america", "bofa", "boa",
            "wells fargo", "hsbc", "us bank", "td", "pnc", "barclays", "santander"
        ]
        if let issuer = issuers.first(where: { lowercased.contains($0) }) {
            fields.append(Field(
                key: "issuer",
                value: issuer.capitalized,
                confidence: 0.85,
                source: .vision
            ))
        }

        // Extract expiry with context
        if let expiryField = extractExpiryDate(from: text) {
            fields.append(expiryField)
        }

        return fields
    }

    private func extractInsuranceFields(from text: String) -> [Field] {
        var fields: [Field] = []

        // Extract member ID (handles formats like "ID W2966", "Member ID 1234", "Subscriber# ABC123456", etc.)
        let memberIDPatterns = [
            "\\bID[:\\s#]+([A-Z0-9][A-Z0-9\\s-]{3,20}?)(?=\\s*\\n|\\s{2,}|$)",
            "(?:member|subscriber)\\s*(?:id|#)?[:\\s#]*([A-Z0-9][A-Z0-9\\s-]{3,20}?)(?=\\s*\\n|\\s{2,}|$)"
        ]

        for pattern in memberIDPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let memberId = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                fields.append(Field(
                    key: "member_id",
                    value: memberId,
                    confidence: 0.85,
                    source: .vision
                ))
                break
            }
        }

        // Extract group number (handles "Den Grp #:", "Group:", etc.)
        let groupPatterns = [
            "(?:den(?:tal)?\\s+)?(?:group|grp)[:\\s#]+([A-Z0-9][A-Z0-9\\s-]{3,25}?)(?=\\s*\\n|\\s{2,}|$)",
            "\\bgrp#?[:\\s#]*([A-Z0-9][A-Z0-9\\s-]{3,25}?)(?=\\s*\\n|\\s{2,}|$)"
        ]

        for pattern in groupPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let groupNum = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                fields.append(Field(
                    key: "group_number",
                    value: groupNum,
                    confidence: 0.85,
                    source: .vision
                ))
                break
            }
        }

        // Extract payer number (new field for dental/medical cards)
        let payerPattern = "payer[:\\s#]+([A-Z0-9][A-Z0-9\\s-]{3,25}?)(?=\\s*\\n|\\s{2,}|$)"
        if let regex = try? NSRegularExpression(pattern: payerPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let payerNum = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            fields.append(Field(
                key: "payer_number",
                value: payerNum,
                confidence: 0.85,
                source: .vision
            ))
        }

        // Extract insurer name from known list
        let insurers = [
            "aetna",
            "cvs health",
            "cvshealth",
            "cigna",
            "unitedhealthcare",
            "anthem",
            "blue cross",
            "blue shield",
            "kaiser",
            "humana"
        ]
        let lower = text.lowercased()
        if let match = insurers.first(where: { lower.contains($0) }) {
            fields.append(Field(
                key: "insurance_company",
                value: match.capitalized,
                confidence: 0.8,
                source: .vision
            ))
        }

        // Extract plan name - prioritize specific plan types over generic terms
        let bulletTrimSet = CharacterSet(charactersIn: "•*·-").union(.punctuationCharacters).union(.whitespaces)
        let lines = text
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .trimmingCharacters(in: bulletTrimSet)
            }
            .filter { !$0.isEmpty }

        // Look for lines with specific plan keywords, prioritizing actual plan types
        let planCandidates = lines.filter { line in
            let lower = line.lowercased()
            // Match actual plan types (PPO, HMO, EPO, etc.) but exclude generic service names
            return (lower.contains("ppo") || lower.contains("hmo") || lower.contains("epo") ||
                    lower.contains("pos") || lower.contains("dental") || lower.contains("vision") ||
                    lower.contains("medical"))
                && !lower.contains("advocate") // Exclude service names
                && !lower.contains("see your plan") // Exclude instructions
                && !lower.contains("www.") // Exclude URLs
                && line.count < 60 // Reasonable plan name length
        }

        // Prefer shortest relevant plan, fall back to the line following insurer if present
        if let plan = planCandidates.min(by: { $0.count < $1.count }) {
            fields.append(Field(
                key: "plan_name",
                value: plan,
                confidence: 0.82,
                source: .vision
            ))
        } else {
            if let insurerLineIndex = lines.firstIndex(where: { line in
                let lowerLine = line.lowercased()
                return lowerLine.contains("aetna") || lowerLine.contains("cvs health")
            }),
               lines.indices.contains(insurerLineIndex + 1) {
                let candidate = lines[insurerLineIndex + 1]
                if candidate.lowercased().contains("ppo") || candidate.lowercased().contains("dental") {
                    fields.append(Field(
                        key: "plan_name",
                        value: candidate,
                        confidence: 0.7,
                        source: .vision
                    ))
                }
            }
        }

        // Extract member names listed with numeric prefixes
        // Handles "01 JAY ZENG" (all caps) or "01. Jay Zeng" (title case)
        let namePattern = #"^\s*\d{1,2}\.?\s+([A-Z][A-Za-z]+(?:\s+[A-Z][A-Za-z]+)+|[A-Z]{2,}(?:\s+[A-Z]{2,})+)"#
        let nameRegex = try? NSRegularExpression(pattern: namePattern, options: [.anchorsMatchLines])
        var enumeratedNames: [String] = []
        if let nameRegex {
            let matches = nameRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range(at: 1), in: text) {
                    let name = String(text[range])
                    // Avoid duplicates
                    if !enumeratedNames.contains(name) {
                        enumeratedNames.append(name)
                    }
                }
            }
        }

        // If we found any enumerated member names, combine them
        if !enumeratedNames.isEmpty {
            let combined = enumeratedNames.joined(separator: ", ")
            fields.append(Field(
                key: "member_name",
                value: combined,
                confidence: enumeratedNames.count > 1 ? 0.82 : 0.78, // Higher confidence for multiple members
                source: .vision
            ))
        }

        // If we captured a payer number but no insurer, map payer as insurance company fallback
        if fields.first(where: { $0.key == "insurance_company" }) == nil,
           let payer = fields.first(where: { $0.key == "payer_number" })?.value {
            fields.append(Field(
                key: "insurance_company",
                value: payer,
                confidence: 0.6,
                source: .vision
            ))
        }

        return fields
    }

    private func extractBillFields(from text: String) -> [Field] {
        var fields: [Field] = []

        // Extract account number
        let accountPattern = "(?:account|acct)[:\\\\s#]+([0-9-]+)"
        if let regex = try? NSRegularExpression(pattern: accountPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            fields.append(Field(
                key: "account_number",
                value: String(text[range]),
                confidence: 0.85,
                source: .vision
            ))
        }

        return fields
    }

    private func extractIDFields(from text: String) -> [Field] {
        var fields: [Field] = []

        // Extract height
        let heightPattern = "(?:ht|height)[:\\\\s]+([45]'[\\\\s]?\\\\d{1,2}\"?|[45]-\\\\d{1,2})"
        if let regex = try? NSRegularExpression(pattern: heightPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            fields.append(Field(
                key: "height",
                value: String(text[range]),
                confidence: 0.8,
                source: .vision
            ))
        }

        return fields
    }

    private func extractLetterFields(from text: String) -> [Field] {
        var fields: [Field] = []

        // Extract RE: or Subject line
        let subjectPattern = "(?:re|subject|regarding)[:\\\\s]+([^\\\\n]{10,100})"
        if let regex = try? NSRegularExpression(pattern: subjectPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            fields.append(Field(
                key: "subject",
                value: String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines),
                confidence: 0.85,
                source: .vision
            ))
        }

        return fields
    }

    private func extractReceiptFields(from text: String) -> [Field] {
        var fields: [Field] = []

        // Extract transaction ID
        let transactionPatterns = [
            "(?:transaction|trans|receipt)[:\\\\s#]+([A-Z0-9-]{6,20})",
            "#([A-Z0-9-]{6,20})"
        ]

        for pattern in transactionPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                fields.append(Field(
                    key: "transaction_id",
                    value: String(text[range]),
                    confidence: 0.75,
                    source: .vision
                ))
                break
            }
        }

        return fields
    }

    private func extractPromotionalFields(from text: String) -> [Field] {
        var fields: [Field] = []

        // Extract promo code
        let promoCodePatterns = [
            "(?:promo(?:tional)?\\s+code|offer\\s+code|use\\s+code)[:\\s]+([A-Z0-9]+)",
            "code[:\\s]+([A-Z0-9]{4,20})"
        ]

        for pattern in promoCodePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                fields.append(Field(
                    key: "promo_code",
                    value: String(text[range]),
                    confidence: 0.9,
                    source: .vision
                ))
                break
            }
        }

        // Extract offer expiration
        let expirationPatterns = [
            "(?:offer\\s+)?expires?[:\\s]+([A-Za-z]+\\s+\\d{1,2},?\\s+\\d{4})",
            "(?:offer\\s+)?ends?[:\\s]+([A-Za-z]+\\s+\\d{1,2},?\\s+\\d{4})",
            "(?:valid\\s+)?(?:through|until|by)[:\\s]+([A-Za-z]+\\s+\\d{1,2},?\\s+\\d{4})",
            "(?:promotion\\s+)?ends?[:\\s]+(\\d{1,2}/\\d{1,2}/\\d{2,4})"
        ]

        for pattern in expirationPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                fields.append(Field(
                    key: "offer_expiry",
                    value: String(text[range]),
                    confidence: 0.85,
                    source: .vision
                ))
                break
            }
        }

        // Extract offer amount
        let offerAmountPatterns = [
            "(?:get|earn|receive|save)\\s+\\$?(\\d{1,4}(?:,\\d{3})*)",
            "\\$?(\\d{1,4}(?:,\\d{3})*)\\s+(?:bonus|reward|off|credit)"
        ]

        for pattern in offerAmountPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                fields.append(Field(
                    key: "offer_amount",
                    value: "$" + String(text[range]),
                    confidence: 0.75,
                    source: .vision
                ))
                break
            }
        }

        return fields
    }

    private func extractExpiryDate(from text: String) -> Field? {
        // Look for expiry with context
        let patterns = [
            "(?:exp(?:iry)?|valid thru|good thru|expires)[:\\\\s]*([0-9]{1,2}[/-][0-9]{2,4})",
            "([0-9]{2}[/-][0-9]{2})\\\\s*(?:exp|expiry|expires)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return Field(
                    key: "expiry_date",
                    value: String(text[range]),
                    confidence: 0.9,
                    source: .vision
                )
            }
        }

        return nil
    }

    // MARK: - Deduplication and Merging

    private func deduplicateAndMerge(_ fields: [Field], docType: DocumentType) -> [Field] {
        var merged: [String: Field] = [:]

        for field in fields {
            let canonical = canonicalize(field, for: docType)
            let key = canonical.key.lowercased()

            if let existing = merged[key] {
                // Keep the field with higher confidence
                if canonical.confidence > existing.confidence {
                    merged[key] = canonical
                } else if canonical.confidence == existing.confidence && canonical.value.count > existing.value.count {
                    // If same confidence, prefer longer/more complete value
                    merged[key] = canonical
                }
            } else {
                merged[key] = canonical
            }
        }

        return Array(merged.values)
    }

    private func canonicalize(_ field: Field, for docType: DocumentType) -> Field {
        let canonicalKey = canonicalKey(for: field.key, docType: docType)
        let normalizedValue = normalizeValue(field.value, for: canonicalKey)

        field.key = canonicalKey
        field.value = normalizedValue
        if field.originalValue.isEmpty {
            field.originalValue = normalizedValue
        }

        return field
    }

    private func canonicalKey(for rawKey: String, docType: DocumentType) -> String {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "exp", "exp_date", "expiry", "expiry_date", "expiration", "expiration_date", "valid_thru", "valid_through":
            return "expiry_date"
        case "card_number", "cardnumber", "card_no", "card_num", "pan":
            return docType == .creditCard ? "card_number" : normalized
        case "cardholder", "card_holder":
            return docType == .creditCard ? "cardholder" : normalized
        case "name":
            if docType == .creditCard { return "cardholder" }
            if docType == .idCard { return "name" }
            return normalized
        case "issuer", "bank", "bank_name":
            return "issuer"
        case "card_type", "network":
            return docType == .creditCard ? "card_type" : normalized
        default:
            return normalized
        }
    }

    private func normalizeValue(_ value: String, for key: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        switch key {
        case "card_number":
            // Strip formatting so deduplication works across sources
            let digits = trimmed.filter(\.isWholeNumber)
            return digits.isEmpty ? trimmed : digits
        case "expiry_date":
            return CardDetailsExtractor.normalizeExpiry(trimmed)
        case "issuer", "card_type":
            return trimmed.capitalized
        default:
            return trimmed
        }
    }

    private func mapToSchema(_ fields: [Field], docType: DocumentType) -> [Field] {
        let allowed = allowedKeys(for: docType)
        guard !allowed.isEmpty else { return fields }

        return fields.compactMap { field in
            let key = field.key.lowercased()
            guard allowed.contains(key) else { return nil }
            return field
        }
    }

    private func allowedKeys(for docType: DocumentType) -> Set<String> {
        switch docType {
        case .creditCard:
            return ["cardholder", "card_number", "expiry_date", "issuer", "card_type"]
        case .insuranceCard:
            return [
                "member_name",
                "member_id",
                "group_number",
                "payer_number",
                "policy_number",
                "plan_name",
                "insurance_company",
                "effective_date",
                "copay",
                "phone_number",
                "rx_bin",
                "rx_pcn"
            ]
        case .billStatement:
            return [
                "account_number",
                "statement_date",
                "due_date",
                "amount_due",
                "minimum_payment",
                "previous_balance",
                "new_charges",
                "merchant",
                "billing_period"
            ]
        case .idCard:
            return [
                "name",
                "id_number",
                "date_of_birth",
                "issue_date",
                "expiry_date",
                "address",
                "issuing_authority",
                "class",
                "height",
                "sex"
            ]
        case .letter:
            return [
                "sender",
                "sender_address",
                "recipient",
                "recipient_address",
                "date",
                "subject",
                "reference_number",
                "key_dates",
                "action_required"
            ]
        case .receipt:
            return ["merchant", "date", "time", "total", "subtotal", "tax", "payment_method", "last_four", "transaction_id", "items"]
        case .promotional:
            return [
                "offer_description",
                "promo_code",
                "offer_amount",
                "requirements",
                "expiration_date",
                "company",
                "phone_number",
                "website",
                "terms"
            ]
        case .generic:
            return []
        }
    }
}

// MARK: - OpenAI LLM Service

/// OpenAI-based LLM service for field extraction
final class OpenAILLMService: LLMService {
    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "gpt-5-mini") {
        self.apiKey = apiKey
        self.model = model
    }

    func extract(prompt: String, text: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages = [
            ["role": "system", "content": prompt],
            ["role": "user", "content": "Document text:\n\n\(text)"]
        ]

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.1,
            "max_tokens": 500,
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "API request failed"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }

        return content
    }

    func cleanText(_ rawText: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Clean up the following OCR-extracted text to make it more readable.
        Fix any obvious OCR errors, normalize spacing and line breaks,
        and format it in a clear, readable way.
        Preserve all important information but make it easier to read.
        Do not translate or summarize - just clean up the formatting and obvious errors.

        Return ONLY the cleaned text, without any explanations or additional commentary.
        """

        let messages = [
            ["role": "system", "content": prompt],
            ["role": "user", "content": rawText]
        ]

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.1,
            "max_tokens": 2000
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "API request failed"])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Apple FoundationModels LLM Service

#if canImport(FoundationModels)
/// Apple's on-device Foundation Models service for field extraction (iOS 18.2+)
@available(iOS 18.2, *)
final class AppleLLMService: LLMService {
    private let model: SystemLanguageModel
    private var availability: SystemLanguageModel.Availability {
        model.availability
    }

    init() {
        self.model = SystemLanguageModel.default
    }

    var isAvailable: Bool {
        if case .available = availability {
            return true
        }
        return false
    }

    func extract(prompt: String, text: String) async throws -> String {
        // Check if model is available
        guard isAvailable else {
            throw NSError(
                domain: "AppleLLM",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Foundation Models are not available. Ensure Apple Intelligence is enabled."]
            )
        }

        // Start a session
        let session = try model.startSession()

        // Construct the full prompt
        let fullPrompt = """
        \(prompt)

        Document text:
        \(text)

        Respond ONLY with valid JSON matching the requested format.
        """

        // Get response from model
        let response = try await session.respond(prompt: fullPrompt)

        guard let content = response.content else {
            throw NSError(
                domain: "AppleLLM",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No content generated from model"]
            )
        }

        return content
    }

    func cleanText(_ rawText: String) async throws -> String {
        // Check if model is available
        guard isAvailable else {
            throw NSError(
                domain: "AppleLLM",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Foundation Models are not available. Ensure Apple Intelligence is enabled."]
            )
        }

        // Start a session
        let session = try model.startSession()

        // Construct the cleanup prompt
        let prompt = """
        Clean up the following OCR-extracted text to make it more readable.
        Fix any obvious OCR errors, normalize spacing and line breaks,
        and format it in a clear, readable way.
        Preserve all important information but make it easier to read.
        Do not translate or summarize - just clean up the formatting and obvious errors.

        Return ONLY the cleaned text, without any explanations or additional commentary.

        Text to clean:
        \(rawText)
        """

        // Get response from model
        let response = try await session.respond(prompt: prompt)

        guard let content = response.content else {
            throw NSError(
                domain: "AppleLLM",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No content generated from model"]
            )
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif

// MARK: - LLM Service Factory

/// Factory for creating appropriate LLM service based on availability and configuration
@MainActor
final class LLMServiceFactory {
    enum ServiceType {
        case apple        // On-device Apple Intelligence (iOS 18.2+)
        case openai(apiKey: String)
        case none         // Disable LLM extraction
    }

    static func create(type: ServiceType) -> LLMService? {
        switch type {
        case .apple:
            #if canImport(FoundationModels)
            if #available(iOS 18.2, *) {
                let service = AppleLLMService()
                return service.isAvailable ? service : nil
            }
            #endif
            return nil

        case .openai(let apiKey):
            return OpenAILLMService(apiKey: apiKey)

        case .none:
            return nil
        }
    }

    static func checkAppleIntelligenceAvailability() -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 18.2, *) {
            let service = AppleLLMService()
            return service.isAvailable
        }
        #endif
        return false
    }
}
