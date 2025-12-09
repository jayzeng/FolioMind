//
//  EmbeddingMigrationView.swift
//  FolioMind
//
//  UI for managing embedding migration to new vector search system.
//

import SwiftUI

struct EmbeddingMigrationView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var services: AppServices

    @State private var migrationProgress: EmbeddingMigrationService.MigrationProgress?
    @State private var isMigrating = false
    @State private var migrationError: Error?
    @State private var migrationStats: EmbeddingMigrationService.MigrationStats?
    @State private var showCompletionAlert = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Vector Search Upgrade")
                        .font(.headline)

                    Text("Upgrade your documents to use Apple's on-device embeddings for improved semantic search quality.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let stats = migrationStats {
                        HStack {
                            Label("\(stats.total)", systemImage: "doc.text")
                            Spacer()
                            Label("\(stats.migrated)", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Spacer()
                            Label("\(stats.pending)", systemImage: "clock")
                                .foregroundColor(.orange)
                        }
                        .font(.caption)
                        .padding(.vertical, 8)
                        .padding(.horizontal)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                }
            }

            Section {
                if isMigrating {
                    migrationProgressView
                } else {
                    Button(action: startMigration) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text(migrationStats?.pending ?? 0 > 0 ? "Start Migration" : "Re-migrate All")
                        }
                    }
                    .disabled(isMigrating)
                }
            } header: {
                Text("Migration")
            } footer: {
                if let error = migrationError {
                    Text("Error: \(error.localizedDescription)")
                        .foregroundColor(.red)
                } else if migrationStats?.pending == 0 && migrationStats?.migrated ?? 0 > 0 {
                    Text("All documents have been migrated to the new vector search system.")
                        .foregroundColor(.green)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(
                        title: "Embedding Model",
                        value: "Apple NLEmbedding"
                    )
                    InfoRow(
                        title: "Vector Dimensions",
                        value: "768D"
                    )
                    InfoRow(
                        title: "Storage",
                        value: "LibSQL (On-device)"
                    )
                    InfoRow(
                        title: "Privacy",
                        value: "100% On-device"
                    )
                }
            } header: {
                Text("Technical Details")
            }
        }
        .navigationTitle("Search Upgrade")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMigrationStats()
        }
        .alert("Migration Complete", isPresented: $showCompletionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let progress = migrationProgress {
                Text("Successfully migrated \(progress.processedDocuments) documents with \(progress.failedDocuments) failures.")
            }
        }
    }

    @ViewBuilder
    private var migrationProgressView: some View {
        VStack(spacing: 12) {
            if let progress = migrationProgress {
                HStack {
                    Text("Migrating...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(progress.processedDocuments)/\(progress.totalDocuments)")
                        .font(.caption)
                        .monospacedDigit()
                }

                ProgressView(value: progress.percentComplete)
                    .progressViewStyle(.linear)

                if let currentDoc = progress.currentDocument {
                    Text(currentDoc)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if progress.failedDocuments > 0 {
                    Label("\(progress.failedDocuments) failed", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else {
                ProgressView()
            }
        }
        .padding(.vertical, 8)
    }

    private func startMigration() {
        guard let libSQLStore = services.libSQLStore else {
            migrationError = NSError(
                domain: "EmbeddingMigration",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "LibSQL store not available"]
            )
            return
        }

        isMigrating = true
        migrationError = nil
        migrationProgress = nil

        Task {
            let migrationService = EmbeddingMigrationService(
                modelContext: modelContext,
                embeddingService: services.embeddingService,
                vectorStore: libSQLStore,
                batchSize: 10
            )

            do {
                for try await progress in migrationService.migrateAllDocuments() {
                    await MainActor.run {
                        migrationProgress = progress
                    }
                }

                // Migration complete
                await MainActor.run {
                    isMigrating = false
                    showCompletionAlert = true
                }

                await loadMigrationStats()

            } catch {
                await MainActor.run {
                    isMigrating = false
                    migrationError = error
                }
            }
        }
    }

    private func loadMigrationStats() async {
        guard let libSQLStore = services.libSQLStore else { return }

        let migrationService = EmbeddingMigrationService(
            modelContext: modelContext,
            embeddingService: services.embeddingService,
            vectorStore: libSQLStore
        )

        do {
            let stats = try migrationService.getMigrationStats()
            await MainActor.run {
                migrationStats = stats
            }
        } catch {
            print("Failed to load migration stats: \(error)")
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        EmbeddingMigrationView()
    }
}
