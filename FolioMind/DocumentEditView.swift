//
//  DocumentEditView.swift
//  FolioMind
//
//  Edit view for modifying document metadata.
//

import SwiftUI

struct DocumentEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var document: Document

    @State private var editedTitle: String = ""
    @State private var editedDocType: DocumentType = .generic
    @State private var editedLocation: String = ""

    var body: some View {
        Form {
            Section("Document Details") {
                TextField("Title", text: $editedTitle)
                    .textInputAutocapitalization(.words)

                Picker("Type", selection: $editedDocType) {
                    ForEach(DocumentType.allCases, id: \.self) { type in
                        Label(type.displayName, systemImage: type.symbolName)
                            .tag(type)
                    }
                }

                TextField("Location", text: $editedLocation)
                    .textInputAutocapitalization(.words)
            }

            Section("Metadata") {
                if let capturedAt = document.capturedAt {
                    LabeledContent("Captured") {
                        Text(capturedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Created") {
                    Text(document.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }

                if !document.fields.isEmpty {
                    LabeledContent("Fields Extracted") {
                        Text("\(document.fields.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("OCR Text") {
                if document.ocrText.isEmpty {
                    Text("No text extracted")
                        .foregroundStyle(.secondary)
                } else {
                    Text(document.ocrText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                }
            }
        }
        .navigationTitle("Edit Document")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveChanges()
                    dismiss()
                }
                .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            editedTitle = document.title
            editedDocType = document.docType
            editedLocation = document.location ?? ""
        }
    }

    private func saveChanges() {
        document.title = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        document.docType = editedDocType
        document.location = editedLocation.isEmpty ? nil : editedLocation.trimmingCharacters(in: .whitespacesAndNewlines)

        try? modelContext.save()
    }
}
