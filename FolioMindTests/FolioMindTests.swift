//
//  FolioMindTests.swift
//  FolioMindTests
//
//  Created by Jay Zeng on 11/23/25.
//

import SwiftData
import Testing
@testable import FolioMind

@MainActor
struct TestDocumentAnalyzer: DocumentAnalyzer {
    func analyze(imageURL: URL, hints: DocumentHints?) async throws -> DocumentAnalysisResult {
        let fields = [
            Field(key: "member_name", value: hints?.personName ?? "Test", confidence: 0.9, source: .vision)
        ]
        return DocumentAnalysisResult(
            ocrText: "OCR for \(imageURL.lastPathComponent)",
            fields: fields,
            docType: hints?.suggestedType ?? .generic,
            faceClusters: []
        )
    }
}

struct FolioMindTests {

    @Test func documentDefaults() {
        let document = Document(title: "Untitled")
        #expect(document.docType == .generic)
        #expect(document.fields.isEmpty)
        #expect(document.faceClusterIDs.isEmpty)
    }

    @Test func analyzerUsesHints() async throws {
        let analyzer = MockDocumentAnalyzer()
        let url = URL(fileURLWithPath: "/tmp/test.png")
        let result = try await analyzer.analyze(
            imageURL: url,
            hints: DocumentHints(suggestedType: .receipt, personName: "Alex")
        )
        #expect(result.docType == .receipt)
        #expect(result.fields.contains { $0.key == "member_name" && $0.value == "Alex" })
    }

    @MainActor
    @Test func documentStoreCreatesStubAndEmbedding() async throws {
        let schema = Schema([
            Document.self,
            Person.self,
            Field.self,
            FaceCluster.self,
            Embedding.self,
            DocumentPersonLink.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let store = DocumentStore(
            analyzer: TestDocumentAnalyzer(),
            embeddingService: SimpleEmbeddingService()
        )
        let created = try await store.createStubDocument(in: context, titleSuffix: 1)
        #expect(created.embedding != nil)
        #expect(!created.fields.isEmpty)
        #expect(!created.faceClusterIDs.isEmpty)

        let documents = try context.fetch(FetchDescriptor<Document>())
        #expect(documents.count == 1)
    }

    @MainActor
    @Test func searchEngineMatchesTitle() async throws {
        let schema = Schema([
            Document.self,
            Person.self,
            Field.self,
            FaceCluster.self,
            Embedding.self,
            DocumentPersonLink.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let doc1 = Document(title: "Alpha Insurance Card", docType: .insuranceCard, ocrText: "Policy 123")
        let doc2 = Document(title: "Beta Receipt", docType: .receipt, ocrText: "Total 42")
        context.insert(doc1)
        context.insert(doc2)

        let search = MockSearchEngine(modelContext: context)
        let results = try await search.search(SearchQuery(text: "Alpha"))
        #expect(!results.isEmpty)
        #expect(results.first?.document.title == "Alpha Insurance Card")
    }

    @MainActor
    @Test func hybridSearchRanksByKeywordAndSemantic() async throws {
        let schema = Schema([
            Document.self,
            Person.self,
            Field.self,
            FaceCluster.self,
            Embedding.self,
            DocumentPersonLink.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let doc1 = Document(title: "Alpha Insurance Card", docType: .insuranceCard, ocrText: "Policy 123")
        let emb1 = Embedding(
            vector: [5.0, 0.0, 1.0],
            source: .mock,
            entityType: .document,
            entityID: doc1.id
        )
        let doc2 = Document(title: "Beta Receipt", docType: .receipt, ocrText: "Total 42")
        let emb2 = Embedding(
            vector: [1.0, 0.0, 0.0],
            source: .mock,
            entityType: .document,
            entityID: doc2.id
        )
        context.insert(doc1)
        context.insert(doc2)
        context.insert(emb1)
        context.insert(emb2)
        doc1.embedding = emb1
        doc2.embedding = emb2

        let search = HybridSearchEngine(
            modelContext: context,
            embeddingService: SimpleEmbeddingService(),
            keywordWeight: 0.5,
            semanticWeight: 0.5
        )
        let results = try await search.search(SearchQuery(text: "Alpha"))
        #expect(results.count == 2)
        #expect(results.first?.document.id == doc1.id)
    }

    @MainActor
    @Test func ingestDocumentsMergesOCRAcrossPages() async throws {
        let schema = Schema([
            Document.self,
            Person.self,
            Field.self,
            FaceCluster.self,
            Embedding.self,
            DocumentPersonLink.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let store = DocumentStore(
            analyzer: TestDocumentAnalyzer(),
            embeddingService: SimpleEmbeddingService()
        )
        let url1 = URL(fileURLWithPath: "/tmp/page1.png")
        let url2 = URL(fileURLWithPath: "/tmp/page2.png")
        let doc = try await store.ingestDocuments(
            from: [url1, url2],
            hints: DocumentHints(suggestedType: .receipt, personName: "Alex"),
            title: "Merged Doc",
            location: nil,
            capturedAt: Date(),
            in: context
        )

        #expect(doc.ocrText.contains("page1"))
        #expect(doc.ocrText.contains("page2"))
    }
}
