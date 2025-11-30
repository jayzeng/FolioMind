//
//  ContentView.swift
//  FolioMind
//
//  Created by Jay Zeng on 11/23/25.
//

import SwiftUI
import SwiftData
import PhotosUI
import Combine
import AVFoundation

/// Shared glassy card used across list and detail screens for a softer look.
struct SurfaceCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground).opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, y: 6)
    }
}

struct PillBadge: View {
    let text: String
    let icon: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.14))
        )
        .foregroundStyle(tint)
    }
}

private enum SpotlightKind: String {
    case person
    case location

    var accentColor: Color {
        switch self {
        case .person: return .blue
        case .location: return .pink
        }
    }

    var symbolName: String {
        switch self {
        case .person: return "person.crop.circle.fill"
        case .location: return "mappin.circle.fill"
        }
    }
}

private struct SpotlightSummary: Identifiable, Hashable {
    let id: String
    let kind: SpotlightKind
    let displayName: String
    let normalizedValue: String
    var documentIDs: Set<UUID>

    var documentCount: Int { documentIDs.count }

    init(kind: SpotlightKind, displayName: String, normalizedValue: String, documentIDs: Set<UUID>) {
        self.kind = kind
        self.displayName = displayName
        self.normalizedValue = normalizedValue
        self.documentIDs = documentIDs
        self.id = "\(kind.rawValue):\(normalizedValue)"
    }

    var initials: String {
        let parts = displayName.split(separator: " ").map(String.init)
        let first = parts.first?.prefix(1) ?? "?"
        let last = parts.dropFirst().first?.prefix(1)
        return String(first + (last ?? ""))
    }
}

extension DocumentType {
    var symbolName: String {
        switch self {
        case .creditCard: "creditcard.fill"
        case .insuranceCard: "cross.vial.fill"
        case .idCard: "person.crop.rectangle"
        case .letter: "envelope.open.fill"
        case .billStatement: "doc.text.below.ecg"
        case .receipt: "scroll.fill"
        case .generic: "doc.richtext.fill"
        }
    }

    var accentGradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .creditCard:
            colors = [Color(hue: 0.34, saturation: 0.68, brightness: 0.66), Color(hue: 0.37, saturation: 0.75, brightness: 0.52)]
        case .insuranceCard:
            colors = [Color(hue: 0.57, saturation: 0.45, brightness: 0.72), Color(hue: 0.55, saturation: 0.55, brightness: 0.54)]
        case .idCard:
            colors = [Color(hue: 0.62, saturation: 0.52, brightness: 0.66), Color(hue: 0.58, saturation: 0.58, brightness: 0.52)]
        case .letter:
            colors = [Color(hue: 0.54, saturation: 0.3, brightness: 0.82), Color(hue: 0.54, saturation: 0.35, brightness: 0.62)]
        case .billStatement:
            colors = [Color(hue: 0.1, saturation: 0.45, brightness: 0.8), Color(hue: 0.08, saturation: 0.55, brightness: 0.62)]
        case .receipt:
            colors = [Color(hue: 0.97, saturation: 0.52, brightness: 0.86), Color(hue: 0.95, saturation: 0.6, brightness: 0.64)]
        case .generic:
            colors = [Color(hue: 0.6, saturation: 0.2, brightness: 0.84), Color(hue: 0.64, saturation: 0.18, brightness: 0.68)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var accentColor: Color {
        switch self {
        case .creditCard: Color(hue: 0.35, saturation: 0.68, brightness: 0.64)
        case .insuranceCard: Color(hue: 0.56, saturation: 0.52, brightness: 0.64)
        case .idCard: Color(hue: 0.6, saturation: 0.58, brightness: 0.62)
        case .letter: Color(hue: 0.55, saturation: 0.34, brightness: 0.68)
        case .billStatement: Color(hue: 0.1, saturation: 0.54, brightness: 0.72)
        case .receipt: Color(hue: 0.95, saturation: 0.55, brightness: 0.74)
        case .generic: Color(hue: 0.62, saturation: 0.22, brightness: 0.76)
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var services: AppServices
    @Query(sort: \Document.createdAt, order: .reverse) private var documents: [Document]
    @Query(sort: \AudioNote.createdAt, order: .reverse) private var audioNotes: [AudioNote]
    @State private var searchText: String = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching: Bool = false
    @State private var isImporting: Bool = false
    @State private var isScanning: Bool = false
    @State private var isRecordingAudio: Bool = false
    @State private var showScanner: Bool = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var documentToEdit: Document?
    @State private var documentToDelete: Document?
    @State private var showDeleteConfirmation: Bool = false
    @State private var showSettings: Bool = false
    @State private var statusNotice: StatusNotice?
    @State private var selectedSpotlightID: String?
    @State private var noteToShow: AudioNote?

    private var scannerAvailable: Bool {
        DocumentScannerView.isAvailable
    }

    private var showingSearchResults: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var spotlightSummaries: [SpotlightSummary] {
        var summaries: [String: SpotlightSummary] = [:]

        for document in documents {
            let names = personNames(for: document)
            for name in names {
                let normalized = normalizedLabel(name)
                guard !normalized.isEmpty else { continue }
                let id = "person:\(normalized)"

                if var existing = summaries[id] {
                    existing.documentIDs.insert(document.id)
                    summaries[id] = existing
                } else {
                    summaries[id] = SpotlightSummary(
                        kind: .person,
                        displayName: name,
                        normalizedValue: normalized,
                        documentIDs: [document.id]
                    )
                }
            }

            if let location = cleanedLocation(document.location) {
                let normalized = normalizedLabel(location)
                guard !normalized.isEmpty else { continue }
                let id = "location:\(normalized)"

                if var existing = summaries[id] {
                    existing.documentIDs.insert(document.id)
                    summaries[id] = existing
                } else {
                    summaries[id] = SpotlightSummary(
                        kind: .location,
                        displayName: location,
                        normalizedValue: normalized,
                        documentIDs: [document.id]
                    )
                }
            }
        }

        return summaries.values.sorted {
            if $0.documentCount == $1.documentCount {
                if $0.kind == $1.kind {
                    return $0.displayName < $1.displayName
                }
                return $0.kind.rawValue < $1.kind.rawValue
            }
            return $0.documentCount > $1.documentCount
        }
    }

    private var selectedSpotlightName: String? {
        guard let selectedSpotlightID else { return nil }
        return spotlightSummaries.first(where: { $0.id == selectedSpotlightID })?.displayName
    }

    private var gridData: (documents: [Document], scores: [SearchScoreComponents]?) {
        if showingSearchResults {
            let filtered = searchResults.filter { documentMatchesSelectedSpotlight($0.document) }
            return (filtered.map(\.document), filtered.map(\.score))
        } else {
            let filtered = documents.filter { documentMatchesSelectedSpotlight($0) }
            return (filtered, nil)
        }
    }

    var body: some View {
        let currentGridData = gridData
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if let notice = statusNotice {
                        InlineStatusBanner(notice: notice)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else if isSearching || isImporting || isScanning || isRecordingAudio {
                        statusBanner
                    }

                    audioSection
                        .padding(.bottom, 10)

                    if !spotlightSummaries.isEmpty {
                        spotlightSection(spotlightSummaries)
                            .padding(.bottom, 10)
                    }

                    if showingSearchResults {
                        if currentGridData.documents.isEmpty && !isSearching {
                            emptySearchView
                        } else {
                            documentGrid(currentGridData.documents, scores: currentGridData.scores)
                        }
                    } else {
                        if documents.isEmpty {
                            emptyStateView
                        } else {
                            if currentGridData.documents.isEmpty {
                                filteredEmptyView
                            } else {
                                documentGrid(currentGridData.documents, scores: nil)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("FolioMind")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
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
            .onChange(of: spotlightSummaries) { _, updated in
                if let selectedSpotlightID, !updated.contains(where: { $0.id == selectedSpotlightID }) {
                    self.selectedSpotlightID = nil
                }
            }
            .onReceive(services.audioRecorder.$isRecording) { isRecording in
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.isRecordingAudio = isRecording
                }
            }
            .sheet(item: $noteToShow) { note in
                AudioNoteDetailView(
                    note: note,
                    onDelete: {
                        deleteAudioNote(note)
                        noteToShow = nil
                    },
                    onError: { message in
                        errorMessage = message
                    }
                )
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
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(item: $documentToEdit) { document in
                NavigationStack {
                    DocumentEditView(document: document)
                }
            }
            .alert("Delete Document", isPresented: $showDeleteConfirmation, presenting: documentToDelete, actions: { document in
                Button("Cancel", role: .cancel) {
                    documentToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    performDeletion()
                }
            }, message: { document in
                Text("Are you sure you want to delete \"\(document.title)\"? This action cannot be undone.")
            })
        .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: {
            if let errorMessage {
                Text(errorMessage)
                }
            })
        }
    }

    private var audioSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio Notes")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(audioNotes.isEmpty ? "No recordings yet" : "\(audioNotes.count) saved")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        toggleAudioRecording()
                    } label: {
                        Label(
                            isRecordingAudio ? "Stop" : "Record",
                            systemImage: isRecordingAudio ? "stop.circle.fill" : "mic.fill"
                        )
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isRecordingAudio ? .red : .blue)
                    .controlSize(.small)
                }

                if isRecordingAudio {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.path")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text("Recording… tap Stop when finished")
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }

                if audioNotes.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.circle")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Capture quick voice notes")
                                .font(.caption.weight(.semibold))
                            Text("Use the mic to add context or reminders.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                } else {
                    VStack(spacing: 8) {
                        ForEach(audioNotes) { note in
                            AudioNoteRow(
                                note: note,
                                onError: { message in
                                    errorMessage = message
                                },
                                onDelete: {
                                    deleteAudioNote(note)
                                },
                                onTap: {
                                    noteToShow = note
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var statusBanner: some View {
        VStack(spacing: 8) {
            if isSearching {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if isImporting {
                Label("Importing document…", systemImage: "arrow.down.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if isScanning {
                Label("Scanning document…", systemImage: "doc.viewfinder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if isRecordingAudio {
                Label("Recording audio…", systemImage: "waveform")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.bottom, 12)
    }

    private var emptySearchView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(searchEmptyTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var searchEmptyTitle: String {
        if let selectedSpotlightName {
            return "No results for \"\(searchText)\" with \(selectedSpotlightName)"
        }
        return "No results for \"\(searchText)\""
    }

    private var filteredEmptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No documents for this filter yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            if let selectedSpotlightName {
                Text("Try clearing the filter or adding a document for \(selectedSpotlightName)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("No Documents")
                    .font(.title2.weight(.semibold))
                Text("Import or scan documents to get started")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    @ViewBuilder
    private func spotlightSection(_ items: [SpotlightSummary]) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("People & Places")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(items.count) detected")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if selectedSpotlightID != nil {
                        Button {
                            selectedSpotlightID = nil
                        } label: {
                            Label("Clear", systemImage: "line.3.horizontal.decrease.circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            SpotlightChip(
                                item: item,
                                isSelected: selectedSpotlightID == item.id,
                                onTap: {
                                    if selectedSpotlightID == item.id {
                                        selectedSpotlightID = nil
                                    } else {
                                        selectedSpotlightID = item.id
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func documentGrid(_ documents: [Document], scores: [SearchScoreComponents]?) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ForEach(Array(documents.enumerated()), id: \.element.id) { index, document in
                NavigationLink {
                    DocumentDetailPageView(document: document, reminderManager: services.reminderManager)
                } label: {
                    DocumentGridCard(
                        document: document,
                        score: scores?[safe: index]
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .contextMenu {
                    Button {
                        editDocument(document)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Divider()

                    Button(role: .destructive) {
                        deleteDocument(document)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .padding(.bottom, 16)
    }

    @MainActor
    private func importSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isImporting = true
        showNotice(StatusNotice(
            title: "Importing photo…",
            subtitle: "Saving and analyzing",
            systemImage: "arrow.down.circle",
            tint: .blue,
            isProgress: true
        ))
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
            showNotice(StatusNotice(
                title: "Photo imported",
                subtitle: "Document created from \(title)",
                systemImage: "checkmark.circle.fill",
                tint: .green,
                isProgress: false
            ), autoHide: 2.5)
        } catch {
            errorMessage = error.localizedDescription
            showNotice(StatusNotice(
                title: "Import failed",
                subtitle: error.localizedDescription,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                isProgress: false
            ), autoHide: 3)
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
            showNotice(StatusNotice(
                title: "Processing \(urls.count) image(s)…",
                subtitle: "Running OCR, classification, embeddings",
                systemImage: "sparkles.rectangle.stack",
                tint: .blue,
                isProgress: true
            ))
            _ = try await services.documentStore.ingestDocuments(
                from: urls,
                hints: DocumentHints(suggestedType: .generic, personName: nil),
                title: baseTitle,
                in: modelContext
            )
            showNotice(StatusNotice(
                title: "Document ready",
                subtitle: "\"\(baseTitle)\" processed",
                systemImage: "checkmark.seal.fill",
                tint: .green,
                isProgress: false
            ), autoHide: 2.5)
        } catch {
            errorMessage = error.localizedDescription
            showNotice(StatusNotice(
                title: "Processing failed",
                subtitle: error.localizedDescription,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange,
                isProgress: false
            ), autoHide: 3)
        }
    }

    private func editDocument(_ document: Document) {
        documentToEdit = document
    }

    private func deleteDocument(_ document: Document) {
        documentToDelete = document
        showDeleteConfirmation = true
    }

    private func performDeletion() {
        guard let doc = documentToDelete else { return }

        // Delay deletion slightly to let SwiftUI finish any in-flight rendering
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            modelContext.delete(doc)
            try? modelContext.save()
            documentToDelete = nil
        }
    }

    @MainActor
    private func toggleAudioRecording() {
        Task { @MainActor in
            if isRecordingAudio {
                await finishAudioRecording()
            } else {
                await startAudioRecording()
            }
        }
    }

    @MainActor
    private func startAudioRecording() async {
        do {
            _ = try await services.audioRecorder.startRecording()
            withAnimation(.easeIn(duration: 0.2)) {
                isRecordingAudio = true
            }
        } catch {
            isRecordingAudio = false
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func finishAudioRecording() async {
        do {
            let result = try services.audioRecorder.stopRecording()
            let note = AudioNote(
                title: recordingTitle(from: result.startedAt),
                fileURL: result.url.path,
                createdAt: result.startedAt,
                duration: result.duration
            )
            modelContext.insert(note)
            try modelContext.save()
            withAnimation(.easeOut(duration: 0.2)) {
                isRecordingAudio = false
            }
            showNotice(StatusNotice(
                title: "Audio saved",
                subtitle: "Recording stored to your library",
                systemImage: "waveform.circle.fill",
                tint: .green,
                isProgress: false
            ), autoHide: 2.5)
        } catch {
            isRecordingAudio = false
            errorMessage = error.localizedDescription
        }
    }

    private func recordingTitle(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Recording \(formatter.string(from: date))"
    }

    private func deleteAudioNote(_ note: AudioNote) {
        do {
            let url = URL(fileURLWithPath: note.fileURL)
            modelContext.delete(note)
            try? FileManager.default.removeItem(at: url)
            try modelContext.save()
            showNotice(StatusNotice(
                title: "Recording deleted",
                subtitle: nil,
                systemImage: "trash.fill",
                tint: .red,
                isProgress: false
            ), autoHide: 2)
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

    private func personNames(for document: Document) -> [String] {
        var names: [String] = []

        let linkedNames = document.personLinks.compactMap { link in
            let trimmed = link.person?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        names.append(contentsOf: linkedNames)

        let nameKeys = ["member_name", "member", "cardholder", "holder", "insured", "patient"]
        let fieldNames = document.fields.compactMap { field -> String? in
            let key = field.key.lowercased()
            let isLikelyName = key.contains("name") || nameKeys.contains(where: { key.contains($0) })
            guard isLikelyName else { return nil }
            let trimmed = field.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        names.append(contentsOf: fieldNames)

        var seen = Set<String>()
        return names.compactMap { name in
            let normalized = normalizedLabel(name)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return name
        }
    }

    private func documentMatchesSelectedSpotlight(_ document: Document) -> Bool {
        guard
            let selectedSpotlightID,
            let filter = spotlightSummaries.first(where: { $0.id == selectedSpotlightID })
        else { return true }

        switch filter.kind {
        case .person:
            return personNames(for: document).contains { normalizedLabel($0) == filter.normalizedValue }
        case .location:
            guard let location = cleanedLocation(document.location) else { return false }
            return normalizedLabel(location) == filter.normalizedValue
        }
    }

    private func normalizedLabel(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    private func cleanedLocation(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func showNotice(_ notice: StatusNotice, autoHide: Double? = nil) {
        withAnimation(.spring(response: 0.3)) {
            statusNotice = notice
        }
        if let delay = autoHide {
            let noticeID = notice.id
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if self.statusNotice?.id == noticeID {
                    withAnimation(.easeOut(duration: 0.2)) {
                        self.statusNotice = nil
                    }
                }
            }
        }
    }
}

// MARK: - Audio Notes

private struct AudioNoteRow: View {
    let note: AudioNote
    let onError: (String) -> Void
    let onDelete: () -> Void
    let onTap: () -> Void

    @State private var isPlaying = false
    @State private var player: AVAudioPlayer?
    @State private var playbackProgress: Double = 0
    @State private var playbackTimer: Timer?
    private let playbackDelegate = PlaybackDelegate()

    private var durationText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = note.duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        formatter.unitsStyle = .short
        return formatter.string(from: note.duration) ?? "0:00"
    }

    private var timestampText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: note.createdAt, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .trim(from: 0, to: CGFloat(playbackProgress))
                        .stroke(isPlaying ? Color.green : Color.blue, lineWidth: 3)
                        .frame(width: 46, height: 46)
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .fill(isPlaying ? Color.green.opacity(0.16) : Color.blue.opacity(0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isPlaying ? Color.green : Color.blue)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(timestampText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(durationText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
        .onTapGesture(perform: onTap)
        .onDisappear {
            stopPlayback()
        }
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard FileManager.default.fileExists(atPath: note.fileURL) else {
            isPlaying = false
            onError("Recording file is missing.")
            return
        }

        do {
            let url = URL(fileURLWithPath: note.fileURL)
            playbackDelegate.onFinish = {
                DispatchQueue.main.async {
                    isPlaying = false
                    playbackProgress = 1
                    playbackTimer?.invalidate()
                    playbackTimer = nil
                }
            }
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = playbackDelegate
            player.prepareToPlay()
            player.play()
            self.player = player
            isPlaying = true
            startProgressTimer()
        } catch {
            isPlaying = false
            onError(error.localizedDescription)
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func startProgressTimer() {
        playbackTimer?.invalidate()
        guard let player else { return }
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            let progress = player.duration > 0 ? player.currentTime / player.duration : 0
            DispatchQueue.main.async {
                playbackProgress = progress
            }
        }
    }

    private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
        var onFinish: (() -> Void)?

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            onFinish?()
        }
    }
}

// MARK: - Audio Note Detail

private struct AudioNoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var services: AppServices

    let note: AudioNote
    let onDelete: () -> Void
    let onError: (String) -> Void

    @State private var transcript: String = ""
    @State private var summary: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var isPlaying = false
    @State private var player: AVAudioPlayer?
    @State private var playbackProgress: Double = 0
    @State private var playbackTimer: Timer?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let errorMessage {
                        InlineStatusBanner(notice: StatusNotice(
                            title: "Transcription failed",
                            subtitle: errorMessage,
                            systemImage: "exclamationmark.triangle.fill",
                            tint: .orange,
                            isProgress: false
                        ))
                    }

                    summaryCard
                    transcriptCard
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Audio Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button {
                            Task { await loadContent(force: true) }
                        } label: {
                            Label("Refresh summary", systemImage: "arrow.clockwise")
                        }

                        Button(role: .destructive) {
                            stopPlayback()
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Delete recording", systemImage: "trash")
                        }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .task { await loadContent(force: false) }
            .onDisappear {
                stopPlayback()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.title)
                .font(.headline)
            HStack(spacing: 12) {
                Label(note.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(durationText, systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                togglePlayback()
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .trim(from: 0, to: CGFloat(playbackProgress))
                            .stroke(isPlaying ? Color.green : Color.blue, lineWidth: 4)
                            .frame(width: 30, height: 30)
                            .rotationEffect(.degrees(-90))
                        Circle()
                            .fill(isPlaying ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                            .frame(width: 28, height: 28)
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isPlaying ? .green : .blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isPlaying ? "Pause" : "Play recording")
                            .font(.subheadline.weight(.semibold))
                        Text(durationText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var summaryCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Summary", systemImage: "text.quote")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                if summary.isEmpty {
                    Text("We’ll summarize this note once transcription finishes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var transcriptCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Transcript", systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))

                if transcript.isEmpty {
                    Text("Transcription will appear here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(transcript)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var durationText: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = note.duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        formatter.unitsStyle = .short
        return formatter.string(from: note.duration) ?? "0:00"
    }

    @MainActor
    private func loadContent(force: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let transcriptText: String
            if force {
                // Clear cached values before reprocessing
                note.transcript = nil
                note.summary = nil
                try? modelContext.save()
                transcriptText = try await services.audioNoteManager.transcribeIfNeeded(note: note)
            } else {
                transcriptText = try await services.audioNoteManager.transcribeIfNeeded(note: note)
            }
            transcript = transcriptText

            let summaryText = try await services.audioNoteManager.summarizeIfNeeded(note: note, transcript: transcriptText)
            summary = summaryText
            try? modelContext.save()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            onError(error.localizedDescription)
        }
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard FileManager.default.fileExists(atPath: note.fileURL) else {
            onError("Recording file is missing.")
            return
        }
        do {
            let audioURL = URL(fileURLWithPath: note.fileURL)
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.delegate = DetailPlaybackDelegate { [self] in
                isPlaying = false
                self.player = nil
            }
            player.prepareToPlay()
            player.play()
            self.player = player
            isPlaying = true
        } catch {
            onError(error.localizedDescription)
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private final class DetailPlaybackDelegate: NSObject, AVAudioPlayerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            onFinish()
        }
    }

    private func startProgressTimer() {
        playbackTimer?.invalidate()
        guard let player else { return }
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            let progress = player.duration > 0 ? player.currentTime / player.duration : 0
            DispatchQueue.main.async {
                playbackProgress = progress
            }
        }
    }
}

// MARK: - Status Notice

struct StatusNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let isProgress: Bool
}

struct InlineStatusBanner: View {
    let notice: StatusNotice

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(notice.tint.opacity(0.15))
                    .frame(width: 34, height: 34)
                if notice.isProgress {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(notice.tint)
                } else {
                    Image(systemName: notice.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(notice.tint)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                if let subtitle = notice.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        )
        .padding(.horizontal, 2)
    }
}

private struct SpotlightChip: View {
    let item: SpotlightSummary
    let isSelected: Bool
    let onTap: () -> Void

    private var tint: Color { item.kind.accentColor }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isSelected ? tint.opacity(0.18) : Color(.tertiarySystemGroupedBackground))
                        .frame(width: 38, height: 38)
                    if item.kind == .person {
                        Text(item.initials.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isSelected ? tint : .secondary)
                    } else {
                        Image(systemName: item.kind.symbolName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isSelected ? tint : .secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(item.documentCount) document\(item.documentCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.12) : Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? tint : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct DocumentRow: View {
    let document: Document
    let score: SearchScoreComponents?

    private var createdDescription: String {
        document.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var previewSnippet: String? {
        let text = document.ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private var matchPercent: Int? {
        guard let score else { return nil }
        let weighted = (score.keyword * 0.6) + (score.semantic * 0.4)
        return Int((min(max(weighted, 0), 1) * 100).rounded())
    }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(document.docType.accentGradient)
                        Image(systemName: document.docType.symbolName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title)
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(createdDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    PillBadge(text: document.docType.displayName, icon: document.docType.symbolName, tint: document.docType.accentColor)
                }

                if let previewSnippet {
                    Text(previewSnippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Label(createdDescription, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let matchPercent {
                        PillBadge(text: "Match \(matchPercent)%", icon: "sparkles", tint: .orange)
                    } else if !document.ocrText.isEmpty {
                        PillBadge(text: "Processed", icon: "checkmark.circle.fill", tint: .green)
                    }
                }
            }
        }
        .listRowBackground(Color.clear)
    }
}

struct DocumentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var document: Document
    @State private var showFullOCR: Bool = false

    private var processed: Bool {
        !document.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !document.fields.isEmpty
    }

    private var hasHighlights: Bool {
        switch document.docType {
        case .creditCard, .insuranceCard, .letter, .billStatement:
            return true
        default:
            return false
        }
    }

    private var statusTitle: String {
        processed ? "Processed" : "Awaiting Analysis"
    }

    private var statusSubtitle: String {
        processed ? "Multi-pass extraction completed" : "Import or scan to unlock highlights"
    }

    private var statusIcon: String {
        processed ? "checkmark.circle.fill" : "hourglass.circle.fill"
    }

    private var statusTint: Color {
        processed ? .green : .orange
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DocumentHeroCard(document: document)
                DocumentStatusCard(
                    title: statusTitle,
                    subtitle: statusSubtitle,
                    icon: statusIcon,
                    tint: statusTint,
                    docType: document.docType
                )
                BelongsToCard(document: document)
                ExtractedDataCard(document: document)
                if hasHighlights {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Smart Highlights")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            DocumentHighlightsView(document: document)
                        }
                    }
                }
                DocumentMetadataCard(document: document)
                OCRCard(text: document.ocrText, showFull: $showFullOCR)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DocumentHeroCard: View {
    let document: Document

    private var capturedDescription: String {
        if let capturedAt = document.capturedAt {
            return capturedAt.formatted(date: .abbreviated, time: .shortened)
        }
        return document.createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var imageURL: URL? {
        guard let assetURLString = document.assetURL else { return nil }
        return URL(fileURLWithPath: assetURLString)
    }

    private var hasImage: Bool {
        guard let url = imageURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    var body: some View {
        VStack(spacing: 0) {
            if hasImage {
                ZoomableImageView(imageURL: imageURL)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                placeholderCard
            }
        }
    }

    private var placeholderCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(document.docType.accentGradient)
                .frame(height: 210)
                .overlay(
                    LinearGradient(
                        colors: [.black.opacity(0.08), .black.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Text(document.docType.displayName.uppercased())
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.2))
                        )
                        .foregroundStyle(.white)
                        .padding(14)
                }

            VStack(alignment: .leading, spacing: 12) {
                Text("Front")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(Color.white.opacity(0.18)))
                    .foregroundStyle(.white)

                Text(document.title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    Label(document.docType.displayName, systemImage: document.docType.symbolName)
                    Label(capturedDescription, systemImage: "clock")
                }
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
            }
            .padding(20)
        }
    }
}

private struct DocumentStatusCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let docType: DocumentType

    var body: some View {
        SurfaceCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.16))
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("Type")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(docType.displayName)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}

private struct BelongsToCard: View {
    let document: Document

    private var primaryLink: DocumentPersonLink? {
        document.personLinks.first
    }

    private var name: String {
        primaryLink?.person?.displayName ?? "Unassigned"
    }

    private var relationship: String {
        if let relationship = primaryLink?.relationship {
            return relationship.displayName
        }
        return "Self"
    }

    private var initials: String {
        let components = name.split(separator: " ")
        let first = components.first?.prefix(1) ?? "U"
        let last = components.dropFirst().first?.prefix(1)
        return String(first + (last ?? ""))
    }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Belongs To")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(document.docType.accentGradient)
                            .frame(width: 46, height: 46)
                        Text(initials.uppercased())
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(.body.weight(.semibold))
                        Text(relationship)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct ExtractedDataCard: View {
    let document: Document

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Extracted Data")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(document.fields.isEmpty ? "Waiting for analysis" : "AI fused fields")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    PillBadge(
                        text: "\(document.fields.count) fields",
                        icon: "doc.text.viewfinder",
                        tint: document.docType.accentColor
                    )
                }

                if document.fields.isEmpty {
                    Label("No fields yet", systemImage: "sparkles")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(document.fields.enumerated()), id: \.element.id) { index, field in
                        if index > 0 {
                            Divider()
                        }
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field.key.capitalized)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(field.value)
                                    .font(.body.weight(.semibold))
                            }
                            Spacer()
                            PillBadge(
                                text: "\(Int(field.confidence * 100))%",
                                icon: "sparkles",
                                tint: .blue
                            )
                        }
                    }
                }

                Text("Data fused from on-device and cloud models.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DocumentMetadataCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var document: Document

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Metadata")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Document Type", selection: $document.docType) {
                    ForEach(DocumentType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: document.docType) { _, _ in
                    try? modelContext.save()
                }

                if let capturedAt = document.capturedAt {
                    MetadataRow(icon: "calendar", title: "Captured", value: capturedAt.formatted(date: .abbreviated, time: .shortened))
                }

                MetadataRow(icon: "clock.arrow.circlepath", title: "Created", value: document.createdAt.formatted(date: .abbreviated, time: .shortened))

                if let location = document.location {
                    MetadataRow(icon: "mappin.and.ellipse", title: "Location", value: location)
                }

                if let assetURL = document.assetURL {
                    MetadataRow(icon: "photo", title: "Asset", value: assetURL)
                }
            }
        }
    }
}

private struct MetadataRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
    }
}

private struct OCRCard: View {
    let text: String
    @Binding var showFull: Bool

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Raw OCR Text")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("View the extracted text as plain text")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    if !text.isEmpty {
                        Button(showFull ? "Collapse" : "Expand") {
                            withAnimation(.easeInOut) {
                                showFull.toggle()
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                    }
                }

                if text.isEmpty {
                    Label("No OCR text yet", systemImage: "text.viewfinder")
                        .foregroundStyle(.secondary)
                } else {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(showFull ? nil : 4)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

#Preview {
    let services = AppServices()
    ContentView()
        .environmentObject(services)
        .modelContainer(services.modelContainer)
}
