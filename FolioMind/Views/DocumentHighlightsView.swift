//
//  DocumentHighlightsView.swift
//  FolioMind
//
//  Specialized highlight views per document type plus raw text helper rendering.
//

import SwiftUI

struct DocumentHighlightsView: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch document.docType {
            case .creditCard:
                CreditCardHighlightView(document: document)
            case .insuranceCard:
                InsuranceCardHighlightView(document: document)
            case .letter:
                LetterHighlightView(document: document)
            case .billStatement:
                BillStatementHighlightView(document: document)
            default:
                EmptyView()
            }
        }
    }
}

private struct CreditCardHighlightView: View {
    let document: Document

    private var details: CardDetails {
        CardDetailsExtractor.extract(ocrText: document.ocrText, fields: document.fields)
    }

    var body: some View {
        HighlightSection(title: "Credit Card") {
            HighlightRow(label: "Cardholder", value: details.holder ?? "—")
            HighlightRow(label: "Card Number", value: details.pan ?? "—")
            HighlightRow(label: "Expiry", value: details.expiry ?? "—")
            HighlightRow(label: "Issuer", value: details.issuer ?? "—")
        }
    }
}

private struct InsuranceCardHighlightView: View {
    let document: Document

    var body: some View {
        HighlightSection(title: "Insurance Card") {
            HighlightRow(label: "Member", value: value(for: ["member_name", "name"]))
            HighlightRow(label: "Policy #", value: value(for: ["policy_number", "policy"]))
            HighlightRow(label: "Group #", value: value(for: ["group_number", "group"]))
            HighlightRow(label: "Provider", value: value(for: ["provider", "insurer"]))
        }
    }

    private func value(for keys: [String]) -> String {
        document.fields.first(where: { keys.contains($0.key.lowercased()) })?.value ?? "—"
    }
}

private struct LetterHighlightView: View {
    let document: Document

    var body: some View {
        HighlightSection(title: "Letter") {
            HighlightRow(label: "From", value: value(for: ["from", "sender"]))
            HighlightRow(label: "To", value: value(for: ["to", "recipient"]))
            HighlightRow(label: "Subject", value: value(for: ["subject", "title"]))
            HighlightRow(label: "Date", value: value(for: ["date", "sent_date"]))
        }
    }

    private func value(for keys: [String]) -> String {
        document.fields.first(where: { keys.contains($0.key.lowercased()) })?.value ?? "—"
    }
}

private struct BillStatementHighlightView: View {
    let document: Document

    var body: some View {
        HighlightSection(title: "Bill Statement") {
            HighlightRow(label: "Account #", value: value(for: ["account_number", "account"]))
            HighlightRow(label: "Amount Due", value: value(for: ["amount_due", "total_due", "balance"]))
            HighlightRow(label: "Due Date", value: value(for: ["due_date", "payment_due"]))
            HighlightRow(label: "Period", value: value(for: ["billing_period", "statement_period"]))
        }
    }

    private func value(for keys: [String]) -> String {
        document.fields.first(where: { keys.contains($0.key.lowercased()) })?.value ?? "—"
    }
}

// MARK: - Shared UI

private struct HighlightSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                content
            }
        }
    }
}

private struct HighlightRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.leading)
        }
    }
}
