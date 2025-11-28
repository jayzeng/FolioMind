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

    init(
        ocrSource: OCRSource? = nil,
        cloudService: CloudOCRService? = nil,
        defaultType: DocumentType = .generic
    ) {
#if canImport(Vision)
        self.ocrSource = ocrSource ?? VisionOCRSource()
#endif
        self.cloudService = cloudService
        self.defaultType = defaultType
    }

    func analyze(imageURL: URL, hints: DocumentHints?) async throws -> DocumentAnalysisResult {
        let localText = try await ocrSource.recognizeText(at:imageURL)
        let faces = try await VisionFaceDetector().detectFaces(at: imageURL)
        let classifiedLocalType = DocumentTypeClassifier.classify(
            ocrText: localText,
            fields: [],
            hinted: hints?.suggestedType,
            defaultType: defaultType
        )

        let localResult = DocumentAnalysisResult(
            ocrText: localText,
            fields: [],
            docType: classifiedLocalType,
            faceClusters: faces
        )

        let cloudResult = try await fetchCloudResult(imageURL: imageURL)
        return merge(local: localResult, cloud: cloudResult, hints: hints)
    }

    private func fetchCloudResult(imageURL: URL) async throws -> DocumentAnalysisResult? {
        guard let cloudService else { return nil }
        return try await cloudService.enrich(imageURL: imageURL)
    }

    private func merge(local: DocumentAnalysisResult, cloud: DocumentAnalysisResult?, hints: DocumentHints?) -> DocumentAnalysisResult {
        guard let cloud = cloud else {
            let filledFields = local.fields.isEmpty ? [
                Field(key: "source", value: "vision_local", confidence: 0.6, source: .vision)
            ] : local.fields
            let classified = DocumentTypeClassifier.classify(
                ocrText: local.ocrText,
                fields: filledFields,
                hinted: hints?.suggestedType,
                defaultType: local.docType
            )
            return DocumentAnalysisResult(
                ocrText: local.ocrText,
                fields: filledFields,
                docType: classified,
                faceClusters: local.faceClusters
            )
        }

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
