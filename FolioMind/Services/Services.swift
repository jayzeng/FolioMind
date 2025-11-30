//
//  Services.swift
//  FolioMind
//
//  Protocols implementations for analysis, embeddings, linking, and search.
//

import Foundation
import SwiftData

struct DocumentHints {
    var suggestedType: DocumentType?
    var personName: String?
}

struct DocumentAnalysisResult {
    var ocrText: String
    var fields: [Field]
    var docType: DocumentType
    var faceClusters: [FaceCluster]
}

struct PersonMatch {
    var person: Person
    var confidence: Double
    var rationale: String
}

struct SearchQuery {
    var text: String
}

struct SearchScoreComponents {
    var keyword: Double
    var semantic: Double
}

struct SearchResult {
    var document: Document
    var score: SearchScoreComponents
}

@MainActor
protocol DocumentAnalyzer {
    func analyze(imageURL: URL, hints: DocumentHints?) async throws -> DocumentAnalysisResult
}

protocol OCRSource {
    func recognizeText(at url: URL) async throws -> String
}

@MainActor
protocol CloudOCRService {
    func enrich(imageURL: URL) async throws -> DocumentAnalysisResult
}

@MainActor
protocol EmbeddingService {
    func embedDocument(_ document: Document) async throws -> Embedding
    func embedPerson(_ person: Person) async throws -> Embedding
    func embedQuery(_ text: String) async throws -> [Double]
}

@MainActor
protocol LinkingEngine {
    func suggestLinks(
        for document: Document,
        people: [Person],
        faceClusters: [FaceCluster]
    ) -> [PersonMatch]
}

@MainActor
protocol SearchEngine {
    func search(_ query: SearchQuery) async throws -> [SearchResult]
}

// MARK: - Default Implementations

@MainActor
struct SimpleEmbeddingService: EmbeddingService {
    private func vector(from text: String) -> [Double] {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let digits = text.filter { $0.isNumber }.count
        let length = min(Double(text.count) / 200.0, 1.0)
        let wordDensity = min(Double(words.count) / 50.0, 1.0)
        let digitRatio = text.isEmpty ? 0.0 : Double(digits) / Double(text.count)
        return [length, wordDensity, digitRatio]
    }

    func embedDocument(_ document: Document) async throws -> Embedding {
        let locationText = document.location ?? ""
        let text = [document.title, document.ocrText, locationText].joined(separator: " ")
        return Embedding(
            vector: vector(from: text),
            source: .mock,
            entityType: .document,
            entityID: document.id
        )
    }

    func embedPerson(_ person: Person) async throws -> Embedding {
        let text = ([person.displayName] + person.aliases + person.emails + person.phones).joined(separator: " ")
        return Embedding(
            vector: vector(from: text),
            source: .mock,
            entityType: .person,
            entityID: person.id
        )
    }

    func embedQuery(_ text: String) async throws -> [Double] {
        vector(from: text)
    }
}

@MainActor
struct BasicLinkingEngine: LinkingEngine {
    func suggestLinks(
        for document: Document,
        people: [Person],
        faceClusters: [FaceCluster]
    ) -> [PersonMatch] {
        // Placeholder: no automatic suggestions until intelligence layer is wired.
        return []
    }
}

// MARK: - Hybrid Search

private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
    let length = min(a.count, b.count)
    guard length > 0 else { return 0 }
    var dot: Double = 0
    var magA: Double = 0
    var magB: Double = 0
    for index in 0..<length {
        let va = a[index]
        let vb = b[index]
        dot += va * vb
        magA += va * va
        magB += vb * vb
    }
    let denominator = sqrt(magA) * sqrt(magB)
    return denominator == 0 ? 0 : dot / denominator
}

@MainActor
final class HybridSearchEngine: SearchEngine {
    private let modelContext: ModelContext
    private let embeddingService: EmbeddingService
    private let keywordWeight: Double
    private let semanticWeight: Double

    init(
        modelContext: ModelContext,
        embeddingService: EmbeddingService,
        keywordWeight: Double = 0.6,
        semanticWeight: Double = 0.4
    ) {
        self.modelContext = modelContext
        self.embeddingService = embeddingService
        self.keywordWeight = keywordWeight
        self.semanticWeight = semanticWeight
    }

    func search(_ query: SearchQuery) async throws -> [SearchResult] {
        let trimmed = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptor = FetchDescriptor<Document>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let documents = try modelContext.fetch(descriptor)
        let queryEmbedding = try await embeddingService.embedQuery(trimmed.isEmpty ? "all" : trimmed)

        let scored = documents.map { document -> SearchResult in
            let keyword = Self.keywordScore(document: document, query: trimmed)
            let semantic = Self.semanticScore(document: document, queryEmbedding: queryEmbedding)
            return SearchResult(document: document, score: SearchScoreComponents(keyword: keyword, semantic: semantic))
        }

        return scored.sorted { lhs, rhs in
            weightedScore(lhs.score) > weightedScore(rhs.score)
        }
    }

    private func weightedScore(_ score: SearchScoreComponents) -> Double {
        (keywordWeight * score.keyword) + (semanticWeight * score.semantic)
    }

    private static func keywordScore(document: Document, query: String) -> Double {
        guard !query.isEmpty else { return 1.0 }
        let locationText = document.location ?? ""
        let haystack = (document.title + " " + document.ocrText + " " + locationText).lowercased()
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
        guard !tokens.isEmpty else { return 0 }
        let matches = tokens.filter { haystack.contains($0) }.count
        return Double(matches) / Double(tokens.count)
    }

    private static func semanticScore(document: Document, queryEmbedding: [Double]) -> Double {
        guard let vector = document.embedding?.vector else { return 0 }
        return cosineSimilarity(vector, queryEmbedding)
    }
}
