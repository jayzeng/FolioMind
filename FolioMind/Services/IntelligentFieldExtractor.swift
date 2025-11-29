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

        return deduplicateAndMerge(fields)
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
        let prompt = buildPrompt(for: docType)
        let response = try await service.extract(prompt: prompt, text: text)
        return parseStructuredResponse(response, docType: docType)
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
              "member_name": "insured member name",
              "member_id": "member/subscriber ID",
              "group_number": "group number",
              "policy_number": "policy number",
              "plan_name": "insurance plan name",
              "insurance_company": "insurance provider/company name",
              "effective_date": "coverage effective date",
              "copay": "copay amounts if shown",
              "phone_number": "customer service phone",
              "rx_bin": "prescription BIN",
              "rx_pcn": "prescription PCN"
            }
            Only include fields you can confidently extract. Use null for missing fields.
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
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return fields
        }

        for (key, value) in json {
            guard let stringValue = value as? String, !stringValue.isEmpty, stringValue != "null" else {
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
        case .generic:
            return []
        }
    }

    private func extractCreditCardFields(from text: String) -> [Field] {
        var fields: [Field] = []

        // Extract card issuer
        let issuers = ["visa", "mastercard", "american express", "amex", "discover", "chase", "citi", "capital one"]
        for issuer in issuers {
            if text.lowercased().contains(issuer) {
                fields.append(Field(
                    key: "issuer",
                    value: issuer.capitalized,
                    confidence: 0.85,
                    source: .vision
                ))
                break
            }
        }

        // Extract expiry with context
        if let expiryField = extractExpiryDate(from: text) {
            fields.append(expiryField)
        }

        return fields
    }

    private func extractInsuranceFields(from text: String) -> [Field] {
        var fields: [Field] = []

        // Extract member ID
        let memberIDPatterns = [
            "(?:member|subscriber|id).*?([A-Z0-9]{8,12})",
            "ID[:\\s]+([A-Z0-9]{8,12})"
        ]

        for pattern in memberIDPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                fields.append(Field(
                    key: "member_id",
                    value: String(text[range]),
                    confidence: 0.8,
                    source: .vision
                ))
                break
            }
        }

        // Extract group number
        let groupPattern = "(?:group|grp)[:\\s#]+([A-Z0-9-]+)"
        if let regex = try? NSRegularExpression(pattern: groupPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            fields.append(Field(
                key: "group_number",
                value: String(text[range]),
                confidence: 0.8,
                source: .vision
            ))
        }

        return fields
    }

    private func extractBillFields(from text: String) -> [Field] {
        var fields: [Field] = []

        // Extract account number
        let accountPattern = "(?:account|acct)[:\\s#]+([0-9-]+)"
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
        let heightPattern = "(?:ht|height)[:\\s]+([45]'[\\s]?\\d{1,2}\"?|[45]-\\d{1,2})"
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
        let subjectPattern = "(?:re|subject|regarding)[:\\s]+([^\\n]{10,100})"
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
            "(?:transaction|trans|receipt)[:\\s#]+([A-Z0-9-]{6,20})",
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

    private func extractExpiryDate(from text: String) -> Field? {
        // Look for expiry with context
        let patterns = [
            "(?:exp(?:iry)?|valid thru|good thru|expires)[:\\s]*([0-9]{1,2}[/-][0-9]{2,4})",
            "([0-9]{2}[/-][0-9]{2})\\s*(?:exp|expiry|expires)"
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

    private func deduplicateAndMerge(_ fields: [Field]) -> [Field] {
        var merged: [String: Field] = [:]

        for field in fields {
            let key = field.key.lowercased()

            if let existing = merged[key] {
                // Keep the field with higher confidence
                if field.confidence > existing.confidence {
                    merged[key] = field
                } else if field.confidence == existing.confidence && field.value.count > existing.value.count {
                    // If same confidence, prefer longer/more complete value
                    merged[key] = field
                }
            } else {
                merged[key] = field
            }
        }

        return Array(merged.values)
    }
}

// MARK: - Mock LLM Service for Development

/// Mock LLM service that simulates responses - replace with real implementation
final class MockLLMService: LLMService {
    func extract(prompt: String, text: String) async throws -> String {
        // Simulate processing delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Return empty JSON for now - would be replaced with actual LLM call
        return "{}"
    }

    func cleanText(_ rawText: String) async throws -> String {
        // Simulate processing delay
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

        // Mock: Just return the raw text as-is
        return rawText
    }
}

// MARK: - OpenAI LLM Service

/// OpenAI-based LLM service for field extraction
final class OpenAILLMService: LLMService {
    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "gpt-4o-mini") {
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
        Clean up the following OCR-extracted text to make it more readable. Fix any obvious OCR errors, normalize spacing and line breaks, and format it in a clear, readable way. Preserve all important information but make it easier to read. Do not translate or summarize - just clean up the formatting and obvious errors.

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
        Clean up the following OCR-extracted text to make it more readable. Fix any obvious OCR errors, normalize spacing and line breaks, and format it in a clear, readable way. Preserve all important information but make it easier to read. Do not translate or summarize - just clean up the formatting and obvious errors.

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
        case mock         // For development/testing
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

        case .mock:
            return MockLLMService()

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
