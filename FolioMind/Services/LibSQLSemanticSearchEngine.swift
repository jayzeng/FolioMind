//
//  LibSQLSemanticSearchEngine.swift
//  FolioMind
//
//  Semantic search engine using LibSQL vector search capabilities.
//

import Foundation
import SwiftData

/// Semantic search engine leveraging LibSQL vector storage
/// This will be upgraded to use vector_top_k() when libsql vector extensions are available
@MainActor
final class LibSQLSemanticSearchEngine: SearchEngine {

    private let modelContext: ModelContext
    private let embeddingService: EmbeddingService
    private let vectorStore: LibSQLStore
    private let keywordWeight: Double
    private let semanticWeight: Double

    init(
        modelContext: ModelContext,
        embeddingService: EmbeddingService,
        vectorStore: LibSQLStore,
        keywordWeight: Double = 0.3,  // Lower keyword weight than before
        semanticWeight: Double = 0.7  // Higher semantic weight with real embeddings
    ) {
        self.modelContext = modelContext
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        self.keywordWeight = keywordWeight
        self.semanticWeight = semanticWeight
    }

    func search(_ query: SearchQuery) async throws -> [SearchResult] {
        let trimmed = query.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty query returns all documents
        guard !trimmed.isEmpty else {
            let descriptor = FetchDescriptor<Document>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            let documents = try modelContext.fetch(descriptor)
            return documents.map { doc in
                SearchResult(document: doc, score: SearchScoreComponents(keyword: 1.0, semantic: 1.0))
            }
        }

        // Generate query embedding for semantic search
        let queryEmbedding = try await embeddingService.embedQuery(trimmed)

        // Try FTS5 pre-filtering for better performance
        let ftsResults = try? vectorStore.ftsSearch(query: trimmed, limit: 100)

        let documents: [Document]
        if let ftsResults = ftsResults, !ftsResults.isEmpty {
            // Use FTS pre-filtered results (faster for large datasets)
            let ftsDocIDs = Set(ftsResults)
            let descriptor = FetchDescriptor<Document>()
            let allDocs = try modelContext.fetch(descriptor)
            documents = allDocs.filter { ftsDocIDs.contains($0.id) }
        } else {
            // Fallback to all documents if FTS not available or no matches
            let descriptor = FetchDescriptor<Document>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
            documents = try modelContext.fetch(descriptor)
        }

        // Score each document
        var scoredResults: [SearchResult] = []

        for document in documents {
            // Get keyword score
            let keywordScore = Self.keywordScore(document: document, query: trimmed)

            // Get semantic score from vector store
            let semanticScore: Double
            if let storedVector = try vectorStore.getDocumentEmbedding(documentID: document.id) {
                semanticScore = cosineSimilarity(queryEmbedding, storedVector)
            } else {
                // Fallback to document's SwiftData embedding if available
                if let embedding = document.embedding {
                    semanticScore = cosineSimilarity(queryEmbedding, embedding.vector)
                } else {
                    semanticScore = 0.0
                }
            }

            let scoreComponents = SearchScoreComponents(
                keyword: keywordScore,
                semantic: semanticScore
            )

            scoredResults.append(SearchResult(
                document: document,
                score: scoreComponents
            ))
        }

        // Sort by weighted score
        return scoredResults.sorted { lhs, rhs in
            weightedScore(lhs.score) > weightedScore(rhs.score)
        }
    }

    private func weightedScore(_ score: SearchScoreComponents) -> Double {
        (keywordWeight * score.keyword) + (semanticWeight * score.semantic)
    }

    private static func keywordScore(document: Document, query: String) -> Double {
        guard !query.isEmpty else { return 1.0 }

        // Build searchable text from document
        let locationText = document.location ?? ""
        let cleanedText = document.cleanedText ?? ""

        // Include location labels and raw values from structured locations
        let locationLabels = document.locations.map { $0.label }.joined(separator: " ")
        let locationRawValues = document.locations.map { $0.rawValue }.joined(separator: " ")

        let haystack = (
            document.title + " " +
            document.ocrText + " " +
            cleanedText + " " +
            locationText + " " +
            locationLabels + " " +
            locationRawValues
        ).lowercased()

        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
        guard !tokens.isEmpty else { return 0 }

        let matches = tokens.filter { haystack.contains($0) }.count
        return Double(matches) / Double(tokens.count)
    }

    private func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        let length = min(lhs.count, rhs.count)
        guard length > 0 else { return 0 }

        var dot: Double = 0
        var magA: Double = 0
        var magB: Double = 0

        for index in 0..<length {
            let va = lhs[index]
            let vb = rhs[index]
            dot += va * vb
            magA += va * va
            magB += vb * vb
        }

        let denominator = sqrt(magA) * sqrt(magB)
        return denominator == 0 ? 0 : dot / denominator
    }
}

// MARK: - Future: libsql vector_top_k Implementation

/// Enhanced version that will use libsql's native vector_top_k() function
/// This requires libsql with vector extension support
@MainActor
final class LibSQLVectorTopKSearchEngine: SearchEngine {

    private let modelContext: ModelContext
    private let embeddingService: EmbeddingService
    private let vectorStore: LibSQLStore

    init(
        modelContext: ModelContext,
        embeddingService: EmbeddingService,
        vectorStore: LibSQLStore
    ) {
        self.modelContext = modelContext
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
    }

    func search(_ query: SearchQuery) async throws -> [SearchResult] {
        let trimmed = query.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Generate query embedding
        let queryEmbedding = try await embeddingService.embedQuery(trimmed.isEmpty ? "all" : trimmed)

        // TODO: When libsql vector_top_k is available, use SQL query like:
        // """
        // SELECT d.id, d.title, vtk.distance
        // FROM vector_top_k('idx_document_embeddings_vector', ?, 20) AS vtk
        // JOIN document_embeddings de ON de.rowid = vtk.id
        // JOIN documents d ON d.id = de.document_id
        // ORDER BY vtk.distance ASC
        // """

        // For now, fallback to fetching all and scoring manually
        let descriptor = FetchDescriptor<Document>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let documents = try modelContext.fetch(descriptor)

        var scoredResults: [SearchResult] = []

        for document in documents {
            if let storedVector = try vectorStore.getDocumentEmbedding(documentID: document.id) {
                let similarity = cosineSimilarity(queryEmbedding, storedVector)

                let scoreComponents = SearchScoreComponents(
                    keyword: 0.0,  // Pure semantic search
                    semantic: similarity
                )

                scoredResults.append(SearchResult(
                    document: document,
                    score: scoreComponents
                ))
            }
        }

        // Sort by semantic similarity
        return scoredResults.sorted { $0.score.semantic > $1.score.semantic }
    }

    private func cosineSimilarity(_ lhs: [Double], _ rhs: [Double]) -> Double {
        let length = min(lhs.count, rhs.count)
        guard length > 0 else { return 0 }

        var dot: Double = 0
        var magA: Double = 0
        var magB: Double = 0

        for index in 0..<length {
            let va = lhs[index]
            let vb = rhs[index]
            dot += va * vb
            magA += va * va
            magB += vb * vb
        }

        let denominator = sqrt(magA) * sqrt(magB)
        return denominator == 0 ? 0 : dot / denominator
    }
}
