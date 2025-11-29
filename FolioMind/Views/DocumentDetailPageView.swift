//
//  DocumentDetailPageView.swift
//  FolioMind
//
//  Redesigned detail view with improved UX and information hierarchy.
//

import SwiftUI
import PhotosUI

struct DocumentDetailPageView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var document: Document
    var reminderManager: ReminderManager?

    @State private var selectedTab: DetailTab = .overview
    @State private var showFullScreenImage: Bool = false
    @State private var showEditSheet: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var showEditOCRSheet: Bool = false
    @State private var copiedField: String?
    @State private var showAddReminderSheet: Bool = false
    @State private var showPermissionAlert: Bool = false
    @State private var showShareSheet: Bool = false
    @State private var showRawText: Bool = false  // Toggle between cleaned and raw text
    @State private var selectedAssetIndex: Int = 0  // Track which asset is being viewed
    @State private var selectedPhotos: [PhotosPickerItem] = []  // For adding new assets

    enum DetailTab: String, CaseIterable {
        case overview = "Overview"
        case details = "Details"
        case ocr = "Text"
    }

    private var imageAssets: [Asset] {
        document.imageAssets
    }

    private var currentAsset: Asset? {
        guard selectedAssetIndex < imageAssets.count else { return nil }
        return imageAssets[selectedAssetIndex]
    }

    private var imageURL: URL? {
        guard let asset = currentAsset else { return nil }
        return URL(fileURLWithPath: asset.fileURL)
    }

    private var hasImage: Bool {
        guard let url = imageURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private var hasMultipleAssets: Bool {
        imageAssets.count > 1
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero Image Section
                if hasImage {
                    imageSection
                } else {
                    placeholderImageSection
                }

                // Tab Selector
                tabSelector

                // Content based on selected tab
                TabView(selection: $selectedTab) {
                    overviewTab
                        .tag(DetailTab.overview)

                    detailsTab
                        .tag(DetailTab.details)

                    ocrTab
                        .tag(DetailTab.ocr)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 1200)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(document.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(document.docType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button {
                        shareDocument()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            NavigationStack {
                DocumentEditView(document: document)
            }
        }
        .fullScreenCover(isPresented: $showFullScreenImage) {
            if let url = imageURL {
                FullScreenImageViewer(imageURL: url)
            }
        }
        .alert("Delete Document", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteDocument()
            }
        } message: {
            Text("Are you sure you want to delete \"\(document.title)\"? This action cannot be undone.")
        }
    }

    // MARK: - Image Sections

    private var imageSection: some View {
        VStack(spacing: 0) {
            // Main image display
            ZStack(alignment: .bottomTrailing) {
                Button {
                    showFullScreenImage = true
                } label: {
                    if let url = imageURL, let image = loadImage(from: url) {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 400)

                            // Page indicator for multiple assets
                            if hasMultipleAssets {
                                HStack(spacing: 4) {
                                    Image(systemName: "photo.stack")
                                        .font(.caption)
                                    Text("\(selectedAssetIndex + 1) of \(imageAssets.count)")
                                        .font(.caption.weight(.medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .padding(12)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                // Floating Add Assets button
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                        Text("Add Images")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(document.docType.accentColor)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                .padding(16)
                .onChange(of: selectedPhotos) { oldValue, newValue in
                    Task {
                        await addNewAssets(from: newValue)
                    }
                }
            }

            // Asset thumbnail strip (shown when multiple assets or when adding assets)
            if hasMultipleAssets || !imageAssets.isEmpty {
                assetThumbnailStrip
            }
        }
    }

    private var assetThumbnailStrip: some View {
        VStack(spacing: 8) {
            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Existing asset thumbnails
                    ForEach(Array(imageAssets.enumerated()), id: \.element.id) { index, asset in
                        assetThumbnail(asset: asset, index: index)
                    }

                    // Add asset button
                    addAssetButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(Color(.systemBackground))
    }

    private func assetThumbnail(asset: Asset, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedAssetIndex = index
            }
        } label: {
            Group {
                let url = URL(fileURLWithPath: asset.fileURL)
                if let image = loadImage(from: url) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(selectedAssetIndex == index ? document.docType.accentColor : .clear, lineWidth: 3)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray5))
                        .frame(width: 60, height: 60)
                        .overlay {
                            Image(systemName: asset.assetType.icon)
                                .foregroundStyle(.secondary)
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var addAssetButton: some View {
        PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, matching: .images) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5]))
                    .foregroundStyle(document.docType.accentColor.opacity(0.5))
                    .frame(width: 60, height: 60)

                VStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(document.docType.accentColor)
                    Text("Add")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var placeholderImageSection: some View {
        ZStack(alignment: .center) {
            Rectangle()
                .fill(document.docType.accentGradient)
                .frame(height: 250)

            VStack(spacing: 16) {
                Image(systemName: document.docType.symbolName)
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.5))
                Text("No Image")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))

                // Add Images button
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                        Text("Add Images")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(document.docType.accentColor)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.white)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                .onChange(of: selectedPhotos) { oldValue, newValue in
                    Task {
                        await addNewAssets(from: newValue)
                    }
                }
            }
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(tab.rawValue)
                            .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)

                        Rectangle()
                            .fill(selectedTab == tab ? document.docType.accentColor : .clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 16)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        VStack(spacing: 16) {
            // Quick Stats
            statsSection
                .padding(.top, 8)

            // Key Information Cards
            keyInfoSection

            // Reminders Section
            if reminderManager != nil {
                remindersSection
            }

            Spacer()
        }
        .padding(16)
    }

    private var keyInfoSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Key Information", icon: "star.fill")

            switch document.docType {
            case .creditCard:
                creditCardInfo
            case .insuranceCard:
                insuranceCardInfo
            case .billStatement:
                billStatementInfo
            case .letter:
                letterInfo
            default:
                genericInfo
            }

            // All extracted fields with actionable buttons (deduplicated)
            let uniqueFields = deduplicateFields(document.fields)
            if !uniqueFields.isEmpty {
                VStack(spacing: 8) {
                    ForEach(uniqueFields, id: \.id) { field in
                        ActionableFieldChip(
                            field: field,
                            onDelete: {
                                deleteField(field)
                            }
                        )
                    }
                }
            }
        }
    }

    private var creditCardInfo: some View {
        let details = CardDetailsExtractor.extract(ocrText: document.ocrText, fields: document.fields)

        return VStack(spacing: 8) {
            if let holder = details.holder {
                EditableInfoChip(
                    label: "Cardholder",
                    value: holder,
                    icon: "person.fill",
                    color: .blue,
                    fieldType: .text,
                    onSave: { newValue in
                        updateOrCreateField(key: "cardholder", value: newValue)
                    }
                )
            }
            if let issuer = details.issuer {
                EditableInfoChip(
                    label: "Issuer",
                    value: issuer,
                    icon: "building.columns.fill",
                    color: .purple,
                    fieldType: .text,
                    onSave: { newValue in
                        updateOrCreateField(key: "issuer", value: newValue)
                    }
                )
            }
            if let pan = details.pan {
                EditableInfoChip(
                    label: "Card Number",
                    value: formatCardNumber(pan),
                    icon: "creditcard.fill",
                    color: .green,
                    fieldType: .text,
                    onSave: { newValue in
                        updateOrCreateField(key: "card_number", value: newValue)
                    }
                )
            }
            if let expiry = details.expiry {
                EditableInfoChip(
                    label: "Expires",
                    value: expiry,
                    icon: "calendar",
                    color: .orange,
                    fieldType: .date,
                    onSave: { newValue in
                        updateOrCreateField(key: "expiry_date", value: newValue)
                    }
                )
            }
        }
    }

    private var insuranceCardInfo: some View {
        VStack(spacing: 8) {
            if let member = fieldValue(for: ["member_name", "name"]) {
                InfoChip(label: "Member", value: member, icon: "person.fill", color: .blue)
            }
            if let provider = fieldValue(for: ["provider", "insurer"]) {
                InfoChip(label: "Provider", value: provider, icon: "cross.vial.fill", color: .purple)
            }
            if let memberId = fieldValue(for: ["member_id", "id"]) {
                InfoChip(label: "Member ID", value: memberId, icon: "number", color: .green, copyable: true)
            }
        }
    }

    private var billStatementInfo: some View {
        VStack(spacing: 8) {
            if let amount = fieldValue(for: ["amount_due", "total_due", "balance"]) {
                InfoChip(label: "Amount Due", value: amount, icon: "dollarsign.circle.fill", color: .red)
            }
            if let dueDate = fieldValue(for: ["due_date", "payment_due"]) {
                InfoChip(label: "Due Date", value: dueDate, icon: "calendar", color: .orange)
            }
        }
    }

    private var letterInfo: some View {
        VStack(spacing: 8) {
            if let from = fieldValue(for: ["from", "sender"]) {
                InfoChip(label: "From", value: from, icon: "envelope.fill", color: .blue)
            }
            if let date = fieldValue(for: ["date"]) {
                InfoChip(label: "Date", value: date, icon: "calendar", color: .purple)
            }
        }
    }

    private var genericInfo: some View {
        VStack(spacing: 8) {
            if !document.fields.isEmpty {
                ForEach(document.fields.prefix(3), id: \.id) { field in
                    InfoChip(label: field.key.capitalized, value: field.value, icon: "tag.fill", color: .blue)
                }
            } else {
                Text("No extracted data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
    }

    private var statsSection: some View {
        HStack(spacing: 12) {
            StatCard(
                value: relativeTime,
                label: "Captured",
                icon: "clock.fill",
                color: .blue
            )

            StatCard(
                value: "\(document.fields.count)",
                label: "Fields",
                icon: "list.bullet.rectangle.fill",
                color: .purple
            )

            StatCard(
                value: document.ocrText.isEmpty ? "0" : "\(document.ocrText.count)",
                label: "Characters",
                icon: "text.alignleft",
                color: .green
            )
        }
    }

    // MARK: - Reminders Section

    private var remindersSection: some View {
        VStack(spacing: 12) {
            HStack {
                SectionHeader(title: "Reminders", icon: "bell.fill")
                Spacer()
                Button {
                    showAddReminderSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
            }

            if document.reminders.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No reminders set")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 8) {
                    ForEach(document.reminders, id: \.id) { reminder in
                        ReminderRow(
                            reminder: reminder,
                            onToggle: {
                                Task {
                                    await toggleReminder(reminder)
                                }
                            },
                            onDelete: {
                                Task {
                                    await deleteReminder(reminder)
                                }
                            }
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showAddReminderSheet) {
            if let reminderManager = reminderManager {
                AddReminderSheet(
                    document: document,
                    reminderManager: reminderManager,
                    onSave: { newReminder in
                        document.reminders.append(newReminder)
                        try? modelContext.save()
                    }
                )
            }
        }
        .alert("Permission Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("FolioMind needs permission to create reminders. Please enable Reminders access in Settings.")
        }
    }

    private func toggleReminder(_ reminder: DocumentReminder) async {
        guard let reminderManager = reminderManager else { return }

        do {
            if reminder.isCompleted {
                // Uncomplete - would need to recreate
                reminder.isCompleted = false
            } else {
                // Mark as complete
                if let eventKitID = reminder.eventKitID {
                    try await reminderManager.completeReminder(eventKitID: eventKitID)
                }
                reminder.isCompleted = true
            }
            try? modelContext.save()
        } catch {
            print("Error toggling reminder: \(error)")
        }
    }

    private func deleteReminder(_ reminder: DocumentReminder) async {
        guard let reminderManager = reminderManager else { return }

        do {
            // Delete from EventKit if exists
            if let eventKitID = reminder.eventKitID {
                try await reminderManager.deleteReminder(eventKitID: eventKitID)
            }

            // Remove from document
            if let index = document.reminders.firstIndex(where: { $0.id == reminder.id }) {
                document.reminders.remove(at: index)
                modelContext.delete(reminder)
                try? modelContext.save()
            }
        } catch {
            print("Error deleting reminder: \(error)")
        }
    }

    // MARK: - Details Tab

    private var detailsTab: some View {
        let uniqueFields = deduplicateFields(document.fields)

        return VStack(spacing: 16) {
            SectionHeader(title: "All Extracted Fields", icon: "list.bullet.rectangle.fill")

            if uniqueFields.isEmpty {
                emptyFieldsView
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(uniqueFields, id: \.id) { field in
                            FieldRow(field: field, onCopy: { value in
                                copyToClipboard(value)
                            })
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(16)
    }

    private var emptyFieldsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Fields Extracted")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("This document doesn't have any structured data")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - OCR Tab

    private var ocrTab: some View {
        VStack(spacing: 16) {
            HStack {
                SectionHeader(title: "Extracted Text", icon: "doc.text.fill")
                Spacer()
                HStack(spacing: 12) {
                    if !document.ocrText.isEmpty {
                        // Toggle between cleaned and raw text
                        if document.cleanedText != nil {
                            Button {
                                showRawText.toggle()
                            } label: {
                                Label(showRawText ? "Cleaned" : "Raw", systemImage: showRawText ? "sparkles" : "text.alignleft")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(document.docType.accentColor)
                            }
                        }

                        Button {
                            showEditOCRSheet = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(document.docType.accentColor)
                        }

                        Button {
                            let textToCopy = showRawText ? document.ocrText : (document.cleanedText ?? document.ocrText)
                            copyToClipboard(textToCopy)
                        } label: {
                            Label("Copy All", systemImage: "doc.on.doc")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(document.docType.accentColor)
                        }
                    }
                }
            }

            if document.ocrText.isEmpty {
                emptyOCRView
            } else {
                ScrollView {
                    let displayText = showRawText ? document.ocrText : (document.cleanedText ?? document.ocrText)
                    Text(displayText)
                        .font(.system(.body, design: showRawText ? .monospaced : .default))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            Spacer()
        }
        .padding(16)
        .sheet(isPresented: $showEditOCRSheet) {
            EditOCRTextSheet(document: document)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(document: document)
        }
    }

    private var emptyOCRView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Text Extracted")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("OCR didn't find any readable text in this document")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Helper Properties

    private var relativeTime: String {
        let date = document.capturedAt ?? document.createdAt
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }


    // MARK: - Helper Functions

    private func fieldValue(for keys: [String]) -> String? {
        document.fields.first(where: { keys.contains($0.key.lowercased()) })?.value
    }

    private func loadImage(from url: URL) -> UIImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func formatCardNumber(_ pan: String) -> String {
        let chunks = stride(from: 0, to: pan.count, by: 4).map { index in
            let start = pan.index(pan.startIndex, offsetBy: index)
            let end = pan.index(start, offsetBy: min(4, pan.count - index))
            return String(pan[start..<end])
        }
        return chunks.joined(separator: " ")
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        copiedField = text

        // Visual feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedField = nil
        }
    }

    private func shareDocument() {
        showShareSheet = true
    }

    private func deleteDocument() {
        modelContext.delete(document)
        try? modelContext.save()
        dismiss()
    }

    private func addNewAssets(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }

            // Create a unique filename in the documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let filename = "\(UUID().uuidString).jpg"
            let fileURL = documentsPath.appendingPathComponent(filename)

            do {
                // Write the image data to the file
                try data.write(to: fileURL)

                // Create a new Asset and add it to the document
                let nextPageNumber = (document.assets.map(\.pageNumber).max() ?? -1) + 1
                let newAsset = Asset(
                    fileURL: fileURL.path,
                    assetType: .image,
                    addedAt: Date(),
                    pageNumber: nextPageNumber
                )

                modelContext.insert(newAsset)
                document.assets.append(newAsset)

                // Update the selected index to show the newly added asset
                selectedAssetIndex = document.imageAssets.count - 1
            } catch {
                print("Error saving asset: \(error.localizedDescription)")
            }
        }

        // Save the context
        try? modelContext.save()

        // Clear the selection
        selectedPhotos = []
    }

    private func updateOrCreateField(key: String, value: String) {
        if let existingField = document.fields.first(where: { $0.key.lowercased() == key.lowercased() }) {
            existingField.value = value
        } else {
            let newField = Field(key: key, value: value, confidence: 1.0, source: .fused)
            modelContext.insert(newField)
            document.fields.append(newField)
        }
        try? modelContext.save()
    }

    private func deduplicateFields(_ fields: [Field]) -> [Field] {
        var seen = Set<String>()
        var unique: [Field] = []

        for field in fields {
            // Normalize the value for comparison
            let normalizedValue: String
            if field.key.lowercased().contains("phone") {
                // For phone numbers, normalize by removing all non-digit characters except +
                normalizedValue = field.value.filter { $0.isNumber || $0 == "+" }
            } else {
                normalizedValue = field.value.lowercased().trimmingCharacters(in: .whitespaces)
            }

            let key = "\(field.key.lowercased()):\(normalizedValue)"
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(field)
            }
        }

        return unique
    }

    private func deleteField(_ field: Field) {
        if let index = document.fields.firstIndex(where: { $0.id == field.id }) {
            document.fields.remove(at: index)
            modelContext.delete(field)
            try? modelContext.save()
        }
    }
}

// MARK: - Supporting Views

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
            Spacer()
        }
        .foregroundStyle(.secondary)
    }
}

struct EditableInfoChip: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    let fieldType: FieldEditType
    let onSave: (String) -> Void

    @State private var showEditSheet: Bool = false

    var body: some View {
        Button {
            showEditSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showEditSheet) {
            FieldEditModal(
                label: label,
                value: value,
                icon: icon,
                color: color,
                fieldType: fieldType,
                onSave: onSave
            )
        }
    }
}

struct InfoChip: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    var copyable: Bool = false

    @State private var showCopied: Bool = false

    var body: some View {
        Button {
            if copyable {
                UIPasteboard.general.string = value
                showCopied = true
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCopied = false
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                if copyable {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(showCopied ? .green : .secondary)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!copyable)
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct FieldRow: View {
    let field: Field
    let onCopy: (String) -> Void

    var body: some View {
        Button {
            onCopy(field.value)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.key.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(field.value)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                Spacer()

                HStack(spacing: 4) {
                    confidenceBadge(field.confidence)
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func confidenceBadge(_ confidence: Double) -> some View {
        let color: Color = confidence > 0.8 ? .green : confidence > 0.5 ? .orange : .red
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }
}

enum FieldAction {
    case call(String)
    case message(String)
    case email(String)
    case openURL(URL)
    case openMaps(String)
    case copy(String)
}

struct ActionableFieldChip: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var field: Field
    var onDelete: (() -> Void)?

    @State private var showEditSheet: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    private var detectedActions: [FieldAction] {
        var actions: [FieldAction] = []
        let value = field.value

        // Phone number detection
        if isPhoneNumber(value) {
            let cleaned = cleanPhoneNumber(value)
            actions.append(.call(cleaned))
            actions.append(.message(cleaned))
        }
        // Email detection
        else if isEmail(value) {
            actions.append(.email(value))
        }
        // URL detection
        else if let url = detectURL(value) {
            actions.append(.openURL(url))
        }
        // Address detection (simple heuristic)
        else if isAddress(value) {
            actions.append(.openMaps(value))
        }

        // Always allow copy
        actions.append(.copy(value))

        return actions
    }

    private var fieldIcon: (icon: String, color: Color) {
        let key = field.key.lowercased()

        // Phone number
        if key.contains("phone") || key.contains("tel") || key.contains("mobile") || key.contains("cell") {
            return ("phone.fill", .green)
        }
        // Email
        else if key.contains("email") || key.contains("mail") {
            return ("envelope.fill", .blue)
        }
        // URL/Website
        else if key.contains("url") || key.contains("website") || key.contains("link") {
            return ("safari.fill", .blue)
        }
        // Address
        else if key.contains("address") || key.contains("location") {
            return ("map.fill", .red)
        }
        // Date
        else if key.contains("date") || key.contains("expir") || key.contains("valid") {
            return ("calendar", .orange)
        }
        // Amount/Money
        else if key.contains("amount") || key.contains("balance") || key.contains("payment") || key.contains("due") {
            return ("dollarsign.circle.fill", .green)
        }
        // Name
        else if key.contains("name") || key.contains("holder") || key.contains("member") {
            return ("person.fill", .blue)
        }
        // Default
        else {
            return ("tag.fill", .gray)
        }
    }

    private var fieldType: FieldEditType {
        let key = field.key.lowercased()

        if key.contains("date") || key.contains("expir") || key.contains("valid") {
            return .date
        } else if key.contains("phone") || key.contains("tel") || key.contains("mobile") || key.contains("cell") {
            return .phone
        } else if key.contains("email") || key.contains("mail") {
            return .email
        } else if key.contains("url") || key.contains("website") {
            return .url
        } else if key.contains("amount") || key.contains("balance") || key.contains("payment") || key.contains("price") {
            return .currency
        } else {
            return .text
        }
    }

    var body: some View {
        Button {
            showEditSheet = true
        } label: {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: fieldIcon.icon)
                    .font(.title3)
                    .foregroundStyle(fieldIcon.color)
                    .frame(width: 40, height: 40)
                    .background(fieldIcon.color.opacity(0.1))
                    .clipShape(Circle())

                // Label and value
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.key.capitalized.replacingOccurrences(of: "_", with: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text(field.value)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        if field.isModified {
                            Image(systemName: "pencil.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Spacer()

                // Action buttons
                HStack(spacing: 6) {
                    ForEach(0..<detectedActions.count, id: \.self) { index in
                        actionButton(for: detectedActions[index])
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Field", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("Are you sure you want to delete this field?")
        }
        .sheet(isPresented: $showEditSheet) {
            FieldEditModal(
                label: field.key.capitalized.replacingOccurrences(of: "_", with: " "),
                value: field.value,
                icon: fieldIcon.icon,
                color: fieldIcon.color,
                fieldType: fieldType,
                originalValue: field.originalValue,
                onSave: { newValue in
                    field.value = newValue
                    try? modelContext.save()
                },
                onReset: {
                    field.reset()
                    try? modelContext.save()
                },
                onDelete: {
                    onDelete?()
                }
            )
        }
    }

    @ViewBuilder
    private func actionButton(for action: FieldAction) -> some View {
        switch action {
        case .call(let number):
            Button {
                if let url = URL(string: "tel:\(number)") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.green)
                    .clipShape(Circle())
            }

        case .message(let number):
            Button {
                if let url = URL(string: "sms:\(number)") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Image(systemName: "message.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.blue)
                    .clipShape(Circle())
            }

        case .email(let email):
            Button {
                if let url = URL(string: "mailto:\(email)") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.blue)
                    .clipShape(Circle())
            }

        case .openURL(let url):
            Button {
                UIApplication.shared.open(url)
            } label: {
                Image(systemName: "safari.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.blue)
                    .clipShape(Circle())
            }

        case .openMaps(let address):
            Button {
                let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "http://maps.apple.com/?address=\(encoded)") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Image(systemName: "map.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.green)
                    .clipShape(Circle())
            }

        case .copy(let text):
            Button {
                UIPasteboard.general.string = text
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Field Type Detection

    private func isPhoneNumber(_ text: String) -> Bool {
        // Remove common phone number characters
        let digits = text.filter { $0.isNumber }
        // US/International phone numbers are typically 10-15 digits
        guard digits.count >= 10 && digits.count <= 15 else { return false }

        // Check if the field key suggests it's a phone number
        let phoneKeywords = ["phone", "tel", "mobile", "cell", "fax"]
        if phoneKeywords.contains(where: { field.key.lowercased().contains($0) }) {
            return true
        }

        // Check for phone number patterns
        let phonePattern = "^[+]?[(]?[0-9]{1,4}[)]?[-\\s\\.]?[(]?[0-9]{1,4}[)]?[-\\s\\.]?[0-9]{1,9}$"
        return text.range(of: phonePattern, options: .regularExpression) != nil
    }

    private func cleanPhoneNumber(_ text: String) -> String {
        text.filter { $0.isNumber || $0 == "+" }
    }

    private func isEmail(_ text: String) -> Bool {
        let emailPattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return text.range(of: emailPattern, options: .regularExpression) != nil
    }

    private func detectURL(_ text: String) -> URL? {
        // Check if field key suggests URL
        let urlKeywords = ["url", "website", "link"]
        let isLikelyURL = urlKeywords.contains(where: { field.key.lowercased().contains($0) })

        if isLikelyURL || text.lowercased().hasPrefix("http") || text.lowercased().hasPrefix("www") {
            var urlString = text
            if !urlString.lowercased().hasPrefix("http") {
                urlString = "https://" + urlString
            }
            return URL(string: urlString)
        }

        return nil
    }

    private func isAddress(_ text: String) -> Bool {
        // Simple heuristic: contains street indicators and has multiple lines or commas
        let addressKeywords = ["street", "address", "st", "ave", "road", "rd", "blvd", "lane", "ln"]
        let hasAddressKeyword = addressKeywords.contains(where: {
            text.lowercased().contains($0) || field.key.lowercased().contains($0)
        })

        let hasMultipleParts = text.contains(",") || text.contains("\n")
        let hasNumbers = text.rangeOfCharacter(from: .decimalDigits) != nil

        return hasAddressKeyword && (hasMultipleParts || hasNumbers) && text.count > 10
    }
}

// MARK: - Field Edit Types

enum FieldEditType {
    case text
    case phone
    case email
    case url
    case date
    case currency
}

// MARK: - Field Edit Modal

struct FieldEditModal: View {
    @Environment(\.dismiss) private var dismiss

    let label: String
    let value: String
    let icon: String
    let color: Color
    let fieldType: FieldEditType
    var originalValue: String? = nil
    let onSave: (String) -> Void
    var onReset: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var editedValue: String = ""
    @State private var selectedDate: Date = Date()
    @State private var showResetConfirmation: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    private var keyboardType: UIKeyboardType {
        switch fieldType {
        case .phone: return .phonePad
        case .email: return .emailAddress
        case .url: return .URL
        case .currency: return .decimalPad
        case .date, .text: return .default
        }
    }

    private var textContentType: UITextContentType? {
        switch fieldType {
        case .phone: return .telephoneNumber
        case .email: return .emailAddress
        case .url: return .URL
        default: return nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundStyle(color)
                            .frame(width: 44, height: 44)
                            .background(color.opacity(0.1))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(label)
                                .font(.headline)
                            if let originalValue = originalValue, !originalValue.isEmpty, originalValue != value {
                                Text("Modified")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                Section("Value") {
                    if fieldType == .date {
                        DatePicker(
                            "Date",
                            selection: $selectedDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .onChange(of: selectedDate) { _, newDate in
                            editedValue = formatDate(newDate)
                        }
                    } else {
                        TextField("Enter value", text: $editedValue, axis: .vertical)
                            .keyboardType(keyboardType)
                            .textContentType(textContentType)
                            .autocorrectionDisabled()
                            .lineLimit(3...6)
                    }
                }

                if let originalValue = originalValue, !originalValue.isEmpty, originalValue != value {
                    Section("Original Value") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(originalValue)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)

                            Button {
                                showResetConfirmation = true
                            } label: {
                                Label("Reset to Original", systemImage: "arrow.counterclockwise")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit \(label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(editedValue)
                        dismiss()
                    }
                    .disabled(editedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if onDelete != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Field", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .onAppear {
                editedValue = value
                if fieldType == .date {
                    selectedDate = parseDate(value) ?? Date()
                }
            }
            .alert("Reset to Original Value", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    onReset?()
                    dismiss()
                }
            } message: {
                if let originalValue = originalValue {
                    Text("This will restore the original value:\n\n\"\(originalValue)\"")
                }
            }
            .alert("Delete Field", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete this field? This action cannot be undone.")
            }
        }
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatters = [
            createFormatter("MM/dd/yyyy"),
            createFormatter("MM-dd-yyyy"),
            createFormatter("MMMM d, yyyy"),
            createFormatter("d MMMM yyyy"),
            createFormatter("MM/yy")
        ]

        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }

    private func createFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Edit OCR Text Sheet

struct EditOCRTextSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var document: Document

    @State private var editedText: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $editedText)
                    .font(.system(.body, design: .monospaced))
                    .padding()
            }
            .navigationTitle("Edit Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        document.ocrText = editedText
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                editedText = document.ocrText
            }
        }
    }
}

// MARK: - Reminder Components

struct ReminderRow: View {
    let reminder: DocumentReminder
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button {
                onToggle()
            } label: {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(reminder.isCompleted ? .green : .gray)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(reminder.title)
                    .font(.headline)
                    .strikethrough(reminder.isCompleted)
                    .foregroundStyle(reminder.isCompleted ? .secondary : .primary)

                // Notes
                if !reminder.notes.isEmpty {
                    Text(reminder.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Due date and type
                HStack(spacing: 8) {
                    Label(formatDate(reminder.dueDate), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                        .frame(height: 12)

                    Image(systemName: reminderTypeIcon(reminder.reminderType))
                        .font(.caption)
                        .foregroundStyle(reminderTypeColor(reminder.reminderType))
                    Text(reminder.reminderType.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(reminderTypeColor(reminder.reminderType))
                }
            }

            Spacer()

            // Delete button
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .alert("Delete Reminder", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Are you sure you want to delete this reminder?")
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func reminderTypeIcon(_ type: ReminderType) -> String {
        switch type {
        case .call: return "phone.fill"
        case .appointment: return "calendar"
        case .payment: return "creditcard.fill"
        case .renewal: return "arrow.clockwise"
        case .followUp: return "checkmark.circle"
        case .custom: return "bell.fill"
        }
    }

    private func reminderTypeColor(_ type: ReminderType) -> Color {
        switch type {
        case .call: return .blue
        case .appointment: return .green
        case .payment: return .red
        case .renewal: return .orange
        case .followUp: return .purple
        case .custom: return .gray
        }
    }
}

// MARK: - Add Reminder Sheet

struct AddReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let document: Document
    let reminderManager: ReminderManager
    let onSave: (DocumentReminder) -> Void

    @State private var selectedSuggestion: ReminderSuggestion?
    @State private var customTitle: String = ""
    @State private var customNotes: String = ""
    @State private var customDate: Date = Date().addingTimeInterval(86400) // Tomorrow
    @State private var customType: ReminderType = .custom
    @State private var showCustomForm: Bool = false
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?

    private var suggestions: [ReminderSuggestion] {
        reminderManager.suggestReminders(for: document)
    }

    var body: some View {
        NavigationStack {
            List {
                if !suggestions.isEmpty && !showCustomForm {
                    Section {
                        ForEach(suggestions) { suggestion in
                            SuggestionRow(
                                suggestion: suggestion,
                                isSelected: selectedSuggestion?.id == suggestion.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSuggestion = suggestion
                            }
                        }
                    } header: {
                        Text("Suggested Reminders")
                    }

                    Section {
                        Button {
                            showCustomForm = true
                        } label: {
                            Label("Create Custom Reminder", systemImage: "plus.circle.fill")
                        }
                    }
                } else {
                    Section {
                        TextField("Title", text: $customTitle)
                            .textInputAutocapitalization(.sentences)

                        TextField("Notes (optional)", text: $customNotes, axis: .vertical)
                            .textInputAutocapitalization(.sentences)
                            .lineLimit(2...4)

                        DatePicker("Due Date", selection: $customDate, displayedComponents: [.date, .hourAndMinute])

                        Picker("Type", selection: $customType) {
                            ForEach(ReminderType.allCases, id: \.self) { type in
                                HStack {
                                    Image(systemName: reminderTypeIcon(type))
                                    Text(type.rawValue.capitalized)
                                }
                                .tag(type)
                            }
                        }
                    } header: {
                        Text("Custom Reminder")
                    }

                    if !suggestions.isEmpty {
                        Section {
                            Button {
                                showCustomForm = false
                                customTitle = ""
                                customNotes = ""
                                customDate = Date().addingTimeInterval(86400)
                                customType = .custom
                            } label: {
                                Label("Back to Suggestions", systemImage: "arrow.left")
                            }
                        }
                    }
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Add Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await createReminder()
                        }
                    }
                    .disabled(!canCreate || isCreating)
                }
            }
            .disabled(isCreating)
        }
    }

    private var canCreate: Bool {
        if showCustomForm {
            return !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            return selectedSuggestion != nil
        }
    }

    private func createReminder() async {
        isCreating = true
        errorMessage = nil

        do {
            // Request permission first
            let hasPermission = await reminderManager.requestPermission()
            guard hasPermission else {
                errorMessage = "Permission denied. Please enable Reminders access in Settings."
                isCreating = false
                return
            }

            let title: String
            let notes: String
            let dueDate: Date
            let type: ReminderType
            let priority: Int

            if let suggestion = selectedSuggestion {
                title = suggestion.title
                notes = suggestion.notes
                dueDate = suggestion.dueDate
                type = suggestion.type
                priority = suggestion.priority
            } else {
                title = customTitle
                notes = customNotes
                dueDate = customDate
                type = customType
                priority = 5 // Medium
            }

            // Create in EventKit
            let eventKitID = try await reminderManager.createReminder(
                title: title,
                notes: notes.isEmpty ? nil : notes,
                dueDate: dueDate,
                priority: priority
            )

            // Create our model
            let reminder = DocumentReminder(
                title: title,
                notes: notes,
                dueDate: dueDate,
                reminderType: type,
                isCompleted: false,
                eventKitID: eventKitID
            )

            modelContext.insert(reminder)
            onSave(reminder)

            isCreating = false
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
        }
    }

    private func reminderTypeIcon(_ type: ReminderType) -> String {
        switch type {
        case .call: return "phone.fill"
        case .appointment: return "calendar"
        case .payment: return "creditcard.fill"
        case .renewal: return "arrow.clockwise"
        case .followUp: return "checkmark.circle"
        case .custom: return "bell.fill"
        }
    }
}

struct SuggestionRow: View {
    let suggestion: ReminderSuggestion
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: suggestion.typeIcon)
                .font(.title2)
                .foregroundStyle(colorFromString(suggestion.typeColor))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title)
                    .font(.headline)

                if !suggestion.notes.isEmpty {
                    Text(suggestion.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Label(formatDate(suggestion.dueDate), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                        .frame(height: 12)

                    Text(suggestion.priorityLabel)
                        .font(.caption)
                        .foregroundStyle(priorityColor(suggestion.priority))
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.gray)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func colorFromString(_ colorString: String) -> Color {
        switch colorString.lowercased() {
        case "blue": return .blue
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        case "purple": return .purple
        case "gray": return .gray
        default: return .gray
        }
    }

    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 1: return .red
        case 5: return .orange
        case 9: return .gray
        default: return .gray
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let document: Document

    @State private var shareItems: [Any] = []
    @State private var showActivityView = false

    enum ShareOption: String, CaseIterable, Identifiable {
        case image = "Image"
        case text = "Text"
        case summary = "Summary"
        case fields = "Extracted Fields"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .image: return "photo"
            case .text: return "doc.text"
            case .summary: return "doc.richtext"
            case .fields: return "list.bullet.rectangle"
            }
        }

        var description: String {
            switch self {
            case .image: return "Share the document image"
            case .text: return "Share raw OCR text"
            case .summary: return "Share formatted summary"
            case .fields: return "Share extracted fields as text"
            }
        }
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
        NavigationStack {
            List {
                Section {
                    Text("Choose what to share")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Share Options") {
                    if hasImage {
                        ShareOptionRow(
                            option: .image,
                            isAvailable: true
                        ) {
                            shareImage()
                        }
                    }

                    ShareOptionRow(
                        option: .text,
                        isAvailable: !document.ocrText.isEmpty
                    ) {
                        shareText()
                    }

                    ShareOptionRow(
                        option: .summary,
                        isAvailable: true
                    ) {
                        shareSummary()
                    }

                    ShareOptionRow(
                        option: .fields,
                        isAvailable: !document.fields.isEmpty
                    ) {
                        shareFields()
                    }
                }
            }
            .navigationTitle("Share Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showActivityView) {
            if !shareItems.isEmpty {
                ActivityViewController(activityItems: shareItems)
            }
        }
    }

    private func shareImage() {
        guard let imageURL = imageURL else { return }
        shareItems = [imageURL]
        showActivityView = true
    }

    private func shareText() {
        shareItems = [document.ocrText]
        showActivityView = true
    }

    private func shareSummary() {
        let summary = generateSummary()
        shareItems = [summary]
        showActivityView = true
    }

    private func shareFields() {
        let fieldsText = generateFieldsText()
        shareItems = [fieldsText]
        showActivityView = true
    }

    private func generateSummary() -> String {
        var summary = """
        \(document.title)
        \(String(repeating: "=", count: document.title.count))

        Type: \(document.docType.displayName)
        """

        if let capturedAt = document.capturedAt {
            summary += "\nCaptured: \(formatDate(capturedAt))"
        }

        summary += "\nCreated: \(formatDate(document.createdAt))"

        if let location = document.location {
            summary += "\nLocation: \(location)"
        }

        if !document.fields.isEmpty {
            summary += "\n\nExtracted Fields:"
            summary += "\n" + String(repeating: "-", count: 20)
            for field in document.fields {
                summary += "\n• \(field.key.capitalized): \(field.value)"
            }
        }

        if !document.ocrText.isEmpty {
            summary += "\n\nExtracted Text:"
            summary += "\n" + String(repeating: "-", count: 20)
            summary += "\n\(document.ocrText)"
        }

        summary += "\n\n---\nGenerated by FolioMind"

        return summary
    }

    private func generateFieldsText() -> String {
        var text = "\(document.title) - Extracted Fields\n"
        text += String(repeating: "=", count: 40) + "\n\n"

        for field in document.fields {
            text += "\(field.key.capitalized):\n"
            text += "  \(field.value)\n"
            text += "  Confidence: \(Int(field.confidence * 100))%\n\n"
        }

        text += "---\nGenerated by FolioMind"

        return text
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ShareOptionRow: View {
    let option: ShareSheet.ShareOption
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.icon)
                    .font(.title3)
                    .foregroundStyle(isAvailable ? .blue : .gray)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(option.rawValue)
                        .font(.headline)
                        .foregroundStyle(isAvailable ? .primary : .secondary)

                    Text(isAvailable ? option.description : "Not available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isAvailable {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .disabled(!isAvailable)
    }
}

// MARK: - Activity View Controller

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
