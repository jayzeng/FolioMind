//
//  DomainModels.swift
//  FolioMind
//
//  Defines core domain models used across capture, analysis, linking, and search.
//

import Foundation
import SwiftData

enum DocumentType: String, Codable, CaseIterable {
    case insuranceCard
    case idCard
    case receipt
    case generic
}

enum FieldSource: String, Codable, CaseIterable {
    case vision
    case gemini
    case openai
    case fused
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
    var confidence: Double
    var source: FieldSource

    init(
        id: UUID = UUID(),
        key: String,
        value: String,
        confidence: Double = 1.0,
        source: FieldSource = .fused
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.confidence = confidence
        self.source = source
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
final class Document {
    @Attribute(.unique) var id: UUID
    var title: String
    var docType: DocumentType
    var ocrText: String
    var fields: [Field]
    var createdAt: Date
    var capturedAt: Date?
    var location: String?
    var assetURL: String?
    var personLinks: [DocumentPersonLink]
    var faceClusterIDs: [UUID]
    var embedding: Embedding?

    init(
        id: UUID = UUID(),
        title: String,
        docType: DocumentType = .generic,
        ocrText: String = "",
        fields: [Field] = [],
        createdAt: Date = Date(),
        capturedAt: Date? = nil,
        location: String? = nil,
        assetURL: String? = nil,
        personLinks: [DocumentPersonLink] = [],
        faceClusterIDs: [UUID] = [],
        embedding: Embedding? = nil
    ) {
        self.id = id
        self.title = title
        self.docType = docType
        self.ocrText = ocrText
        self.fields = fields
        self.createdAt = createdAt
        self.capturedAt = capturedAt
        self.location = location
        self.assetURL = assetURL
        self.personLinks = personLinks
        self.faceClusterIDs = faceClusterIDs
        self.embedding = embedding
    }
}
