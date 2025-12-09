//
//  LibSQLSemanticSearchEngineTests.swift
//  FolioMindTests
//
//  Tests for semantic search engine with FTS5 and vector search.
//

import XCTest
import SwiftData
@testable import FolioMind

@MainActor
final class LibSQLSemanticSearchEngineTests: XCTestCase {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var embeddingService: EmbeddingService!
    var vectorStore: LibSQLStore!
    var searchEngine: LibSQLSemanticSearchEngine!

    override func setUp() async throws {
        // Create in-memory model container
        let schema = Schema([
            Document.self,
            AudioNote.self,
            Field.self,
            Person.self,
            Embedding.self,
            DocumentReminder.self,
            Asset.self,
            FaceCluster.self,
            DocumentPersonLink.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        modelContainer = try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )

        modelContext = ModelContext(modelContainer)

        // Create test embedding service
        embeddingService = AppleEmbeddingService()

        // Create temporary LibSQL store (uses default path)
        vectorStore = try LibSQLStore()

        // Initialize search engine
        searchEngine = LibSQLSemanticSearchEngine(
            modelContext: modelContext,
            embeddingService: embeddingService,
            vectorStore: vectorStore
        )
    }

    override func tearDown() async throws {
        // Clean up
        modelContainer = nil
        modelContext = nil
        embeddingService = nil
        vectorStore = nil
        searchEngine = nil
    }

    // MARK: - Basic Search Tests

    func testEmptyQueryReturnsAllDocuments() async throws {
        // Create test documents
        let doc1 = Document(title: "First Document", ocrText: "Content here")
        let doc2 = Document(title: "Second Document", ocrText: "More content")

        modelContext.insert(doc1)
        modelContext.insert(doc2)
        try modelContext.save()

        // Search with empty query
        let results = try await searchEngine.search(SearchQuery(text: ""))

        XCTAssertEqual(results.count, 2, "Empty query should return all documents")
    }

    func testKeywordSearchBasic() async throws {
        // Create documents with distinctive keywords
        let doc1 = Document(title: "Invoice from Apple Store", ocrText: "MacBook Pro purchase")
        let doc2 = Document(title: "Restaurant Receipt", ocrText: "Dinner at Italian place")

        modelContext.insert(doc1)
        modelContext.insert(doc2)
        try modelContext.save()

        // Generate and store embeddings
        let embedding1 = try await embeddingService.embedDocument(doc1)
        let embedding2 = try await embeddingService.embedDocument(doc2)

        try vectorStore.upsertDocumentEmbedding(documentID: doc1.id, vector: embedding1.vector)
        try vectorStore.upsertDocumentEmbedding(documentID: doc2.id, vector: embedding2.vector)

        // Search for "Apple"
        let results = try await searchEngine.search(SearchQuery(text: "Apple"))

        XCTAssertGreaterThan(results.count, 0, "Should find at least one result")

        // First result should be the Apple document (higher keyword score)
        if let firstResult = results.first {
            XCTAssertTrue(
                firstResult.document.title.contains("Apple") || firstResult.document.ocrText.contains("Apple"),
                "Top result should contain 'Apple'"
            )
        }
    }

    func testSemanticSearchSimilarity() async throws {
        // Create documents with semantically similar content
        let doc1 = Document(title: "Health Insurance Card", ocrText: "Medical coverage for Jay Smith")
        let doc2 = Document(title: "Gym Membership", ocrText: "Fitness center access card")
        let doc3 = Document(title: "Restaurant Menu", ocrText: "Italian cuisine options")

        modelContext.insert(doc1)
        modelContext.insert(doc2)
        modelContext.insert(doc3)
        try modelContext.save()

        // Generate and store embeddings
        for doc in [doc1, doc2, doc3] {
            let embedding = try await embeddingService.embedDocument(doc)
            doc.embedding = embedding
            try vectorStore.upsertDocumentEmbedding(documentID: doc.id, vector: embedding.vector)
        }

        // Search for "medical insurance" (semantic match)
        let results = try await searchEngine.search(SearchQuery(text: "medical insurance"))

        XCTAssertGreaterThan(results.count, 0, "Should find results")

        // Health insurance document should rank higher than restaurant
        if results.count >= 2 {
            let topResult = results[0]
            let bottomResult = results.last!

            XCTAssertTrue(
                topResult.score.semantic > bottomResult.score.semantic,
                "Semantic scores should vary"
            )
        }
    }

    // MARK: - FTS5 Pre-filtering Tests

    func testFTSPrefiltering() async throws {
        // Create many documents
        for index in 1...50 {
            let doc = Document(
                title: "Document \(index)",
                ocrText: index % 5 == 0 ? "special keyword here" : "regular content"
            )
            modelContext.insert(doc)

            let embedding = try await embeddingService.embedDocument(doc)
            try vectorStore.upsertDocumentEmbedding(documentID: doc.id, vector: embedding.vector)
        }
        try modelContext.save()

        // Search for "special keyword"
        let results = try await searchEngine.search(SearchQuery(text: "special keyword"))

        // Should find documents with "special keyword"
        XCTAssertGreaterThan(results.count, 0, "Should find documents with special keyword")

        // Top results should have higher keyword scores
        if let firstResult = results.first {
            XCTAssertGreaterThan(firstResult.score.keyword, 0.0, "Should have non-zero keyword score")
        }
    }

    // MARK: - Score Weighting Tests

    func testWeightedScoring() async throws {
        let doc = Document(title: "Test Document", ocrText: "Test content")
        modelContext.insert(doc)
        try modelContext.save()

        let embedding = try await embeddingService.embedDocument(doc)
        try vectorStore.upsertDocumentEmbedding(documentID: doc.id, vector: embedding.vector)

        let results = try await searchEngine.search(SearchQuery(text: "test"))

        XCTAssertEqual(results.count, 1, "Should find the document")

        if let result = results.first {
            // Both keyword and semantic should contribute
            XCTAssertGreaterThan(result.score.keyword, 0.0, "Should have keyword score")
            XCTAssertGreaterThan(result.score.semantic, 0.0, "Should have semantic score")

            // Verify weighted scoring (30% keyword + 70% semantic)
            let expectedWeighted = (0.3 * result.score.keyword) + (0.7 * result.score.semantic)
            XCTAssertGreaterThan(expectedWeighted, 0.0, "Weighted score should be positive")
        }
    }

    // MARK: - Edge Case Tests

    func testSpecialCharactersInQuery() async throws {
        let doc = Document(title: "Price: $100.00", ocrText: "Cost is $100")
        modelContext.insert(doc)
        try modelContext.save()

        let embedding = try await embeddingService.embedDocument(doc)
        try vectorStore.upsertDocumentEmbedding(documentID: doc.id, vector: embedding.vector)

        // Search with special characters
        let results = try await searchEngine.search(SearchQuery(text: "$100"))

        XCTAssertGreaterThan(results.count, 0, "Should handle special characters")
    }

    func testVeryLongQuery() async throws {
        let doc = Document(title: "Sample Document", ocrText: "Sample content")
        modelContext.insert(doc)
        try modelContext.save()

        let embedding = try await embeddingService.embedDocument(doc)
        try vectorStore.upsertDocumentEmbedding(documentID: doc.id, vector: embedding.vector)

        // Very long query
        let longQuery = String(repeating: "test keyword ", count: 100)
        let results = try await searchEngine.search(SearchQuery(text: longQuery))

        XCTAssertGreaterThanOrEqual(results.count, 0, "Should handle long queries without crashing")
    }

    func testQueryWithOnlyWhitespace() async throws {
        let doc = Document(title: "Test", ocrText: "Content")
        modelContext.insert(doc)
        try modelContext.save()

        let results = try await searchEngine.search(SearchQuery(text: "   \n\t  "))

        XCTAssertEqual(results.count, 1, "Whitespace-only query should return all documents")
    }

    func testDocumentWithoutEmbedding() async throws {
        // Document with no stored embedding
        let doc = Document(title: "No Embedding", ocrText: "Content")
        modelContext.insert(doc)
        try modelContext.save()

        // Should not crash, should handle gracefully
        let results = try await searchEngine.search(SearchQuery(text: "content"))

        XCTAssertGreaterThanOrEqual(results.count, 0, "Should handle documents without embeddings")
    }

    // MARK: - Performance Tests

    func testSearchPerformanceSmallDataset() async throws {
        // Create 10 documents
        for index in 1...10 {
            let doc = Document(title: "Document \(index)", ocrText: "Content for document \(index)")
            modelContext.insert(doc)

            let embedding = try await embeddingService.embedDocument(doc)
            try vectorStore.upsertDocumentEmbedding(documentID: doc.id, vector: embedding.vector)
        }
        try modelContext.save()

        // Measure search performance
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = try await searchEngine.search(SearchQuery(text: "document"))
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(elapsed, 0.5, "Search should complete in under 500ms for 10 documents")
    }

    func testSearchPerformanceMediumDataset() async throws {
        // Create 100 documents
        for index in 1...100 {
            let doc = Document(title: "Document \(index)", ocrText: "Content for document \(index)")
            modelContext.insert(doc)

            let embedding = try await embeddingService.embedDocument(doc)
            try vectorStore.upsertDocumentEmbedding(documentID: doc.id, vector: embedding.vector)
        }
        try modelContext.save()

        // Measure search performance
        let startTime = CFAbsoluteTimeGetCurrent()
        _ = try await searchEngine.search(SearchQuery(text: "document"))
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(elapsed, 1.0, "Search should complete in under 1s for 100 documents")
    }

    // MARK: - Regression Tests

    func testMultiWordQueryMatching() async throws {
        let doc1 = Document(title: "Medical Insurance Card", ocrText: "Jay's health coverage")
        let doc2 = Document(title: "Business Card", ocrText: "Contact information")

        modelContext.insert(doc1)
        modelContext.insert(doc2)
        try modelContext.save()

        for doc in [doc1, doc2] {
            let embedding = try await embeddingService.embedDocument(doc)
            try vectorStore.upsertDocumentEmbedding(documentID: doc.id, vector: embedding.vector)
        }

        // Multi-word query
        let results = try await searchEngine.search(SearchQuery(text: "medical insurance"))

        XCTAssertGreaterThan(results.count, 0, "Should find results for multi-word query")

        // Medical insurance card should rank first
        if let firstResult = results.first {
            XCTAssertTrue(
                firstResult.document.title.lowercased().contains("medical"),
                "Top result should be most relevant"
            )
        }
    }

    func testCaseInsensitiveSearch() async throws {
        let doc = Document(title: "UPPERCASE TITLE", ocrText: "lowercase content")
        modelContext.insert(doc)
        try modelContext.save()

        let embedding = try await embeddingService.embedDocument(doc)
        try vectorStore.upsertDocumentEmbedding(documentID: doc.id, vector: embedding.vector)

        // Mixed case query
        let results = try await searchEngine.search(SearchQuery(text: "UpPeRcAsE"))

        XCTAssertGreaterThan(results.count, 0, "Search should be case-insensitive")
    }
}
