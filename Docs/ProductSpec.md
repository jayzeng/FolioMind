# FolioMind Product Spec

## Overview
- FolioMind is an iOS SwiftUI app for capturing, organizing, and searching personal documents (cards, bills, letters, receipts). It uses SwiftData for local persistence, Vision/VisionKit for OCR and scanning, optional LLM enrichment, and hybrid keyword + embedding search. Current UI centers on a document grid with search, import/scan entry points, and a rich document detail view with multi-asset support.

## Goals
- Fast capture: import from photos or scan documents, create structured records automatically.
- Reliable organization: classify document types, extract key fields, and link to people/reminders for follow-up.
- Powerful recall: hybrid search that mixes keyword and semantic signals to surface the right document.
- Local-first: function offline with on-device OCR and embeddings; allow optional cloud/LLM enrichment when available.

## Target Users & Personas
- Organizer: keeps medical/insurance/ID/billing documents handy, needs quick lookup and due-date awareness.
- Power filer: scans multi-page receipts/bills, wants auto-extracted fields and reminders for payments/renewals.
- Mobile-first professional: captures documents on the go, expects reliable search and rich previews.

## Core User Stories (v1 implemented unless otherwise noted)
- As a user, I can import images from Photos or scan with the camera to create documents.
- As a user, I see my documents in a grid with type badges, previews, and recency metadata.
- As a user, I can search documents by text and get ranked results (keyword + semantic).
- As a user, I can open a document to view details: hero image(s), status, highlights by type, metadata, and OCR text.
- As a user, I can edit document title/type/location and view extracted fields.
- As a user, I can manage multiple images per document (view, zoom, swipe, add).
- As a user, I can delete documents with confirmation.
- As a user, I can trigger reminders suggestions (manager present; UI hooks to expand).
- Future: share/export document, smarter reminder scheduling, people linking UI, cloud enrichment configuration.

## Functional Requirements

### Capture & Ingestion
- Import from Photos (`PhotosPicker`) and VisionKit scan (`VNDocumentCameraViewController`) with availability gating.
- For each import/scan:
  - Run OCR via Vision/VisionKit (`VisionDocumentAnalyzer` using `VisionOCRSource`/`VisionKitOCRSource`).
  - Detect faces (`VisionFaceDetector`) for potential linking.
  - Extract fields via heuristics (`FieldExtractor`) and optional intelligent extraction (`IntelligentFieldExtractor` with LLM).
  - Classify document type via `DocumentTypeClassifier` (creditCard, insuranceCard, idCard, letter, billStatement, receipt, generic).
  - Create one `Document` with:
    - Combined OCR text across pages.
    - Merged fields (pattern + intelligent).
    - Assets per page (ordered).
    - Face cluster IDs.
    - Cleaned text when LLM available.
  - Generate embedding for the document (`SimpleEmbeddingService`) and attach to the record.
- Default titles derive from provided title, hints, or file names.

### Document Management
- Browse in `ContentView` via `NavigationStack` grid:
  - Three-column adaptive grid, SurfaceCard aesthetic, badges for type and match score.
  - Empty states for no docs and empty search.
- Context actions:
  - Edit opens `DocumentEditView`.
  - Delete prompts confirmation; deletion persisted via `modelContext`.
- Detail experience (`DocumentDetailPageView`):
  - Tabs: Overview, Details, Text.
  - Multi-asset hero with zoom, full-screen viewer, pagination indicator, thumbnail strip, add-images button.
  - Highlights per type (credit card, insurance, letter, bill) via `DocumentHighlightsView`.
  - Metadata editing: doc type picker, captured/created timestamps, location, asset URL display.
  - Extracted fields shown with chips and confidence badges; reset/merge logic handled at ingestion level.
  - OCR view with expand/collapse.
- Sharing: UI hook exists; actual share payload not yet implemented (future).

### Search
- Search bar in `ContentView` with live updates.
- `HybridSearchEngine`:
  - Fetches all documents (sorted by createdAt desc).
  - Keyword score: token containment in title + OCR.
  - Semantic score: cosine between document embedding and query embedding.
  - Weighted rank (default 0.6 keyword / 0.4 semantic).
- Results show match percent badges; empty state messaging.

### Reminders
- `ReminderManager` wraps EventKit:
  - Permission handling for reminders/events.
  - Create/delete/complete reminders and calendar events.
  - Suggest reminders from document type and fields (e.g., bill due date, insurance call/appointment, renewal).
- UI currently surfaces reminder manager in detail view; additional flows needed to create/track reminders visibly.

### People & Linking
- Models exist for `Person`, `DocumentPersonLink`, `FaceCluster`; `LinkingEngine` stubbed (`BasicLinkingEngine` returns empty).
- Current UI shows "Belongs To" card with initials/name placeholder; full linking flows TBD.

### Intelligence & LLMs
- `LLMServiceFactory`:
  - Prefers Apple Foundation Models (iOS 18.2+) when available.
  - Optional OpenAI fallback (API key placeholder in `AppServices`; must not ship secrets).
  - `IntelligentFieldExtractor` uses NLTagger, document-type prompts, and comprehensive generic prompt; merges with heuristic fields.
- Text cleaning via LLM when available; safe fallback to raw OCR.

## Data Model (SwiftData)
- `Document`: id, title, docType, ocrText, cleanedText?, fields [Field], createdAt, capturedAt?, location?, assets [Asset], personLinks [DocumentPersonLink], faceClusterIDs [UUID], embedding?, reminders [DocumentReminder]; computed `assetURL`, `imageAssets`.
- `Asset`: id, fileURL, assetType (image/pdf/document), addedAt, pageNumber, thumbnailURL?, document?.
- `Field`: id, key, value, originalValue, confidence, source (vision/gemini/openai/fused); helpers for modification/reset.
- `FaceCluster`: id, descriptor, label?, lastUpdated.
- `Person`: id, displayName, aliases, emails, phones, addresses, faceClusterIDs, notes, embedding?.
- `Embedding`: id, vector [Double], source (gemini/openai/mock), entityType (document/person), entityID.
- `DocumentPersonLink`: id, person?, relationship (owner/dependent/mentioned), confidence.
- `DocumentReminder`: id, title, notes, dueDate, reminderType, isCompleted, eventKitID?, createdAt.

## Architecture & Services
- `AppServices` (DI container):
  - Builds SwiftData `ModelContainer` with full schema; recreates store on migration failure (dev-only behavior).
  - Owns `DocumentStore`, `VisionDocumentAnalyzer`, `SimpleEmbeddingService`, `HybridSearchEngine`, `BasicLinkingEngine`, `ReminderManager`, optional LLM service.
- `DocumentStore`:
  - `ingestDocuments` orchestrates OCR, classification, field fusion, asset creation, embeddings, persistence.
  - `createStubDocument` for testing/demo; `delete` helper for list bindings.
- `VisionDocumentAnalyzer`:
  - Uses Vision/VisionKit OCR, face detection, field extraction merge (pattern + intelligent), optional cloud enrichment hook.
  - Cleans text via LLM when available.
- `FieldExtractor`:
  - Heuristic extraction for phones, emails, URLs, dates (context-aware keys), addresses, amounts, names; deduplication.
- `DocumentTypeClassifier`:
  - Heuristic scoring for credit/insurance/bill/letter, Luhn/expiry detection for cards, debug logging gate.
- `CardDetailsExtractor`:
  - PAN/expiry/holder/issuer parsing with Luhn and context filters, used for highlights and key info.
- Search: `HybridSearchEngine` (keyword + embedding), `SimpleEmbeddingService` (mock vectors) for offline determinism.
- Reminder: `ReminderManager` (EventKit wrapper) with suggestion logic by doc type.

## UX Flows (current)
1) Landing: `ContentView` loads documents via `@Query`, shows status banners for search/import/scan, displays grid or empty state.
2) Import: pick image -> async load data -> temp file -> `ingestDocuments` -> grid updates; error message on failure.
3) Scan: VisionKit sheet -> returns page URLs -> `ingestDocuments`; availability gating with fallback error alert.
4) Search: type into search bar -> async search -> shows results grid or "No results" state; match badges shown.
5) Detail: tap card -> `DocumentDetailPageView` with hero image, tabs, highlights, metadata picker, OCR, reminders section placeholder, share menu, edit sheet, delete alert.
6) Edit: `DocumentEditView` allows title/type/location edits, shows timestamps and OCR preview.
7) Images: tap hero to zoom/fullscreen; thumbnail strip to switch pages; add assets via PhotosPicker.

## Non-Functional Requirements
- Local-first, offline-capable for core browse/search/edit when assets exist on device.
- Handle missing features gracefully: if scanner unavailable, show error; if LLM unavailable, fall back to heuristics.
- Performance: ingest multiple pages without blocking UI; search returns promptly with small corpus; avoid blocking main thread during OCR/LLM.
- Privacy: documents and embeddings are stored locally; avoid shipping API keys; prompt for permissions (Photos, Camera/Scanner, Reminders/Calendar).
- Resilience: safe optional chaining, no force unwraps; defensive against missing files/asset URLs.

## Analytics & Telemetry (future)
- Track ingestion success/failure, search queries and dwell, reminder creation/usage, and doc type distribution (opt-in).
- Surface quality metrics: extraction coverage, classifier accuracy, search click-through.

## Open Questions / Next Steps
- Define sharing/export payload (images + cleaned text + fields?) and destinations (Files/ShareSheet/PDF export).
- Add UI for reminder suggestions and EventKit-backed tracking, including completion states on documents.
- People linking flows: pick/create people, face clustering, suggested links review.
- Cloud/LLM config UI: API key management, toggle Apple Intelligence availability, safe secrets handling.
- Attachments beyond images (PDF ingest) and multi-page ordering controls.
- Access control/backups: iCloud sync vs. local-only stance; migration strategy for schema evolution.

## Testing Expectations
- Unit tests using `Testing` package with in-memory SwiftData containers; mocks for analyzers/search/embeddings.
- Cover: ingestion merges OCR across pages, classifier/extractor accuracy, embedding search ordering, reminder suggestion logic, card detail parsing.
- UI tests via XCTest for launch/navigation smoke and performance baseline; expand with flows as features ship.
