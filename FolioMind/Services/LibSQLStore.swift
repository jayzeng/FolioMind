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
        }
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

            let createEmbeddings = """
            CREATE TABLE IF NOT EXISTS embeddings (
                id TEXT PRIMARY KEY,
                entity_type TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                vector_json TEXT NOT NULL
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

            for sql in [createDocuments, createEmbeddings, createAssets, createUsers]
            where sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
                throw StoreError.statementFailed(errorMessage(from: db))
            }
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
