//
//  EmbeddingMigrationService.swift
//  FolioMind
//
//  Service for migrating documents to use new vector embeddings.
//

import Foundation
import SwiftData

/// Service for batch re-embedding documents with real embeddings
@MainActor
final class EmbeddingMigrationService {

    enum MigrationError: LocalizedError {
        case noDocuments
        case embeddingFailed(String)
        case storageFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDocuments:
                return "No documents found to migrate"
            case .embeddingFailed(let message):
                return "Embedding generation failed: \(message)"
            case .storageFailed(let message):
                return "Storage failed: \(message)"
            }
        }
    }

    struct MigrationProgress {
        var totalDocuments: Int
        var processedDocuments: Int
        var failedDocuments: Int
        var currentDocument: String?

        var percentComplete: Double {
            guard totalDocuments > 0 else { return 0 }
            return Double(processedDocuments) / Double(totalDocuments)
        }
    }

    struct MigrationStats {
        let total: Int
        let migrated: Int
        let pending: Int
    }

    private let modelContext: ModelContext
    private let embeddingService: EmbeddingService
    private let vectorStore: LibSQLStore
    private let batchSize: Int

    init(
        modelContext: ModelContext,
        embeddingService: EmbeddingService,
        vectorStore: LibSQLStore,
        batchSize: Int = 10
    ) {
        self.modelContext = modelContext
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        self.batchSize = batchSize
    }

    /// Migrate all documents to new vector embeddings
    /// Returns progress updates via async stream
    func migrateAllDocuments() -> AsyncThrowingStream<MigrationProgress, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    // Fetch all documents
                    let descriptor = FetchDescriptor<Document>(sortBy: [SortDescriptor(\.createdAt)])
                    let documents = try modelContext.fetch(descriptor)

                    guard !documents.isEmpty else {
                        throw MigrationError.noDocuments
                    }

                    let total = documents.count
                    var processed = 0
                    var failed = 0

                    // Process in batches
                    for batch in documents.chunked(into: batchSize) {
                        var batchEmbeddings: [(UUID, [Double])] = []

                        for document in batch {
                            do {
                                // Send progress update
                                continuation.yield(MigrationProgress(
                                    totalDocuments: total,
                                    processedDocuments: processed,
                                    failedDocuments: failed,
                                    currentDocument: document.title
                                ))

                                // Generate embedding
                                let embedding = try await embeddingService.embedDocument(document)
                                batchEmbeddings.append((document.id, embedding.vector))

                                // Update SwiftData with embedding reference
                                document.embedding = embedding

                                processed += 1

                            } catch {
                                print("Failed to embed document \(document.title): \(error)")
                                failed += 1
                            }
                        }

                        // Batch insert into LibSQL
                        if !batchEmbeddings.isEmpty {
                            do {
                                try vectorStore.batchUpsertDocumentEmbeddings(batchEmbeddings)
                            } catch {
                                throw MigrationError.storageFailed(error.localizedDescription)
                            }
                        }

                        // Save SwiftData changes
                        try modelContext.save()

                        // Send batch completion progress
                        continuation.yield(MigrationProgress(
                            totalDocuments: total,
                            processedDocuments: processed,
                            failedDocuments: failed,
                            currentDocument: nil
                        ))
                    }

                    // Complete
                    continuation.finish()

                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Migrate a single document
    func migrateDocument(_ document: Document) async throws {
        // Generate embedding
        let embedding = try await embeddingService.embedDocument(document)

        // Store in LibSQL vector table
        try vectorStore.upsertDocumentEmbedding(
            documentID: document.id,
            vector: embedding.vector,
            modelVersion: "apple-embed-v1"
        )

        // Update SwiftData
        document.embedding = embedding
        try modelContext.save()
    }

    /// Check migration status for a document
    func isMigrated(documentID: UUID) throws -> Bool {
        let vector = try vectorStore.getDocumentEmbedding(documentID: documentID)
        return vector != nil
    }

    /// Get migration statistics
    func getMigrationStats() throws -> MigrationStats {
        let descriptor = FetchDescriptor<Document>()
        let allDocuments = try modelContext.fetch(descriptor)

        var migratedCount = 0
        for document in allDocuments where (try? vectorStore.getDocumentEmbedding(documentID: document.id)) != nil {
            migratedCount += 1
        }

        return MigrationStats(
            total: allDocuments.count,
            migrated: migratedCount,
            pending: allDocuments.count - migratedCount
        )
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
