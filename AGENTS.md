# Repository Guidelines

## Project Structure & Module Organization
- `FolioMind/`: SwiftUI sources. `FolioMindApp.swift` boots `AppServices`, injects it with `.environmentObject`, and attaches the shared SwiftData `ModelContainer`. `Models/DomainModels.swift` defines persisted models (`Document`, `Asset`, `Person`, `Field`, `FaceCluster`, `Embedding`, `DocumentPersonLink`, `DocumentReminder` plus enums). UI lives under `Views/` (navigation-stack grid in `ContentView`, detail in `DocumentDetailPageView`, edit sheet, scanner, highlights, image viewer). Service layer lives under `Services/` (DI container, `DocumentStore`, Vision analyzer, embeddings/search/linking/reminders, LLM integrations). Heuristics live under `Extractors/` (document type classifier, card details, field extractor). Visual assets sit in `Assets.xcassets/`.
- `FolioMindTests/`: unit tests using Swift’s `Testing` package; mocks for analyzers/search/embedding live alongside feature tests in `FolioMindTests.swift`.
- `FolioMindUITests/`: UI and launch performance tests using XCTest.
- `Docs/`: repo documentation (e.g., `SPEA.md`, `step1.md`); place new guides here.
- Backend/API planning currently lives in `Docs/ProductSpec.md`; update this doc when adding backend-facing requirements, API contracts, or data flow notes.

## Build, Test, and Development Commands
- `open FolioMind.xcodeproj` — develop with Xcode; target `FolioMind`.
- `xcodebuild -scheme FolioMind -destination 'platform=iOS Simulator,name=iPhone 15' clean build` — CI-friendly build.
- `xcodebuild test -scheme FolioMind -destination 'platform=iOS Simulator,name=iPhone 15'` — run unit + UI tests; add `-enableCodeCoverage YES` when measuring coverage.
- Prefer Simulator runs; if adding scripts, keep them idempotent and pinned to a scheme/destination.

## Coding Style & Naming Conventions
- Swift 5.9+ with SwiftData; keep views as `struct`s, models with `@Model`, and data access via `@Query`/`@Environment(\.modelContext)` plus DI through `@EnvironmentObject AppServices`.
- Indent with 4 spaces; keep lines readable (~120 cols); one primary type per file.
- UpperCamelCase for types and protocols; lowerCamelCase for vars/functions; suffix views with `View`, models with clear nouns.
- Avoid force unwraps; prefer `guard` for early exits and `Task` for async UI work; mirror existing UI styling (SurfaceCard/PillBadge, gradient accents per `DocumentType`, NavigationStack).
- When adding/altering models, update the schema list in `AppServices` so the `ModelContainer` and in-memory test containers stay in sync.

## Testing Guidelines
- Unit tests live in `FolioMindTests` with `@Test` and `#expect`; use in-memory `ModelConfiguration(isStoredInMemoryOnly: true)` and lightweight mocks (see `MockDocumentAnalyzer`, `MockSearchEngine`) to keep tests deterministic. Add coverage for ingestion, classifiers/extractors, embedding/search ranking, reminders, and UI-visible model changes.
- UI flows in `FolioMindUITests`; prefix methods with `test…` and keep launch/setup code reusable.
- Reset or stub SwiftData state per test; add coverage for new user-visible behaviors, navigation paths, and persistence changes.

## Commit & Pull Request Guidelines
- Commit messages: imperative, concise (e.g., `Add item deletion animation`). Keep logical scopes small.
- PRs should include a short purpose statement, screenshots for UI changes, tests/commands run, and linked issues/tasks.
- Keep diffs tight, update docs/tests alongside feature code, and note any migration impacts when touching `Document` models or storage schema.

## Architecture Overview
- Single-scene SwiftUI app with a `NavigationStack`: `ContentView` shows a search-enabled document grid (ingest via PhotosPicker import or VisionKit scanner) and routes to `DocumentDetailPageView` (tabbed overview/details/OCR, multi-asset viewer, edit sheet, sharing, reminder hooks).
- Dependency injection via `AppServices`, which builds the shared SwiftData `ModelContainer` (models: `Document`, `Asset`, `Person`, `Field`, `FaceCluster`, `Embedding`, `DocumentPersonLink`, `DocumentReminder`) and wires `DocumentStore`, `VisionDocumentAnalyzer`, `SimpleEmbeddingService`, `HybridSearchEngine`, `BasicLinkingEngine`, and `ReminderManager`.
- Ingestion pipeline: `DocumentStore.ingestDocuments` runs OCR/faces through `VisionDocumentAnalyzer` (Vision/VisionKit), merges heuristic fields (`FieldExtractor`) with optional LLM-driven `IntelligentFieldExtractor`, classifies via `DocumentTypeClassifier`, creates `Asset` records, and saves embeddings for hybrid search.
- Intelligence: LLM integration is optional; `LLMServiceFactory` prefers Apple Foundation Models when available and can fall back to OpenAI (API key placeholder in `AppServices`—keep secrets out of commits).
- Persistence: documents can hold multiple image assets (`assets` + `imageAssets` helpers) with computed `assetURL` for legacy access; embeddings and person links/reminders are modeled explicitly for future linking and notification features.
- Backend/API direction: plan for a service that accepts uploads, stores files, and runs summarization/transcription/information extraction. Keep the app local-first; any client/backend bridges should be optional, respect privacy, and keep secrets/config outside source. Document API shape and data contracts in `Docs/ProductSpec.md` before implementation.

## Search Architecture (Planned v2)

**See [Docs/SearchArchitecture.md](Docs/SearchArchitecture.md) for comprehensive specification.**

The search system is being evolved from basic hybrid search (keyword + mock embeddings) to an **intelligent, multi-modal platform** with:

**Core Components**:
- **Query Understanding Layer** (`Services/QueryUnderstanding/`): Intent classification, entity extraction (people, dates, amounts, types), temporal expression parsing, query rewriting
- **Multi-Engine Search** (`Services/Search/`): FTS5 full-text indexing, libsql native vector search (768D via Apple Embed with `vector_top_k()`), structured field search, audio transcript search, unified ranking
- **Aggregation Engine** (`Services/Aggregation/`): Computational queries (SUM, COUNT, AVG) with natural language responses
- **Quick Action System** (`Services/Actions/`): Command palette (`>` prefix or `⌘K`) for executing actions like "create reminder", "scan document"
- **Indexing Pipeline** (`Services/Indexing/`): LibSQL FTS5 tables, F32_BLOB vector columns with ANN indexes, automatic sync triggers, batch embedding generation

**Key Enhancements**:
- Replace mock 3D embeddings with production-quality 768D vectors (Apple Embed on-device or Gemini cloud opt-in)
- Use **libsql native vector search** with F32_BLOB columns and `vector_top_k()` function (10x faster than in-memory cosine similarity)
- Add SQLite FTS5 virtual tables for sub-millisecond keyword search (`documents_fts`, `audio_fts`)
- Support natural language queries: "how much did I spend last week" → temporal aggregation, "jay's insurance card" → person + type filtering
- Hybrid ranking with 5 signals: FTS (30%) + semantic (40%) + field matches (20%) + recency (5%) + usage (5%)
- Adaptive learning from user interactions (click-through rates adjust ranking weights)

**Data Model Updates**:
- `Document`: Add `lastAccessedAt`, `accessCount`, `searchRelevanceBoost`, computed `searchableText`/`searchableFieldValues`
- `AudioNote`: Add `tags`, `embedding`, computed `searchableText`
- `Embedding`: Add `dimension`, `modelVersion`, `createdAt` for versioning
- New models: `SearchQuery` (query history), `ActionExecution` (command analytics)

**Database Schema (LibSQL)**:
```sql
-- Vector search with F32_BLOB columns (libsql native)
CREATE TABLE document_embeddings (
    document_id TEXT PRIMARY KEY,
    embedding F32_BLOB(768),  -- 768D vector for Apple Embed
    model_version TEXT DEFAULT 'apple-embed-v1',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_document_embeddings_vector ON document_embeddings(libsql_vector_idx(embedding));

CREATE TABLE audio_embeddings (
    audio_note_id TEXT PRIMARY KEY,
    embedding F32_BLOB(768),
    model_version TEXT DEFAULT 'apple-embed-v1',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_audio_embeddings_vector ON audio_embeddings(libsql_vector_idx(embedding));

-- FTS virtual tables
CREATE VIRTUAL TABLE documents_fts USING fts5(document_id UNINDEXED, title, ocr_text, cleaned_text, field_values, person_names, location, tokenize='unicode61 remove_diacritics 2');
CREATE VIRTUAL TABLE audio_fts USING fts5(audio_note_id UNINDEXED, title, transcript, summary, tokenize='unicode61 remove_diacritics 2');

-- Auto-sync triggers (keep FTS and embeddings in sync with documents)
CREATE TRIGGER documents_ad AFTER DELETE ON documents BEGIN
    DELETE FROM documents_fts WHERE document_id = old.id;
    DELETE FROM document_embeddings WHERE document_id = old.id;
END;

-- Search analytics (local only, privacy-preserving)
CREATE TABLE search_queries (id, query, intent_type, timestamp, result_count, clicked_document_id, clicked_position);
CREATE TABLE action_executions (id, action_id, context, timestamp, success, execution_time_ms);
```

**Implementation Approach**:
- **Phase 1**: Replace mock embeddings, add FTS indexing, basic query analyzer
- **Phase 2**: Natural language understanding (temporal parsing, entity extraction)
- **Phase 3**: Aggregation engine for computational queries
- **Phase 4**: Audio search integration
- **Phase 5**: Quick actions / command palette
- **Phase 6**: Performance optimization, adaptive learning

**Guidelines for Implementation**:
- Maintain local-first privacy: prefer Apple on-device embeddings, no telemetry without consent
- Keep search services protocol-driven for testability (mock implementations for unit tests)
- Use SwiftData observation for automatic index updates (onChange triggers for FTS sync)
- Handle migration gracefully: batch re-embedding when upgrading embedding models
- Test with realistic data: 1000+ document corpus for performance validation
- Follow existing patterns: service layer in `Services/`, models in `DomainModels.swift`, UI in `Views/`
