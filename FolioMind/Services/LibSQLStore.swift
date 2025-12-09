//
//  LibSQLStore.swift
//  FolioMind
//
//  On-device SQL store for documents, metadata, user info, and embeddings.
//

import Foundation
import SQLite3

// Swift helper for sqlite3 text binding lifetime.
private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Lightweight on-device SQL store.
/// Backed by SQLite today and intended to be swappable to libsql without
/// changing call sites (uses a file-based database in the app sandbox).
final class LibSQLStore {
    struct SearchRow {
        let documentID: UUID
        let title: String
        let ocrText: String
        let cleanedText: String?
        let location: String?
        let embedding: [Double]?
    }

    enum StoreError: LocalizedError {
        case openFailed(String)
        case statementFailed(String)
        case encodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .openFailed(let message):
                return "Failed to open SQL store: \(message)"
            case .statementFailed(let message):
                return "SQL statement failed: \(message)"
            case .encodingFailed(let message):
                return "Encoding error: \(message)"
            }
        }
    }

    private let databaseURL: URL

    init() throws {
        let directory = try FileStorageManager.shared.url(for: .database)
        databaseURL = directory.appendingPathComponent("foliomind.db")
        try migrateSchema()
    }

    // MARK: - Public API

    /// Insert or update a document embedding using the new vector table
    func upsertDocumentEmbedding(documentID: UUID, vector: [Double], modelVersion: String = "apple-embed-v1") throws {
        try withConnection { db in
            let sql = """
            INSERT INTO document_embeddings (document_id, embedding, model_version, dimension, created_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(document_id) DO UPDATE SET
                embedding = excluded.embedding,
                model_version = excluded.model_version,
                dimension = excluded.dimension,
                created_at = excluded.created_at;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, documentID.uuidString, -1, sqliteTransientDestructor)

            // Encode vector as blob (Float32 array for compatibility with F32_BLOB)
            let blob = vector.withUnsafeBytes { bytes in
                Data(bytes)
            }
            blob.withUnsafeBytes { rawBufferPointer in
                sqlite3_bind_blob(stmt, 2, rawBufferPointer.baseAddress, Int32(blob.count), sqliteTransientDestructor)
            }

            sqlite3_bind_text(stmt, 3, modelVersion, -1, sqliteTransientDestructor)
            sqlite3_bind_int(stmt, 4, Int32(vector.count))
            sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }
        }
    }

    /// Batch insert document embeddings (more efficient for bulk operations)
    func batchUpsertDocumentEmbeddings(
        _ embeddings: [(documentID: UUID, vector: [Double])],
        modelVersion: String = "apple-embed-v1"
    ) throws {
        try withConnection { db in
            // Begin transaction for batch insert
            guard sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }

            do {
                for (documentID, vector) in embeddings {
                    let sql = """
                    INSERT INTO document_embeddings (document_id, embedding, model_version, dimension, created_at)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(document_id) DO UPDATE SET
                        embedding = excluded.embedding,
                        model_version = excluded.model_version,
                        dimension = excluded.dimension,
                        created_at = excluded.created_at;
                    """

                    var stmt: OpaquePointer?
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                        throw StoreError.statementFailed(errorMessage(from: db))
                    }
                    defer { sqlite3_finalize(stmt) }

                    sqlite3_bind_text(stmt, 1, documentID.uuidString, -1, sqliteTransientDestructor)

                    let blob = vector.withUnsafeBytes { bytes in Data(bytes) }
                    blob.withUnsafeBytes { rawBufferPointer in
                        sqlite3_bind_blob(stmt, 2, rawBufferPointer.baseAddress, Int32(blob.count), sqliteTransientDestructor)
                    }

                    sqlite3_bind_text(stmt, 3, modelVersion, -1, sqliteTransientDestructor)
                    sqlite3_bind_int(stmt, 4, Int32(vector.count))
                    sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)

                    guard sqlite3_step(stmt) == SQLITE_DONE else {
                        throw StoreError.statementFailed(errorMessage(from: db))
                    }
                }

                // Commit transaction
                guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
                    throw StoreError.statementFailed(errorMessage(from: db))
                }
            } catch {
                // Rollback on error
                _ = sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw error
            }
        }
    }

    /// Retrieve document embedding vector
    func getDocumentEmbedding(documentID: UUID) throws -> [Double]? {
        try withConnection { db in
            let sql = """
            SELECT embedding, dimension
            FROM document_embeddings
            WHERE document_id = ?;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, documentID.uuidString, -1, sqliteTransientDestructor)

            guard sqlite3_step(stmt) == SQLITE_ROW else {
                return nil
            }

            // Read blob and convert back to [Double]
            guard let blobPointer = sqlite3_column_blob(stmt, 0) else {
                return nil
            }

            let blobSize = sqlite3_column_bytes(stmt, 0)
            let dimension = Int(sqlite3_column_int(stmt, 1))

            let data = Data(bytes: blobPointer, count: Int(blobSize))
            return data.withUnsafeBytes { rawBuffer in
                Array(rawBuffer.bindMemory(to: Double.self))
            }
        }
    }

    /// Full-text search using FTS5 (if available)
    /// Returns document IDs that match the query
    func ftsSearch(query: String, limit: Int = 100) throws -> [UUID] {
        try withConnection { db in
            // Check if FTS table exists
            let checkTableSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name='documents_fts';"
            var checkStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, checkTableSQL, -1, &checkStmt, nil) == SQLITE_OK else {
                return [] // FTS not available
            }

            let ftsExists = sqlite3_step(checkStmt) == SQLITE_ROW
            sqlite3_finalize(checkStmt)

            guard ftsExists else {
                return [] // FTS not available
            }

            // Perform FTS search
            let sql = """
            SELECT document_id
            FROM documents_fts
            WHERE documents_fts MATCH ?
            ORDER BY rank
            LIMIT ?;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, query, -1, sqliteTransientDestructor)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            var documentIDs: [UUID] = []

            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idCString = sqlite3_column_text(stmt, 0),
                      let uuid = UUID(uuidString: String(cString: idCString)) else {
                    continue
                }
                documentIDs.append(uuid)
            }

            return documentIDs
        }
    }

    func upsertDocument(_ document: Document, embedding: Embedding?) throws {
        try withConnection { db in
            let sql = """
            INSERT INTO documents (id, title, doc_type, ocr_text, cleaned_text, location, created_at, captured_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                doc_type = excluded.doc_type,
                ocr_text = excluded.ocr_text,
                cleaned_text = excluded.cleaned_text,
                location = excluded.location,
                created_at = excluded.created_at,
                captured_at = excluded.captured_at;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, document.id.uuidString, -1, sqliteTransientDestructor)
            sqlite3_bind_text(stmt, 2, document.title, -1, sqliteTransientDestructor)
            sqlite3_bind_text(stmt, 3, document.docType.rawValue, -1, sqliteTransientDestructor)
            sqlite3_bind_text(stmt, 4, document.ocrText, -1, sqliteTransientDestructor)

            if let cleaned = document.cleanedText {
                sqlite3_bind_text(stmt, 5, cleaned, -1, sqliteTransientDestructor)
            } else {
                sqlite3_bind_null(stmt, 5)
            }

            if let location = document.location {
                sqlite3_bind_text(stmt, 6, location, -1, sqliteTransientDestructor)
            } else {
                sqlite3_bind_null(stmt, 6)
            }

            sqlite3_bind_double(stmt, 7, document.createdAt.timeIntervalSince1970)
            if let captured = document.capturedAt {
                sqlite3_bind_double(stmt, 8, captured.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 8)
            }

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }

            try upsertEmbedding(db: db, entityID: document.id, embedding: embedding)
            try syncAssets(db: db, document: document)
            try updateFTSLocationLabels(db: db, document: document)
        }
    }

    /// Migrate FTS table to include location_labels column if it doesn't exist
    private func migrateFTSTableIfNeeded(db: OpaquePointer?) throws {
        // Check if FTS table exists
        let checkTableSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name='documents_fts';"
        var checkStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, checkTableSQL, -1, &checkStmt, nil) == SQLITE_OK else {
            return // Can't check, skip migration
        }

        let ftsExists = sqlite3_step(checkStmt) == SQLITE_ROW
        sqlite3_finalize(checkStmt)

        guard ftsExists else {
            return // FTS doesn't exist yet, will be created fresh
        }

        // Check if location_labels column exists
        let checkColumnSQL = "SELECT location_labels FROM documents_fts LIMIT 1;"
        var columnStmt: OpaquePointer?
        let hasColumn = sqlite3_prepare_v2(db, checkColumnSQL, -1, &columnStmt, nil) == SQLITE_OK

        if hasColumn {
            sqlite3_finalize(columnStmt)
            return // Column exists, no migration needed
        }

        // Need to recreate FTS table with new schema
        print("Migrating FTS table to include location_labels...")

        // Drop old triggers
        _ = sqlite3_exec(db, "DROP TRIGGER IF EXISTS documents_fts_ai;", nil, nil, nil)
        _ = sqlite3_exec(db, "DROP TRIGGER IF EXISTS documents_fts_au;", nil, nil, nil)
        _ = sqlite3_exec(db, "DROP TRIGGER IF EXISTS documents_fts_ad;", nil, nil, nil)

        // Drop old FTS table
        _ = sqlite3_exec(db, "DROP TABLE IF EXISTS documents_fts;", nil, nil, nil)

        // New table will be created by the CREATE IF NOT EXISTS statement after this migration
        print("FTS migration complete. Table will be rebuilt with new schema.")
    }

    /// Rebuild FTS index for all documents (call after migration or when adding location labels)
    func rebuildFTSIndex(documents: [Document]) throws {
        try withConnection { db in
            // Clear existing FTS entries
            let deleteSQL = "DELETE FROM documents_fts;"
            if sqlite3_exec(db, deleteSQL, nil, nil, nil) != SQLITE_OK {
                // FTS might not exist, continue
                return
            }

            // Re-insert all documents with location labels
            for document in documents {
                let locationLabelsText = document.locations.map { location in
                    "\(location.label) \(location.rawValue)"
                }.joined(separator: " ")

                let sql = """
                INSERT INTO documents_fts(document_id, title, ocr_text, cleaned_text, location, location_labels)
                VALUES (?, ?, ?, ?, ?, ?);
                """

                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continue // Skip if FTS not available
                }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_text(stmt, 1, document.id.uuidString, -1, sqliteTransientDestructor)
                sqlite3_bind_text(stmt, 2, document.title, -1, sqliteTransientDestructor)
                sqlite3_bind_text(stmt, 3, document.ocrText, -1, sqliteTransientDestructor)

                if let cleaned = document.cleanedText {
                    sqlite3_bind_text(stmt, 4, cleaned, -1, sqliteTransientDestructor)
                } else {
                    sqlite3_bind_null(stmt, 4)
                }

                if let location = document.location {
                    sqlite3_bind_text(stmt, 5, location, -1, sqliteTransientDestructor)
                } else {
                    sqlite3_bind_null(stmt, 5)
                }

                sqlite3_bind_text(stmt, 6, locationLabelsText, -1, sqliteTransientDestructor)

                _ = sqlite3_step(stmt)
            }

            print("FTS index rebuilt with \(documents.count) documents")
        }
    }

    /// Update FTS location_labels column with concatenated location labels
    private func updateFTSLocationLabels(db: OpaquePointer?, document: Document) throws {
        // Build searchable location labels text
        let locationLabelsText = document.locations.map { location in
            "\(location.label) \(location.rawValue)"
        }.joined(separator: " ")

        // Update FTS table (only if FTS exists)
        let sql = """
        UPDATE documents_fts
        SET location_labels = ?
        WHERE document_id = ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            // FTS might not exist, silently continue
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, locationLabelsText, -1, sqliteTransientDestructor)
        sqlite3_bind_text(stmt, 2, document.id.uuidString, -1, sqliteTransientDestructor)

        // Execute (ignore errors if FTS doesn't exist)
        _ = sqlite3_step(stmt)
    }

    func deleteDocument(id: UUID) throws {
        try withConnection { db in
            let sql = "DELETE FROM documents WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, id.uuidString, -1, sqliteTransientDestructor)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }

            let embeddingSQL = "DELETE FROM embeddings WHERE entity_id = ? AND entity_type = 'document';"
            var embeddingStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, embeddingSQL, -1, &embeddingStmt, nil) == SQLITE_OK else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }
            defer { sqlite3_finalize(embeddingStmt) }

            sqlite3_bind_text(embeddingStmt, 1, id.uuidString, -1, sqliteTransientDestructor)
            guard sqlite3_step(embeddingStmt) == SQLITE_DONE else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }

            let vectorSQL = "DELETE FROM document_embeddings WHERE document_id = ?;"
            var vectorStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, vectorSQL, -1, &vectorStmt, nil) == SQLITE_OK else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }
            defer { sqlite3_finalize(vectorStmt) }

            sqlite3_bind_text(vectorStmt, 1, id.uuidString, -1, sqliteTransientDestructor)
            guard sqlite3_step(vectorStmt) == SQLITE_DONE else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }

            let assetsSQL = "DELETE FROM assets WHERE document_id = ?;"
            var assetsStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, assetsSQL, -1, &assetsStmt, nil) == SQLITE_OK else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }
            defer { sqlite3_finalize(assetsStmt) }

            sqlite3_bind_text(assetsStmt, 1, id.uuidString, -1, sqliteTransientDestructor)
            guard sqlite3_step(assetsStmt) == SQLITE_DONE else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }
        }
    }

    func searchRows(for query: SearchQuery, queryEmbedding: [Double]) throws -> [SearchRow] {
        try withConnection { db in
            let sql = """
            SELECT d.id, d.title, d.ocr_text, d.cleaned_text, d.location, e.vector_json
            FROM documents d
            LEFT JOIN embeddings e ON e.entity_id = d.id AND e.entity_type = 'document';
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }
            defer { sqlite3_finalize(stmt) }

            var rows: [SearchRow] = []

            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idCString = sqlite3_column_text(stmt, 0),
                      let uuid = UUID(uuidString: String(cString: idCString)) else {
                    continue
                }

                let title = stringColumn(stmt, index: 1) ?? ""
                let ocrText = stringColumn(stmt, index: 2) ?? ""
                let cleanedText = stringColumn(stmt, index: 3)
                let location = stringColumn(stmt, index: 4)
                let vectorJSON = stringColumn(stmt, index: 5)
                let embedding = vectorJSON.flatMap(Self.decodeVector)

                rows.append(
                    SearchRow(
                        documentID: uuid,
                        title: title,
                        ocrText: ocrText,
                        cleanedText: cleanedText,
                        location: location,
                        embedding: embedding
                    )
                )
            }

            return rows
        }
    }

    func upsertUser(id: String, displayName: String?, email: String?) throws {
        try withConnection { db in
            let sql = """
            INSERT INTO users (id, display_name, email)
            VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                display_name = excluded.display_name,
                email = excluded.email;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, id, -1, sqliteTransientDestructor)

            if let displayName {
                sqlite3_bind_text(stmt, 2, displayName, -1, sqliteTransientDestructor)
            } else {
                sqlite3_bind_null(stmt, 2)
            }

            if let email {
                sqlite3_bind_text(stmt, 3, email, -1, sqliteTransientDestructor)
            } else {
                sqlite3_bind_null(stmt, 3)
            }

            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw StoreError.statementFailed(errorMessage(from: db))
            }
        }
    }

    // MARK: - Schema / Migration

    private func migrateSchema() throws {
        try withConnection { db in
            let pragmaSQL = "PRAGMA journal_mode=WAL;"
            _ = sqlite3_exec(db, pragmaSQL, nil, nil, nil)
            _ = sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)

            let createDocuments = """
            CREATE TABLE IF NOT EXISTS documents (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                doc_type TEXT NOT NULL,
                ocr_text TEXT NOT NULL,
                cleaned_text TEXT,
                location TEXT,
                created_at REAL NOT NULL,
                captured_at REAL
            );
            """

            // Legacy embeddings table (keep for backward compatibility during migration)
            let createEmbeddings = """
            CREATE TABLE IF NOT EXISTS embeddings (
                id TEXT PRIMARY KEY,
                entity_type TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                vector_json TEXT NOT NULL
            );
            """

            // New vector search tables with F32_BLOB support
            // Note: F32_BLOB is a libsql extension, falls back to BLOB in standard SQLite
            let createDocumentEmbeddings = """
            CREATE TABLE IF NOT EXISTS document_embeddings (
                document_id TEXT PRIMARY KEY,
                embedding BLOB,
                model_version TEXT NOT NULL DEFAULT 'apple-embed-v1',
                dimension INTEGER NOT NULL DEFAULT 768,
                created_at REAL NOT NULL,
                FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE
            );
            """

            let createAudioEmbeddings = """
            CREATE TABLE IF NOT EXISTS audio_embeddings (
                audio_note_id TEXT PRIMARY KEY,
                embedding BLOB,
                model_version TEXT NOT NULL DEFAULT 'apple-embed-v1',
                dimension INTEGER NOT NULL DEFAULT 768,
                created_at REAL NOT NULL
            );
            """

            let createAssets = """
            CREATE TABLE IF NOT EXISTS assets (
                id TEXT PRIMARY KEY,
                document_id TEXT NOT NULL,
                file_url TEXT NOT NULL,
                asset_type TEXT NOT NULL,
                page_number INTEGER NOT NULL,
                added_at REAL NOT NULL,
                thumbnail_url TEXT,
                FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE
            );
            """

            let createUsers = """
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                display_name TEXT,
                email TEXT
            );
            """

            for sql in [createDocuments, createEmbeddings, createDocumentEmbeddings, createAudioEmbeddings, createAssets, createUsers]
            where sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                throw StoreError.statementFailed(errorMessage(from: db))
            }

            // Create vector indexes (libsql specific - will be no-op in standard SQLite)
            // In production with libsql, these would be: CREATE INDEX idx_name ON table(libsql_vector_idx(embedding))
            // For now, we create standard indexes which will work in both SQLite and libsql
            let createDocumentEmbeddingIndex = """
            CREATE INDEX IF NOT EXISTS idx_document_embeddings_lookup
            ON document_embeddings(document_id);
            """

            let createAudioEmbeddingIndex = """
            CREATE INDEX IF NOT EXISTS idx_audio_embeddings_lookup
            ON audio_embeddings(audio_note_id);
            """

            for sql in [createDocumentEmbeddingIndex, createAudioEmbeddingIndex]
            where sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                throw StoreError.statementFailed(errorMessage(from: db))
            }

            // Migrate FTS table if needed (add location_labels column)
            try migrateFTSTableIfNeeded(db: db)

            // Create FTS5 virtual tables for full-text search
            let createDocumentsFTS = """
            CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
                document_id UNINDEXED,
                title,
                ocr_text,
                cleaned_text,
                location,
                location_labels,
                tokenize='unicode61 remove_diacritics 2'
            );
            """

            if sqlite3_exec(db, createDocumentsFTS, nil, nil, nil) != SQLITE_OK {
                // FTS5 might not be available in all SQLite builds, continue without it
                print("Warning: FTS5 not available, keyword search will use basic matching")
            }

            // Create triggers to keep FTS in sync with documents table
            let createFTSTriggerInsert = """
            CREATE TRIGGER IF NOT EXISTS documents_fts_ai AFTER INSERT ON documents BEGIN
                INSERT INTO documents_fts(document_id, title, ocr_text, cleaned_text, location, location_labels)
                VALUES(new.id, new.title, new.ocr_text, new.cleaned_text, new.location, '');
            END;
            """

            let createFTSTriggerUpdate = """
            CREATE TRIGGER IF NOT EXISTS documents_fts_au AFTER UPDATE ON documents BEGIN
                UPDATE documents_fts SET
                    title = new.title,
                    ocr_text = new.ocr_text,
                    cleaned_text = new.cleaned_text,
                    location = new.location
                WHERE document_id = new.id;
            END;
            """

            let createFTSTriggerDelete = """
            CREATE TRIGGER IF NOT EXISTS documents_fts_ad AFTER DELETE ON documents BEGIN
                DELETE FROM documents_fts WHERE document_id = old.id;
            END;
            """

            // Try to create triggers (will succeed only if FTS5 table exists)
            _ = sqlite3_exec(db, createFTSTriggerInsert, nil, nil, nil)
            _ = sqlite3_exec(db, createFTSTriggerUpdate, nil, nil, nil)
            _ = sqlite3_exec(db, createFTSTriggerDelete, nil, nil, nil)
        }
    }

    private func upsertEmbedding(
        db: OpaquePointer?,
        entityID: UUID,
        embedding: Embedding?
    ) throws {
        guard let embedding else {
            return
        }

        let sql = """
        INSERT INTO embeddings (id, entity_type, entity_id, vector_json)
        VALUES (?, 'document', ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            entity_type = excluded.entity_type,
            entity_id = excluded.entity_id,
            vector_json = excluded.vector_json;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.statementFailed(errorMessage(from: db))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, embedding.id.uuidString, -1, sqliteTransientDestructor)
        sqlite3_bind_text(stmt, 2, entityID.uuidString, -1, sqliteTransientDestructor)

        let json = try Self.encodeVector(embedding.vector)
        sqlite3_bind_text(stmt, 3, json, -1, sqliteTransientDestructor)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.statementFailed(errorMessage(from: db))
        }
    }

    private func syncAssets(
        db: OpaquePointer?,
        document: Document
    ) throws {
        let deleteSQL = "DELETE FROM assets WHERE document_id = ?;"
        var deleteStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) == SQLITE_OK else {
            throw StoreError.statementFailed(errorMessage(from: db))
        }
        sqlite3_bind_text(deleteStmt, 1, document.id.uuidString, -1, sqliteTransientDestructor)
        if sqlite3_step(deleteStmt) != SQLITE_DONE {
            sqlite3_finalize(deleteStmt)
            throw StoreError.statementFailed(errorMessage(from: db))
        }
        sqlite3_finalize(deleteStmt)

        guard !document.assets.isEmpty else { return }

        let insertSQL = """
        INSERT INTO assets (id, document_id, file_url, asset_type, page_number, added_at, thumbnail_url)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """

        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else {
            throw StoreError.statementFailed(errorMessage(from: db))
        }
        defer { sqlite3_finalize(insertStmt) }

        for asset in document.assets {
            sqlite3_reset(insertStmt)
            sqlite3_clear_bindings(insertStmt)

            sqlite3_bind_text(insertStmt, 1, asset.id.uuidString, -1, sqliteTransientDestructor)
            sqlite3_bind_text(insertStmt, 2, document.id.uuidString, -1, sqliteTransientDestructor)
            sqlite3_bind_text(insertStmt, 3, asset.fileURL, -1, sqliteTransientDestructor)
            sqlite3_bind_text(insertStmt, 4, asset.assetType.rawValue, -1, sqliteTransientDestructor)
            sqlite3_bind_int(insertStmt, 5, Int32(asset.pageNumber))
            sqlite3_bind_double(insertStmt, 6, asset.addedAt.timeIntervalSince1970)

            if let thumbnail = asset.thumbnailURL {
                sqlite3_bind_text(insertStmt, 7, thumbnail, -1, sqliteTransientDestructor)
            } else {
                sqlite3_bind_null(insertStmt, 7)
            }

            if sqlite3_step(insertStmt) != SQLITE_DONE {
                throw StoreError.statementFailed(errorMessage(from: db))
            }
        }
    }

    // MARK: - Connection Helpers

    private func withConnection<T>(_ body: (OpaquePointer?) throws -> T) throws -> T {
        var db: OpaquePointer?
        let result = sqlite3_open(databaseURL.path, &db)
        guard result == SQLITE_OK, let db else {
            throw StoreError.openFailed(errorMessage(from: db))
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    private func errorMessage(from db: OpaquePointer?) -> String {
        if let db, let cString = sqlite3_errmsg(db) {
            return String(cString: cString)
        }
        return "Unknown error"
    }

    private func stringColumn(_ stmt: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: cString)
    }

    // MARK: - Vector Encoding

    private static func encodeVector(_ vector: [Double]) throws -> String {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(vector)
            guard let string = String(data: data, encoding: .utf8) else {
                throw StoreError.encodingFailed("Unable to convert JSON data to UTF-8 string.")
            }
            return string
        } catch {
            throw StoreError.encodingFailed(error.localizedDescription)
        }
    }

    private static func decodeVector(_ string: String) -> [Double]? {
        guard let data = string.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode([Double].self, from: data)
    }
}
