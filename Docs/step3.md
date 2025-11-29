# Step 3 – Document Surfaces & Management

Goal: make browsing, viewing, and editing documents polished and reliable.

- Build `ContentView` NavigationStack grid (three-column adaptive) with SurfaceCard styling, type/match badges, empty states for no docs and empty search, plus import/scan status banners.
- Hook actions: edit opens `DocumentEditView` for title/type/location/timestamps, delete prompts confirmation then removes via `modelContext`, and add-images button lets users append assets.
- Flesh out `DocumentDetailPageView` tabs (Overview/Details/Text) with multi-asset hero (zoom, pagination indicator, thumbnail strip, full-screen viewer), highlights per doc type (`DocumentHighlightsView`), and metadata display including asset URL and captured/created times.
- Show extracted fields with chips/confidence badges and OCR text with expand/collapse; keep the share menu hook visible even if payload is stubbed.
