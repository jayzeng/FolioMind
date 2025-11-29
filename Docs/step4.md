# Step 4 – Search & Intelligence

Goal: deliver reliable recall with hybrid scoring and cleaned text.

- Wire the search bar in `ContentView` to `HybridSearchEngine` with live updates, fetching documents sorted by `createdAt` before ranking.
- Implement keyword scoring (title + OCR token containment) and semantic scoring (cosine between query embedding and document embedding) with default weighting 0.6 keyword / 0.4 semantic; surface match percent badges and empty-search states.
- Ensure `SimpleEmbeddingService` produces deterministic vectors offline; regenerate embeddings during ingest and when cleaned text changes.
- When LLM is available, clean OCR text and merge intelligent fields without blocking UI; fall back to heuristic paths gracefully.
