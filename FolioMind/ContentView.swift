//
//  ContentView.swift
//  FolioMind
//
//  Created by Jay Zeng on 11/23/25.
//

import SwiftUI
import SwiftData
import PhotosUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var services: AppServices
    @Query(sort: \Document.createdAt, order: .reverse) private var documents: [Document]
    @State private var stubCounter: Int = 1
    @State private var searchText: String = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching: Bool = false
    @State private var isImporting: Bool = false
    @State private var isScanning: Bool = false
    @State private var showScanner: Bool = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var errorMessage: String?

    private var scannerAvailable: Bool {
        DocumentScannerView.isAvailable
    }

    private var showingSearchResults: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if isSearching {
                    ProgressView("Searching…")
                }

                if isImporting {
                    Label("Importing document…", systemImage: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                }

                if isScanning {
                    Label("Scanning document…", systemImage: "doc.viewfinder")
                        .foregroundStyle(.secondary)
                }

                if showingSearchResults {
                    if searchResults.isEmpty && !isSearching {
                        Text("No results for \"\(searchText)\"")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(searchResults, id: \.document.id) { result in
                            NavigationLink {
                                DocumentDetailView(document: result.document)
                            } label: {
                                DocumentRow(document: result.document, score: result.score)
                            }
                        }
                    }
                } else {
                    ForEach(documents, id: \.id) { document in
                        NavigationLink {
                            DocumentDetailView(document: document)
                        } label: {
                            DocumentRow(document: document, score: nil)
                        }
                    }
                    .onDelete { offsets in
                        services.documentStore.delete(at: offsets, from: documents, in: modelContext)
                    }
                }
            }
            .navigationTitle("FolioMind")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: addStubDocument) {
                        Label("Add Document", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addDocumentButton")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        Label("Import", systemImage: "photo")
                    }
                    .disabled(isImporting)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        if scannerAvailable {
                            showScanner = true
                        } else {
                            errorMessage = "Document scanning is unavailable on this device."
                        }
                    } label: {
                        Label("Scan", systemImage: "doc.viewfinder")
                    }
                    .disabled(isScanning || !scannerAvailable)
                }
            }
            .searchable(text: $searchText, prompt: "Search documents")
            .onChange(of: searchText) { _, newValue in
                Task { await performSearch(text: newValue) }
            }
            .onChange(of: photoPickerItem) { _, newItem in
                Task { await importSelectedPhoto(newItem) }
            }
            .sheet(isPresented: $showScanner) {
                DocumentScannerView {
                    urls in Task { try? await ingestURLs(urls) }
                } onCancel: {
                    showScanner = false
                } onError: { error in
                    showScanner = false
                    errorMessage = error.localizedDescription
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
                Button("OK") { errorMessage = nil }
            }, message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            })
        }
    }

    private func addStubDocument() {
        let titleSuffix = stubCounter
        stubCounter += 1
        Task {
            do {
                _ = try await services.documentStore.createStubDocument(in: modelContext, titleSuffix: titleSuffix)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func importSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isImporting = true
        defer { isImporting = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Unable to load selected image."
                return
            }
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            try data.write(to: tempURL)
            let title = item.itemIdentifier ?? tempURL.deletingPathExtension().lastPathComponent
            try await ingestURLs([tempURL], preferredTitle: title)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func ingestURLs(_ urls: [URL], preferredTitle: String? = nil) async throws {
        guard !urls.isEmpty else { return }
        isScanning = true
        defer {
            isScanning = false
            showScanner = false
        }
        let baseTitle = preferredTitle ?? urls.first!.deletingPathExtension().lastPathComponent
        do {
            _ = try await services.documentStore.ingestDocuments(
                from: urls,
                hints: DocumentHints(suggestedType: .generic, personName: nil),
                title: baseTitle,
                location: nil,
                capturedAt: Date(),
                in: modelContext
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func performSearch(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        do {
            let results = try await services.searchEngine.search(SearchQuery(text: trimmed))
            searchResults = results
            isSearching = false
        } catch {
            isSearching = false
            errorMessage = error.localizedDescription
        }
    }
}

struct DocumentRow: View {
    let document: Document
    let score: SearchScoreComponents?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.title)
                .font(.headline)
            Text(document.createdAt, format: Date.FormatStyle(date: .numeric, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !document.ocrText.isEmpty {
                Text(document.ocrText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let score {
                Text("Keyword \(String(format: "%.2f", score.keyword)), Semantic \(String(format: "%.2f", score.semantic))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DocumentDetailView: View {
    let document: Document

    var body: some View {
        Form {
            Section("Document") {
                LabeledContent("Type", value: document.docType.rawValue)
                if let capturedAt = document.capturedAt {
                    LabeledContent("Captured", value: capturedAt.formatted(date: .numeric, time: .shortened))
                }
                if let location = document.location {
                    LabeledContent("Location", value: location)
                }
                if let assetURL = document.assetURL {
                    LabeledContent("Asset URL", value: assetURL)
                }
            }

            Section("Fields") {
                if document.fields.isEmpty {
                    Text("No fields yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(document.fields, id: \.id) { field in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.key)
                                .font(.subheadline)
                            Text(field.value)
                                .font(.body)
                            Text("\(field.source.rawValue) • \(Int(field.confidence * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("OCR") {
                Text(document.ocrText.isEmpty ? "No OCR text yet" : document.ocrText)
                    .font(.body)
            }
        }
        .navigationTitle(document.title)
    }
}

#Preview {
    let services = AppServices()
    ContentView()
        .environmentObject(services)
        .modelContainer(services.modelContainer)
}
