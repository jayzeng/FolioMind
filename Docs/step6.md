# Step 6 – Quality, Performance, and Testing

Goal: keep the app robust, offline-capable, and measurable.

- Guarantee local-first behavior: operate when offline with on-device OCR/embeddings; gate scanner/LLM with graceful fallbacks and user messaging.
- Performance/resilience: keep ingestion/search off the main thread, handle missing asset files/URLs defensively, avoid force unwraps, and support multi-page ingest without UI stalls.
- Privacy/permissions: prompt for Photos/Camera/Scanner/Reminders/Calendar only when needed; store documents/embeddings locally and never ship API keys.
- Testing: add unit coverage (ingestion merges OCR, classifier/extractor accuracy, embedding ranking, reminder suggestions, card parsing) using the `Testing` package with an in-memory container; expand UI tests for launch/search/navigation and add a performance baseline.
- Analytics future: plan opt-in telemetry for ingestion success, search queries, reminder usage, and doc type distribution.
