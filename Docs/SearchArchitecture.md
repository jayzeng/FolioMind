# FolioMind Search Architecture Specification

**Version**: 2.0 (Planned)
**Status**: Design Phase
**Last Updated**: 2025-12-07

---

## Executive Summary

This document specifies the comprehensive search architecture for FolioMind, transforming the current basic hybrid search (keyword + mock embeddings) into an **intelligent, multi-modal search platform** that:

1. **Understands natural language queries**: "how much did I spend last week"
2. **Searches across all content types**: documents, audio, images, fields
3. **Performs computational queries**: aggregations, analytics, trends
4. **Provides quick actions**: universal command palette (`⌘K` or `>` prefix)

---

## Current State Analysis

### ✅ Strengths
- Hybrid search foundation (60% keyword + 40% semantic)
- Rich data model (Documents, Fields, Audio, People, Embeddings)
- Dual storage (SwiftData + LibSQL)
- OCR + LLM pipeline (Vision + intelligent extraction)
- Local-first architecture with optional cloud enrichment

### ❌ Critical Gaps

| Gap | Impact | Example Failure |
|-----|--------|----------------|
| **Mock embeddings** (3D vectors) | Poor semantic quality | "insurance" won't find semantically similar docs |
| **No query understanding** | Can't parse intent | "last week" treated as literal keywords |
| **No full-text indexing** | O(n) linear scan | Slow with 1000+ documents |
| **No audio search** | Audio invisible | Can't find "meeting notes from Monday" |
| **No aggregation** | Can't compute | "total spending" requires manual calculation |
| **No fuzzy matching** | Typos fail | "insurence" returns nothing |
| **No command system** | Search-only UI | Can't "create reminder" from search bar |

---

## Target Capabilities

### 1. Natural Language Query Examples

#### Query: "how much did I spend last week"
**Required Components:**
- ✨ Intent: `AGGREGATION_QUERY`
- 📅 Temporal: "last week" → `[2025-11-30, 2025-12-06]`
- 💰 Field: "spend" → amount fields
- 📄 Types: receipts, bills, statements
- 🧮 Operation: `SUM(amount) WHERE date IN range`

**Response:**
```
💵 You spent $342.67 last week
📊 5 transactions: 3 receipts • 2 bills
[Show breakdown →]
```

#### Query: "the streetlight"
**Required Components:**
- 🖼️ Visual/semantic search (real embeddings)
- 🔍 OCR text search ("streetlight")
- 🏷️ Tag/label search
- 🌐 Location context

**Response:**
```
📸 Found 2 matches
1. Photo from Main St (89% match)
2. Receipt - City Utilities "streetlight repair" (67% match)
```

#### Query: "jay's medical insurance card"
**Required Components:**
- 👤 Person: "jay" → Person(id)
- 🏥 Type: "insurance card" → `insuranceCard`
- 🔗 Relationship: person-document linking
- 📋 Field: "medical" in insurance type

**Response:**
```
🏥 Jay's Medical Insurance
Blue Cross PPO (#123456789)
Last updated: 2024-03-15
[View details →]
```

### 2. Universal Search Scope

| Content Type | Current | Target |
|-------------|---------|--------|
| **Document OCR** | ✅ Keyword | ✅ Keyword + Semantic + FTS |
| **Extracted Fields** | ❌ Not searchable | ✅ Field-specific (`amount:>100`) |
| **Audio Transcripts** | ❌ Not indexed | ✅ Full transcript search |
| **Audio Summaries** | ❌ Not indexed | ✅ Semantic summary search |
| **People Names** | ⚠️ Basic filter | ✅ Alias + fuzzy + relationship |
| **Locations** | ⚠️ Basic filter | ✅ Geocoded + fuzzy |
| **Document Types** | ⚠️ Exact match | ✅ Synonym ("receipt" = "bill") |
| **Dates/Times** | ❌ Not queryable | ✅ Natural language ("yesterday") |
| **Amounts** | ❌ Not queryable | ✅ Ranges ("over $100") |

### 3. Quick Actions / Command Palette

**Trigger**: `>` prefix or `⌘K` shortcut

```
CREATE:
  > create reminder
  > scan document
  > add person
  > new audio note

MODIFY:
  > edit document
  > change type
  > add tag
  > link to person

DELETE:
  > delete document
  > archive old bills

NAVIGATE:
  > show all receipts
  > go to settings
  > find expired cards

EXPORT:
  > export pdf
  > share selected
  > backup to cloud
```

**Benefits:**
- Keyboard-first power users
- Contextual suggestions
- Reduces UI chrome
- Discoverable features

---

## Architecture Components

### A. Query Understanding Layer 🧠

#### 1. Query Analyzer

```swift
protocol QueryAnalyzer {
    func analyze(_ query: String) -> QueryIntent
}

struct QueryIntent {
    var type: IntentType              // search, command, aggregation
    var entities: [ExtractedEntity]   // people, dates, amounts, types
    var filters: [SearchFilter]       // derived constraints
    var action: QuickAction?          // if command intent
    var temporalContext: DateRange?   // for time-based queries
}

enum IntentType {
    case simpleSearch                 // keyword lookup
    case semanticSearch               // "find similar to..."
    case aggregationQuery             // "how much...", "how many..."
    case navigationCommand            // "show...", "go to..."
    case actionCommand                // "create...", "delete..."
    case questionAnswering            // "when did I...", "what was..."
}
```

**Implementation Phases:**
- **Phase 1**: Pattern-based (regex + keyword matching)
  - "how much" + amount words → AGGREGATION
  - "create|add|new" → COMMAND
  - Person names + doc types → FILTERED_SEARCH

- **Phase 2**: On-device NLP (`NaturalLanguage` framework)
  - `NLTokenizer` for entity boundaries
  - `NLTagger` for named entity recognition
  - Custom CoreML intent classifier

- **Phase 3**: Optional LLM-powered (Apple Intelligence or OpenAI)
  - Complex query rewriting
  - Structured filter extraction
  - Ambiguity clarification

#### 2. Entity Extractor

```swift
struct ExtractedEntity {
    var type: EntityType
    var value: String
    var normalizedValue: Any?         // parsed representation
    var confidence: Double
    var range: Range<String.Index>
}

enum EntityType {
    case person(personID: UUID?)
    case documentType(DocumentType)
    case temporalExpression(DateRange)
    case amount(Decimal)
    case location(String, coordinate: CLLocationCoordinate2D?)
    case field(key: String)
}
```

**Recognition Pipeline:**

1. **Temporal**: "last week", "yesterday", "march", "2024"
   - `DataDetector` for absolute dates
   - Custom parser for relative expressions

2. **People**: "jay", "dr. smith", "john's"
   - Match against `Person` entities (name, aliases)
   - Fuzzy matching (Levenshtein distance ≤2)
   - Possessive handling ("jay's" → filter by person)

3. **Document Types**: "receipt", "insurance", "id card"
   - Synonym dictionary: "bill" → "receipt"
   - Fuzzy matching: "insurence" → "insurance"

4. **Amounts**: "$50", "100 dollars", "over 500"
   - Currency regex patterns
   - Range operators: "over", "under", "between"

5. **Locations**: "main street", "cvs", "home"
   - Match against document.location
   - Optional geocoding for addresses

#### 3. Query Rewriter

```swift
struct SearchQuery {
    var keywords: [String]              // tokenized, normalized
    var filters: [SearchFilter]         // structured constraints
    var embedding: [Double]?            // for semantic search
    var requiredFields: [String: Any]   // must-match fields
    var aggregation: AggregationSpec?   // for computational queries
}

enum SearchFilter {
    case documentType([DocumentType])
    case person(UUID)
    case dateRange(from: Date, to: Date)
    case amountRange(min: Decimal?, max: Decimal?)
    case location(String)
    case hasField(key: String)
    case processingStatus(ProcessingStatus)
}
```

---

### B. Multi-Modal Search Engine 🔍

#### 1. Full-Text Search (SQLite FTS5)

**Schema:**
```sql
CREATE VIRTUAL TABLE documents_fts USING fts5(
    document_id UNINDEXED,
    title,
    ocr_text,
    cleaned_text,
    field_values,        -- concatenated "key: value"
    person_names,        -- denormalized for search
    location,
    tokenize='unicode61 remove_diacritics 2'
);

CREATE VIRTUAL TABLE audio_fts USING fts5(
    audio_note_id UNINDEXED,
    title,
    transcript,
    summary,
    tokenize='unicode61 remove_diacritics 2'
);

-- Auto-sync triggers
CREATE TRIGGER documents_ai AFTER INSERT ON documents BEGIN
    INSERT INTO documents_fts(document_id, title, ocr_text, ...)
    VALUES(new.id, new.title, new.ocr_text, ...);
END;
```

**Features:**
- **Fuzzy matching**: Trigram similarity in post-filter
- **Phrase queries**: `"insurance card"` (exact)
- **Boolean operators**: `receipt AND (cvs OR walgreens)`
- **Prefix matching**: `insur*` → insurance, insured
- **BM25 ranking**: Built-in relevance scoring

#### 2. Semantic Search (Real Embeddings with libsql Vector Search)

**Current**: Mock 3D vectors (length, density, digit ratio) with in-memory cosine similarity
**Target**: 768-1536D production embeddings with libsql native vector indexing

**Provider Options:**

| Provider | Dimensions | On-Device | Quality | Cost |
|----------|-----------|-----------|---------|------|
| **Apple Embed (iOS 18.2+)** | 768 | ✅ | High | Free |
| **OpenAI text-embedding-3-small** | 1536 | ❌ | Very High | ~$0.02/1M tokens |
| **Gemini text-embedding-004** | 768 | ❌ | Very High | Free (limits) |
| **Sentence Transformers (CoreML)** | 384-768 | ✅ | Medium | Free |

**Recommendation:**
- **Primary**: Apple Embed (768D, on-device, privacy-first, free)
- **Fallback**: Gemini (768D, cloud, opt-in for higher quality)
- **Dev/Testing**: Sentence Transformers (CoreML for offline dev)

**libsql Native Vector Search Integration:**

libsql (via Turso) provides **built-in vector search** with zero setup—embeddings are just a column type with automatic indexing. This eliminates the need for in-memory vector operations and provides significant performance benefits.

**Schema Design:**
```sql
-- Document embeddings table with F32_BLOB vector column
CREATE TABLE document_embeddings (
    document_id TEXT PRIMARY KEY,
    embedding F32_BLOB(768),  -- 768-dimensional float32 vector (Apple Embed)
    model_version TEXT NOT NULL DEFAULT 'apple-embed-v1',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create vector index for ANN (Approximate Nearest Neighbors)
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

**Inserting Embeddings:**
```swift
// Swift wrapper for libsql vector insertion
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
```

**Querying with vector_top_k:**
```sql
-- Find top-20 semantically similar documents
SELECT
    d.id,
    d.title,
    d.doc_type,
    d.created_at,
    vtk.distance  -- similarity score from vector search
FROM vector_top_k('idx_document_embeddings_vector', ?, 20) AS vtk
JOIN document_embeddings de ON de.rowid = vtk.id
JOIN documents d ON d.id = de.document_id
ORDER BY vtk.distance ASC;
```

**Swift Implementation:**
```swift
protocol EmbeddingService {
    func generateEmbedding(for text: String) async throws -> [Double]
    func generateBatchEmbeddings(for texts: [String]) async throws -> [[Double]]
}

class HybridEmbeddingService: EmbeddingService {
    let primaryService: EmbeddingService      // Apple Embed
    let fallbackService: EmbeddingService?    // Gemini (opt-in)

    func generateEmbedding(for text: String) async throws -> [Double] {
        do {
            return try await primaryService.generateEmbedding(for: text)
        } catch {
            guard let fallback = fallbackService else { throw error }
            return try await fallback.generateEmbedding(for: text)
        }
    }
}

// Semantic search engine using libsql vector_top_k
struct LibSQLSemanticSearchEngine {
    let db: LibSQLDatabase
    let embeddingService: EmbeddingService

    func search(query: String, limit: Int = 20, filters: [SearchFilter] = []) async throws -> [SearchResult] {
        // 1. Generate query embedding
        let queryEmbedding = try await embeddingService.generateEmbedding(for: query)

        // 2. Convert embedding to JSON array string
        let vectorJSON = "[\(queryEmbedding.map { String($0) }.joined(separator: ","))]"

        // 3. Build SQL with optional filters
        var sql = """
        SELECT
            d.id,
            d.title,
            d.doc_type,
            d.ocr_text,
            d.created_at,
            vtk.distance as semantic_score
        FROM vector_top_k('idx_document_embeddings_vector', ?, ?) AS vtk
        JOIN document_embeddings de ON de.rowid = vtk.id
        JOIN documents d ON d.id = de.document_id
        """

        // Add WHERE clauses for filters
        if !filters.isEmpty {
            sql += " WHERE " + buildFilterSQL(filters)
        }

        sql += " ORDER BY vtk.distance ASC"

        // 4. Execute query
        let rows = try await db.query(sql, [vectorJSON, limit] + filterParams(filters))

        // 5. Map to SearchResult
        return rows.map { row in
            SearchResult(
                document: mapRowToDocument(row),
                score: 1.0 - row["semantic_score"] as! Double,  // distance → similarity
                scoreBreakdown: ["semantic": 1.0 - row["semantic_score"] as! Double]
            )
        }
    }
}
```

**Hybrid Search with FTS Pre-filtering:**
```swift
// Combine FTS and vector search for best performance
struct HybridLibSQLSearchEngine {
    func search(query: String, limit: Int = 20) async throws -> [SearchResult] {
        // Strategy 1: For broad queries, use vector search directly
        if shouldUseVectorOnly(query) {
            return try await vectorSearch(query, limit: limit)
        }

        // Strategy 2: For specific queries, FTS pre-filter → vector rank
        // 1. FTS finds ~100 candidates
        let candidates = try await ftsSearch(query, limit: 100)
        let candidateIDs = candidates.map { $0.id.uuidString }

        // 2. Vector search within candidates only
        let vectorJSON = try await generateQueryVector(query)

        let sql = """
        SELECT
            d.id,
            d.title,
            vtk.distance as semantic_score
        FROM vector_top_k('idx_document_embeddings_vector', ?, 20) AS vtk
        JOIN document_embeddings de ON de.rowid = vtk.id
        JOIN documents d ON d.id = de.document_id
        WHERE d.id IN (\(candidateIDs.map { "'\($0)'" }.joined(separator: ",")))
        ORDER BY vtk.distance ASC
        """

        return try await db.query(sql, [vectorJSON])
    }
}
```

**Performance Benefits:**

| Approach | Current (In-Memory) | Target (libsql vector_top_k) |
|----------|---------------------|------------------------------|
| **Vector storage** | SwiftData + manual serialization | Native F32_BLOB column |
| **Indexing** | None (linear scan) | ANN index (libsql_vector_idx) |
| **Search complexity** | O(n) cosine for all docs | O(log n) with ANN |
| **1000 docs latency** | ~200ms | <50ms |
| **10k docs latency** | ~2000ms | <100ms |
| **Memory usage** | Load all vectors | On-disk, paged access |

**Migration Strategy:**

1. **Phase 1**: Add vector columns to existing embeddings table
2. **Phase 2**: Batch re-embed documents with real embeddings (Apple Embed)
3. **Phase 3**: Create vector indexes (instant with libsql)
4. **Phase 4**: Replace HybridSearchEngine with LibSQLSemanticSearchEngine
5. **Phase 5**: Optimize query strategies (FTS pre-filter vs direct vector search)

#### 3. Structured Field Search

**Examples:**
- `amount:>100` → amount fields > $100
- `expiry:<2024-12-31` → expired cards
- `type:insurance AND person:jay`

**Implementation:**
```swift
enum FieldFilter {
    case equals(key: String, value: String)
    case contains(key: String, substring: String)
    case numericRange(key: String, min: Decimal?, max: Decimal?)
    case dateRange(key: String, from: Date?, to: Date?)
}

struct FieldSearchEngine {
    func search(fieldFilters: [FieldFilter]) -> [Document] {
        // SQL with field joins
        """
        SELECT DISTINCT d.*
        FROM documents d
        JOIN fields f ON f.document_id = d.id
        WHERE f.key = ? AND f.value LIKE ?
        """
    }
}
```

**Indexes:**
```sql
CREATE INDEX idx_fields_search ON fields(key, value);
CREATE INDEX idx_fields_numeric ON fields(key, CAST(value AS REAL))
    WHERE value GLOB '[0-9]*';
```

#### 4. Audio Content Search

**Integration:**
1. Index `AudioNote.transcript` in FTS
2. Index `AudioNote.summary` in FTS
3. Metadata: title, date, duration
4. Hybrid ranking: boost transcript over summary

**Schema Updates:**
```swift
@Model
class AudioNote {
    // ... existing ...

    var tags: [String] = []
    var embedding: Embedding?
    var searchableText: String {
        [title, transcript, summary]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
```

---

### C. Aggregation & Computation Engine 🧮

```swift
enum AggregationType {
    case sum(field: String)
    case count
    case average(field: String)
    case min(field: String)
    case max(field: String)
    case groupBy(field: String, aggregation: AggregationType)
}

struct AggregationSpec {
    var type: AggregationType
    var filters: [SearchFilter]
    var groupBy: String?
}

struct AggregationResult {
    var value: Any                    // aggregated value
    var count: Int                    // number of items
    var breakdown: [String: Any]?     // for group-by
    var sourceDocuments: [UUID]       // provenance
}
```

**Example: "how much did I spend last week"**
```swift
let spec = AggregationSpec(
    type: .sum(field: "amount"),
    filters: [
        .documentType([.receipt, .billStatement]),
        .dateRange(from: lastWeekStart, to: lastWeekEnd),
        .hasField(key: "amount")
    ]
)

let result = try await aggregationEngine.execute(spec)
// result.value = 342.67
// result.count = 5
```

**SQL Implementation:**
```sql
SELECT
    SUM(CAST(f.value AS REAL)) as total,
    COUNT(*) as count,
    d.doc_type,
    COUNT(*) as type_count
FROM documents d
JOIN fields f ON f.document_id = d.id
WHERE d.doc_type IN ('receipt', 'billStatement')
  AND d.created_at BETWEEN ? AND ?
  AND f.key = 'amount'
GROUP BY d.doc_type;
```

---

### D. Quick Action / Command System ⚡

#### Command Registry

```swift
protocol QuickAction {
    var id: String { get }
    var title: String { get }
    var description: String { get }
    var keywords: [String] { get }
    var icon: String { get }          // SF Symbol
    var category: ActionCategory { get }
    var requiresContext: Bool { get }

    func canExecute(context: ActionContext) -> Bool
    func execute(context: ActionContext) async throws
}

enum ActionCategory {
    case create, modify, delete, navigate, export, search
}

struct ActionContext {
    var selectedDocuments: [Document]
    var currentView: ViewContext
    var user: User?
}
```

#### Built-in Actions (Examples)

```swift
struct CreateReminderAction: QuickAction {
    let id = "create.reminder"
    let title = "Create Reminder"
    let keywords = ["create", "add", "remind", "notify"]
    let icon = "bell.badge.fill"
    let category = .create
    let requiresContext = true

    func execute(context: ActionContext) async throws {
        guard let doc = context.selectedDocuments.first else { return }
        await showReminderSheet(for: doc)
    }
}

struct ScanDocumentAction: QuickAction {
    let id = "scan.document"
    let title = "Scan Document"
    let keywords = ["scan", "camera", "capture"]
    let icon = "doc.viewfinder.fill"
    let category = .create
    let requiresContext = false

    func execute(context: ActionContext) async throws {
        await showDocumentScanner()
    }
}
```

#### Action Matching

```swift
class ActionMatcher {
    func match(query: String, context: ActionContext) -> [ScoredAction] {
        let normalizedQuery = query.lowercased()

        return actionRegistry.actions
            .filter { $0.canExecute(context: context) }
            .map { action in
                var score = 0.0

                // Exact title match
                if action.title.lowercased() == normalizedQuery {
                    score += 1.0
                }
                // Title contains query
                else if action.title.lowercased().contains(normalizedQuery) {
                    score += 0.8
                }
                // Keyword match
                else if action.keywords.contains(where: { $0.contains(normalizedQuery) }) {
                    score += 0.6
                }
                // Fuzzy match (Levenshtein ≤2)
                else {
                    let distance = levenshteinDistance(normalizedQuery, action.title.lowercased())
                    if distance <= 2 { score += 0.4 }
                }

                // Boost recent actions
                if recentActions.contains(action.id) {
                    score += 0.2
                }

                return ScoredAction(action: action, score: score)
            }
            .filter { $0.score > 0.3 }
            .sorted { $0.score > $1.score }
    }
}
```

---

### E. Ranking & Fusion Strategy 🎯

```swift
struct SearchRanker {
    struct SignalWeights {
        var fts: Double = 0.3         // full-text BM25
        var semantic: Double = 0.4     // embedding similarity
        var field: Double = 0.2        // field matches
        var recency: Double = 0.05     // time decay
        var usage: Double = 0.05       // interaction history
    }

    func rank(results: [SearchCandidate],
              weights: SignalWeights = .default) -> [SearchResult] {

        return results.map { candidate in
            let ftsScore = normalize(candidate.ftsScore)
            let semanticScore = normalize(candidate.semanticScore)
            let fieldScore = normalize(candidate.fieldMatchCount / 10.0)
            let recencyScore = exp(-daysSince(candidate.document.createdAt) / 30.0)
            let usageScore = normalize(candidate.document.accessCount / 100.0)

            let finalScore =
                ftsScore * weights.fts +
                semanticScore * weights.semantic +
                fieldScore * weights.field +
                recencyScore * weights.recency +
                usageScore * weights.usage

            return SearchResult(
                document: candidate.document,
                score: finalScore,
                scoreBreakdown: [
                    "fts": ftsScore,
                    "semantic": semanticScore,
                    "field": fieldScore,
                    "recency": recencyScore,
                    "usage": usageScore
                ]
            )
        }.sorted { $0.score > $1.score }
    }
}
```

**Adaptive Learning:**
```swift
class AdaptiveRanker {
    func updateWeights(click: SearchResult, position: Int, query: String) {
        // Online learning via gradient descent on NDCG-style objective
        let learningRate = 0.01
        let target = 1.0 / Double(position + 1)

        // Update weights based on which signals were strong for clicked result
        // (Implementation of learning algorithm)
    }
}
```

---

## Implementation Phases

### Phase 1: Foundation (Weeks 1-2) 🏗️

**Goal**: Upgrade core infrastructure

**Tasks:**
1. Replace mock embeddings with Apple Embed
   - Implement `AppleEmbeddingService`
   - Batch re-embedding existing documents
   - Update LibSQL schema (dimension, model_version)

2. Add FTS5 indexing
   - Create `documents_fts` and `audio_fts` tables
   - Implement sync triggers
   - Migrate existing documents

3. Basic query analyzer
   - Pattern-based intent classification
   - Simple entity extraction (dates, amounts, types)
   - Query rewriter → `SearchQuery`

**Success Metrics:**
- [ ] All documents have real embeddings
- [ ] FTS queries <50ms for 1000 docs
- [ ] "last week" parsed to date range

---

### Phase 2: Natural Language Search (Weeks 3-4) 🗣️

**Tasks:**
1. Temporal expression parser
   - Relative: "yesterday", "last month"
   - Absolute: "march 2024", "12/15/2023"
   - Ranges: "between jan and march"

2. Entity extractor
   - Person name matching (fuzzy)
   - Document type synonyms
   - Location matching

3. Filter builder
   - Entities → `SearchFilter`
   - AND/OR logic

4. Semantic search integration
   - Hybrid FTS + vector
   - Configurable fusion weights

**Success Metrics:**
- [ ] "jay's insurance card" works
- [ ] "receipts from last week" filters correctly
- [ ] Semantic finds conceptually similar docs

---

### Phase 3: Aggregation & Computation (Weeks 5-6) 🧮

**Tasks:**
1. Aggregation engine
   - SUM, COUNT, AVG, MIN, MAX
   - GROUP BY support
   - SQL query builder

2. Amount/number extraction
   - Currency parsing ("$50", "100 dollars")
   - Range operators ("over 100")

3. Response formatter
   - Natural language presentation
   - Breakdown visualizations

**Success Metrics:**
- [ ] "how much did I spend last week" accurate
- [ ] "how many receipts" returns count
- [ ] Results show source documents

---

### Phase 4: Audio & Multi-Modal (Weeks 7-8) 🎙️

**Tasks:**
1. Audio indexing
   - FTS for transcripts/summaries
   - Embeddings for audio
   - Unified search

2. Audio-specific queries
   - "meeting notes from Monday"
   - "transcripts mentioning budget"

3. Search results UI
   - Unified cards (docs + audio)
   - Inline audio playback
   - Transcript highlighting

**Success Metrics:**
- [ ] Audio in search results
- [ ] Play audio from search
- [ ] Hybrid ranking across types

---

### Phase 5: Quick Actions (Weeks 9-10) ⚡

**Tasks:**
1. Action registry
   - 20+ core actions
   - Category organization
   - Permission/context checks

2. Command matching
   - Fuzzy matching
   - Usage frequency ranking
   - Contextual filtering

3. UI implementation
   - `>` prefix trigger
   - `⌘K` shortcut
   - Action execution

**Success Metrics:**
- [ ] `> create reminder` works
- [ ] Command suggestions
- [ ] Recent actions ranked higher

---

### Phase 6: Polish & Performance (Weeks 11-12) ✨

**Tasks:**
1. Performance optimization
   - Query caching
   - Incremental indexing
   - Background re-indexing

2. Advanced features
   - Search history
   - Saved searches
   - Autocomplete suggestions
   - "Did you mean...?"

3. Analytics & learning
   - Query pattern tracking
   - Click-through rates
   - Adaptive ranking

4. Testing
   - Unit tests (all components)
   - Integration tests
   - Performance benchmarks

**Success Metrics:**
- [ ] 95th percentile <100ms
- [ ] CTR improves over time
- [ ] Zero crashes

---

## Data Model Changes

### SwiftData Models

```swift
// Add to Document
@Model
class Document {
    // ... existing fields ...

    var lastAccessedAt: Date?
    var accessCount: Int = 0
    var searchRelevanceBoost: Double = 1.0

    var searchableText: String {
        [title, ocrText, cleanedText, location]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    var searchableFieldValues: String {
        fields.map { "\($0.key): \($0.value)" }.joined(separator: " ")
    }
}

// New models
@Model
class SearchQuery {
    var id: UUID
    var query: String
    var timestamp: Date
    var resultCount: Int
    var clickedDocumentID: UUID?
    var clickedPosition: Int?
}

// Extend AudioNote
@Model
class AudioNote {
    // ... existing ...

    var tags: [String] = []
    var embedding: Embedding?

    var searchableText: String {
        [title, transcript, summary]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

// Extend Embedding
@Model
class Embedding {
    // ... existing ...

    var dimension: Int
    var modelVersion: String
    var createdAt: Date
}
```

### LibSQL Schema

```sql
-- ============================================================================
-- VECTOR SEARCH TABLES (libsql native vector support)
-- ============================================================================

-- Document embeddings with F32_BLOB vector column
CREATE TABLE document_embeddings (
    document_id TEXT PRIMARY KEY,
    embedding F32_BLOB(768),  -- 768-dimensional float32 vector (Apple Embed default)
    model_version TEXT NOT NULL DEFAULT 'apple-embed-v1',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
);

-- Create vector index for ANN (Approximate Nearest Neighbors)
CREATE INDEX idx_document_embeddings_vector
ON document_embeddings(libsql_vector_idx(embedding));

-- Audio note embeddings (same pattern)
CREATE TABLE audio_embeddings (
    audio_note_id TEXT PRIMARY KEY,
    embedding F32_BLOB(768),
    model_version TEXT NOT NULL DEFAULT 'apple-embed-v1',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_audio_embeddings_vector
ON audio_embeddings(libsql_vector_idx(embedding));

-- Optional: Person embeddings for semantic person search
CREATE TABLE person_embeddings (
    person_id TEXT PRIMARY KEY,
    embedding F32_BLOB(768),
    model_version TEXT NOT NULL DEFAULT 'apple-embed-v1',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_person_embeddings_vector
ON person_embeddings(libsql_vector_idx(embedding));

-- ============================================================================
-- FULL-TEXT SEARCH TABLES (FTS5)
-- ============================================================================

-- Document full-text search
CREATE VIRTUAL TABLE documents_fts USING fts5(
    document_id UNINDEXED,
    title,
    ocr_text,
    cleaned_text,
    field_values,        -- denormalized "key: value" pairs
    person_names,        -- denormalized person names
    location,
    tokenize='unicode61 remove_diacritics 2'
);

-- Audio note full-text search
CREATE VIRTUAL TABLE audio_fts USING fts5(
    audio_note_id UNINDEXED,
    title,
    transcript,
    summary,
    tokenize='unicode61 remove_diacritics 2'
);

-- Auto-sync triggers for FTS tables
CREATE TRIGGER documents_ai AFTER INSERT ON documents BEGIN
    INSERT INTO documents_fts(document_id, title, ocr_text, cleaned_text, field_values, person_names, location)
    VALUES(
        new.id,
        new.title,
        new.ocr_text,
        new.cleaned_text,
        (SELECT GROUP_CONCAT(key || ': ' || value, ' ') FROM fields WHERE document_id = new.id),
        (SELECT GROUP_CONCAT(name, ' ') FROM persons p JOIN document_person_links dpl ON p.id = dpl.person_id WHERE dpl.document_id = new.id),
        new.location
    );
END;

CREATE TRIGGER documents_au AFTER UPDATE ON documents BEGIN
    UPDATE documents_fts SET
        title = new.title,
        ocr_text = new.ocr_text,
        cleaned_text = new.cleaned_text,
        location = new.location
    WHERE document_id = new.id;
END;

CREATE TRIGGER documents_ad AFTER DELETE ON documents BEGIN
    DELETE FROM documents_fts WHERE document_id = old.id;
    DELETE FROM document_embeddings WHERE document_id = old.id;
END;

-- Similar triggers for audio_fts
CREATE TRIGGER audio_ai AFTER INSERT ON audio_notes BEGIN
    INSERT INTO audio_fts(audio_note_id, title, transcript, summary)
    VALUES(new.id, new.title, new.transcript, new.summary);
END;

CREATE TRIGGER audio_au AFTER UPDATE ON audio_notes BEGIN
    UPDATE audio_fts SET
        title = new.title,
        transcript = new.transcript,
        summary = new.summary
    WHERE audio_note_id = new.id;
END;

CREATE TRIGGER audio_ad AFTER DELETE ON audio_notes BEGIN
    DELETE FROM audio_fts WHERE audio_note_id = old.id;
    DELETE FROM audio_embeddings WHERE audio_note_id = old.id;
END;

-- ============================================================================
-- SEARCH ANALYTICS (privacy-preserving, local only)
-- ============================================================================

CREATE TABLE search_queries (
    id INTEGER PRIMARY KEY,
    query TEXT NOT NULL,
    intent_type TEXT,  -- search, command, aggregation, etc.
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    result_count INTEGER,
    clicked_document_id TEXT,
    clicked_position INTEGER,
    execution_time_ms INTEGER
);

CREATE TABLE action_executions (
    id INTEGER PRIMARY KEY,
    action_id TEXT NOT NULL,
    context TEXT,  -- JSON of ActionContext
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    success BOOLEAN,
    execution_time_ms INTEGER
);

-- ============================================================================
-- PERFORMANCE INDEXES
-- ============================================================================

-- Search analytics indexes
CREATE INDEX idx_search_queries_timestamp ON search_queries(timestamp);
CREATE INDEX idx_search_queries_intent ON search_queries(intent_type, timestamp);
CREATE INDEX idx_action_executions_action ON action_executions(action_id, timestamp);

-- Field search indexes
CREATE INDEX idx_fields_search ON fields(key, value);
CREATE INDEX idx_fields_numeric ON fields(key, CAST(value AS REAL))
    WHERE value GLOB '[0-9]*';

-- Document indexes for filters
CREATE INDEX idx_documents_type_date ON documents(doc_type, created_at);
CREATE INDEX idx_documents_location ON documents(location) WHERE location IS NOT NULL;

-- ============================================================================
-- MIGRATION NOTES
-- ============================================================================

-- To migrate from existing embeddings table:
-- 1. Create new document_embeddings table with F32_BLOB
-- 2. Batch convert existing embeddings:
--    INSERT INTO document_embeddings (document_id, embedding, model_version)
--    SELECT entity_id, vector32('[' || vector || ']'), source
--    FROM embeddings WHERE entity_type = 'document';
-- 3. Create vector index
-- 4. Drop old embeddings table (or keep for rollback)
```

---

## UX Flows

### Enhanced Search Interface

```swift
struct UniversalSearchBar: View {
    @State private var query = ""
    @State private var mode: SearchMode = .search

    enum SearchMode {
        case search      // normal search
        case command     // starts with >
        case aggregation // detected intent

        var icon: String {
            switch self {
            case .search: return "magnifyingglass"
            case .command: return "chevron.right"
            case .aggregation: return "function"
            }
        }

        var color: Color {
            switch self {
            case .search: return .blue
            case .command: return .purple
            case .aggregation: return .orange
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: mode.icon)
                    .foregroundColor(.secondary)

                TextField("Search or type > for commands", text: $query)
                    .onChange(of: query) { detectMode($0) }

                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
            }
            .padding()
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(mode.color, lineWidth: 2))

            // Results
            if mode == .command {
                CommandPaletteView(query: String(query.dropFirst()))
            } else {
                SearchResultsView(query: query)
            }
        }
    }
}
```

### Result Cards

```swift
struct UnifiedResultCard: View {
    let result: UnifiedSearchResult

    var body: some View {
        HStack(spacing: 12) {
            resultIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(result.highlightedTitle)
                    .font(.headline)

                if let context = result.matchContext {
                    Text(context)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    result.badge
                    Spacer()
                    Text(result.timestamp.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                }
            }

            CircularProgressView(value: result.score)
                .frame(width: 32, height: 32)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
```

### Aggregation Results

```swift
struct AggregationResultCard: View {
    let aggregation: AggregationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(aggregation.formattedValue)
                    .font(.system(size: 48, weight: .bold))

                Spacer()

                Image(systemName: aggregation.icon)
                    .font(.largeTitle)
                    .foregroundColor(aggregation.color)
            }

            Text(aggregation.summary)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let breakdown = aggregation.breakdown {
                BreakdownChartView(breakdown)
            }

            Button("Show \(aggregation.count) sources →") {
                showSourceDocuments(aggregation.sourceDocuments)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [aggregation.color.opacity(0.1), aggregation.color.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
    }
}
```

---

## Testing Strategy

### Unit Tests

```swift
@Test("Query analyzer detects aggregation intent")
func testAggregationIntent() async throws {
    let analyzer = QueryAnalyzer()
    let intent = analyzer.analyze("how much did I spend last week")

    #expect(intent.type == .aggregationQuery)
    #expect(intent.entities.contains { $0.type == .temporalExpression })
}

@Test("Temporal expression parser handles relative dates")
func testTemporalParser() {
    let parser = TemporalExpressionParser()
    let range = parser.parse("last week")

    let expectedStart = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    #expect(range.start.timeIntervalSince(expectedStart) < 86400)
}

@Test("FTS search outperforms linear scan")
func testFTSPerformance() async throws {
    let documents = generateTestDocuments(count: 1000)
    let ftsEngine = FTSSearchEngine(documents: documents)
    let linearEngine = HybridSearchEngine(documents: documents)

    let ftsTime = measure { _ = try! await ftsEngine.search("insurance") }
    let linearTime = measure { _ = try! await linearEngine.search("insurance") }

    #expect(ftsTime < linearTime * 0.1)  // 10x faster
}
```

### Performance Benchmarks

| Operation | Current | Target |
|-----------|---------|--------|
| **Simple keyword** | 150ms | <50ms |
| **Semantic search** | 200ms | <100ms |
| **Aggregation** | N/A | <200ms |
| **FTS index build** | N/A | <5s |
| **Embedding gen** | N/A | <1s/doc |

---

## Privacy & Security

### Principles

1. **On-Device First**: Apple Embed (no network)
2. **Cloud Opt-In**: User consent for cloud embeddings
3. **No Telemetry**: Queries stay local
4. **User Control**: Disable history, export data
5. **Secure Storage**: LibSQL encrypted at rest
6. **Audit Trail**: Local logs (user-visible)

### Embedding Privacy

- **Primary**: Apple on-device (iOS 18.2+)
- **Optional**: Cloud with explicit consent
- **Storage**: Local SwiftData + LibSQL only

### Search Analytics

- **Local only**: No server telemetry
- **User control**: Settings to disable
- **Retention**: 30 days default

---

## Success Metrics

### Phase 1 (Foundation)
- [ ] 100% real embeddings (not mock)
- [ ] FTS index created
- [ ] Search latency <50ms

### Phase 2 (NLP)
- [ ] 90% temporal parsing accuracy
- [ ] 85% entity extraction precision
- [ ] 80% top-5 relevance

### Phase 3 (Aggregation)
- [ ] 100% aggregation accuracy
- [ ] <200ms query latency

### Phase 4 (Audio)
- [ ] Audio transcripts indexed
- [ ] Hybrid ranking with docs

### Phase 5 (Commands)
- [ ] 20+ actions implemented
- [ ] 90% command matching accuracy
- [ ] 5+ actions per power user session

### Phase 6 (Polish)
- [ ] 95th percentile <100ms
- [ ] Zero crashes (1000 queries)
- [ ] +20% CTR improvement

---

## Open Questions

1. **Embedding Model**: Apple Embed vs cloud?
   - **Recommendation**: Apple primary, cloud opt-in

2. **FTS Tokenization**: Unicode61 vs Porter?
   - **Recommendation**: Unicode61 (multilingual)

3. **Command Trigger**: `>` vs `⌘K`?
   - **Recommendation**: Both

4. **Aggregation Caching**: Cache results?
   - **Recommendation**: Yes, with invalidation

5. **Search History**: Retention period?
   - **Recommendation**: 30 days, user setting

6. **Backend Integration**: Server-side indexing?
   - **Recommendation**: Phase 7 (future), local-first now

---

## Appendix: Service Architecture

### File Structure

```
FolioMind/
  Services/
    QueryUnderstanding/
      QueryAnalyzer.swift
      TemporalExpressionParser.swift
      EntityExtractor.swift
      QueryRewriter.swift

    Search/
      FTSSearchEngine.swift
      SemanticSearchEngine.swift
      FieldSearchEngine.swift
      UniversalSearchService.swift
      SearchRanker.swift

    Aggregation/
      AggregationEngine.swift
      AggregationPresenter.swift
      AggregationVisualizer.swift

    Actions/
      QuickAction.swift
      ActionRegistry.swift
      ActionMatcher.swift
      ActionExecutor.swift
      Actions/
        CreateReminderAction.swift
        ScanDocumentAction.swift
        ...

    Indexing/
      SearchIndexManager.swift
      FTSSyncManager.swift

    Embeddings/
      AppleEmbeddingService.swift
      GeminiEmbeddingService.swift
      HybridEmbeddingService.swift
```

### Service Protocols

```swift
// Main search service
protocol UniversalSearchService {
    func search(_ query: String, options: SearchOptions) async throws -> SearchResponse
}

struct SearchOptions {
    var maxResults: Int = 20
    var includeAudio: Bool = true
    var includeDocuments: Bool = true
    var filters: [SearchFilter] = []
    var sortBy: SortOption = .relevance
}

struct SearchResponse {
    var results: [UnifiedSearchResult]
    var totalCount: Int
    var queryIntent: QueryIntent
    var suggestions: [String]           // "did you mean..."
    var aggregation: AggregationResult?
    var executionTime: TimeInterval
}

enum SortOption {
    case relevance, recency, title, documentType
}
```

---

**End of Document**
