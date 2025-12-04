# FolioMind Product Spec

## Overview
- FolioMind is an iOS SwiftUI app for capturing, organizing, and searching personal documents (cards, bills, letters, receipts). It uses SwiftData for local persistence, Vision/VisionKit for OCR and scanning, optional LLM enrichment, and hybrid keyword + embedding search. Current UI centers on a document grid with search, import/scan entry points, and a rich document detail view with multi-asset support.
- A lightweight backend API will store uploaded files and run AI tasks (document summarization, audio transcription, information extraction) to complement the local-first experience and enable cloud-backed workflows.

## Goals
- Fast capture: import from photos or scan documents, create structured records automatically.
- Reliable organization: classify document types, extract key fields, and link to people/reminders for follow-up.
- Powerful recall: hybrid search that mixes keyword and semantic signals to surface the right document.
- Local-first: function offline with on-device OCR and embeddings; allow optional cloud/LLM enrichment when available.
- Cloud assist: optionally upload files to a backend for storage/backup and async processing (summary, transcription, extraction) with clear consent and auditability.
- API-first: maintain stable contracts so mobile and future web/partner clients can create files, request processing, and fetch results reliably.

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
- Future/backlog: as a user, I can sync documents/files to a backend for backup and remote processing (summary, transcription, extraction) and see results stitched back into my document view.
- Future/backlog: as a user, I can upload audio (voice notes/recordings) and receive transcription plus extracted fields/summary.
- Future/backlog: as a user, I can request a summary or extraction for any stored document and be notified when it is ready.

## Backend/API Scope
- Responsibilities: accept uploads (images, PDFs, audio), store file metadata, and run asynchronous AI jobs (summaries, transcriptions, structured extractions) that feed back into the client’s document model.
- Principles: opt-in cloud use, authenticated per user/account, deletable on request, auditable (job history), and minimal coupling so the app can remain offline-first.
- Outputs should map cleanly to existing entities (`Document`, `Field`, `Asset`, `Embedding`) so results can be merged locally without schema churn.

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

### Backend & Cloud Services
- API surface (REST or HTTP+JSON first): auth via bearer token, versioned endpoints, all responses include request IDs and job IDs for tracing.
- File storage:
  - Upload endpoint accepts image, PDF, and audio blobs; returns `fileId`, checksum, MIME type, size, and optional client-provided hints (doc type, title, timestamps).
  - Supports resumable/chunked upload for large files and optional presigned-URL flow.
  - Files belong to an owning user/account; deletion endpoint purges stored data and associated AI outputs.
- Processing jobs (async):
  - `summary` job: input `fileId` or `documentId`, optional instructions (length/format), outputs short + detailed summaries, bullets, and suggested tags.
  - `transcription` job: input `fileId` (audio), language hint, and optional diarization flag; outputs full transcript with timestamps and confidence.
  - `extraction` job: input `fileId` or `documentId`, extraction profile (fields expected), and optional schema for custom fields; outputs key-value pairs with confidences plus raw spans.
  - Jobs expose statuses (`queued`, `running`, `succeeded`, `failed`), start/end timestamps, and error payloads; results retrievable via polling and optional webhook callback.
- Document sync:
  - Endpoint to create/update a cloud `document` that references uploaded files and client metadata (title, docType, capturedAt, location, tags).
  - Results from jobs can be attached to the document record (e.g., summaries, transcript text, extracted fields).
- Client behaviors:
  - Mobile app can opt in per document/asset to upload and trigger jobs; results merged into SwiftData (`cleanedText`, `fields`, `summary`, transcript) while preserving local data.
  - Respect network/permission settings; queue requests offline and sync when online if enabled.

## Data Model (SwiftData)
- `Document`: id, title, docType, ocrText, cleanedText?, fields [Field], createdAt, capturedAt?, location?, assets [Asset], personLinks [DocumentPersonLink], faceClusterIDs [UUID], embedding?, reminders [DocumentReminder]; computed `assetURL`, `imageAssets`.
- `Asset`: id, fileURL, assetType (image/pdf/document), addedAt, pageNumber, thumbnailURL?, document?.
- `Field`: id, key, value, originalValue, confidence, source (vision/gemini/openai/fused); helpers for modification/reset.
- `FaceCluster`: id, descriptor, label?, lastUpdated.
- `Person`: id, displayName, aliases, emails, phones, addresses, faceClusterIDs, notes, embedding?.
- `Embedding`: id, vector [Double], source (gemini/openai/mock), entityType (document/person), entityID.
- `DocumentPersonLink`: id, person?, relationship (owner/dependent/mentioned), confidence.
- `DocumentReminder`: id, title, notes, dueDate, reminderType, isCompleted, eventKitID?, createdAt.

## Backend Entities (API)
- `File`: `fileId`, ownerId, storage URL/location, MIME type, size, checksum, createdAt, source (upload/presigned), optional hints (docType, title), and retention policy.
- `Document` (cloud): `documentId`, ownerId, title, docType, capturedAt, location, related `fileIds`, tags, status, and a map of attached outputs (summaries, transcriptId, extractionId).
- `Job`: `jobId`, type (`summary`/`transcription`/`extraction`), input references (`fileId`/`documentId`), status, timestamps, progress, errors, and output references.
- `Transcript`: `transcriptId`, `fileId`, language, segments with timestamps/confidence, full text.
- `Summary`: `summaryId`, `documentId` or `fileId`, short summary, detailed summary, bullets, tags, tone/length metadata.
- `Extraction`: `extractionId`, `documentId` or `fileId`, fields (key/value/confidence/source/span), and any normalized amounts/dates/entities.

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
- Backend integration (planned):
  - Client-side uploader with retry/backoff for `fileId` creation; respects metered networks and user consent.
  - Sync manager to request jobs, poll statuses, merge outputs into local models, and reconcile deletions.
  - Webhook handler (server) and local notification surface (client) for completed jobs; fallback to polling.

## UX Flows (current)
1) Landing: `ContentView` loads documents via `@Query`, shows status banners for search/import/scan, displays grid or empty state.
2) Import: pick image -> async load data -> temp file -> `ingestDocuments` -> grid updates; error message on failure.
3) Scan: VisionKit sheet -> returns page URLs -> `ingestDocuments`; availability gating with fallback error alert.
4) Search: type into search bar -> async search -> shows results grid or "No results" state; match badges shown.
5) Detail: tap card -> `DocumentDetailPageView` with hero image, tabs, highlights, metadata picker, OCR, reminders section placeholder, share menu, edit sheet, delete alert.
6) Edit: `DocumentEditView` allows title/type/location edits, shows timestamps and OCR preview.
7) Images: tap hero to zoom/fullscreen; thumbnail strip to switch pages; add assets via PhotosPicker.
8) Cloud assist (future): choose documents/audio to upload -> backend returns `fileId` -> request summary/transcription/extraction -> user sees pending status -> results attached to document text/fields/highlights when complete.

## Non-Functional Requirements
- Local-first, offline-capable for core browse/search/edit when assets exist on device.
- Handle missing features gracefully: if scanner unavailable, show error; if LLM unavailable, fall back to heuristics.
- Performance: ingest multiple pages without blocking UI; search returns promptly with small corpus; avoid blocking main thread during OCR/LLM.
- Privacy: documents and embeddings are stored locally; avoid shipping API keys; prompt for permissions (Photos, Camera/Scanner, Reminders/Calendar).
- Resilience: safe optional chaining, no force unwraps; defensive against missing files/asset URLs.
- Security (backend): authenticated requests, encryption at rest/in transit, role/user isolation, and explicit retention/deletion policies for files and AI outputs.
- Reliability: idempotent upload and job creation, retries with backoff, and observability (metrics/logs/traces) for API operations.

## Analytics & Telemetry (future)
- Track ingestion success/failure, search queries and dwell, reminder creation/usage, and doc type distribution (opt-in).
- Surface quality metrics: extraction coverage, classifier accuracy, search click-through.
- For backend, capture job volume/success rates, latency per model/type, upload sizes, and storage usage (aggregated/anonymous).

## Open Questions / Next Steps
- Define sharing/export payload (images + cleaned text + fields?) and destinations (Files/ShareSheet/PDF export).
- Add UI for reminder suggestions and EventKit-backed tracking, including completion states on documents.
- People linking flows: pick/create people, face clustering, suggested links review.
- Cloud/LLM config UI: API key management, toggle Apple Intelligence availability, safe secrets handling.
- Attachments beyond images (PDF ingest) and multi-page ordering controls.
- Access control/backups: iCloud sync vs. local-only stance; migration strategy for schema evolution.
- Backend decisions: choose hosting/runtime, storage backend (e.g., object storage), model providers per job type, and webhook vs. long-poll default.
- Contract validation: define JSON schemas/examples for upload and job endpoints; add client stubs/mocks for offline testing.

## Testing Expectations
- Unit tests using `Testing` package with in-memory SwiftData containers; mocks for analyzers/search/embeddings.
- Cover: ingestion merges OCR across pages, classifier/extractor accuracy, embedding search ordering, reminder suggestion logic, card detail parsing.
- UI tests via XCTest for launch/navigation smoke and performance baseline; expand with flows as features ship.
- Add contract tests/mocks for backend API calls (upload, job creation, job polling) to keep mobile integration deterministic without network access.
