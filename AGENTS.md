# Repository Guidelines

## Project Structure & Module Organization
- `FolioMind/`: SwiftUI sources. `FolioMindApp.swift` wires the shared SwiftData `ModelContainer`; `ContentView.swift` hosts the navigation split view and list; `Item.swift` defines the persisted model; visuals live in `Assets.xcassets`.
- `FolioMindTests/`: unit tests using Swift’s `Testing` package.
- `FolioMindUITests/`: UI and launch performance tests using XCTest.
- `Docs/`: repo documentation (e.g., `SPEA.md`); place new guides here.

## Build, Test, and Development Commands
- `open FolioMind.xcodeproj` — develop with Xcode; target `FolioMind`.
- `xcodebuild -scheme FolioMind -destination 'platform=iOS Simulator,name=iPhone 15' clean build` — CI-friendly build.
- `xcodebuild test -scheme FolioMind -destination 'platform=iOS Simulator,name=iPhone 15'` — run unit + UI tests; add `-enableCodeCoverage YES` when measuring coverage.
- Prefer Simulator runs; if adding scripts, keep them idempotent and pinned to a scheme/destination.

## Coding Style & Naming Conventions
- Swift 5.9+ with SwiftData; keep View types as `struct`s, data models with `@Model`, and data access via `@Query`/`@Environment(\.modelContext)`.
- Indent with 4 spaces; keep lines readable (~120 cols); one primary type per file.
- UpperCamelCase for types and protocols; lowerCamelCase for vars/functions; suffix views with `View`, models with clear nouns.
- Avoid force unwraps; prefer `guard` for early exits and `Task` for async UI work.

## Testing Guidelines
- Unit tests live in `FolioMindTests` with `@Test` and `#expect`; mirror feature names (e.g., `ItemListTests.swift`).
- UI flows in `FolioMindUITests`; prefix methods with `test…` and keep launch/setup code reusable.
- Reset or stub SwiftData state per test; add coverage for new user-visible behaviors, navigation paths, and persistence changes.

## Commit & Pull Request Guidelines
- Commit messages: imperative, concise (e.g., `Add item deletion animation`). Keep logical scopes small.
- PRs should include a short purpose statement, screenshots for UI changes, tests/commands run, and linked issues/tasks.
- Keep diffs tight, update docs/tests alongside feature code, and note any migration impacts when touching `Item` or storage.

## Architecture Overview
- Single-scene SwiftUI app with a `NavigationSplitView` listing persisted `Item` timestamps.
- Shared SwiftData `ModelContainer` configured in `FolioMindApp`; storage is on-device by default—plan migrations before altering the schema.
