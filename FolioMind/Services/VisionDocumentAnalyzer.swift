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
#if canImport(VisionKit)
import VisionKit
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct VisionDocumentAnalyzer: DocumentAnalyzer {
    let ocrSource: OCRSource
    let cloudService: CloudOCRService?
    let defaultType: DocumentType
    let intelligentExtractor: IntelligentFieldExtractor?
    let llmService: LLMService?

    init(
        ocrSource: OCRSource? = nil,
        cloudService: CloudOCRService? = nil,
        defaultType: DocumentType = .generic,
        intelligentExtractor: IntelligentFieldExtractor? = nil,
        llmService: LLMService? = nil
    ) {
#if canImport(Vision)
        if let ocrSource {
            self.ocrSource = ocrSource
        } else {
#if canImport(VisionKit)
            if #available(iOS 16.0, *) {
                self.ocrSource = VisionKitOCRSource()
            } else {
                self.ocrSource = VisionOCRSource()
            }
#else
            self.ocrSource = VisionOCRSource()
#endif
        }
#endif
        self.cloudService = cloudService
        self.defaultType = defaultType
        self.intelligentExtractor = intelligentExtractor
        self.llmService = llmService
    }

    func analyze(imageURL: URL, hints: DocumentHints?) async throws -> DocumentAnalysisResult {
        let rawText = try await ocrSource.recognizeText(at: imageURL)
        let cleanedText = await cleanIfPossible(rawText)
        let localText = cleanedText ?? rawText
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
                print("🧠 Running intelligent field extraction for \(preliminaryType.displayName)...")
                let intelligentFields = try await intelligentExtractor.extractFields(
                    from: localText,
                    docType: preliminaryType
                )
                print("✅ Intelligent extraction found \(intelligentFields.count) fields")
                // Merge pattern-based and LLM-based fields
                extractedFields = mergeFields(pattern: patternFields, intelligent: intelligentFields)
                print("📊 Total fields after merge: \(extractedFields.count)")
            } catch {
                // Fall back to pattern-based fields if intelligent extraction fails
                print("⚠️ Intelligent extraction failed: \(error)")
                print("📝 Using pattern-based fields only (\(patternFields.count) fields)")
            }
        } else {
            print("ℹ️ Intelligent extractor not configured, using pattern-based extraction only")
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

    private func cleanIfPossible(_ text: String) async -> String? {
        guard let llmService, !text.isEmpty else { return nil }
        do {
            return try await llmService.cleanText(text)
        } catch {
            print("Text cleaning with LLM failed: \(error.localizedDescription)")
            return nil
        }
    }
}

#if canImport(Vision)
struct VisionOCRSource: OCRSource {
    func recognizeText(at url: URL) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(url: url)
        try handler.perform([request])

        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}

@MainActor
struct VisionFaceDetector {
    func detectFaces(at url: URL) async throws -> [FaceCluster] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(url: url)
        try handler.perform([request])
        let observations = request.results ?? []
        return observations.enumerated().map { index, face in
            let descriptorValues = [
                face.boundingBox.origin.x,
                face.boundingBox.origin.y,
                face.boundingBox.size.width,
                face.boundingBox.size.height
            ]
            let descriptorString = descriptorValues.map { "\($0)" }.joined(separator: ",")
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
        throw NSError(
            domain: "FolioMind.Vision",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: "Vision OCR is unavailable on this platform."
            ]
        )
    }
}

@MainActor
struct VisionFaceDetector {
    func detectFaces(at url: URL) async throws -> [FaceCluster] {
        throw NSError(
            domain: "FolioMind.Vision",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: "Vision face detection is unavailable on this platform."
            ]
        )
    }
}
#endif

#if canImport(VisionKit)
@available(iOS 16.0, *)
struct VisionKitOCRSource: OCRSource {
    func recognizeText(at url: URL) async throws -> String {
        guard let image = UIImage(contentsOfFile: url.path) else {
            throw NSError(domain: "FolioMind.VisionKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not load image for OCR."])
        }

        let analyzer = ImageAnalyzer()
        let configuration = ImageAnalyzer.Configuration([.text])
        let analysis = try await analyzer.analyze(image, configuration: configuration)
        let transcript = analysis.transcript
        if !transcript.isEmpty {
            return transcript
        }
        return ""
    }
}
#endif
