# Step 2 – Capture & Ingestion

Goal: let users import or scan documents and produce structured records automatically.

- Implement Photos import via `PhotosPicker` and VisionKit scan (`VNDocumentCameraViewController`) with availability gating and clear failure messaging.
- For each page set, run OCR (Vision/VisionKit), detect faces, extract fields via `FieldExtractor`, optionally merge `IntelligentFieldExtractor` (LLM) results, and classify with `DocumentTypeClassifier` (creditCard/insuranceCard/idCard/letter/billStatement/receipt/generic).
- Construct one `Document` per ingest with combined OCR text, merged fields, ordered assets per page, face cluster IDs, cleaned text when LLM is available, and default titles derived from hints/file names.
- Generate embeddings via `SimpleEmbeddingService`, attach to the document, and persist through `DocumentStore.ingestDocuments`; ensure multi-page ordering and asset URL handling stay consistent.
