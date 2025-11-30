//
//  DocumentGridCard.swift
//  FolioMind
//
//  Grid card component for displaying documents with images and metadata.
//

import SwiftUI

struct DocumentGridCard: View {
    let document: Document
    let score: SearchScoreComponents?

    private let thumbnailPadding: CGFloat = 6.0
    private let thumbnailHeight: CGFloat = 160
    private let metadataHeight: CGFloat = 110

    struct DisplayField: Equatable {
        let key: String
        let value: String
        let confidence: Double
    }

    // Cache critical properties to prevent crashes when document is deleted
    @State private var cachedDocType: DocumentType?
    @State private var cachedTitle: String = ""
    @State private var cachedDate: Date?
    @State private var cachedOCRText: String = ""
    @State private var cachedFields: [DisplayField] = []
    @State private var cachedLocation: String?

    private var safeDocType: DocumentType {
        cachedDocType ?? .generic
    }

    private var imageURL: URL? {
        guard let assetURLString = document.assetURL else { return nil }
        return URL(fileURLWithPath: assetURLString)
    }

    private var hasImage: Bool {
        guard let url = imageURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private var relativeTime: String {
        let date = cachedDate ?? Date()
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var keyInfo: String? {
        switch safeDocType {
        case .creditCard:
            let details = CardDetailsExtractor.extract(ocrText: cachedOCRText, fields: cachedFields.map {
                Field(key: $0.key, value: $0.value, confidence: $0.confidence, source: .vision)
            })
            if let holder = details.holder, let issuer = details.issuer {
                return "\(holder)'s \(issuer)"
            } else if let holder = details.holder {
                return "\(holder)'s Card"
            } else if let issuer = details.issuer {
                return issuer
            }
        case .insuranceCard:
            if let member = fieldValue(for: ["member_name", "name"]),
               let provider = fieldValue(for: ["provider", "insurer"]) {
                return "\(member)'s \(provider)"
            } else if let member = fieldValue(for: ["member_name", "name"]) {
                return "\(member)'s Insurance"
            }
        case .letter:
            if let from = fieldValue(for: ["from", "sender"]) {
                return "From \(from)"
            }
        case .billStatement:
            if let amount = fieldValue(for: ["amount_due", "total_due", "balance"]) {
                return "Due: \(amount)"
            }
        default:
            break
        }

        // Fallback to first few words of OCR text
        if !cachedOCRText.isEmpty {
            let words = cachedOCRText.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            let preview = words.prefix(3).joined(separator: " ")
            return preview.isEmpty ? nil : preview
        }

        return nil
    }

    private func fieldValue(for keys: [String]) -> String? {
        cachedFields.first(where: { keys.contains($0.key.lowercased()) })?.value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnailView
            metadataView
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onAppear {
            // Cache values on appear to prevent crashes when document is deleted
            updateCachedValues()
        }
        .task(id: document.id) {
            // Update cached values when document changes
            updateCachedValues()
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if hasImage, let url = imageURL, let image = loadImage(from: url) {
                    Color(.tertiarySystemBackground)
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(thumbnailPadding)
                        }
                } else {
                    Rectangle()
                        .fill(safeDocType.accentGradient)
                        .overlay(
                            Image(systemName: safeDocType.symbolName)
                                .font(.system(size: 36))
                                .foregroundStyle(.white.opacity(0.3))
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: thumbnailHeight)
            .clipped()

            PillBadge(
                text: safeDocType.displayName,
                icon: nil,
                tint: .white
            )
            .background(
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.3))
                    .blur(radius: 4)
            )
            .padding(8)
        }
    }

    @ViewBuilder
    private var metadataView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let keyInfo = keyInfo {
                Text(keyInfo)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            } else {
                Text(cachedTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(relativeTime)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            if let location = cachedLocation {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 10))
                    Text(location)
                        .font(.caption2)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(.secondary)
            }

            if let score = score {
                let matchPercent = Int((score.keyword * 0.6 + score.semantic * 0.4) * 100)
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                    Text("\(matchPercent)% match")
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: metadataHeight, alignment: .top)
    }

    private func updateCachedValues() {
        // If the backing model is gone (deleted), avoid touching it to prevent crashes.
        guard document.modelContext != nil else { return }
        cachedDocType = document.docType
        cachedTitle = document.title
        cachedDate = document.capturedAt ?? document.createdAt
        cachedOCRText = document.ocrText
        cachedLocation = cleanedLocation(document.location)
        cachedFields = document.fields.map {
            DisplayField(key: $0.key, value: $0.value, confidence: $0.confidence)
        }
    }

    private func loadImage(from url: URL) -> UIImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func cleanedLocation(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
