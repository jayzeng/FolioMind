//
//  AppleEmbeddingService.swift
//  FolioMind
//
//  Embedding service using Apple's on-device NLEmbedding or Foundation Models.
//

import Foundation
import NaturalLanguage

/// Apple's on-device embedding service using NLEmbedding
/// Provides 768-dimensional vectors for semantic search
@MainActor
final class AppleEmbeddingService: EmbeddingService {

    enum EmbeddingError: LocalizedError {
        case embeddingFailed(String)
        case unsupportedLanguage
        case modelNotAvailable

        var errorDescription: String? {
            switch self {
            case .embeddingFailed(let message):
                return "Embedding generation failed: \(message)"
            case .unsupportedLanguage:
                return "Language not supported for embedding"
            case .modelNotAvailable:
                return "Embedding model not available on this device"
            }
        }
    }

    private let language: NLLanguage
    private let dimension: Int

    init(language: NLLanguage = .english, dimension: Int = 768) {
        self.language = language
        self.dimension = dimension
    }

    func embedDocument(_ document: Document) async throws -> Embedding {
        let locationText = document.location ?? ""
        let text = [document.title, document.ocrText, locationText].joined(separator: " ")
        let vector = try await generateEmbedding(for: text)

        return Embedding(
            vector: vector,
            source: .appleEmbed,  // Note: Need to add this to EmbeddingSource enum
            entityType: .document,
            entityID: document.id
        )
    }

    func embedPerson(_ person: Person) async throws -> Embedding {
        let text = ([person.displayName] + person.aliases + person.emails + person.phones).joined(separator: " ")
        let vector = try await generateEmbedding(for: text)

        return Embedding(
            vector: vector,
            source: .appleEmbed,
            entityType: .person,
            entityID: person.id
        )
    }

    func embedQuery(_ text: String) async throws -> [Double] {
        try await generateEmbedding(for: text)
    }

    /// Generate embedding vector for given text
    /// Returns a 768-dimensional vector using Apple's NLEmbedding
    private func generateEmbedding(for text: String) async throws -> [Double] {
        // For iOS 18+, we can use NLEmbedding which provides sentence-level embeddings
        // This is a simplified implementation - in production, you might want to use
        // Apple's Foundation Models if available (iOS 18.2+)

        guard !text.isEmpty else {
            // Return zero vector for empty text
            return Array(repeating: 0.0, count: dimension)
        }

        // Check if NLEmbedding is available for the language
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else {
            // Fallback: use word-level embeddings and average them
            return try await generateWordAverageEmbedding(for: text)
        }

        // Get sentence embedding
        if let vector = embedding.vector(for: text) {
            // NLEmbedding typically returns variable-sized vectors
            // We need to normalize to our target dimension
            return normalizeVector(Array(vector), targetDimension: dimension)
        }

        // Fallback to word-level averaging
        return try await generateWordAverageEmbedding(for: text)
    }

    /// Fallback method: average word embeddings
    private func generateWordAverageEmbedding(for text: String) async throws -> [Double] {
        guard let wordEmbedding = NLEmbedding.wordEmbedding(for: language) else {
            throw EmbeddingError.modelNotAvailable
        }

        // Tokenize text
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(language)

        var wordVectors: [[Double]] = []

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let word = String(text[tokenRange])
            if let vector = wordEmbedding.vector(for: word) {
                wordVectors.append(Array(vector))
            }
            return true
        }

        guard !wordVectors.isEmpty else {
            // Return zero vector if no word embeddings found
            return Array(repeating: 0.0, count: dimension)
        }

        // Average the word vectors
        let averageVector = averageVectors(wordVectors)
        return normalizeVector(averageVector, targetDimension: dimension)
    }

    /// Average multiple vectors element-wise
    private func averageVectors(_ vectors: [[Double]]) -> [Double] {
        guard !vectors.isEmpty else { return [] }
        guard let firstVector = vectors.first else { return [] }

        let dimension = firstVector.count
        var result = Array(repeating: 0.0, count: dimension)

        for vector in vectors {
            for (index, value) in vector.enumerated() where index < dimension {
                result[index] += value
            }
        }

        let count = Double(vectors.count)
        return result.map { $0 / count }
    }

    /// Normalize vector to target dimension
    /// If source is smaller, pad with zeros
    /// If source is larger, truncate or apply dimensionality reduction
    private func normalizeVector(_ vector: [Double], targetDimension: Int) -> [Double] {
        let currentDimension = vector.count

        if currentDimension == targetDimension {
            return vector
        } else if currentDimension < targetDimension {
            // Pad with zeros
            return vector + Array(repeating: 0.0, count: targetDimension - currentDimension)
        } else {
            // Truncate to target dimension
            // In production, you might want to use PCA or other dimensionality reduction
            return Array(vector.prefix(targetDimension))
        }
    }
}
