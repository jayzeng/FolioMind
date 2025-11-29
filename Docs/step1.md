# Step 1 – Foundations & Data Layer

Goal: stand up SwiftData schema, DI, and storage so the app runs offline by default.

- Confirm `@Model` definitions for `Document`, `Asset`, `Field`, `FaceCluster`, `Person`, `Embedding`, `DocumentPersonLink`, `DocumentReminder`, including helpers like `assetURL`/`imageAssets`.
- Wire `AppServices` to build the full `ModelContainer` (dev-only reset on migration failure) and inject it plus `AppServices` via `FolioMindApp` environment.
- Ensure `DocumentStore` exposes `ingestDocuments`, `createStubDocument` for demo/testing, and `delete` helper; keep an in-memory configuration path for deterministic tests.
- Add a lightweight seed/dev toggle to confirm the UI renders from SwiftData without external services.
- Set up the `Testing` package harness with in-memory `ModelConfiguration` to validate save/delete and container wiring.
