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

    private var imageURL: URL? {
        guard let assetURLString = document.assetURL else { return nil }
        return URL(fileURLWithPath: assetURLString)
    }

    private var hasImage: Bool {
        guard let url = imageURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private var relativeTime: String {
        let date = document.capturedAt ?? document.createdAt
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var keyInfo: String? {
        switch document.docType {
        case .creditCard:
            let details = CardDetailsExtractor.extract(ocrText: document.ocrText, fields: document.fields)
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
        if !document.ocrText.isEmpty {
            let words = document.ocrText.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            let preview = words.prefix(3).joined(separator: " ")
            return preview.isEmpty ? nil : preview
        }

        return nil
    }

    private func fieldValue(for keys: [String]) -> String? {
        document.fields.first(where: { keys.contains($0.key.lowercased()) })?.value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image
            if hasImage, let url = imageURL, let image = loadImage(from: url) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 140)
                        .clipped()

                    // Document type badge
                    PillBadge(
                        text: document.docType.displayName,
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
            } else {
                // Placeholder with gradient
                ZStack(alignment: .topTrailing) {
                    Rectangle()
                        .fill(document.docType.accentGradient)
                        .frame(height: 140)
                        .overlay(
                            Image(systemName: document.docType.symbolName)
                                .font(.system(size: 36))
                                .foregroundStyle(.white.opacity(0.3))
                        )

                    // Document type badge
                    PillBadge(
                        text: document.docType.displayName,
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

            // Metadata
            VStack(alignment: .leading, spacing: 6) {
                // Title or key info
                if let keyInfo = keyInfo {
                    Text(keyInfo)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                } else {
                    Text(document.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                // Time
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(relativeTime)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)

                // Match score if searching
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
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private func loadImage(from url: URL) -> UIImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
