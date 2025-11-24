You are an expert iOS architect and senior Swift/SwiftUI engineer. Your job is to help me DESIGN and IMPLEMENT a full iOS app that manages and searches real-world information via photos and documents.

## High-level goal

Build an iOS app where a user can:

1. Scan or upload a photo/document (e.g., insurance card, receipts, ID cards, forms, letters, business cards).
2. Automatically extract information from the image:
   - OCR text
   - Metadata (timestamp, location if available, device info)
   - Detected people/faces and other entities (names, organizations, phone numbers, policy numbers, etc.).
3. Automatically link and group information across images:
   - Example: If I upload an insurance card, the app extracts the card details, detects the person’s name, and asks if we should link this card to an existing person profile in the app or create a new one.
   - Later, I should be able to search with something like “John’s insurance card” even if the raw text in the image does not contain the exact phrase “insurance card”.

The key is smart structuring + semantic linking on top of raw images and OCR.

## Platform / Tech constraints

- Target platform: iOS (latest stable).
- Language: Swift.
- UI framework: SwiftUI preferred. If UIKit is clearly better for specific pieces (e.g., low-level camera integration), explain why and how to bridge it.
- Use Apple frameworks when reasonable:
  - Vision / VisionKit / VisionKit document scanner for capturing and basic OCR.
  - CoreImage / AVFoundation / Photos for access to images, metadata, camera.
  - Vision for face detection, face bounding boxes, and possibly face embeddings (for clustering/grouping, not recognition of identity).
  - CoreData or another persistent store (e.g., SQLite via GRDB) for local data models.

### OCR and perception stack (IMPORTANT)

Design a **multi-source OCR + perception pipeline**:

1. **Capture**:
   - Use the native iOS document scanner (VisionKit / VNDocumentCameraViewController or the modern equivalent) for scanning documents.
   - Allow picking from Photo Library / Files as well.

2. **Local OCR & metadata**:
   - Run iOS Vision text recognition on-device first to get baseline OCR (for privacy and offline behavior).
   - Extract EXIF/metadata (timestamp, GPS location, orientation, etc.).
   - Use Vision to detect faces and their bounding boxes and generate any available face descriptors/embeddings for grouping faces across photos (without doing external identity recognition).

3. **Cloud OCR & enrichment**:
   - Then call **Google Gemini** (vision/multimodal endpoint) as the primary cloud OCR + understanding engine:
     - Provide the image (or image URL) and ask Gemini to:
       - Return cleaned OCR text.
       - Extract structured fields (names, IDs, policy numbers, etc.).
       - Classify document type (insurance card, ID, receipt, bill, generic, etc.).
       - Extract entities (people, organizations, addresses, phone numbers, emails).
   - If Gemini fails or returns low-confidence results, use **OpenAI (vision model)** as a backup:
     - Ask OpenAI to perform similar OCR + document understanding.
   - Combine outputs from:
     - iOS Vision OCR
     - Gemini OCR
     - OpenAI OCR
     into a single, merged representation:
     - Design a conflict-resolution strategy:
       - E.g., align by line/region when possible, use confidence scores, majority voting, or prefer Gemini/OpenAI for semantic structuring while using Vision for pixel-perfect text.
     - Implement a fusion layer that produces:
       - Final `ocrText` (string).
       - A list of `Field` objects with `key`, `value`, and `confidence`.
       - Document type classification.
       - Candidate person names and other entities.

4. **Face/person understanding**:
   - Use Vision framework for face detection and face feature descriptors.
   - Cluster faces locally to identify “same person across multiple photos” in a privacy-respecting way.
   - Introduce a concept like “face cluster” which the user can label as a Person (e.g., “John”) once, then reuse across documents.

Make sure to define all relevant DTOs and Swift models for the outputs of Vision, Gemini, and OpenAI, and show how they are merged.

## AI / Intelligence layer (IMPORTANT)

Define a clear “Intelligence Layer” with well-defined interfaces:

- `DocumentAnalyzer`:
  - Input: image (or local URL) + optional hints.
  - Output:
    - Combined OCR text (from Vision + Gemini + OpenAI).
    - Document type classification.
    - Candidate structured fields (policy_number, member_name, provider_name, etc.).
    - Extracted entities: people, organizations, contact info, etc.
    - Face clusters / IDs for linking with Person records.

- `LinkingEngine`:
  - Input: extracted entities + face clusters + existing database of people/documents.
  - Output:
    - Suggested `Person` matches with confidence scores.
    - Suggested links: (document ↔ person) with relation types (owner, dependent, etc.).
  - Logic:
    - Match by names, emails, phones, addresses.
    - Match by overlapping face clusters.
    - Allow user confirmation to avoid auto-linking mistakes.

- `SemanticSearchEngine` (critical; see next section).

Make sure to encapsulate calls to Gemini and OpenAI behind protocol-based services so they can be swapped/mocked in tests.

## Search & Matching (CRITICAL)

Think very carefully about search and matching. We want robust support for:

1. **Keyword-based search** (fast, deterministic).
2. **Natural language search** (semantic, fuzzy).
3. **Hybrid search** that blends both.

Design a search subsystem that includes:

### Data to index

For each `Document`:
- OCR text.
- Structured fields (e.g., policy number, member name, provider).
- Document type (insurance_card, id_card, receipt, generic, etc.).
- Linked people.
- Metadata: createdAt, capture date, location, tags.

For each `Person`:
- Name and aliases.
- Emails, phones, addresses.
- Linked documents and their types.
- Optional face cluster IDs.

### Keyword search

- Maintain a simple **inverted index** or use CoreData queries plus derived/search tables for:
  - Tokenized OCR text.
  - Field values.
  - Person names and aliases.
- Implement text normalization (lowercasing, removing punctuation, basic stemming or not depending on complexity).
- Queries like:
  - “RxBIN 010101”
  - “policy 123456”
  - “Blue Cross”
  should be quick and accurate using keyword + field filters.

### Embedding-based semantic search

- Use embeddings for both:
  - Documents and persons.
  - User queries.

**Design requirements:**

- For each `Document`, precompute one or more embedding vectors using a cloud model:
  - This can be via Gemini embedding API or OpenAI embeddings (pick one as primary and one as backup; or choose one and explain why).
  - Embedding input should include:
    - OCR text.
    - Important structured fields (e.g., “Document type: insurance card. Policy holder: John Smith. Provider: Blue Shield.”).
- For each `Person`, compute an embedding from their:
  - Name and aliases.
  - Notes.
  - Short textual summary based on their linked documents (“John Smith, has health insurance, dental insurance, etc.”).

- For **queries**, compute embeddings on the fly:
  - Example queries:
    - “John’s insurance card”
    - “my dental coverage”
    - “receipts from Boston trip”
  - Use the same embedding model and compare via cosine similarity.

### Hybrid ranking

- When a user searches:
  1. Parse the query text.
  2. Run:
     - Keyword search (inverted index / CoreData queries).
     - Embedding-based semantic search (ANN search over vectors; we can start with a simple brute-force cosine similarity implementation and optimize later).
  3. Combine the scores from both to produce a final ranking:
     - E.g., `finalScore = w_keyword * keywordScore + w_semantic * semanticScore`.
  4. Use filters inferred from the query:
     - “John’s insurance card”:
       - Likely Person filter = John.
       - Likely docType filter = insurance_card.
       - You can either:
         - Use a small LLM call to classify the query into (personName, docType, timeRange, location, etc.), OR
         - Start with simpler heuristics and later upgrade.

- Show how to implement this **hybrid search pipeline**:
  - Define Swift types for:
    - `SearchQuery`
    - `SearchResult`
    - `SearchScoreComponents`
  - Provide pseudocode and actual Swift code for:
    - Computing cosine similarity.
    - Ranking results.
    - Combining keyword + embedding scores.

### Matching & linking behaviors

- When adding a new document:
  - Use extracted person names + face clusters + embeddings to find candidate Persons:
    - Score candidates by:
      - Name similarity.
      - Shared phone/email.
      - Shared face cluster.
      - Embedding similarity between:
        - “short description of document” and “short description of person”.
  - Present suggestions to the user:
    - “This looks like it belongs to John Smith (95%). Link?”
  - Allow “Not this person” → create new person.

- Over time, the system should support queries like:
  - “John’s insurance card”
  - “Lydia’s vaccination record”
  - “documents from last November in Seattle”
  even if these phrases don’t literally appear in the OCR text, relying on:
  - Document type classification.
  - Person–document links.
  - Metadata (dates, locations).
  - Embeddings.

## Data Modeling

Propose and implement a clean data model, for example:

- `Person`
  - id
  - fullName
  - aliases
  - emails
  - phones
  - notes
  - faceClusterIds (for Vision-based face grouping)
  - embeddingVector (for semantic search, e.g., `[Float]` stored in a blob)

- `Document`
  - id
  - createdAt
  - capturedAt
  - originalImageURL / blob
  - thumbnail
  - ocrText
  - docType (enum/string: insurance_card, id_card, receipt, bill, generic, etc.)
  - rawMetadata (JSON: EXIF, GPS, etc.)
  - location (optional, normalized)
  - embeddingVector (for semantic search)

- `Field`
  - id
  - documentId
  - key (e.g., "policy_number", "member_name", "provider_name", "rx_bin")
  - value (string)
  - confidenceScore (float)
  - source (vision/gemini/openai/merged)

- `PersonDocumentLink`
  - personId
  - documentId
  - relationType (owner, dependent, spouse, child, etc.)

Refine the schema as needed, but justify the choices and show CoreData entities or alternative persistence models.

## Core use cases / flows

Design and implement the app and code with these flows:

1. Capture / Upload
2. Extraction & Structuring (multi-source OCR + Gemini + OpenAI backup)
3. Linking & Grouping (using people + face clusters)
4. Search & Retrieval (keyword + embedding-based hybrid)
5. Detail View & Editing
6. People & Entity Management

(See above for detailed behavior for each.)

## UI / UX

Design a clean, opinionated SwiftUI UI:

- Tab bar: e.g. “Home”, “People”, “Search”, “Settings”.
- “Home”:
  - Quick actions: Scan Document, Upload Photo.
  - Recent documents list/grid with thumbnails and tags.
- “Search”:
  - Search bar that accepts both short keywords and natural language queries.
  - Optional filters: People, Document type, Date ranges, Locations.
  - Results list showing thumbnails, title/summary, type, and linked person.
- Detail screens:
  - Document detail: image, extracted text, structured fields, linked people, metadata.
  - Person detail: profile info, linked documents grouped by type.
- Provide clear loading/error states for:
  - OCR and AI processing.
  - Network failures.
  - Partial results (e.g., local OCR done, cloud OCR still pending).

## Implementation style

When responding:

1. Start by summarizing the architecture you recommend (layers, main modules, data flow), highlighting:
   - Multi-source OCR pipeline (Vision + Gemini + OpenAI backup).
   - Intelligence layer (DocumentAnalyzer, LinkingEngine, SemanticSearchEngine).
   - Search subsystem (keyword + embedding + hybrid ranking).

2. Propose the data model and show actual Swift models:
   - CoreData entities or plain structs + persistence layer.
   - Include fields for embeddings as stored vectors.

3. Show the main SwiftUI view hierarchy and navigation structure.

4. Provide concrete code examples for:
   - Using VisionKit / document scanner.
   - Running Vision OCR.
   - Calling Gemini for OCR/entity extraction and merging results.
   - Calling OpenAI as backup and merging.
   - Parsing/normalizing OCR results into structured fields.
   - Linking documents to people (including face cluster-based matching).
   - Implementing keyword search over CoreData.
   - Implementing a basic embedding-based semantic search and hybrid ranking in Swift.

5. Use production-oriented patterns:
   - MVVM or similar.
   - Dependency injection for AI/Intelligence services.
   - Testable components for parsing, fusion, linking, and search logic.

6. Make reasonable assumptions where necessary, and clearly state them before showing code.

Ask clarifying questions only if absolutely necessary; otherwise, assume sensible defaults and move forward with a concrete, implementation-oriented answer.

