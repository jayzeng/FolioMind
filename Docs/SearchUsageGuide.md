# Search System Usage Guide

This guide provides practical examples and usage patterns for FolioMind's semantic search system.

## Overview

FolioMind implements a hybrid search system that combines:
- **FTS5 Full-Text Search** for fast keyword matching
- **Vector Semantic Search** using Apple's on-device embeddings (768D)
- **Weighted Scoring** (30% keyword + 70% semantic) for optimal relevance

## Quick Start

### Basic Search

```swift
// Initialize search engine (typically done in AppServices)
let searchEngine = LibSQLSemanticSearchEngine(
    modelContext: modelContext,
    embeddingService: AppleEmbeddingService(),
    vectorStore: libSQLStore
)

// Perform a search
let results = try await searchEngine.search(SearchQuery(text: "medical insurance"))

// Results are sorted by relevance
for result in results {
    print("\(result.document.title): \(result.score)")
}
```

### Empty Query

An empty query returns all documents, sorted by creation date (most recent first):

```swift
let allDocuments = try await searchEngine.search(SearchQuery(text: ""))
```

## Search Query Examples

### 1. Keyword Search

Best for exact matches and specific terms:

```swift
// Find invoices
let results = try await searchEngine.search(SearchQuery(text: "invoice"))

// Find credit card documents
let results = try await searchEngine.search(SearchQuery(text: "credit card"))

// Find documents with specific amount
let results = try await searchEngine.search(SearchQuery(text: "$500"))
```

### 2. Semantic Search

Best for concept-based queries and natural language:

```swift
// Find medical-related documents
let results = try await searchEngine.search(SearchQuery(text: "health coverage"))
// Will match: "Medical Insurance Card", "Health Plan Document", etc.

// Find receipts by category
let results = try await searchEngine.search(SearchQuery(text: "restaurant dinner"))
// Will match: "Italian Restaurant Receipt", "Dining at The Bistro", etc.

// Find documents by description
let results = try await searchEngine.search(SearchQuery(text: "car insurance policy"))
// Will match: "Auto Coverage Policy", "Vehicle Insurance Document", etc.
```

### 3. Multi-word Queries

The system handles multi-word queries intelligently:

```swift
// Finds documents with both "jay" and "insurance"
let results = try await searchEngine.search(SearchQuery(text: "jay's insurance card"))

// Semantic match for location queries
let results = try await searchEngine.search(SearchQuery(text: "near the streetlight"))
```

### 4. Person-based Search

```swift
// Find all documents related to a person
let results = try await searchEngine.search(SearchQuery(text: "jay smith"))

// Find specific document types for a person
let results = try await searchEngine.search(SearchQuery(text: "jay medical card"))
```

### 5. Temporal Queries (Future Enhancement)

Currently, temporal queries like "last week" require manual date filtering. Future versions will support natural language date parsing.

```swift
// Current approach: manual date filtering after search
let results = try await searchEngine.search(SearchQuery(text: "spending"))
let lastWeek = results.filter { result in
    result.document.createdAt > Date().addingTimeInterval(-7 * 24 * 60 * 60)
}
```

## Document Embedding Migration

### Migrating Existing Documents

Before using semantic search, documents need embeddings. Use the migration service:

```swift
let migrationService = EmbeddingMigrationService(
    modelContext: modelContext,
    embeddingService: AppleEmbeddingService(),
    vectorStore: libSQLStore,
    batchSize: 10
)

// Async migration with progress tracking
for try await progress in migrationService.migrateAllDocuments() {
    print("Progress: \(progress.processedDocuments)/\(progress.totalDocuments)")
    print("Current: \(progress.currentDocument ?? "")")
    print("Failed: \(progress.failedDocuments)")
}
```

### UI Migration (Settings)

Users can trigger migration from the app settings:

```swift
NavigationLink("Search Upgrade") {
    EmbeddingMigrationView()
        .environmentObject(services)
}
```

The migration UI shows:
- Total documents count
- Migrated vs pending count
- Real-time progress with current document
- Error reporting

### Checking Migration Status

```swift
// Get migration statistics
let stats = try migrationService.getMigrationStats()
print("Total: \(stats.total)")
print("Migrated: \(stats.migrated)")
print("Pending: \(stats.pending)")

// Check if specific document is migrated
let isMigrated = try migrationService.isMigrated(documentID: document.id)
```

## Embedding New Documents

When creating new documents, generate and store embeddings immediately:

```swift
// Create document
let document = Document(title: "New Invoice", ocrText: "Invoice content...")
modelContext.insert(document)

// Generate embedding
let embedding = try await embeddingService.embedDocument(document)
document.embedding = embedding

// Store in vector table
try libSQLStore.upsertDocumentEmbedding(
    documentID: document.id,
    vector: embedding.vector,
    modelVersion: "apple-embed-v1"
)

// Save
try modelContext.save()
```

## Search Result Interpretation

### Understanding Scores

Each search result includes two score components:

```swift
struct SearchResult {
    var document: Document
    var score: SearchScoreComponents
}

struct SearchScoreComponents {
    var keyword: Double     // 0.0 to 1.0 (exact text matching)
    var semantic: Double    // 0.0 to 1.0 (semantic similarity)
}
```

### Score Interpretation

- **keyword**: Fraction of query terms found in document
  - 1.0 = all query words present
  - 0.5 = half of query words present
  - 0.0 = no query words present

- **semantic**: Cosine similarity of embeddings
  - 1.0 = perfect semantic match
  - 0.7-0.9 = very similar meaning
  - 0.5-0.7 = somewhat related
  - < 0.5 = less related

### Weighted Final Score

Results are sorted by: `(0.3 × keyword) + (0.7 × semantic)`

This favors semantic relevance while still rewarding exact keyword matches.

## Performance Optimization

### FTS5 Pre-filtering

The search engine automatically uses FTS5 to narrow down candidates:

```swift
// Automatically happens in LibSQLSemanticSearchEngine.search()
// 1. FTS5 finds up to 100 keyword-matching documents (fast, <10ms)
// 2. Vector similarity only computed on those 100 (slower, ~50-100ms)
// 3. Results sorted by weighted score

// Without FTS5: O(n) vector operations on all documents
// With FTS5: O(k) vector operations where k ≈ 100
```

### Batch Operations

When embedding multiple documents, use batch operations:

```swift
// Inefficient: individual inserts
for (docID, vector) in embeddings {
    try vectorStore.upsertDocumentEmbedding(documentID: docID, vector: vector)
}

// Efficient: batch insert with transaction
try vectorStore.batchUpsertDocumentEmbeddings(embeddings)
```

### Performance Targets

- FTS5 pre-filtering: < 10ms
- Vector similarity (100 docs): < 100ms
- Total search time: < 150ms (for 1000+ documents)
- Embedding generation: ~50-100ms per document

## Advanced Usage

### Custom Weight Configuration

Adjust keyword vs semantic balance:

```swift
let searchEngine = LibSQLSemanticSearchEngine(
    modelContext: modelContext,
    embeddingService: embeddingService,
    vectorStore: vectorStore,
    keywordWeight: 0.5,   // Higher keyword importance
    semanticWeight: 0.5   // Lower semantic importance
)
```

Use cases:
- Higher keyword weight (0.5+): Technical documents, code, IDs
- Higher semantic weight (0.7+): Natural text, descriptions, general content

### Direct Vector Store Access

For advanced use cases:

```swift
// Get stored embedding
let vector = try libSQLStore.getDocumentEmbedding(documentID: document.id)

// Update embedding
try libSQLStore.upsertDocumentEmbedding(
    documentID: document.id,
    vector: newVector,
    modelVersion: "apple-embed-v2"
)

// FTS search only
let documentIDs = try libSQLStore.ftsSearch(query: "keyword", limit: 50)
```

## Troubleshooting

### No Results Returned

1. **Check if documents have embeddings:**
```swift
let stats = try migrationService.getMigrationStats()
if stats.migrated == 0 {
    // Run migration first
}
```

2. **Verify FTS5 availability:**
```swift
let ftsResults = try? libSQLStore.ftsSearch(query: "test", limit: 10)
if ftsResults == nil {
    // FTS5 not available, search will fall back to all documents
}
```

3. **Check search query:**
```swift
// Empty or whitespace-only queries return all documents
let trimmed = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
if trimmed.isEmpty {
    // Returns all documents
}
```

### Poor Search Quality

1. **Re-generate embeddings** if model version changed:
```swift
// Migration service handles re-embedding
for try await progress in migrationService.migrateAllDocuments() {
    // Track progress
}
```

2. **Adjust weighting** for your content type:
```swift
// More keyword-focused for technical docs
LibSQLSemanticSearchEngine(..., keywordWeight: 0.6, semanticWeight: 0.4)
```

3. **Improve document content**:
- Ensure OCR text is clean and accurate
- Use descriptive titles
- Add location metadata for place-based queries

### Slow Search Performance

1. **Verify FTS5 is working:**
```swift
// FTS5 pre-filtering should reduce candidates to ~100
// If searching all documents, check FTS5 setup
```

2. **Check dataset size:**
```swift
let descriptor = FetchDescriptor<Document>()
let allDocs = try modelContext.fetch(descriptor)
print("Total documents: \(allDocs.count)")

// Performance degrades significantly above 10,000 documents
// without FTS5 pre-filtering
```

3. **Profile embedding generation:**
```swift
let start = CFAbsoluteTimeGetCurrent()
let embedding = try await embeddingService.embedQuery("test")
let elapsed = CFAbsoluteTimeGetCurrent() - start
print("Embedding time: \(elapsed * 1000)ms")

// Should be < 100ms. If slower, check:
// - Device performance
// - Text length (very long queries are slower)
```

## API Reference

### LibSQLSemanticSearchEngine

```swift
@MainActor
final class LibSQLSemanticSearchEngine: SearchEngine {
    init(
        modelContext: ModelContext,
        embeddingService: EmbeddingService,
        vectorStore: LibSQLStore,
        keywordWeight: Double = 0.3,
        semanticWeight: Double = 0.7
    )

    func search(_ query: SearchQuery) async throws -> [SearchResult]
}
```

### EmbeddingMigrationService

```swift
@MainActor
final class EmbeddingMigrationService {
    init(
        modelContext: ModelContext,
        embeddingService: EmbeddingService,
        vectorStore: LibSQLStore,
        batchSize: Int = 10
    )

    struct MigrationStats {
        let total: Int
        let migrated: Int
        let pending: Int
    }

    func migrateAllDocuments() -> AsyncThrowingStream<MigrationProgress, Error>
    func migrateDocument(_ document: Document) async throws
    func isMigrated(documentID: UUID) throws -> Bool
    func getMigrationStats() throws -> MigrationStats
}
```

### AppleEmbeddingService

```swift
final class AppleEmbeddingService: EmbeddingService {
    init(dimension: Int = 768)

    func embedDocument(_ document: Document) async throws -> Embedding
    func embedQuery(_ text: String) async throws -> [Double]
}
```

### LibSQLStore (Vector Operations)

```swift
final class LibSQLStore {
    func upsertDocumentEmbedding(
        documentID: UUID,
        vector: [Double],
        modelVersion: String = "apple-embed-v1"
    ) throws

    func batchUpsertDocumentEmbeddings(
        _ embeddings: [(documentID: UUID, vector: [Double])],
        modelVersion: String = "apple-embed-v1"
    ) throws

    func getDocumentEmbedding(documentID: UUID) throws -> [Double]?

    func ftsSearch(query: String, limit: Int = 100) throws -> [UUID]
}
```

## Examples by Use Case

### 1. Search for Receipts

```swift
// Semantic search
let results = try await searchEngine.search(SearchQuery(text: "restaurant receipt"))

// With price filter (post-search)
let expensiveReceipts = results.filter { result in
    // Extract amount from OCR text or fields
    // Filter by amount threshold
}
```

### 2. Find Insurance Documents

```swift
// General insurance
let results = try await searchEngine.search(SearchQuery(text: "insurance"))

// Specific person's insurance
let results = try await searchEngine.search(SearchQuery(text: "jay's medical insurance"))

// Semantic match
let results = try await searchEngine.search(SearchQuery(text: "health coverage card"))
```

### 3. Search by Location

```swift
// Visual location
let results = try await searchEngine.search(SearchQuery(text: "near the streetlight"))

// Business location
let results = try await searchEngine.search(SearchQuery(text: "downtown restaurant"))
```

### 4. Find Documents by Date (Manual Filtering)

```swift
let results = try await searchEngine.search(SearchQuery(text: "spending receipt"))

// Filter by last week
let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
let recentResults = results.filter { $0.document.createdAt > lastWeek }

// Group by month
let byMonth = Dictionary(grouping: results) { result in
    Calendar.current.dateComponents([.year, .month], from: result.document.createdAt)
}
```

### 5. Aggregate Search Results

```swift
// Find all expenses
let results = try await searchEngine.search(SearchQuery(text: "receipt invoice"))

// Calculate total (requires field extraction)
let total = results.compactMap { result in
    // Extract amount from result.document.fields
    result.document.fields.first { $0.key == "amount" }?.value
}.compactMap { Double($0) }.reduce(0, +)

print("Total spending: $\(total)")
```

## Next Steps

For planned enhancements (not yet implemented), see:
- `Docs/SearchArchitecture.md` - Full technical specification
- `Docs/ProductSpec.md` - Product roadmap
- `AGENTS.md` - Architecture overview

Upcoming features:
- Natural language query understanding (temporal, aggregations)
- Quick actions / command palette
- Audio content search
- Search analytics and adaptive learning
