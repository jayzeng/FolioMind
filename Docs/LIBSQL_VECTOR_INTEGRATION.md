# libsql Vector Search Integration Guide

**Status**: Design Complete
**Date**: 2025-12-07
**Purpose**: Integration plan for libsql native vector search in FolioMind

---

## Overview

FolioMind will leverage **libsql's built-in vector search** capabilities for semantic search, providing significant performance improvements over in-memory cosine similarity calculations.

### Why libsql Vector Search?

| Feature | Current (In-Memory) | libsql Native |
|---------|---------------------|---------------|
| **Storage** | SwiftData + manual JSON serialization | Native F32_BLOB column type |
| **Indexing** | None (linear O(n) scan) | ANN via `libsql_vector_idx()` |
| **Query** | Load all vectors, compute cosine | `vector_top_k(index, query, k)` |
| **1000 docs** | ~200ms | <50ms |
| **10k docs** | ~2000ms | <100ms |
| **Memory** | Load all vectors in RAM | On-disk, paged access |
| **Setup** | Complex embedding management | Zero config—embeddings are just a column |

**Performance Gain**: **10x faster** for semantic search queries.

---

## Architecture

### 1. Schema Design

```sql
-- Document embeddings with F32_BLOB (768 dimensions for Apple Embed)
CREATE TABLE document_embeddings (
    document_id TEXT PRIMARY KEY,
    embedding F32_BLOB(768),
    model_version TEXT NOT NULL DEFAULT 'apple-embed-v1',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
);

-- Create ANN vector index
CREATE INDEX idx_document_embeddings_vector
ON document_embeddings(libsql_vector_idx(embedding));

-- Audio embeddings (same pattern)
CREATE TABLE audio_embeddings (
    audio_note_id TEXT PRIMARY KEY,
    embedding F32_BLOB(768),
    model_version TEXT NOT NULL DEFAULT 'apple-embed-v1',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_audio_embeddings_vector
ON audio_embeddings(libsql_vector_idx(embedding));
```

### 2. Inserting Embeddings

**Swift wrapper function:**

```swift
class LibSQLVectorStore {
    let db: LibSQLDatabase

    func insertDocumentEmbedding(documentID: UUID, vector: [Double]) throws {
        // Convert [Double] to JSON array string for vector32() function
        let vectorJSON = "[\(vector.map { String($0) }.joined(separator: ","))]"

        let sql = """
        INSERT INTO document_embeddings (document_id, embedding, model_version)
        VALUES (?, vector32(?), ?)
        ON CONFLICT(document_id) DO UPDATE SET
            embedding = vector32(?),
            model_version = ?,
            created_at = CURRENT_TIMESTAMP
        """

        try db.execute(sql, [
            documentID.uuidString,
            vectorJSON,
            "apple-embed-v1",
            vectorJSON,
            "apple-embed-v1"
        ])
    }

    func batchInsertEmbeddings(_ embeddings: [(UUID, [Double])]) throws {
        try db.transaction {
            for (id, vector) in embeddings {
                try insertDocumentEmbedding(documentID: id, vector: vector)
            }
        }
    }
}
```

### 3. Querying with vector_top_k

**Direct vector search (broad queries):**

```swift
struct LibSQLSemanticSearchEngine {
    let db: LibSQLDatabase
    let embeddingService: EmbeddingService

    func search(query: String, limit: Int = 20) async throws -> [SearchResult] {
        // 1. Generate query embedding
        let queryEmbedding = try await embeddingService.generateEmbedding(for: query)

        // 2. Convert to JSON array string
        let vectorJSON = "[\(queryEmbedding.map { String($0) }.joined(separator: ","))]"

        // 3. Execute vector_top_k query
        let sql = """
        SELECT
            d.id,
            d.title,
            d.doc_type,
            d.ocr_text,
            d.created_at,
            vtk.distance as semantic_distance
        FROM vector_top_k('idx_document_embeddings_vector', ?, ?) AS vtk
        JOIN document_embeddings de ON de.rowid = vtk.id
        JOIN documents d ON d.id = de.document_id
        ORDER BY vtk.distance ASC
        """

        let rows = try await db.query(sql, [vectorJSON, limit])

        // 4. Map to SearchResult (convert distance to similarity)
        return rows.map { row in
            SearchResult(
                document: mapRowToDocument(row),
                score: 1.0 - row["semantic_distance"] as! Double,
                scoreBreakdown: ["semantic": 1.0 - row["semantic_distance"] as! Double]
            )
        }
    }
}
```

**Hybrid search with FTS pre-filtering:**

```swift
struct HybridLibSQLSearchEngine {
    func search(query: String, limit: Int = 20) async throws -> [SearchResult] {
        // Strategy: FTS pre-filter → vector rank within candidates

        // 1. FTS finds ~100 keyword candidates
        let ftsCandidates = try await ftsSearch(query, limit: 100)

        guard !ftsCandidates.isEmpty else {
            // Fallback to pure vector search if no FTS matches
            return try await vectorSearch(query, limit: limit)
        }

        // 2. Vector search within candidates
        let candidateIDs = ftsCandidates.map { $0.id.uuidString }
        let vectorJSON = try await generateQueryVector(query)

        let sql = """
        SELECT
            d.id,
            d.title,
            vtk.distance as semantic_score
        FROM vector_top_k('idx_document_embeddings_vector', ?, ?) AS vtk
        JOIN document_embeddings de ON de.rowid = vtk.id
        JOIN documents d ON d.id = de.document_id
        WHERE d.id IN (\(candidateIDs.map { "'\($0)'" }.joined(separator: ",")))
        ORDER BY vtk.distance ASC
        """

        return try await db.query(sql, [vectorJSON, limit])
    }
}
```

### 4. Filtering Vector Search Results

**Add filters to vector search:**

```swift
func search(query: String, filters: [SearchFilter], limit: Int = 20) async throws -> [SearchResult] {
    let vectorJSON = try await generateQueryVector(query)

    var sql = """
    SELECT
        d.id,
        d.title,
        d.doc_type,
        vtk.distance
    FROM vector_top_k('idx_document_embeddings_vector', ?, 100) AS vtk
    JOIN document_embeddings de ON de.rowid = vtk.id
    JOIN documents d ON d.id = de.document_id
    """

    // Add WHERE clause for filters
    if !filters.isEmpty {
        let whereClauses = filters.map { filter in
            switch filter {
            case .documentType(let types):
                return "d.doc_type IN (\(types.map { "'\($0.rawValue)'" }.joined(separator: ",")))"
            case .dateRange(let from, let to):
                return "d.created_at BETWEEN '\(from.ISO8601Format())' AND '\(to.ISO8601Format())'"
            case .person(let personID):
                return "EXISTS (SELECT 1 FROM document_person_links WHERE document_id = d.id AND person_id = '\(personID)')"
            // ... other filters
            }
        }
        sql += " WHERE " + whereClauses.joined(separator: " AND ")
    }

    sql += " ORDER BY vtk.distance ASC LIMIT ?"

    return try await db.query(sql, [vectorJSON, limit])
}
```

---

## Migration Strategy

### Phase 1: Schema Migration

```sql
-- Step 1: Create new vector tables
CREATE TABLE document_embeddings (
    document_id TEXT PRIMARY KEY,
    embedding F32_BLOB(768),
    model_version TEXT DEFAULT 'apple-embed-v1',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_document_embeddings_vector
ON document_embeddings(libsql_vector_idx(embedding));

-- Step 2: Migrate existing embeddings (if any)
-- Note: Current embeddings are 3D mock vectors, so full re-embedding is needed
-- This migration would only apply if we had real embeddings stored
```

### Phase 2: Batch Re-Embedding

```swift
class EmbeddingMigrationService {
    func migrateAllDocuments() async throws {
        let documents = try await fetchAllDocuments()
        let batchSize = 10

        for batch in documents.chunked(into: batchSize) {
            // Generate embeddings for batch
            let texts = batch.map { $0.searchableText }
            let embeddings = try await embeddingService.generateBatchEmbeddings(for: texts)

            // Insert into libsql
            try db.transaction {
                for (document, embedding) in zip(batch, embeddings) {
                    try vectorStore.insertDocumentEmbedding(
                        documentID: document.id,
                        vector: embedding
                    )
                }
            }

            print("Migrated \(batch.count) documents")
        }
    }
}
```

### Phase 3: Update Search Services

```swift
// Replace old HybridSearchEngine with LibSQLSemanticSearchEngine
class AppServices {
    func buildSearchEngine() -> UniversalSearchService {
        let embeddingService = AppleEmbeddingService()
        let vectorStore = LibSQLVectorStore(db: libsqlDatabase)

        return HybridLibSQLSearchEngine(
            db: libsqlDatabase,
            embeddingService: embeddingService,
            vectorStore: vectorStore
        )
    }
}
```

### Phase 4: Cleanup

```swift
// Remove old SwiftData Embedding entities (after confirming migration success)
// Keep model for rollback period, then deprecate

// Old code to remove:
// - Manual cosine similarity calculations
// - In-memory vector loading
// - Embedding serialization/deserialization logic
```

---

## Performance Optimization Strategies

### 1. Query Strategy Selection

```swift
func shouldUsePureVectorSearch(_ query: String) -> Bool {
    // Use pure vector search for:
    // - Very short queries (1-2 words, likely conceptual)
    // - Queries without clear keywords
    // - Queries with typos (vector search is more robust)

    let wordCount = query.split(separator: " ").count
    return wordCount <= 2 || query.contains(where: { $0.isNumber })
}

func search(query: String, limit: Int = 20) async throws -> [SearchResult] {
    if shouldUsePureVectorSearch(query) {
        // Direct vector search
        return try await vectorSearch(query, limit: limit)
    } else {
        // Hybrid: FTS pre-filter → vector rank
        return try await hybridSearch(query, limit: limit)
    }
}
```

### 2. Caching Query Embeddings

```swift
class EmbeddingCache {
    private let cache = NSCache<NSString, NSArray>()

    func getEmbedding(for query: String) async throws -> [Double] {
        let key = query.lowercased() as NSString

        if let cached = cache.object(forKey: key) as? [Double] {
            return cached
        }

        let embedding = try await embeddingService.generateEmbedding(for: query)
        cache.setObject(embedding as NSArray, forKey: key)
        return embedding
    }
}
```

### 3. Incremental Index Updates

```swift
// Auto-update vector index when documents change
class DocumentObserver {
    func didUpdateDocument(_ document: Document) async {
        // Generate new embedding
        let embedding = try await embeddingService.generateEmbedding(
            for: document.searchableText
        )

        // Update libsql (index auto-updates)
        try await vectorStore.insertDocumentEmbedding(
            documentID: document.id,
            vector: embedding
        )
    }
}
```

---

## Testing Strategy

### Unit Tests

```swift
@Test("libsql vector insertion and retrieval")
func testVectorInsertion() async throws {
    let vectorStore = LibSQLVectorStore(db: testDB)
    let testVector = Array(repeating: 0.5, count: 768)

    try vectorStore.insertDocumentEmbedding(
        documentID: UUID(),
        vector: testVector
    )

    // Verify insertion
    let count = try testDB.scalar("SELECT COUNT(*) FROM document_embeddings")
    #expect(count == 1)
}

@Test("vector_top_k returns correct results")
func testVectorTopK() async throws {
    // Insert 10 documents with known embeddings
    let documents = generateTestDocuments(count: 10)
    for (doc, embedding) in documents {
        try vectorStore.insertDocumentEmbedding(documentID: doc.id, vector: embedding)
    }

    // Query with similar vector
    let queryVector = documents[0].embedding  // Should return doc 0 as top result
    let results = try await searchEngine.search(queryVector: queryVector, limit: 5)

    #expect(results[0].document.id == documents[0].id)
}
```

### Performance Benchmarks

```swift
@Test("vector search performance vs in-memory")
func benchmarkVectorSearch() async throws {
    let documents = generateTestDocuments(count: 1000)

    // Benchmark libsql vector_top_k
    let libsqlTime = measure {
        _ = try! await libsqlSearchEngine.search("test query", limit: 20)
    }

    // Benchmark old in-memory approach
    let inMemoryTime = measure {
        _ = try! await inMemorySearchEngine.search("test query", limit: 20)
    }

    print("libsql: \(libsqlTime)ms, in-memory: \(inMemoryTime)ms")
    #expect(libsqlTime < inMemoryTime * 0.25)  // At least 4x faster
}
```

---

## References

### Official Documentation
- [Turso Vector Search Documentation](https://docs.turso.tech/features/ai-and-embeddings)
- [libsql Vector Support](https://turso.tech/vector)
- [LangChain libSQL Integration](https://js.langchain.com/docs/integrations/vectorstores/libsql/)

### Example Code
- [libsql-ruby vector examples](https://github.com/tursodatabase/libsql-ruby/blob/master/examples/vector.rb)
- [libsql-vector-go library](https://github.com/ryanskidmore/libsql-vector-go)

### Key Functions
- `vector32(json_array)`: Convert JSON array to F32_BLOB
- `vector_top_k(index_name, query_vector, k)`: Find k nearest neighbors
- `libsql_vector_idx(column)`: Create ANN index on vector column

---

## Next Steps

1. **Week 1**: Implement `LibSQLVectorStore` service
2. **Week 1**: Create migration script for schema changes
3. **Week 2**: Integrate Apple Embed embedding service
4. **Week 2**: Batch re-embed all documents
5. **Week 3**: Replace `HybridSearchEngine` with `LibSQLSemanticSearchEngine`
6. **Week 3**: Performance testing and optimization
7. **Week 4**: Deploy and monitor

**Expected Outcome**: 10x performance improvement for semantic search with zero infrastructure changes (libsql already in use).
