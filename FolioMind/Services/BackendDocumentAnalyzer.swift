//
//  BackendDocumentAnalyzer.swift
//  FolioMind
//
//  Document analyzer that uses the backend API for classification and extraction.
//

import Foundation

#if canImport(Vision)
import Vision
#endif

@MainActor
struct BackendDocumentAnalyzer: DocumentAnalyzer {
    let backendService: BackendAPIService
    let ocrSource: OCRSource?
    /// Allow backend OCR as a fallback when on-device OCR is unavailable or empty.
    let useBackendOCR: Bool

    init(
        backendService: BackendAPIService = BackendAPIService(),
        ocrSource: OCRSource? = nil,
        useBackendOCR: Bool = false
    ) {
        self.backendService = backendService
        self.ocrSource = ocrSource
        self.useBackendOCR = useBackendOCR
    }

    func analyze(imageURL: URL, hints: DocumentHints?) async throws -> DocumentAnalysisResult {
        // Prefer on-device OCR (VisionKit) to speed up backend processing
        let analysisResult: AnalysisData

        do {
            let ocrText = try await performLocalOCR(at: imageURL)
            guard !ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LocalOCRError.emptyText
            }
            analysisResult = try await analyzeWithOCRText(ocrText, hints: hints)
        } catch {
            guard useBackendOCR else { throw error }
            print("⚠️ Local OCR unavailable or empty (\(error.localizedDescription)), uploading image for backend OCR...")
            analysisResult = try await analyzeWithBackendOCR(imageURL: imageURL, hints: hints)
        }

        // Detect faces locally
        #if canImport(Vision)
        let faces = try await VisionFaceDetector().detectFaces(at: imageURL)
        #else
        let faces: [FaceCluster] = []
        #endif

        return DocumentAnalysisResult(
            ocrText: analysisResult.ocrText,
            fields: analysisResult.fields,
            docType: analysisResult.docType,
            faceClusters: faces
        )
    }

    // MARK: - Private Analysis Methods

    private struct AnalysisData {
        let ocrText: String
        let fields: [Field]
        let docType: DocumentType
    }

    private enum LocalOCRError: LocalizedError {
        case unavailable
        case emptyText

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "Local OCR is unavailable on this platform."
            case .emptyText:
                return "Local OCR returned empty text."
            }
        }
    }

    private func analyzeWithBackendOCR(imageURL: URL, hints: DocumentHints?) async throws -> AnalysisData {
        let response = try await backendService.uploadImage(imageURL)

        return AnalysisData(
            ocrText: response.ocrText ?? "",
            fields: convertBackendFields(response.fields),
            docType: DocumentType.fromBackendString(response.documentType)
        )
    }

    private func performLocalOCR(at imageURL: URL) async throws -> String {
        if let ocrSource {
            return try await ocrSource.recognizeText(at: imageURL)
        }

        #if canImport(Vision)
        #if canImport(VisionKit)
        if #available(iOS 16.0, *) {
            return try await VisionKitOCRSource().recognizeText(at: imageURL)
        }
        #endif
        return try await VisionOCRSource().recognizeText(at: imageURL)
        #else
        throw LocalOCRError.unavailable
        #endif
    }

    private func analyzeWithOCRText(_ ocrText: String, hints: DocumentHints?) async throws -> AnalysisData {
        print("📝 OCR extracted \(ocrText.count) characters")
        print("🌐 Sending text to backend for classification and extraction...")
        let response = try await backendService.analyze(
            ocrText: ocrText,
            hint: hints?.suggestedType
        )

        print("✅ Backend classified as: \(response.documentType) (confidence: \(String(format: "%.2f", response.confidence)))")
        print("📊 Backend extracted \(response.fields.count) fields")

        return AnalysisData(
            ocrText: ocrText,
            fields: convertBackendFields(response.fields),
            docType: DocumentType.fromBackendString(response.documentType)
        )
    }

    private func convertBackendFields(_ backendFields: [FieldModel]) -> [Field] {
        var expandedFields: [Field] = []

        for backendField in backendFields {
            let fields = expandArrayField(backendField)
            expandedFields.append(contentsOf: fields)
        }

        return expandedFields
    }

    private func expandArrayField(_ backendField: FieldModel) -> [Field] {
        let source = convertFieldSource(backendField.source)

        // Check if value looks like a JSON array
        let trimmedValue = backendField.value.trimmingCharacters(in: .whitespaces)
        guard trimmedValue.hasPrefix("[") && trimmedValue.hasSuffix("]") else {
            // Not an array, return as-is
            return [Field(
                key: backendField.key,
                value: backendField.value,
                confidence: backendField.confidence,
                source: source
            )]
        }

        // Try to parse as JSON array
        let data = Data(trimmedValue.utf8)
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            // Failed to parse, return as-is
            return [Field(
                key: backendField.key,
                value: backendField.value,
                confidence: backendField.confidence,
                source: source
            )]
        }

        // Successfully parsed as array - expand into multiple fields
        print("📋 Expanding array field '\(backendField.key)' with \(array.count) items")

        return array.enumerated().map { index, item in
            let itemValue = formattedArrayItem(item)

            return Field(
                key: "\(backendField.key)_\(index + 1)",
                value: itemValue,
                confidence: backendField.confidence,
                source: source
            )
        }
    }

    private func formattedArrayItem(_ item: Any) -> String {
        if let dictionary = item as? [String: Any] {
            let parts = dictionary
                .sorted { $0.key < $1.key }
                .compactMap { key, value -> String? in
                    let formatted = formatArrayValue(value)
                    guard !formatted.isEmpty else { return nil }
                    return "\(key)=\(formatted)"
                }

            let joined = parts.joined(separator: " | ")
            return joined.isEmpty ? "\(item)" : joined
        }

        if let array = item as? [Any] {
            let values = array.compactMap { formatArrayValue($0) }
            let joined = values.joined(separator: ", ")
            return joined.isEmpty ? "\(item)" : joined
        }

        return formatArrayValue(item)
    }

    private func formatArrayValue(_ value: Any) -> String {
        if value is NSNull { return "" }

        if let string = value as? String {
            return string
        }

        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }

        if let dictionary = value as? [String: Any] {
            let parts = dictionary
                .sorted { $0.key < $1.key }
                .compactMap { key, nested -> String? in
                    let formatted = formatArrayValue(nested)
                    guard !formatted.isEmpty else { return nil }
                    return "\(key)=\(formatted)"
                }
            return parts.joined(separator: " | ")
        }

        if let array = value as? [Any] {
            return array
                .compactMap { formatArrayValue($0) }
                .joined(separator: ", ")
        }

        return "\(value)"
    }

    private func convertFieldSource(_ sourceString: String?) -> FieldSource {
        guard let sourceString else { return .fused }

        switch sourceString.lowercased() {
        case "ocr", "vision":
            return .vision
        case "llm", "baml", "gemini":
            return .gemini
        case "openai":
            return .openai
        default:
            return .fused
        }
    }
}
