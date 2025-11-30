//
//  DomainModels.swift
//  FolioMind
//
//  Defines core domain models used across capture, analysis, linking, and search.
//

import Foundation
import SwiftData

enum DocumentType: String, Codable, CaseIterable {
    case creditCard
    case insuranceCard
    case idCard
    case letter
    case billStatement
    case receipt
    case generic
}

enum FieldSource: String, Codable, CaseIterable {
    case vision
    case gemini
    case openai
    case fused
}

enum AssetType: String, Codable, CaseIterable {
    case image
    case pdf
    case document

    var icon: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.text"
        case .document: return "doc"
        }
    }
}

enum DocumentRelationship: String, Codable, CaseIterable {
    case owner
    case dependent
    case mentioned
}

enum EmbeddingSource: String, Codable, CaseIterable {
    case gemini
    case openai
    case mock
}

enum EmbeddingEntityType: String, Codable, CaseIterable {
    case document
    case person
}

enum ReminderType: String, Codable, CaseIterable {
    case call
    case appointment
    case payment
    case renewal
    case followUp
    case custom
}

@Model
final class AudioNote {
    @Attribute(.unique) var id: UUID
    var title: String
    var fileURL: String
    var createdAt: Date
    var duration: TimeInterval
    var transcript: String?
    var summary: String?

    init(
        id: UUID = UUID(),
        title: String,
        fileURL: String,
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        transcript: String? = nil,
        summary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.duration = duration
        self.transcript = transcript
        self.summary = summary
    }
}

@Model
final class Embedding {
    @Attribute(.unique) var id: UUID
    var vector: [Double]
    var source: EmbeddingSource
    var entityType: EmbeddingEntityType
    var entityID: UUID

    init(
        id: UUID = UUID(),
        vector: [Double],
        source: EmbeddingSource,
        entityType: EmbeddingEntityType,
        entityID: UUID
    ) {
        self.id = id
        self.vector = vector
        self.source = source
        self.entityType = entityType
        self.entityID = entityID
    }
}

@Model
final class Field {
    @Attribute(.unique) var id: UUID
    var key: String
    var value: String
    @Attribute(.preserveValueOnDeletion) var originalValue: String = ""
    var confidence: Double
    var source: FieldSource

    init(
        id: UUID = UUID(),
        key: String,
        value: String,
        originalValue: String? = nil,
        confidence: Double = 1.0,
        source: FieldSource = .fused
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.originalValue = originalValue ?? value
        self.confidence = confidence
        self.source = source
    }

    var isModified: Bool {
        !originalValue.isEmpty && value != originalValue
    }

    func reset() {
        if !originalValue.isEmpty {
            value = originalValue
        }
    }
}

@Model
final class FaceCluster {
    @Attribute(.unique) var id: UUID
    var descriptor: Data
    var label: String?
    var lastUpdated: Date

    init(
        id: UUID = UUID(),
        descriptor: Data = Data(),
        label: String? = nil,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.descriptor = descriptor
        self.label = label
        self.lastUpdated = lastUpdated
    }
}

@Model
final class Person {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var aliases: [String]
    var emails: [String]
    var phones: [String]
    var addresses: [String]
    var faceClusterIDs: [UUID]
    var notes: String
    var embedding: Embedding?

    init(
        id: UUID = UUID(),
        displayName: String,
        aliases: [String] = [],
        emails: [String] = [],
        phones: [String] = [],
        addresses: [String] = [],
        faceClusterIDs: [UUID] = [],
        notes: String = "",
        embedding: Embedding? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.emails = emails
        self.phones = phones
        self.addresses = addresses
        self.faceClusterIDs = faceClusterIDs
        self.notes = notes
        self.embedding = embedding
    }
}

@Model
final class DocumentPersonLink {
    @Attribute(.unique) var id: UUID
    var person: Person?
    var relationship: DocumentRelationship
    var confidence: Double

    init(
        id: UUID = UUID(),
        person: Person? = nil,
        relationship: DocumentRelationship = .owner,
        confidence: Double = 1.0
    ) {
        self.id = id
        self.person = person
        self.relationship = relationship
        self.confidence = confidence
    }
}

@Model
final class DocumentReminder {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var dueDate: Date
    var reminderType: ReminderType
    var isCompleted: Bool
    var eventKitID: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueDate: Date,
        reminderType: ReminderType = .custom,
        isCompleted: Bool = false,
        eventKitID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.reminderType = reminderType
        self.isCompleted = isCompleted
        self.eventKitID = eventKitID
        self.createdAt = createdAt
    }
}

// MARK: - Asset Model

/// Represents a single file/image asset belonging to a document
@Model
final class Asset {
    @Attribute(.unique) var id: UUID
    var fileURL: String  // Local file path
    var assetType: AssetType
    var addedAt: Date
    var pageNumber: Int  // Order/page number within the document
    var thumbnailURL: String?  // Optional thumbnail for quick preview

    // Relationship
    var document: Document?

    init(
        id: UUID = UUID(),
        fileURL: String,
        assetType: AssetType,
        addedAt: Date = Date(),
        pageNumber: Int = 0,
        thumbnailURL: String? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.assetType = assetType
        self.addedAt = addedAt
        self.pageNumber = pageNumber
        self.thumbnailURL = thumbnailURL
    }
}

// MARK: - Document Model

@Model
final class Document {
    @Attribute(.unique) var id: UUID
    var title: String
    var docType: DocumentType
    var ocrText: String
    var cleanedText: String?  // LLM-cleaned version of OCR text for better readability
    var fields: [Field]
    var createdAt: Date
    var capturedAt: Date?
    var location: String?
    var assets: [Asset]  // Multiple images/files belonging to this document
    var personLinks: [DocumentPersonLink]
    var faceClusterIDs: [UUID]
    var embedding: Embedding?
    var reminders: [DocumentReminder]

    init(
        id: UUID = UUID(),
        title: String,
        docType: DocumentType = .generic,
        ocrText: String = "",
        cleanedText: String? = nil,
        fields: [Field] = [],
        createdAt: Date = Date(),
        capturedAt: Date? = nil,
        location: String? = nil,
        assets: [Asset] = [],
        personLinks: [DocumentPersonLink] = [],
        faceClusterIDs: [UUID] = [],
        embedding: Embedding? = nil,
        reminders: [DocumentReminder] = []
    ) {
        self.id = id
        self.title = title
        self.docType = docType
        self.ocrText = ocrText
        self.cleanedText = cleanedText
        self.fields = fields
        self.createdAt = createdAt
        self.capturedAt = capturedAt
        self.location = location
        self.assets = assets
        self.personLinks = personLinks
        self.faceClusterIDs = faceClusterIDs
        self.embedding = embedding
        self.reminders = reminders
    }

    // Computed property for backward compatibility - returns first asset URL
    var assetURL: String? {
        assets.first?.fileURL
    }

    // Returns all image assets sorted by page number
    var imageAssets: [Asset] {
        assets
            .filter { $0.assetType == .image }
            .sorted { $0.pageNumber < $1.pageNumber }
    }
}

// MARK: - Localized Display Names

extension DocumentType {
    var displayName: String {
        switch self {
        case .creditCard:
            String(localized: "document.type.creditCard", defaultValue: "Credit Card", comment: "Document type: Credit Card")
        case .insuranceCard:
            String(localized: "document.type.insuranceCard", defaultValue: "Insurance Card", comment: "Document type: Insurance Card")
        case .idCard:
            String(localized: "document.type.idCard", defaultValue: "ID Card", comment: "Document type: ID Card")
        case .letter:
            String(localized: "document.type.letter", defaultValue: "Letter", comment: "Document type: Letter")
        case .billStatement:
            String(localized: "document.type.billStatement", defaultValue: "Bill Statement", comment: "Document type: Bill Statement")
        case .receipt:
            String(localized: "document.type.receipt", defaultValue: "Receipt", comment: "Document type: Receipt")
        case .generic:
            String(localized: "document.type.generic", defaultValue: "Document", comment: "Document type: Generic Document")
        }
    }
}

extension FieldSource {
    var displayName: String {
        switch self {
        case .vision:
            String(localized: "field.source.vision", defaultValue: "Vision", comment: "Field source: Vision Framework")
        case .gemini:
            String(localized: "field.source.gemini", defaultValue: "Gemini", comment: "Field source: Google Gemini")
        case .openai:
            String(localized: "field.source.openai", defaultValue: "OpenAI", comment: "Field source: OpenAI")
        case .fused:
            String(localized: "field.source.fused", defaultValue: "Fused", comment: "Field source: Fused from multiple sources")
        }
    }
}

extension AssetType {
    var displayName: String {
        switch self {
        case .image:
            String(localized: "asset.type.image", defaultValue: "Image", comment: "Asset type: Image")
        case .pdf:
            String(localized: "asset.type.pdf", defaultValue: "PDF", comment: "Asset type: PDF")
        case .document:
            String(localized: "asset.type.document", defaultValue: "Document", comment: "Asset type: Document")
        }
    }
}

extension DocumentRelationship {
    var displayName: String {
        switch self {
        case .owner:
            String(localized: "relationship.owner", defaultValue: "Owner", comment: "Document relationship: Owner")
        case .dependent:
            String(localized: "relationship.dependent", defaultValue: "Dependent", comment: "Document relationship: Dependent")
        case .mentioned:
            String(localized: "relationship.mentioned", defaultValue: "Mentioned", comment: "Document relationship: Mentioned")
        }
    }
}

extension ReminderType {
    var displayName: String {
        switch self {
        case .call:
            String(localized: "reminder.type.call", defaultValue: "Call", comment: "Reminder type: Phone Call")
        case .appointment:
            String(localized: "reminder.type.appointment", defaultValue: "Appointment", comment: "Reminder type: Appointment")
        case .payment:
            String(localized: "reminder.type.payment", defaultValue: "Payment", comment: "Reminder type: Payment")
        case .renewal:
            String(localized: "reminder.type.renewal", defaultValue: "Renewal", comment: "Reminder type: Renewal")
        case .followUp:
            String(localized: "reminder.type.followUp", defaultValue: "Follow Up", comment: "Reminder type: Follow Up")
        case .custom:
            String(localized: "reminder.type.custom", defaultValue: "Custom", comment: "Reminder type: Custom")
        }
    }
}
