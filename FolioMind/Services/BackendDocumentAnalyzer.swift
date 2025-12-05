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
        // Decide whether to use backend OCR or local OCR
        let analysisResult: AnalysisData

        if useBackendOCR {
            // Upload image to backend for complete processing (OCR + classification + extraction)
            print("📤 Uploading image to backend for full analysis...")
            analysisResult = try await analyzeWithBackendOCR(imageURL: imageURL, hints: hints)
        } else {
            // Use local OCR + backend classification/extraction
            print("🔍 Using local OCR + backend analysis...")
            analysisResult = try await analyzeWithLocalOCR(imageURL: imageURL, hints: hints)
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

    private func analyzeWithBackendOCR(imageURL: URL, hints: DocumentHints?) async throws -> AnalysisData {
        let response = try await backendService.uploadImage(imageURL)

        return AnalysisData(
            ocrText: response.ocrText ?? "",
            fields: convertBackendFields(response.fields),
            docType: DocumentType.fromBackendString(response.documentType)
        )
    }

    private func analyzeWithLocalOCR(imageURL: URL, hints: DocumentHints?) async throws -> AnalysisData {
        // Perform local OCR
        let ocrText: String
        if let ocrSource {
            ocrText = try await ocrSource.recognizeText(at: imageURL)
        } else {
            #if canImport(Vision)
            #if canImport(VisionKit)
            if #available(iOS 16.0, *) {
                ocrText = try await VisionKitOCRSource().recognizeText(at: imageURL)
            } else {
                ocrText = try await VisionOCRSource().recognizeText(at: imageURL)
            }
            #else
            ocrText = try await VisionOCRSource().recognizeText(at: imageURL)
            #endif
            #else
            throw NSError(domain: "FolioMind.OCR", code: -1, userInfo: [NSLocalizedDescriptionKey: "OCR is unavailable on this platform."])
            #endif
        }

        print("📝 OCR extracted \(ocrText.count) characters")

        // Send OCR text to backend for analysis
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
            let itemValue: String
            if let stringValue = item as? String {
                itemValue = stringValue
            } else if let numberValue = item as? NSNumber {
                itemValue = numberValue.stringValue
            } else {
                itemValue = "\(item)"
            }

            return Field(
                key: "\(backendField.key)_\(index + 1)",
                value: itemValue,
                confidence: backendField.confidence,
                source: source
            )
        }
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
