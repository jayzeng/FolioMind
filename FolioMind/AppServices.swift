//
//  AppServices.swift
//  FolioMind
//
//  Wires model container, services, and storage utilities for dependency injection.
//

import Foundation
import SwiftData

@MainActor
final class AppServices: ObservableObject {
    let modelContainer: ModelContainer
    let documentStore: DocumentStore
    let analyzer: DocumentAnalyzer
    let searchEngine: SearchEngine
    let embeddingService: EmbeddingService
    let linkingEngine: LinkingEngine

    init() {
        let schema = Schema([
            Document.self,
            Person.self,
            Field.self,
            FaceCluster.self,
            Embedding.self,
            DocumentPersonLink.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        analyzer = VisionDocumentAnalyzer(
            cloudService: nil,
            defaultType: .generic
        )
        embeddingService = SimpleEmbeddingService()
        linkingEngine = BasicLinkingEngine()

        let modelContext = ModelContext(modelContainer)
        searchEngine = HybridSearchEngine(
            modelContext: modelContext,
            embeddingService: embeddingService
        )
        documentStore = DocumentStore(analyzer: analyzer, embeddingService: embeddingService)
    }
}

@MainActor
final class DocumentStore {
    private let analyzer: DocumentAnalyzer
    private let embeddingService: EmbeddingService

    init(analyzer: DocumentAnalyzer, embeddingService: EmbeddingService) {
        self.analyzer = analyzer
        self.embeddingService = embeddingService
    }

    func createStubDocument(in context: ModelContext, titleSuffix: Int) async throws -> Document {
        let now = Date()
        let stubField = Field(key: "note", value: "Sample stub", confidence: 0.5, source: .fused)
        let document = Document(
            title: "Sample Document \(titleSuffix)",
            docType: .generic,
            ocrText: "Stub document created at \(now)",
            fields: [stubField],
            createdAt: now,
            capturedAt: now,
            location: "Local",
            assetURL: nil,
            personLinks: [],
            faceClusterIDs: []
        )
        context.insert(document)
        let embedding = try await embeddingService.embedDocument(document)
        context.insert(embedding)
        document.embedding = embedding
        try context.save()
        return document
    }

    func delete(at offsets: IndexSet, from documents: [Document], in context: ModelContext) {
        for index in offsets {
            context.delete(documents[index])
        }
        try? context.save()
    }

    func ingestDocuments(
        from imageURLs: [URL],
        hints: DocumentHints? = nil,
        title: String? = nil,
        location: String? = nil,
        capturedAt: Date? = Date(),
        in context: ModelContext
    ) async throws -> Document {
        guard !imageURLs.isEmpty else {
            throw NSError(domain: "FolioMind", code: -1, userInfo: [NSLocalizedDescriptionKey: "No images to ingest."])
        }

        var analyses: [DocumentAnalysisResult] = []
        for url in imageURLs {
            let analysis = try await analyzer.analyze(imageURL: url, hints: hints)
            analyses.append(analysis)
        }

        let combinedOCR = analyses.map(\.ocrText).joined(separator: "\n\n")
        let combinedFields = analyses.flatMap(\.fields)
        let combinedFaces = analyses.flatMap(\.faceClusters)
        let faceIDs = combinedFaces.map { $0.id }
        let derivedTitle = title ?? hints?.personName.map { "\($0)'s Document" }
            ?? imageURLs.first!.deletingPathExtension().lastPathComponent
        let docType = hints?.suggestedType ?? analyses.first?.docType ?? .generic

        combinedFields.forEach { context.insert($0) }
        combinedFaces.forEach { context.insert($0) }

        let document = Document(
            title: derivedTitle,
            docType: docType,
            ocrText: combinedOCR,
            fields: combinedFields,
            createdAt: Date(),
            capturedAt: capturedAt,
            location: location,
            assetURL: imageURLs.first?.path,
            personLinks: [],
            faceClusterIDs: faceIDs
        )
        context.insert(document)
        let embedding = try await embeddingService.embedDocument(document)
        context.insert(embedding)
        document.embedding = embedding
        try context.save()
        return document
    }
}
