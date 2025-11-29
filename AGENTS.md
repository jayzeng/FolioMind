# Repository Guidelines

## Project Structure & Module Organization
- `FolioMind/`: SwiftUI sources. `FolioMindApp.swift` boots `AppServices`, injects it with `.environmentObject`, and attaches the shared SwiftData `ModelContainer`. `Models/DomainModels.swift` defines persisted models (`Document`, `Asset`, `Person`, `Field`, `FaceCluster`, `Embedding`, `DocumentPersonLink`, `DocumentReminder` plus enums). UI lives under `Views/` (navigation-stack grid in `ContentView`, detail in `DocumentDetailPageView`, edit sheet, scanner, highlights, image viewer). Service layer lives under `Services/` (DI container, `DocumentStore`, Vision analyzer, embeddings/search/linking/reminders, LLM integrations). Heuristics live under `Extractors/` (document type classifier, card details, field extractor). Visual assets sit in `Assets.xcassets/`.
- `FolioMindTests/`: unit tests using Swift’s `Testing` package; mocks for analyzers/search/embedding live alongside feature tests in `FolioMindTests.swift`.
- `FolioMindUITests/`: UI and launch performance tests using XCTest.
- `Docs/`: repo documentation (e.g., `SPEA.md`, `step1.md`); place new guides here.

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
