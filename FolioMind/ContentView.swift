//
//  ContentView.swift
//  FolioMind
//
//  Created by Jay Zeng on 11/23/25.
//

import SwiftUI
import SwiftData
import PhotosUI

/// Shared glassy card used across list and detail screens for a softer look.
struct SurfaceCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground).opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 14, y: 8)
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

extension DocumentType {
    var displayName: String {
        switch self {
        case .creditCard: "Credit Card"
        case .insuranceCard: "Insurance"
        case .idCard: "ID Card"
        case .letter: "Letter"
        case .billStatement: "Statement"
        case .receipt: "Receipt"
        case .generic: "Document"
        }
    }

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
    @State private var searchText: String = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching: Bool = false
    @State private var isImporting: Bool = false
    @State private var isScanning: Bool = false
    @State private var showScanner: Bool = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var documentToEdit: Document?
    @State private var documentToDelete: Document?
    @State private var showDeleteConfirmation: Bool = false

    private var scannerAvailable: Bool {
        DocumentScannerView.isAvailable
    }

    private var showingSearchResults: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if isSearching || isImporting || isScanning {
                        statusBanner
                    }

                    if showingSearchResults {
                        if searchResults.isEmpty && !isSearching {
                            emptySearchView
                        } else {
                            documentGrid(searchResults.map { $0.document }, scores: searchResults.map { $0.score })
                        }
                    } else {
                        if documents.isEmpty {
                            emptyStateView
                        } else {
                            documentGrid(documents, scores: nil)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("FolioMind")
            .toolbar {
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
                    if let doc = documentToDelete {
                        modelContext.delete(doc)
                        try? modelContext.save()
                        documentToDelete = nil
                    }
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
            Text("No results for \"\(searchText)\"")
                .font(.headline)
                .foregroundStyle(.secondary)
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
    private func documentGrid(_ documents: [Document], scores: [SearchScoreComponents]?) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            ForEach(Array(documents.enumerated()), id: \.element.id) { index, document in
                NavigationLink {
                    DocumentDetailViewRevamped(document: document)
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

    private func editDocument(_ document: Document) {
        documentToEdit = document
    }

    private func deleteDocument(_ document: Document) {
        documentToDelete = document
        showDeleteConfirmation = true
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

private extension DocumentRelationship {
    var displayName: String {
        switch self {
        case .owner: "Owner"
        case .dependent: "Dependent"
        case .mentioned: "Mentioned"
        }
    }
}

#Preview {
    let services = AppServices()
    ContentView()
        .environmentObject(services)
        .modelContainer(services.modelContainer)
}
