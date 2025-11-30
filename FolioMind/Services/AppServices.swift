//
//  AppServices.swift
//  FolioMind
//
//  Wires model container, services, and storage utilities for dependency injection.
//

import Foundation
import AVFoundation
import SwiftData

struct AudioRecordingResult {
    let url: URL
    let startedAt: Date
    let duration: TimeInterval
}

@MainActor
final class AudioRecorderService: NSObject, ObservableObject, AVAudioRecorderDelegate {
    enum RecorderError: LocalizedError {
        case permissionDenied
        case alreadyRecording
        case noActiveRecording
        case configurationFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone access is needed to record audio."
            case .alreadyRecording:
                return "Recording is already in progress."
            case .noActiveRecording:
                return "No recording is currently in progress."
            case .configurationFailed(let message):
                return "Could not start recording: \(message)"
            }
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var lastError: String?

    private var recorder: AVAudioRecorder?
    private var currentURL: URL?
    private var recordingStartDate: Date?
    private let directoryName = "FolioMindRecordings"

    func startRecording() async throws -> URL {
        guard !isRecording else { throw RecorderError.alreadyRecording }
        lastError = nil

        let session = AVAudioSession.sharedInstance()
        let granted = try await requestPermission(session: session)
        guard granted else { throw RecorderError.permissionDenied }

        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            lastError = error.localizedDescription
            throw RecorderError.configurationFailed(error.localizedDescription)
        }

        let url = try makeRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            guard recorder?.record() == true else {
                lastError = "Unable to start microphone recording."
                throw RecorderError.configurationFailed("Unable to start microphone recording.")
            }
            currentURL = url
            recordingStartDate = Date()
            isRecording = true
            return url
        } catch {
            lastError = error.localizedDescription
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            throw RecorderError.configurationFailed(error.localizedDescription)
        }
    }

    func stopRecording() throws -> AudioRecordingResult {
        guard isRecording, let recorder, let url = currentURL, let startedAt = recordingStartDate else {
            throw RecorderError.noActiveRecording
        }

        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        currentURL = nil
        recordingStartDate = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        return AudioRecordingResult(url: url, startedAt: startedAt, duration: duration)
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        _ = recorder
        if let error {
            lastError = error.localizedDescription
        }
    }

    private func requestPermission(session: AVAudioSession) async throws -> Bool {
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func makeRecordingURL() throws -> URL {
        let fm = FileManager.default
        let documents = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = documents.appendingPathComponent(directoryName, isDirectory: true)
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("\(UUID().uuidString).m4a")
    }
}

@MainActor
final class AppServices: ObservableObject {
    let modelContainer: ModelContainer
    let documentStore: DocumentStore
    let analyzer: DocumentAnalyzer
    let searchEngine: SearchEngine
    let embeddingService: EmbeddingService
    let linkingEngine: LinkingEngine
    let reminderManager: ReminderManager
    let audioRecorder: AudioRecorderService
    let audioNoteManager: AudioNoteManager
    let llmService: LLMService?

    init() {
        let schema = Schema([
            Document.self,
            Asset.self,
            Person.self,
            Field.self,
            FaceCluster.self,
            Embedding.self,
            DocumentPersonLink.self,
            DocumentReminder.self,
            AudioNote.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // If migration fails, delete the store and recreate it (development only)
            print("Migration failed, attempting to recreate store: \(error)")

            // Delete the old store
            let storeURL = configuration.url
            try? FileManager.default.removeItem(at: storeURL)

            // Also remove associated files
            let shmURL = storeURL.appendingPathExtension("shm")
            let walURL = storeURL.appendingPathExtension("wal")
            try? FileManager.default.removeItem(at: shmURL)
            try? FileManager.default.removeItem(at: walURL)

            // Try again with a fresh store
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Could not create ModelContainer even after cleanup: \(error)")
            }
        }

        // Initialize intelligent field extractor with LLM
        // Try Apple Intelligence first, fall back to OpenAI if configured
        var llmService: LLMService? = nil

        // Check user preferences
        let useAppleIntelligence = UserDefaults.standard.bool(forKey: "use_apple_intelligence")
        let useOpenAIFallback = UserDefaults.standard.bool(forKey: "use_openai_fallback")

        // Set defaults on first launch
        if !UserDefaults.standard.bool(forKey: "has_launched_before") {
            UserDefaults.standard.set(true, forKey: "use_apple_intelligence")
            UserDefaults.standard.set(true, forKey: "use_openai_fallback")
            UserDefaults.standard.set(true, forKey: "has_launched_before")
        }

        // Try Apple Intelligence if enabled and available
        if useAppleIntelligence {
            llmService = LLMServiceFactory.create(type: .apple)
            if llmService != nil {
                print("✅ Apple Intelligence available for intelligent field extraction")
            }
        }

        // Fallback to OpenAI if enabled and API key is configured
        if llmService == nil && useOpenAIFallback {
            if let apiKey = UserDefaults.standard.string(forKey: "openai_api_key"), !apiKey.isEmpty {
                llmService = LLMServiceFactory.create(type: .openai(apiKey: apiKey))
                print("✅ Using OpenAI for intelligent field extraction")
            } else {
                print("⚠️ OpenAI fallback enabled but no API key configured.")
                print("💡 Add your API key in Settings to enable OpenAI intelligent extraction.")
            }
        }

        if llmService == nil {
            print("ℹ️ No LLM service available. Using pattern-based extraction only.")
            print("💡 To enable intelligent extraction:")
            print("   • Use iOS 18.2+ with Apple Intelligence, or")
            print("   • Add OpenAI API key in Settings")
        }

        let intelligentExtractor = IntelligentFieldExtractor(
            llmService: llmService,
            useNaturalLanguage: true
        )

        analyzer = VisionDocumentAnalyzer(
            cloudService: nil,
            defaultType: .generic,
            intelligentExtractor: intelligentExtractor,
            llmService: llmService
        )
        embeddingService = SimpleEmbeddingService()
        linkingEngine = BasicLinkingEngine()
        reminderManager = ReminderManager()
        audioRecorder = AudioRecorderService()
        audioNoteManager = AudioNoteManager(llmService: llmService)
        self.llmService = llmService

        let modelContext = ModelContext(modelContainer)
        searchEngine = HybridSearchEngine(
            modelContext: modelContext,
            embeddingService: embeddingService
        )
        documentStore = DocumentStore(analyzer: analyzer, embeddingService: embeddingService, llmService: llmService)
    }
}

@MainActor
final class DocumentStore {
    enum StoreError: LocalizedError {
        case noAssets

        var errorDescription: String? {
            switch self {
            case .noAssets:
                return "This document has no images to re-extract from."
            }
        }
    }

    private let analyzer: DocumentAnalyzer
    private let embeddingService: EmbeddingService
    private let llmService: LLMService?
    private let metadataExtractor: ImageMetadataExtracting
    private let assetDirectoryName = "FolioMindAssets"

    init(
        analyzer: DocumentAnalyzer,
        embeddingService: EmbeddingService,
        llmService: LLMService? = nil,
        metadataExtractor: ImageMetadataExtracting = ImageMetadataExtractor()
    ) {
        self.analyzer = analyzer
        self.embeddingService = embeddingService
        self.llmService = llmService
        self.metadataExtractor = metadataExtractor
    }

    func createStubDocument(in context: ModelContext, titleSuffix: Int) async throws -> Document {
        let now = Date()
        let stubField = Field(key: "note", value: "Sample stub", confidence: 0.5, source: .fused)
        let document = Document(
            title: "Sample Document \(titleSuffix)",
            docType: .generic,
            ocrText: "Stub document created at \(now)",
            fields: [stubField],
            createdAt: now,
            capturedAt: now,
            location: "Local",
            assets: [],
            personLinks: [],
            faceClusterIDs: []
        )
        context.insert(document)
        let embedding = try await embeddingService.embedDocument(document)
        context.insert(embedding)
        document.embedding = embedding
        try context.save()
        return document
    }

    func delete(at offsets: IndexSet, from documents: [Document], in context: ModelContext) {
        for index in offsets {
            context.delete(documents[index])
        }
        try? context.save()
    }

    func ingestDocuments(
        from imageURLs: [URL],
        hints: DocumentHints? = nil,
        title: String? = nil,
        location: String? = nil,
        capturedAt: Date? = nil,
        in context: ModelContext
    ) async throws -> Document {
        guard !imageURLs.isEmpty else {
            throw NSError(domain: "FolioMind", code: -1, userInfo: [NSLocalizedDescriptionKey: "No images to ingest."])
        }

        // Persist assets into Documents/FolioMindAssets so they survive rebuilds/restarts
        let persistentURLs = try imageURLs.map { try persistAsset(from: $0) }

        let metadataSnapshots = persistentURLs.map { metadataExtractor.extract(from: $0) }
        let metadataLocation = metadataSnapshots
            .compactMap { cleanedLocation($0.locationDescription) }
            .first
        let metadataCaptureDate = metadataSnapshots.compactMap { $0.captureDate }.sorted().first

        var analyses: [DocumentAnalysisResult] = []
        for url in persistentURLs {
            let analysis = try await analyzer.analyze(imageURL: url, hints: hints)
            analyses.append(analysis)
        }

        let combinedOCR = analyses.map(\.ocrText).joined(separator: "\n\n")
        let combinedFields = analyses.flatMap(\.fields)
        let combinedFaces = analyses.flatMap(\.faceClusters)
        let faceIDs = combinedFaces.map { $0.id }
        let derivedTitle = title ?? hints?.personName.map { "\($0)'s Document" }
            ?? imageURLs.first!.deletingPathExtension().lastPathComponent
        let docType = DocumentTypeClassifier.classify(
            ocrText: combinedOCR,
            fields: combinedFields,
            hinted: hints?.suggestedType ?? analyses.first?.docType,
            defaultType: .generic
        )

        // Generate cleaned text using LLM if available
        var cleanedText: String? = nil
        if let llmService = llmService, !combinedOCR.isEmpty {
            do {
                cleanedText = try await llmService.cleanText(combinedOCR)
            } catch {
                // Fall back to nil if cleaning fails
                print("Text cleaning failed: \(error.localizedDescription)")
            }
        }

        combinedFields.forEach { context.insert($0) }
        combinedFaces.forEach { context.insert($0) }

        // Create Asset objects for each image
        let assets = persistentURLs.enumerated().map { index, url in
            Asset(
                fileURL: url.path,
                assetType: .image,
                addedAt: Date(),
                pageNumber: index
            )
        }
        assets.forEach { context.insert($0) }

        let document = Document(
            title: derivedTitle,
            docType: docType,
            ocrText: combinedOCR,
            cleanedText: cleanedText,
            fields: combinedFields,
            createdAt: Date(),
            capturedAt: capturedAt ?? metadataCaptureDate ?? Date(),
            location: cleanedLocation(location) ?? metadataLocation,
            assets: assets,
            personLinks: [],
            faceClusterIDs: faceIDs
        )
        context.insert(document)
        let embedding = try await embeddingService.embedDocument(document)
        context.insert(embedding)
        document.embedding = embedding
        try context.save()
        return document
    }

    // MARK: - Asset Persistence

    private func cleanedLocation(_ location: String?) -> String? {
        guard let trimmed = location?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Copy an asset into a persistent app Documents subdirectory and return its new URL.
    private func persistAsset(from url: URL) throws -> URL {
        let fm = FileManager.default
        let destDir = try ensureAssetDirectory()
        let destination = destDir.appendingPathComponent("\(UUID().uuidString)\(url.pathExtension.isEmpty ? "" : ".")\(url.pathExtension)")

        // If the source is already in our destination directory, skip the copy
        if url.deletingLastPathComponent() == destDir {
            return url
        }

        // Avoid duplicating files if an identical name exists
        if !fm.fileExists(atPath: destination.path) {
            try fm.copyItem(at: url, to: destination)
        }

        return destination
    }

    private func ensureAssetDirectory() throws -> URL {
        let fm = FileManager.default
        let documents = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = documents.appendingPathComponent(assetDirectoryName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Re-run extraction for an existing document using its current image assets.
    func reextract(
        document: Document,
        in context: ModelContext
    ) async throws -> Document {
        let imageAssets = document.imageAssets
        guard !imageAssets.isEmpty else {
            throw StoreError.noAssets
        }

        var analyses: [DocumentAnalysisResult] = []
        for asset in imageAssets {
            let url = URL(fileURLWithPath: asset.fileURL)
            let analysis = try await analyzer.analyze(
                imageURL: url,
                hints: DocumentHints(
                    suggestedType: document.docType,
                    personName: nil
                )
            )
            analyses.append(analysis)
        }

        let combinedOCR = analyses.map(\.ocrText).joined(separator: "\n\n")
        let combinedFields = analyses.flatMap(\.fields)
        let combinedFaces = analyses.flatMap(\.faceClusters)
        let faceIDs = combinedFaces.map { $0.id }

        let docType = DocumentTypeClassifier.classify(
            ocrText: combinedOCR,
            fields: combinedFields,
            hinted: document.docType,
            defaultType: document.docType
        )

        var cleanedText: String? = nil
        if let llmService = llmService, !combinedOCR.isEmpty {
            do {
                cleanedText = try await llmService.cleanText(combinedOCR)
            } catch {
                print("Text cleaning failed during re-extraction: \(error.localizedDescription)")
            }
        }

        // Replace existing fields to avoid stale SwiftData objects
        document.fields.forEach { context.delete($0) }
        document.fields.removeAll()
        combinedFields.forEach { context.insert($0) }
        combinedFaces.forEach { context.insert($0) }

        document.docType = docType
        document.ocrText = combinedOCR
        document.cleanedText = cleanedText
        document.fields = combinedFields
        document.faceClusterIDs = faceIDs

        // Update embedding in place if present
        let freshEmbedding = try await embeddingService.embedDocument(document)
        if let existingEmbedding = document.embedding {
            existingEmbedding.vector = freshEmbedding.vector
            existingEmbedding.source = freshEmbedding.source
            existingEmbedding.entityType = freshEmbedding.entityType
            existingEmbedding.entityID = freshEmbedding.entityID
        } else {
            context.insert(freshEmbedding)
            document.embedding = freshEmbedding
        }

        try context.save()
        return document
    }
}
