//
//  DocumentDetailViewRevamped.swift
//  FolioMind
//
//  Redesigned detail view with improved UX and information hierarchy.
//

import SwiftUI

struct DocumentDetailViewRevamped: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var document: Document

    @State private var selectedTab: DetailTab = .overview
    @State private var showFullScreenImage: Bool = false
    @State private var showEditSheet: Bool = false
    @State private var showDeleteAlert: Bool = false
    @State private var copiedField: String?

    enum DetailTab: String, CaseIterable {
        case overview = "Overview"
        case details = "Details"
        case ocr = "Text"
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
                .frame(height: 600)
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
        Button {
            showFullScreenImage = true
        } label: {
            if let url = imageURL, let image = loadImage(from: url) {
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 400)

                    // Full screen indicator
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                        Text("View Full Size")
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(12)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var placeholderImageSection: some View {
        ZStack {
            Rectangle()
                .fill(document.docType.accentGradient)
                .frame(height: 200)

            VStack(spacing: 12) {
                Image(systemName: document.docType.symbolName)
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.5))
                Text("No Image")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))
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

            // Key Information Cards
            keyInfoSection

            // All Recognized Fields
            if !document.fields.isEmpty {
                recognizedFieldsSection
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
        }
    }

    private var creditCardInfo: some View {
        let details = CardDetailsExtractor.extract(ocrText: document.ocrText, fields: document.fields)

        return VStack(spacing: 8) {
            if let holder = details.holder {
                InfoChip(label: "Cardholder", value: holder, icon: "person.fill", color: .blue)
            }
            if let issuer = details.issuer {
                InfoChip(label: "Issuer", value: issuer, icon: "building.columns.fill", color: .purple)
            }
            if let pan = details.pan {
                InfoChip(label: "Card Number", value: formatCardNumber(pan), icon: "creditcard.fill", color: .green, copyable: true)
            }
            if let expiry = details.expiry {
                InfoChip(label: "Expires", value: expiry, icon: "calendar", color: .orange)
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

    private var recognizedFieldsSection: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Recognized Fields", icon: "list.bullet.rectangle.fill")

            VStack(spacing: 8) {
                ForEach(document.fields, id: \.id) { field in
                    ActionableFieldChip(field: field)
                }
            }
        }
    }

    // MARK: - Details Tab

    private var detailsTab: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "All Extracted Fields", icon: "list.bullet.rectangle.fill")

            if document.fields.isEmpty {
                emptyFieldsView
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(document.fields, id: \.id) { field in
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
                if !document.ocrText.isEmpty {
                    Button {
                        copyToClipboard(document.ocrText)
                    } label: {
                        Label("Copy All", systemImage: "doc.on.doc")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(document.docType.accentColor)
                    }
                }
            }

            if document.ocrText.isEmpty {
                emptyOCRView
            } else {
                ScrollView {
                    Text(document.ocrText)
                        .font(.system(.body, design: .monospaced))
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
        // TODO: Implement share functionality
    }

    private func deleteDocument() {
        modelContext.delete(document)
        try? modelContext.save()
        dismiss()
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

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
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

struct ActionableFieldChip: View {
    let field: Field

    @State private var showCopied: Bool = false

    private enum FieldAction {
        case call(String)
        case message(String)
        case email(String)
        case openURL(URL)
        case openMaps(String)
        case copy(String)
    }

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

    var body: some View {
        HStack(spacing: 12) {
            // Icon and label
            VStack(alignment: .leading, spacing: 4) {
                Text(field.key.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(field.value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                ForEach(detectedActions.indices, id: \.self) { index in
                    actionButton(for: detectedActions[index])
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
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
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
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
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.blue)
                    .clipShape(Circle())
            }

        case .openURL(let url):
            Button {
                UIApplication.shared.open(url)
            } label: {
                Image(systemName: "safari.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
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
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.green)
                    .clipShape(Circle())
            }

        case .copy(let text):
            Button {
                UIPasteboard.general.string = text
                showCopied = true
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCopied = false
                }
            } label: {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(showCopied ? .white : .secondary)
                    .frame(width: 28, height: 28)
                    .background(showCopied ? Color.green : Color(.tertiarySystemGroupedBackground))
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

