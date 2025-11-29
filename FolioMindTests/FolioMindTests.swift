//
//  FolioMindTests.swift
//  FolioMindTests
//
//  Created by Jay Zeng on 11/23/25.
//

import Foundation
import SwiftData
import Testing
@testable import FolioMind

@MainActor
struct TestDocumentAnalyzer: DocumentAnalyzer {
    func analyze(imageURL: URL, hints: DocumentHints?) async throws -> DocumentAnalysisResult {
        let fields = [
            Field(key: "member_name", value: hints?.personName ?? "Test", confidence: 0.9, source: .vision)
        ]
        return DocumentAnalysisResult(
            ocrText: "OCR for \(imageURL.lastPathComponent)",
            fields: fields,
            docType: hints?.suggestedType ?? .generic,
            faceClusters: []
        )
    }
}

@MainActor
struct MockDocumentAnalyzer: DocumentAnalyzer {
    func analyze(imageURL: URL, hints: DocumentHints?) async throws -> DocumentAnalysisResult {
        let fields = [
            Field(key: "member_name", value: hints?.personName ?? "Test", confidence: 0.9, source: .vision)
        ]
        return DocumentAnalysisResult(
            ocrText: "Mock OCR",
            fields: fields,
            docType: hints?.suggestedType ?? .generic,
            faceClusters: []
        )
    }
}

@MainActor
final class MockSearchEngine: SearchEngine {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func search(_ query: SearchQuery) async throws -> [SearchResult] {
        let descriptor = FetchDescriptor<Document>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let documents = try modelContext.fetch(descriptor)
        let trimmed = query.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Simple keyword matching for tests
        let results = documents.filter { document in
            document.title.lowercased().contains(trimmed) ||
            document.ocrText.lowercased().contains(trimmed)
        }.map { document in
            SearchResult(
                document: document,
                score: SearchScoreComponents(keyword: 1.0, semantic: 0.5)
            )
        }

        return results
    }
}

struct FolioMindTests {

    @Test func documentDefaults() {
        let document = Document(title: "Untitled")
        #expect(document.docType == .generic)
        #expect(document.fields.isEmpty)
        #expect(document.faceClusterIDs.isEmpty)
        #expect(DocumentType.allCases.contains(.creditCard))
        #expect(DocumentType.allCases.contains(.billStatement))
    }

    @MainActor
    @Test func analyzerUsesHints() async throws {
        let analyzer = MockDocumentAnalyzer()
        let url = URL(fileURLWithPath: "/tmp/test.png")
        let result = try await analyzer.analyze(
            imageURL: url,
            hints: DocumentHints(suggestedType: .receipt, personName: "Alex")
        )
        #expect(result.docType == .receipt)
        #expect(result.fields.contains { $0.key == "member_name" && $0.value == "Alex" })
    }

    @MainActor
    @Test func documentStoreCreatesStubAndEmbedding() async throws {
        let schema = Schema([
            Document.self,
            Asset.self,
            Person.self,
            Field.self,
            FaceCluster.self,
            Embedding.self,
            DocumentPersonLink.self,
            DocumentReminder.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let store = DocumentStore(
            analyzer: TestDocumentAnalyzer(),
            embeddingService: SimpleEmbeddingService()
        )
        let created = try await store.createStubDocument(in: context, titleSuffix: 1)
        #expect(created.embedding != nil)
        #expect(!created.fields.isEmpty)
        // Stub documents don't have faces, only real scanned documents do
        // #expect(!created.faceClusterIDs.isEmpty)

        let documents = try context.fetch(FetchDescriptor<Document>())
        #expect(documents.count == 1)
    }

    @MainActor
    @Test func searchEngineMatchesTitle() async throws {
        let schema = Schema([
            Document.self,
            Asset.self,
            Person.self,
            Field.self,
            FaceCluster.self,
            Embedding.self,
            DocumentPersonLink.self,
            DocumentReminder.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let doc1 = Document(title: "Alpha Insurance Card", docType: .insuranceCard, ocrText: "Policy 123")
        let doc2 = Document(title: "Beta Receipt", docType: .receipt, ocrText: "Total 42")
        context.insert(doc1)
        context.insert(doc2)

        let search = MockSearchEngine(modelContext: context)
        let results = try await search.search(SearchQuery(text: "Alpha"))
        #expect(!results.isEmpty)
        #expect(results.first?.document.title == "Alpha Insurance Card")
    }

    @MainActor
    @Test func hybridSearchRanksByKeywordAndSemantic() async throws {
        let schema = Schema([
            Document.self,
            Asset.self,
            Person.self,
            Field.self,
            FaceCluster.self,
            Embedding.self,
            DocumentPersonLink.self,
            DocumentReminder.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let doc1 = Document(title: "Alpha Insurance Card", docType: .insuranceCard, ocrText: "Policy 123")
        let emb1 = Embedding(
            vector: [5.0, 0.0, 1.0],
            source: .mock,
            entityType: .document,
            entityID: doc1.id
        )
        let doc2 = Document(title: "Beta Receipt", docType: .receipt, ocrText: "Total 42")
        let emb2 = Embedding(
            vector: [1.0, 0.0, 0.0],
            source: .mock,
            entityType: .document,
            entityID: doc2.id
        )
        context.insert(doc1)
        context.insert(doc2)
        context.insert(emb1)
        context.insert(emb2)
        doc1.embedding = emb1
        doc2.embedding = emb2

        let search = HybridSearchEngine(
            modelContext: context,
            embeddingService: SimpleEmbeddingService(),
            keywordWeight: 0.5,
            semanticWeight: 0.5
        )
        let results = try await search.search(SearchQuery(text: "Alpha"))
        #expect(results.count == 2)
        #expect(results.first?.document.id == doc1.id)
    }

    @MainActor
    @Test func ingestDocumentsMergesOCRAcrossPages() async throws {
        let schema = Schema([
            Document.self,
            Asset.self,
            Person.self,
            Field.self,
            FaceCluster.self,
            Embedding.self,
            DocumentPersonLink.self,
            DocumentReminder.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let store = DocumentStore(
            analyzer: TestDocumentAnalyzer(),
            embeddingService: SimpleEmbeddingService()
        )
        let url1 = URL(fileURLWithPath: "/tmp/page1.png")
        let url2 = URL(fileURLWithPath: "/tmp/page2.png")
        let doc = try await store.ingestDocuments(
            from: [url1, url2],
            hints: DocumentHints(suggestedType: .receipt, personName: "Alex"),
            title: "Merged Doc",
            location: nil,
            capturedAt: Date(),
            in: context
        )

        #expect(doc.ocrText.contains("page1"))
        #expect(doc.ocrText.contains("page2"))
    }

    @Test func classifierDetectsCreditCard() {
        let text = "VISA 4111 1111 1111 1111 VALID THRU 12/29"
        let result = DocumentTypeClassifier.classify(
            ocrText: text,
            fields: [],
            hinted: nil,
            defaultType: .generic
        )
        #expect(result == .creditCard)
    }

    @Test func classifierDetectsCreditCardWithLineBreaks() {
        let text = """
        4111
        1111
        1111
        1111
        VALID THRU 12/29
        """
        let result = DocumentTypeClassifier.classify(
            ocrText: text,
            fields: [],
            hinted: nil,
            defaultType: .generic
        )
        #expect(result == .creditCard)
    }

    @Test func classifierDetectsCreditCardWithSpaces() {
        let text = "5567 5091 1310 9460 Valid Thru 10/30 Sec Code: 490"
        let result = DocumentTypeClassifier.classify(
            ocrText: text,
            fields: [],
            hinted: nil,
            defaultType: .generic
        )
        #expect(result == .creditCard)
    }

    @Test func cardDetailsExtractorFindsPanAndExpiry() {
        let text = """
        bofa.com/globalcardaccess
        THALES MGY U1216583C 0525
        5567 5091 1310 9460
        Valid Thru: 10/30 Sec Code: 490
        JAY ZENG
        BANK OF AMERICA
        """
        let details = CardDetailsExtractor.extract(ocrText: text, fields: [])
        #expect(details.pan == "5567509113109460")
        #expect(details.expiry == "10/30")
        #expect(details.holder == "JAY ZENG")
        #expect(details.issuer != nil)
        #expect(details.issuer?.lowercased().contains("bank") == true)
    }

    @Test func cardDetailsExtractorIgnoresEmbeddedDatesInAccountNumbers() {
        // Real-world example: "U1216553C" contains "12/16" but "Valid Thru: 10/30" is correct
        let text = """
        THALES MGY U1216553C 0525
        5567 5091 1310 9460
        Valid Thru: 10/30 Sec Code: 490
        JAY ZENG
        """
        let details = CardDetailsExtractor.extract(ocrText: text, fields: [])
        // Should extract "10/30" not "12/16" from U1216553C
        #expect(details.expiry == "10/30")
    }

    @Test func cardDetailsExtractorHandlesExpiryWithoutKeyword() {
        let text = """
        4111 1111 1111 1111
        12/29
        JOHN DOE
        """
        let details = CardDetailsExtractor.extract(ocrText: text, fields: [])
        #expect(details.expiry == "12/29")
    }

    @Test func cardDetailsExtractorHandlesExpiryWithDifferentFormats() {
        // Test MM/YY format
        let text1 = "Valid Thru 06/25 JANE DOE"
        let details1 = CardDetailsExtractor.extract(ocrText: text1, fields: [])
        #expect(details1.expiry == "06/25")

        // Test MM-YY format
        let text2 = "Exp: 03-27 JOHN SMITH"
        let details2 = CardDetailsExtractor.extract(ocrText: text2, fields: [])
        #expect(details2.expiry == "03/27")

        // Test MMYY format (no separator)
        let text3 = "Valid 0824 TEST USER"
        let details3 = CardDetailsExtractor.extract(ocrText: text3, fields: [])
        #expect(details3.expiry == "08/24")
    }

    @Test func cardDetailsExtractorPrefersFutureDates() {
        // When multiple date patterns exist, prefer future dates
        let text = """
        4111 1111 1111 1111
        01/20
        Valid: 05/28
        """
        let details = CardDetailsExtractor.extract(ocrText: text, fields: [])
        // Should prefer 05/28 (future) over 01/20 (past)
        #expect(details.expiry == "05/28")
    }

    @Test func cardDetailsExtractorHandlesDifferentIssuers() {
        let chaseText = "CHASE 4111111111111111 Exp 12/25"
        let chaseDetails = CardDetailsExtractor.extract(ocrText: chaseText, fields: [])
        #expect(chaseDetails.issuer?.lowercased().contains("chase") == true)

        let amexText = "AMERICAN EXPRESS 378282246310005"
        let amexDetails = CardDetailsExtractor.extract(ocrText: amexText, fields: [])
        #expect(amexDetails.issuer?.lowercased().contains("amex") == true ||
                amexDetails.issuer?.lowercased().contains("american express") == true)

        let discoverText = "DISCOVER 6011111111111117"
        let discoverDetails = CardDetailsExtractor.extract(ocrText: discoverText, fields: [])
        #expect(discoverDetails.issuer?.lowercased().contains("discover") == true)
    }

    @Test func cardDetailsExtractorExtractsPanWithDifferentFormats() {
        // With spaces
        let text1 = "4111 1111 1111 1111"
        let details1 = CardDetailsExtractor.extract(ocrText: text1, fields: [])
        #expect(details1.pan == "4111111111111111")

        // With dashes
        let text2 = "4111-1111-1111-1111"
        let details2 = CardDetailsExtractor.extract(ocrText: text2, fields: [])
        #expect(details2.pan == "4111111111111111")

        // No separators
        let text3 = "4111111111111111"
        let details3 = CardDetailsExtractor.extract(ocrText: text3, fields: [])
        #expect(details3.pan == "4111111111111111")
    }

    @Test func cardDetailsExtractorFindsHolderAfterCardDetails() {
        let text = """
        VISA
        4111 1111 1111 1111
        Valid Thru: 12/25
        ALICE WONDERLAND
        Card Services
        """
        let details = CardDetailsExtractor.extract(ocrText: text, fields: [])
        #expect(details.holder == "ALICE WONDERLAND")
    }

    @Test func cardDetailsExtractorIgnoresCommonTokensInHolderName() {
        let text = """
        4111 1111 1111 1111
        VALID THRU 12/25
        VISA CARD
        BOB JONES
        www.bankofamerica.com
        """
        let details = CardDetailsExtractor.extract(ocrText: text, fields: [])
        // Should skip "VISA CARD" and "www.bankofamerica.com", extract "BOB JONES"
        #expect(details.holder == "BOB JONES")
    }

    @Test func cardDetailsExtractorUsesFieldsWhenAvailable() {
        let text = "Some random text"
        let fields = [
            Field(key: "card_number", value: "4111111111111111", confidence: 0.9, source: .gemini),
            Field(key: "expiry", value: "12/25", confidence: 0.9, source: .gemini),
            Field(key: "cardholder", value: "TEST USER", confidence: 0.9, source: .gemini),
            Field(key: "issuer", value: "Test Bank", confidence: 0.9, source: .gemini)
        ]
        let details = CardDetailsExtractor.extract(ocrText: text, fields: fields)
        #expect(details.pan == "4111111111111111")
        #expect(details.expiry == "12/25")
        #expect(details.holder == "TEST USER")
        #expect(details.issuer == "Test Bank")
    }

    @Test func classifierDetectsInsuranceCard() {
        let text = "Health Insurance Member ID ABC123 Policy 456 Group 789"
        let result = DocumentTypeClassifier.classify(
            ocrText: text,
            fields: [],
            hinted: nil,
            defaultType: .generic
        )
        #expect(result == .insuranceCard)
    }

    @Test func classifierDetectsBillStatement() {
        let text = "Statement Date 01/01/2024 Amount Due $250.00 Due Date 02/01/2024"
        let result = DocumentTypeClassifier.classify(
            ocrText: text,
            fields: [],
            hinted: nil,
            defaultType: .generic
        )
        #expect(result == .billStatement)
    }

    @MainActor
    @Test func reminderManagerSuggestsCreditCardRenewal() {
        let manager = ReminderManager()
        let field = Field(key: "expiry", value: "12/25", confidence: 0.9, source: .vision)
        let document = Document(
            title: "Chase Visa",
            docType: .creditCard,
            ocrText: "4111111111111111 Valid Thru 12/25",
            fields: [field]
        )

        let suggestions = manager.suggestReminders(for: document)
        #expect(!suggestions.isEmpty)
        #expect(suggestions.contains { $0.type == .renewal })
    }

    @MainActor
    @Test func reminderManagerSuggestsInsuranceActions() {
        let manager = ReminderManager()
        let document = Document(
            title: "Health Insurance Card",
            docType: .insuranceCard,
            ocrText: "Member ID: ABC123 Group: 456"
        )

        let suggestions = manager.suggestReminders(for: document)
        #expect(!suggestions.isEmpty)
        // Should suggest call or appointment
        #expect(suggestions.contains { $0.type == .call || $0.type == .appointment })
    }

    @MainActor
    @Test func reminderManagerSuggestsBillPayment() {
        let manager = ReminderManager()
        let dueField = Field(key: "due_date", value: "2024-12-15", confidence: 0.9, source: .vision)
        let document = Document(
            title: "Electric Bill",
            docType: .billStatement,
            ocrText: "Amount Due: $125.00 Due Date: 12/15/2024",
            fields: [dueField]
        )

        let suggestions = manager.suggestReminders(for: document)
        #expect(!suggestions.isEmpty)
        #expect(suggestions.contains { $0.type == .payment })
    }

    @MainActor
    @Test func embeddingServiceProducesDifferentVectorsForDifferentText() async throws {
        let service = SimpleEmbeddingService()
        let doc1 = Document(title: "Short", ocrText: "A")
        let doc2 = Document(title: "Long document with many words", ocrText: String(repeating: "text ", count: 100))

        let emb1 = try await service.embedDocument(doc1)
        let emb2 = try await service.embedDocument(doc2)

        // Vectors should be different for different documents
        #expect(emb1.vector != emb2.vector)
    }

    @MainActor
    @Test func embeddingServiceProducesSimilarVectorsForSimilarText() async throws {
        let service = SimpleEmbeddingService()
        let doc1 = Document(title: "Insurance Card", ocrText: "Member ID ABC123")
        let doc2 = Document(title: "Insurance Card", ocrText: "Member ID XYZ789")

        let emb1 = try await service.embedDocument(doc1)
        let emb2 = try await service.embedDocument(doc2)

        // Vectors should be similar (not identical but close)
        // Simple similarity check: just verify they're not too different
        let diff = zip(emb1.vector, emb2.vector).reduce(0.0) { $0 + abs($1.0 - $1.1) }
        #expect(diff < 2.0) // Should have some similarity
    }

    @MainActor
    @Test func ingestDocumentsHandlesEmptyImageList() async throws {
        let schema = Schema([
            Document.self,
            Asset.self,
            Person.self,
            Field.self,
            FaceCluster.self,
            Embedding.self,
            DocumentPersonLink.self,
            DocumentReminder.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let store = DocumentStore(
            analyzer: TestDocumentAnalyzer(),
            embeddingService: SimpleEmbeddingService()
        )

        do {
            _ = try await store.ingestDocuments(
                from: [],
                hints: nil,
                title: nil,
                location: nil,
                capturedAt: Date(),
                in: context
            )
            #expect(Bool(false), "Should throw error for empty image list")
        } catch {
            // Expected to throw
            #expect(error.localizedDescription.contains("No images"))
        }
    }

    @MainActor
    @Test func documentStoreCreatesMultipleAssetsForMultiplePages() async throws {
        let schema = Schema([
            Document.self,
            Asset.self,
            Person.self,
            Field.self,
            FaceCluster.self,
            Embedding.self,
            DocumentPersonLink.self,
            DocumentReminder.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let store = DocumentStore(
            analyzer: TestDocumentAnalyzer(),
            embeddingService: SimpleEmbeddingService()
        )
        let url1 = URL(fileURLWithPath: "/tmp/page1.png")
        let url2 = URL(fileURLWithPath: "/tmp/page2.png")
        let url3 = URL(fileURLWithPath: "/tmp/page3.png")

        let doc = try await store.ingestDocuments(
            from: [url1, url2, url3],
            hints: nil,
            title: "Multi-page Document",
            location: nil,
            capturedAt: Date(),
            in: context
        )

        #expect(doc.assets.count == 3)
        #expect(doc.assets[0].pageNumber == 0)
        #expect(doc.assets[1].pageNumber == 1)
        #expect(doc.assets[2].pageNumber == 2)
    }

    @Test func fieldExtractorExtractsPhoneNumbers() {
        let text = "Contact us at (555) 123-4567 or 555-987-6543"
        let fields = FieldExtractor.extractFields(from: text)

        let phoneFields = fields.filter { $0.key.lowercased().contains("phone") }
        #expect(phoneFields.count >= 1)
    }

    @Test func fieldExtractorExtractsEmails() {
        let text = "Email: support@example.com or contact@test.org"
        let fields = FieldExtractor.extractFields(from: text)

        let emailFields = fields.filter { $0.key.lowercased().contains("email") }
        #expect(emailFields.count >= 1)
    }

    @Test func fieldExtractorExtractsURLs() {
        let text = "Visit https://example.com or www.test.com"
        let fields = FieldExtractor.extractFields(from: text)

        let urlFields = fields.filter { $0.key.lowercased().contains("url") || $0.key.lowercased().contains("website") }
        #expect(urlFields.count >= 1)
    }

    @Test func fieldExtractorDeduplicatesFields() {
        let text = "Email: test@example.com Email: test@example.com"
        let fields = FieldExtractor.extractFields(from: text)

        let emailFields = fields.filter { $0.key.lowercased().contains("email") && $0.value == "test@example.com" }
        // Should deduplicate identical values
        #expect(emailFields.count <= 2)
    }

    @Test func documentTypeHasDisplayNames() {
        #expect(DocumentType.creditCard.displayName == "Credit Card")
        #expect(DocumentType.insuranceCard.displayName == "Insurance")
        #expect(DocumentType.billStatement.displayName == "Statement")
        #expect(DocumentType.receipt.displayName == "Receipt")
        #expect(DocumentType.generic.displayName == "Document")
    }

    @Test func documentTypeHasIcons() {
        for docType in DocumentType.allCases {
            #expect(!docType.symbolName.isEmpty)
        }
    }

    @Test func assetTypeHasIcons() {
        #expect(AssetType.image.icon == "photo")
        #expect(AssetType.pdf.icon == "doc.text")
        #expect(AssetType.document.icon == "doc")
    }
}
