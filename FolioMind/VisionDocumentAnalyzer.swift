//
//  VisionDocumentAnalyzer.swift
//  FolioMind
//
//  Local Vision-based analyzer that fuses on-device OCR/face detection with optional cloud enrichment.
//

import Foundation

#if canImport(Vision)
import Vision
#endif

@MainActor
struct VisionDocumentAnalyzer: DocumentAnalyzer {
    let ocrSource: OCRSource
    let cloudService: CloudOCRService?
    let defaultType: DocumentType
    let intelligentExtractor: IntelligentFieldExtractor?

    init(
        ocrSource: OCRSource? = nil,
        cloudService: CloudOCRService? = nil,
        defaultType: DocumentType = .generic,
        intelligentExtractor: IntelligentFieldExtractor? = nil
    ) {
#if canImport(Vision)
        self.ocrSource = ocrSource ?? VisionOCRSource()
#endif
        self.cloudService = cloudService
        self.defaultType = defaultType
        self.intelligentExtractor = intelligentExtractor
    }

    func analyze(imageURL: URL, hints: DocumentHints?) async throws -> DocumentAnalysisResult {
        let localText = try await ocrSource.recognizeText(at:imageURL)
        let faces = try await VisionFaceDetector().detectFaces(at: imageURL)

        // Classify document type first (for intelligent extraction)
        let patternFields = FieldExtractor.extractFields(from: localText)
        let preliminaryType = DocumentTypeClassifier.classify(
            ocrText: localText,
            fields: patternFields,
            hinted: hints?.suggestedType,
            defaultType: defaultType
        )

        // Use intelligent field extraction if available
        var extractedFields = patternFields
        if let intelligentExtractor = intelligentExtractor {
            do {
                let intelligentFields = try await intelligentExtractor.extractFields(
                    from: localText,
                    docType: preliminaryType
                )
                // Merge pattern-based and LLM-based fields
                extractedFields = mergeFields(pattern: patternFields, intelligent: intelligentFields)
            } catch {
                // Fall back to pattern-based fields if intelligent extraction fails
                print("Intelligent extraction failed: \(error), using pattern-based fields")
            }
        }

        let classifiedLocalType = DocumentTypeClassifier.classify(
            ocrText: localText,
            fields: extractedFields,
            hinted: hints?.suggestedType,
            defaultType: preliminaryType
        )

        let localResult = DocumentAnalysisResult(
            ocrText: localText,
            fields: extractedFields,
            docType: classifiedLocalType,
            faceClusters: faces
        )

        let cloudResult = try await fetchCloudResult(imageURL: imageURL)
        return merge(local: localResult, cloud: cloudResult, hints: hints)
    }

    private func mergeFields(pattern: [Field], intelligent: [Field]) -> [Field] {
        var merged: [String: Field] = [:]

        // Add pattern-based fields first
        for field in pattern {
            let key = field.key.lowercased()
            merged[key] = field
        }

        // Override or add intelligent fields (they have higher confidence)
        for field in intelligent {
            let key = field.key.lowercased()
            if let existing = merged[key] {
                // Prefer intelligent field if confidence is higher or values are different
                if field.confidence >= existing.confidence || field.value.count > existing.value.count {
                    merged[key] = field
                }
            } else {
                merged[key] = field
            }
        }

        return Array(merged.values)
    }

    private func fetchCloudResult(imageURL: URL) async throws -> DocumentAnalysisResult? {
        guard let cloudService else { return nil }
        return try await cloudService.enrich(imageURL: imageURL)
    }

    private func merge(local: DocumentAnalysisResult, cloud: DocumentAnalysisResult?, hints: DocumentHints?) -> DocumentAnalysisResult {
        guard let cloud = cloud else {
            // No cloud result - use local extraction
            let classified = DocumentTypeClassifier.classify(
                ocrText: local.ocrText,
                fields: local.fields,
                hinted: hints?.suggestedType,
                defaultType: local.docType
            )
            return DocumentAnalysisResult(
                ocrText: local.ocrText,
                fields: local.fields,
                docType: classified,
                faceClusters: local.faceClusters
            )
        }

        // Merge local and cloud results
        let mergedOCR = cloud.ocrText.isEmpty ? local.ocrText : cloud.ocrText
        let mergedType = cloud.docType == .generic ? local.docType : cloud.docType
        let mergedFields = (local.fields + cloud.fields)
        let mergedFaces = local.faceClusters.isEmpty ? cloud.faceClusters : local.faceClusters
        let classified = DocumentTypeClassifier.classify(
            ocrText: mergedOCR,
            fields: mergedFields,
            hinted: hints?.suggestedType ?? mergedType,
            defaultType: mergedType
        )

        return DocumentAnalysisResult(
            ocrText: mergedOCR,
            fields: mergedFields,
            docType: classified,
            faceClusters: mergedFaces
        )
    }
}

#if canImport(Vision)
struct VisionOCRSource: OCRSource {
    func recognizeText(at url: URL) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = try VNImageRequestHandler(url: url)
        try handler.perform([request])

        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}

struct VisionFaceDetector {
    func detectFaces(at url: URL) async throws -> [FaceCluster] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = try VNImageRequestHandler(url: url)
        try handler.perform([request])
        let observations = request.results ?? []
        return observations.enumerated().map { index, face in
            let descriptorString = "\(face.boundingBox.origin.x),\(face.boundingBox.origin.y),\(face.boundingBox.size.width),\(face.boundingBox.size.height)"
            return FaceCluster(
                id: UUID(),
                descriptor: Data(descriptorString.utf8),
                label: "Face \(index + 1)",
                lastUpdated: Date()
            )
        }
    }
}
#else
struct VisionOCRSource: OCRSource {
    func recognizeText(at url: URL) async throws -> String {
        throw NSError(domain: "FolioMind.Vision", code: -1, userInfo: [NSLocalizedDescriptionKey: "Vision OCR is unavailable on this platform."])
    }
}

struct VisionFaceDetector {
    func detectFaces(at url: URL) async throws -> [FaceCluster] {
        throw NSError(domain: "FolioMind.Vision", code: -1, userInfo: [NSLocalizedDescriptionKey: "Vision face detection is unavailable on this platform."])
    }
}
#endif
