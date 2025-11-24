# Step 1 — Foundations & Data Model

## Goal
Stand up the core domain, protocols, and storage scaffolding so we can plug in Vision, Gemini, and OpenAI later without rewriting the app. Deliver a runnable SwiftUI shell with compile-time-complete models and interfaces.

## Target Outcomes
- Stable SwiftData (or Core Data fallback) schema for `Document`, `Person`, `FaceCluster`, `Field`, and `Embedding`.
- Protocol-first services for OCR, cloud enrichment, embeddings, search, and linking.
- A minimal SwiftUI surface that can create placeholder documents and list them, proving persistence + dependency injection work.

## Domain Model (SwiftData)
Use SwiftData for speed; keep Core Data compatibility in mind by avoiding exotic types.
- `Document`: `id`, `title`, `docType` (enum: insuranceCard, idCard, receipt, generic), `ocrText`, `[Field]`, `createdAt`, `capturedAt`, `location` (optional), `assetURL` (local file URL string), `personLinks: [DocumentPersonLink]`, `faceClusterIDs: [UUID]`, `embeddingID`.
- `Field`: `id`, `key`, `value`, `confidence` (0–1), `source` (vision/gemini/openai/fused).
- `Person`: `id`, `displayName`, `aliases`, `emails`, `phones`, `addresses`, `faceClusterIDs`, `notes`, `embeddingID`.
- `FaceCluster`: `id`, `descriptor` (Data), `label` (optional), `lastUpdated`.
- `Embedding`: `id`, `vector` ([Float]), `source` (gemini/openai), `entityType` (document/person), `entityID`.
- `DocumentPersonLink`: lightweight join with `relationship` (owner/dependent/mentioned) and `confidence`.

## Service Protocols (keep testable)
- `DocumentAnalyzer`: `analyze(imageURL:hints:) async -> DocumentAnalysisResult` (contains fused OCR text, fields, docType, faceClusters).
- `OCRSource`: for local Vision OCR; emits raw text blocks + confidences.
- `CloudOCRService`: for Gemini/OpenAI; returns cleaned text + structured fields + doc type.
- `EmbeddingService`: `embedDocument(Document) async -> Embedding`, `embedPerson(Person) async -> Embedding`, `embedQuery(String) async -> [Float]`.
- `LinkingEngine`: `suggestLinks(for: Document, people: [Person], faceClusters: [FaceCluster]) -> [PersonMatch]`.
- `SearchEngine`: hybrid keyword + vector; `search(_ query: SearchQuery) async -> [SearchResult]`.

## App Structure (initial SwiftUI wiring)
- Use dependency injection via environment objects or a small `AppContainer` that holds services (`DocumentStore`, `DocumentAnalyzer`, `SearchEngine`).
- Provide a seed screen: list of `Document` titles + createdAt; add button creates a stub document to validate storage.
- Keep navigation simple now; detail screen can show fields and linked people once populated.

## Build & Integration Plan
1) Define the models above in `FolioMind` and migrate the sample app to use them (no UI overhaul yet).  
2) Add protocol definitions + placeholder implementations (no network calls) that return deterministic mock data.  
3) Wire an `AppContainer` and inject into `ContentView` so the UI compiles.  
4) Add lightweight unit tests for model defaults and protocol contracts (in `FolioMindTests`).  
5) Verify `xcodebuild -scheme FolioMind -destination 'platform=iOS Simulator,name=iPhone 15' test` passes with mocks.  
6) Document any schema changes in migration notes for future Core Data parity.  
7) Commit once the app builds, persists stub documents, and tests pass; proceed to Step 2 (pipeline implementation).
