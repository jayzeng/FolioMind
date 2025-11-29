# Step 5 – Reminders, People, and Sharing Futures

Goal: layer follow-up and linking while keeping hooks ready for expansion.

- Use `ReminderManager` for permission handling and create/delete/complete flows; surface reminder suggestions from document type/fields in detail view with room for visible tracking states.
- Expand people linking: show the "Belongs To" card using `Person`/`DocumentPersonLink`/`FaceCluster`, and prepare selection/creation flows consistent with the current `BasicLinkingEngine` stub.
- Decide on share/export payload (images + cleaned text + fields) and destinations (ShareSheet/Files/PDF); keep the current share UI wired to future implementation.
- Add cloud/LLM configuration affordances (API key input, Apple Intelligence toggle) and attachment roadmap (PDF ingest, page ordering controls) while keeping secrets out of commits.
