//
//  BackendAPIService.swift
//  FolioMind
//
//  Backend API client for document classification and field extraction.
//  Replaces on-device LLM processing with cloud-based BAML service.
//

import Foundation

// MARK: - API Models

struct ClassificationSignals: Codable {
    let promotional: Bool
    let receipt: Bool
    let bill: Bool
    let insuranceCard: Bool
    let creditCard: Bool
    let letter: Bool
    let details: [String: AnyCodable]?
    let keyPhrases: [String]?
    let indicators: [String]?
    let counterIndicators: [String]?
    let reasoning: String?

    enum CodingKeys: String, CodingKey {
        case promotional, receipt, bill
        case insuranceCard = "insurance_card"
        case creditCard = "credit_card"
        case letter, details
        case keyPhrases = "key_phrases"
        case indicators
        case counterIndicators = "counter_indicators"
        case reasoning
    }
}

struct FieldModel: Codable {
    let key: String
    let value: String
    let confidence: Double
    let source: String?
}

// MARK: - API Request/Response Models

struct ClassifyRequest: Codable {
    let ocrText: String
    let fields: [FieldModel]?
    let hint: String?

    enum CodingKeys: String, CodingKey {
        case ocrText = "ocr_text"
        case fields, hint
    }
}

struct ClassifyResponse: Codable {
    let documentType: String
    let confidence: Double
    let signals: ClassificationSignals

    enum CodingKeys: String, CodingKey {
        case documentType = "document_type"
        case confidence, signals
    }
}

struct ExtractRequest: Codable {
    let ocrText: String
    let documentType: String

    enum CodingKeys: String, CodingKey {
        case ocrText = "ocr_text"
        case documentType = "document_type"
    }
}

struct ExtractResponse: Codable {
    let fields: [FieldModel]
}

struct AnalyzeRequest: Codable {
    let ocrText: String
    let hint: String?

    enum CodingKeys: String, CodingKey {
        case ocrText = "ocr_text"
        case hint
    }
}

struct AnalyzeResponse: Codable {
    let documentType: String
    let confidence: Double
    let signals: ClassificationSignals
    let fields: [FieldModel]

    enum CodingKeys: String, CodingKey {
        case documentType = "document_type"
        case confidence, signals, fields
    }
}

struct UploadResponseWithMetadata: Codable {
    let ocrText: String?
    let transcription: String?
    let documentType: String
    let confidence: Double
    let signals: ClassificationSignals
    let fields: [FieldModel]

    enum CodingKeys: String, CodingKey {
        case ocrText = "ocr_text"
        case transcription
        case documentType = "document_type"
        case confidence, signals, fields
    }
}

// MARK: - Helper for dynamic JSON

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

// MARK: - Backend API Service

final class BackendAPIService {
    enum APIError: LocalizedError {
        case invalidURL
        case invalidResponse
        case httpError(statusCode: Int, message: String?)
        case decodingError(Error)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid API URL"
            case .invalidResponse:
                return "Invalid response from server"
            case .httpError(let statusCode, let message):
                return "HTTP \(statusCode): \(message ?? "Unknown error")"
            case .decodingError(let error):
                return "Failed to decode response: \(error.localizedDescription)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            }
        }
    }

    private let baseURL: String
    private let session: URLSession

    init(baseURL: String = "https://foliomind-backend.fly.dev/", session: URLSession = .shared) {
        if baseURL.hasSuffix("/") {
            self.baseURL = String(baseURL.dropLast())
        } else {
            self.baseURL = baseURL
        }
        self.session = session
    }

    // MARK: - Public API Methods

    /// Classify a document from OCR text
    func classify(ocrText: String, fields: [Field]? = nil, hint: DocumentType? = nil) async throws -> ClassifyResponse {
        guard let url = URL(string: "\(baseURL)/api/v1/classify") else {
            throw APIError.invalidURL
        }

        let apiFields = fields?.map { field in
            FieldModel(
                key: field.key,
                value: field.value,
                confidence: field.confidence,
                source: field.source.rawValue
            )
        }

        let request = ClassifyRequest(
            ocrText: ocrText,
            fields: apiFields,
            hint: hint?.toBackendString()
        )

        return try await post(url: url, body: request)
    }

    /// Extract fields from a document
    func extract(ocrText: String, documentType: DocumentType) async throws -> ExtractResponse {
        guard let url = URL(string: "\(baseURL)/api/v1/extract") else {
            throw APIError.invalidURL
        }

        let request = ExtractRequest(
            ocrText: ocrText,
            documentType: documentType.toBackendString()
        )

        return try await post(url: url, body: request)
    }

    /// Perform full document analysis (classify + extract)
    func analyze(ocrText: String, hint: DocumentType? = nil) async throws -> AnalyzeResponse {
        guard let url = URL(string: "\(baseURL)/api/v1/analyze") else {
            throw APIError.invalidURL
        }

        let request = AnalyzeRequest(
            ocrText: ocrText,
            hint: hint?.toBackendString()
        )

        return try await post(url: url, body: request)
    }

    /// Upload image for OCR, classification, and extraction
    func uploadImage(_ imageURL: URL) async throws -> UploadResponseWithMetadata {
        guard let url = URL(string: "\(baseURL)/api/v1/upload/image") else {
            throw APIError.invalidURL
        }

        let imageData = try Data(contentsOf: imageURL)
        return try await uploadFile(url: url, fileData: imageData, fileName: "image.jpg", mimeType: "image/jpeg")
    }

    /// Upload audio for transcription, classification, and extraction
    func uploadAudio(_ audioURL: URL, language: String? = nil) async throws -> UploadResponseWithMetadata {
        var urlString = "\(baseURL)/api/v1/upload/audio"
        if let language {
            urlString += "?language=\(language)"
        }

        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        let audioData = try Data(contentsOf: audioURL)
        let fileName = audioURL.lastPathComponent
        let mimeType = "audio/m4a"

        return try await uploadFile(url: url, fileData: audioData, fileName: fileName, mimeType: mimeType)
    }

    // MARK: - Private Helper Methods

    private func post<T: Encodable, R: Decodable>(url: URL, body: T) async throws -> R {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        return try await performRequest(request)
    }

    private func uploadFile<R: Decodable>(
        url: URL,
        fileData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> R {
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add file data
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n".utf8))
        body.append(Data("--\(boundary)--\r\n".utf8))

        request.httpBody = body

        return try await performRequest(request)
    }

    private func performRequest<R: Decodable>(_ request: URLRequest) async throws -> R {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(R.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}

// MARK: - DocumentType Extension

extension DocumentType {
    func toBackendString() -> String {
        switch self {
        case .creditCard: return "creditCard"
        case .insuranceCard: return "insuranceCard"
        case .idCard: return "generic"  // Backend doesn't have idCard
        case .letter: return "letter"
        case .billStatement: return "billStatement"
        case .receipt: return "receipt"
        case .promotional: return "promotional"
        case .generic: return "generic"
        }
    }

    static func fromBackendString(_ string: String) -> DocumentType {
        switch string {
        case "creditCard": return .creditCard
        case "insuranceCard": return .insuranceCard
        case "letter": return .letter
        case "billStatement": return .billStatement
        case "receipt": return .receipt
        case "promotional": return .promotional
        default: return .generic
        }
    }
}

// MARK: - Backend LLM Service Implementation

/// LLMService implementation that uses the backend API
final class BackendLLMService: LLMService {
    private let apiService: BackendAPIService

    init(apiService: BackendAPIService = BackendAPIService()) {
        self.apiService = apiService
    }

    func extract(prompt: String, text: String) async throws -> String {
        // Use the analyze endpoint for general extraction
        let response = try await apiService.analyze(ocrText: text)

        // Convert fields to JSON string format
        let fields = response.fields.map { field in
            "\"\(field.key)\": \"\(field.value)\""
        }.joined(separator: ", ")

        return "{\(fields)}"
    }

    func cleanText(_ rawText: String) async throws -> String {
        // For now, just return the text as-is
        // The backend doesn't have a dedicated text cleaning endpoint
        return rawText
    }
}
