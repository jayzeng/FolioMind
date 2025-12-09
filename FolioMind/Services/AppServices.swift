//
//  AppServices.swift
//  FolioMind
//
//  Wires model container, services, and storage utilities for dependency injection.
//

import Foundation
import AVFoundation
import SwiftData
import UIKit

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
    @Published private(set) var isPaused = false
    @Published private(set) var lastError: String?
    @Published private(set) var audioLevel: Float = 0.0
    @Published private(set) var currentDuration: TimeInterval = 0.0

    private var recorder: AVAudioRecorder?
    private var currentURL: URL?
    private var recordingStartDate: Date?
    private var levelTimer: Timer?
    private let storageManager = FileStorageManager.shared

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
            recorder?.isMeteringEnabled = true
            guard recorder?.record() == true else {
                lastError = "Unable to start microphone recording."
                throw RecorderError.configurationFailed("Unable to start microphone recording.")
            }
            currentURL = url
            recordingStartDate = Date()
            isRecording = true
            isPaused = false
            startLevelMonitoring()
            return url
        } catch {
            lastError = error.localizedDescription
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            throw RecorderError.configurationFailed(error.localizedDescription)
        }
    }

    func pauseRecording() {
        guard isRecording, !isPaused, let recorder else { return }
        recorder.pause()
        isPaused = true
        stopLevelMonitoring()
    }

    func resumeRecording() {
        guard isRecording, isPaused, let recorder else { return }
        recorder.record()
        isPaused = false
        startLevelMonitoring()
    }

    func stopRecording() throws -> AudioRecordingResult {
        guard isRecording, let recorder, let url = currentURL, let startedAt = recordingStartDate else {
            throw RecorderError.noActiveRecording
        }

        let duration = recorder.currentTime
        recorder.stop()
        stopLevelMonitoring()
        self.recorder = nil
        currentURL = nil
        recordingStartDate = nil
        isRecording = false
        isPaused = false
        audioLevel = 0.0
        currentDuration = 0.0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        return AudioRecordingResult(url: url, startedAt: startedAt, duration: duration)
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        _ = recorder
        if let error {
            Task { @MainActor in
                self.lastError = error.localizedDescription
            }
        }
    }

    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let recorder = await self.recorder else { return }
                recorder.updateMeters()
                let averagePower = recorder.averagePower(forChannel: 0)
                // Convert dB to 0-1 range (dB range typically -160 to 0)
                let normalizedLevel = pow(10, averagePower / 20)
                await self.updateAudioMetrics(level: normalizedLevel, duration: recorder.currentTime)
            }
        }
    }

    private func updateAudioMetrics(level: Float, duration: TimeInterval) {
        self.audioLevel = level
        self.currentDuration = duration
    }

    private func stopLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
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
        let directory = try storageManager.url(for: .recordings)
        let filename = storageManager.uniqueFilename(withExtension: "m4a")
        return directory.appendingPathComponent(filename)
    }
}

@MainActor
final class AppServices: ObservableObject {
    let modelContainer: ModelContainer
    let documentStore: DocumentStore
    let analyzer: DocumentAnalyzer
    let searchEngine: SearchEngine
    let libSQLStore: LibSQLStore?
    let embeddingService: EmbeddingService
    let linkingEngine: LinkingEngine
    let reminderManager: ReminderManager
    let audioRecorder: AudioRecorderService
    let audioPlayer: AudioPlayerService
    let audioNoteManager: AudioNoteManaging
    let audioTranscriptionService: AudioTranscriptionService
    let llmService: LLMService?
    let authViewModel: AuthViewModel
    let useBackendProcessing: Bool

    init() {
        // Initialize authentication first
        self.authViewModel = AuthViewModel()

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

        // Set default to use backend on first launch
        if !UserDefaults.standard.bool(forKey: "has_launched_before") {
            UserDefaults.standard.set(true, forKey: "use_backend_processing")
            UserDefaults.standard.set(true, forKey: "has_launched_before")
        }

        // Migration: If the backend setting doesn't exist yet (from older version), set it to true
        if UserDefaults.standard.object(forKey: "use_backend_processing") == nil {
            print("🔄 Migrating to backend processing mode")
            UserDefaults.standard.set(true, forKey: "use_backend_processing")
        }

        // Check user preference for backend vs local processing (after setting defaults)
        let useBackend = UserDefaults.standard.bool(forKey: "use_backend_processing")

        var llmService: LLMService?
        let libSQLStore: LibSQLStore?

        do {
            libSQLStore = try LibSQLStore()
            print("✅ LibSQLStore initialized for on-device search index")
        } catch {
            libSQLStore = nil
            print("⚠️ LibSQLStore unavailable: \(error.localizedDescription)")
        }

        print("⚙️ Processing mode: \(useBackend ? "Backend API" : "Local on-device")")

        if useBackend {
            // Use backend API service
            print("🌐 Using backend API for document processing")
            let backendService = BackendAPIService(tokenManager: authViewModel.getTokenManager())
            llmService = BackendLLMService(apiService: backendService)
            analyzer = BackendDocumentAnalyzer(
                backendService: backendService,
                useBackendOCR: true
            )
            audioNoteManager = BackendAudioNoteManager(backendService: backendService)
        } else {
            // Use local processing with Apple Intelligence or OpenAI
            print("📱 Using local on-device processing")

            let useAppleIntelligence = UserDefaults.standard.bool(forKey: "use_apple_intelligence")
            let useOpenAIFallback = UserDefaults.standard.bool(forKey: "use_openai_fallback")

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
            audioNoteManager = AudioNoteManager(llmService: llmService)
        }

        // Use Apple's on-device embedding service for real 768D vectors
        embeddingService = AppleEmbeddingService()

        linkingEngine = BasicLinkingEngine()
        reminderManager = ReminderManager()
        audioRecorder = AudioRecorderService()
        audioPlayer = AudioPlayerService()
        audioTranscriptionService = AudioTranscriptionService(audioNoteManager: audioNoteManager)
        self.llmService = llmService
        self.libSQLStore = libSQLStore
        self.useBackendProcessing = useBackend

        let modelContext = ModelContext(modelContainer)
        if let libSQLStore {
            // Use new LibSQLSemanticSearchEngine with vector storage
            searchEngine = LibSQLSemanticSearchEngine(
                modelContext: modelContext,
                embeddingService: embeddingService,
                vectorStore: libSQLStore
            )
        } else {
            // Fallback to old HybridSearchEngine if LibSQL not available
            searchEngine = HybridSearchEngine(
                modelContext: modelContext,
                embeddingService: embeddingService
            )
        }

        documentStore = DocumentStore(
            analyzer: analyzer,
            embeddingService: embeddingService,
            llmService: llmService,
            metadataExtractor: ImageMetadataExtractor(),
            libSQLStore: libSQLStore,
            useBackendProcessing: useBackend
        )

        // Migrate existing files to App Group container
        Task {
            do {
                try await FileStorageManager.shared.migrateExistingFiles()
            } catch {
                print("⚠️ File migration failed: \(error)")
            }
        }

        if let libSQLStore {
            Task { @MainActor in
                let descriptor = FetchDescriptor<Document>()
                if let documents = try? modelContext.fetch(descriptor) {
                    for document in documents {
                        try? libSQLStore.upsertDocument(document, embedding: document.embedding)
                    }
                }
            }
        }

        // Migrate existing audio notes to have transcription status
        Task { @MainActor in
            let descriptor = FetchDescriptor<AudioNote>()
            if let audioNotes = try? modelContext.fetch(descriptor) {
                for note in audioNotes where note.transcriptionStatus == nil {
                    if let transcript = note.transcript, !transcript.isEmpty {
                        note.transcriptionStatus = .completed
                    } else {
                        note.transcriptionStatus = .processing
                    }
                }
                try? modelContext.save()
            }

            // Process pending audio transcriptions on startup
            await audioTranscriptionService.processPending(in: modelContext)
        }
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

    struct DocumentIngestOptions {
        var hints: DocumentHints?
        var title: String?
        var location: String?
        var capturedAt: Date?
    }

    private struct StubMetadata {
        let title: String
        let docType: DocumentType
        let subtitle: String
        let detail: String
        let fields: [Field]
        let ocrText: String
        let capturedAt: Date
        let location: String
    }

    private let analyzer: DocumentAnalyzer
    private let embeddingService: EmbeddingService
    private let llmService: LLMService?
    private let metadataExtractor: ImageMetadataExtracting
    private let storageManager = FileStorageManager.shared
    private let libSQLStore: LibSQLStore?
    private let useBackendProcessing: Bool

    init(
        analyzer: DocumentAnalyzer,
        embeddingService: EmbeddingService,
        llmService: LLMService? = nil,
        metadataExtractor: ImageMetadataExtracting = ImageMetadataExtractor(),
        libSQLStore: LibSQLStore? = nil,
        useBackendProcessing: Bool = false
    ) {
        self.analyzer = analyzer
        self.embeddingService = embeddingService
        self.llmService = llmService
        self.metadataExtractor = metadataExtractor
        self.libSQLStore = libSQLStore
        self.useBackendProcessing = useBackendProcessing
    }

    @MainActor
    func createStubDocument(in context: ModelContext, titleSuffix: Int) async throws -> Document {
        let now = Date()
        let stubInfo = stubMetadata(for: titleSuffix, now: now)

        let imageURL = try makeStubImage(
            title: stubInfo.title,
            subtitle: stubInfo.subtitle,
            detail: stubInfo.detail,
            docType: stubInfo.docType
        )

        let asset = Asset(
            fileURL: imageURL.path,
            assetType: .image,
            addedAt: now,
            pageNumber: 0
        )
        context.insert(asset)
        stubInfo.fields.forEach { context.insert($0) }

        let document = Document(
            title: stubInfo.title,
            docType: stubInfo.docType,
            ocrText: stubInfo.ocrText,
            fields: stubInfo.fields,
            createdAt: now,
            capturedAt: stubInfo.capturedAt,
            location: stubInfo.location,
            assets: [asset],
            personLinks: [],
            faceClusterIDs: [],
            isSample: true
        )
        context.insert(document)
        let embedding = try await embeddingService.embedDocument(document)
        context.insert(embedding)
        document.embedding = embedding
        try context.save()

        if let libSQLStore {
            try? libSQLStore.upsertDocument(document, embedding: embedding)
            // Also store in new vector table
            try? libSQLStore.upsertDocumentEmbedding(
                documentID: document.id,
                vector: embedding.vector,
                modelVersion: "apple-embed-v1"
            )
        }

        return document
    }

    func delete(at offsets: IndexSet, from documents: [Document], in context: ModelContext) {
        for index in offsets {
            let document = documents[index]
            try? deleteDocument(document, in: context, autoSave: false)
        }
        try? context.save()
    }

    @MainActor
    func deleteSampleDocuments(in context: ModelContext) async throws -> Int {
        let descriptor = FetchDescriptor<Document>(predicate: #Predicate { $0.isSample == true })
        let samples = try context.fetch(descriptor)
        guard !samples.isEmpty else { return 0 }

        for document in samples {
            try deleteDocument(document, in: context, autoSave: false)
        }

        try context.save()
        return samples.count
    }

    func deleteDocument(
        _ document: Document,
        in context: ModelContext,
        autoSave: Bool = true
    ) throws {
        let id = document.id

        // Remove associated asset files and models
        for asset in document.assets {
            let assetURL = URL(fileURLWithPath: asset.fileURL)
            if storageManager.fileExists(atPath: asset.fileURL) {
                try? storageManager.deleteFile(at: assetURL)
            }
            context.delete(asset)
        }

        // Clean up linked models to avoid orphans
        document.fields.forEach { context.delete($0) }
        document.personLinks.forEach { context.delete($0) }
        document.reminders.forEach { context.delete($0) }

        if let embedding = document.embedding {
            context.delete(embedding)
        }

        context.delete(document)

        if let libSQLStore {
            try? libSQLStore.deleteDocument(id: id)
        }

        if autoSave {
            try context.save()
        }
    }

    private func stubMetadata(
        for index: Int,
        now: Date
    ) -> StubMetadata {
        let calendar = Calendar.current
        let captured = calendar.date(byAdding: .day, value: -index, to: now) ?? now

        switch index % 4 {
        case 1:
            let title = "March Rent Receipt"
            let amount = "$2,150.00"
            let vendor = "Brightview Apartments"
            let fields = [
                Field(key: "total", value: amount, confidence: 0.98, source: .fused),
                Field(key: "merchant", value: vendor, confidence: 0.96, source: .fused)
            ]
            let ocrText = """
            \(vendor)
            Rent payment receipt
            Amount: \(amount)
            """
            return StubMetadata(
                title: title,
                docType: .receipt,
                subtitle: vendor,
                detail: amount,
                fields: fields,
                ocrText: ocrText,
                capturedAt: captured,
                location: "San Francisco, CA"
            )
        case 2:
            let title = "Health Insurance Card"
            let member = "Alex Martinez"
            let plan = "Silver PPO 2500"
            let fields = [
                Field(key: "member_name", value: member, confidence: 0.99, source: .fused),
                Field(key: "plan", value: plan, confidence: 0.95, source: .fused)
            ]
            let ocrText = """
            \(member)
            Member ID: FM-2748392
            Plan: \(plan)
            """
            return StubMetadata(
                title: title,
                docType: .insuranceCard,
                subtitle: member,
                detail: plan,
                fields: fields,
                ocrText: ocrText,
                capturedAt: captured,
                location: "Sample Folio"
            )
        case 3:
            let title = "Pediatric Visit Summary"
            let child = "Milo Chen"
            let clinic = "Lakeside Pediatrics"
            let fields = [
                Field(key: "patient_name", value: child, confidence: 0.97, source: .fused),
                Field(key: "provider", value: clinic, confidence: 0.94, source: .fused)
            ]
            let ocrText = """
            \(clinic)
            Patient: \(child)
            Follow-up in 6 months.
            """
            return StubMetadata(
                title: title,
                docType: .letter,
                subtitle: clinic,
                detail: child,
                fields: fields,
                ocrText: ocrText,
                capturedAt: captured,
                location: "Sample Folio"
            )
        default:
            let title = "Passport Scan"
            let holder = "Jordan Lee"
            let fields = [
                Field(key: "holder", value: holder, confidence: 0.98, source: .fused),
                Field(key: "doc_number", value: "XK3928471", confidence: 0.93, source: .fused)
            ]
            let ocrText = """
            Passport
            \(holder)
            Document No: XK3928471
            """
            return StubMetadata(
                title: title,
                docType: .idCard,
                subtitle: holder,
                detail: "Document No. XK3928471",
                fields: fields,
                ocrText: ocrText,
                capturedAt: captured,
                location: "Sample Folio"
            )
        }
    }

    @MainActor
    private func makeStubImage(
        title: String,
        subtitle: String,
        detail: String,
        docType: DocumentType
    ) throws -> URL {
        let size = CGSize(width: 900, height: 1200)
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { context in
            let bounds = CGRect(origin: .zero, size: size)

            UIColor.systemBackground.setFill()
            context.fill(bounds)

            let cardRect = bounds.insetBy(dx: 80, dy: 140)
            let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 32)
            UIColor.secondarySystemBackground.setFill()
            cardPath.fill()

            let accentColor: UIColor
            switch docType {
            case .receipt:
                accentColor = UIColor.systemOrange
            case .insuranceCard:
                accentColor = UIColor.systemTeal
            case .idCard:
                accentColor = UIColor.systemIndigo
            case .letter:
                accentColor = UIColor.systemBlue
            case .billStatement:
                accentColor = UIColor.systemRed
            case .promotional:
                accentColor = UIColor.systemPink
            case .creditCard:
                accentColor = UIColor.systemGreen
            case .generic:
                accentColor = UIColor.systemGray
            }

            let stripeRect = CGRect(
                x: cardRect.minX,
                y: cardRect.minY,
                width: cardRect.width,
                height: 96
            )
            accentColor.setFill()
            context.fill(stripeRect)

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 40, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9)
            ]

            let textInset: CGFloat = 20
            let titleRect = stripeRect.insetBy(dx: textInset, dy: 18)
            (title as NSString).draw(
                in: CGRect(
                    x: titleRect.minX,
                    y: titleRect.minY,
                    width: titleRect.width,
                    height: 44
                ),
                withAttributes: titleAttributes
            )

            (subtitle as NSString).draw(
                in: CGRect(
                    x: titleRect.minX,
                    y: titleRect.maxY - 4,
                    width: titleRect.width,
                    height: 28
                ),
                withAttributes: subtitleAttributes
            )

            let bodyTop = stripeRect.maxY + 28
            let bodyRect = CGRect(
                x: cardRect.minX + 24,
                y: bodyTop,
                width: cardRect.width - 48,
                height: cardRect.height - (bodyTop - cardRect.minY) - 40
            )

            let labelAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                .foregroundColor: UIColor.label
            ]

            let label = "Key detail"
            (label as NSString).draw(
                at: CGPoint(x: bodyRect.minX, y: bodyRect.minY),
                withAttributes: labelAttributes
            )

            (detail as NSString).draw(
                in: CGRect(
                    x: bodyRect.minX,
                    y: bodyRect.minY + 18,
                    width: bodyRect.width,
                    height: 60
                ),
                withAttributes: valueAttributes
            )

            let footerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let footer = "Sample generated by FolioMind • Not real data"
            let footerSize = (footer as NSString).size(withAttributes: footerAttributes)
            (footer as NSString).draw(
                at: CGPoint(
                    x: cardRect.midX - footerSize.width / 2,
                    y: cardRect.maxY - 28
                ),
                withAttributes: footerAttributes
            )
        }

        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "FolioMind", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to encode sample image."])
        }

        let filename = storageManager.uniqueFilename(withExtension: "jpg")
        return try storageManager.save(data, to: .assets, filename: filename)
    }

    func ingestDocuments(
        from imageURLs: [URL],
        options: DocumentIngestOptions = DocumentIngestOptions(),
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

        let now = Date()
        let derivedTitle = options.title ?? options.hints?.personName.map { "\($0)'s Document" }
            ?? imageURLs.first!.deletingPathExtension().lastPathComponent

        let initialDocType = options.hints?.suggestedType ?? .generic
        let initialCapturedAt = options.capturedAt ?? metadataCaptureDate ?? now
        let initialLocation = cleanedLocation(options.location) ?? metadataLocation

        let document = Document(
            title: derivedTitle,
            docType: initialDocType,
            ocrText: "",
            cleanedText: nil,
            fields: [],
            createdAt: now,
            capturedAt: initialCapturedAt,
            location: initialLocation,
            assets: assets,
            personLinks: [],
            faceClusterIDs: [],
            embedding: nil,
            reminders: [],
            isSample: false,
            processingStatus: useBackendProcessing ? .processing : .completed
        )

        context.insert(document)
        try context.save()

        if let libSQLStore {
            try? libSQLStore.upsertDocument(document, embedding: nil)
        }

        if useBackendProcessing {
            scheduleBackendProcessing(
                document: document,
                assetURLs: persistentURLs,
                options: options,
                in: context
            )
            return document
        }

        // Local/on-device processing path: run full analysis inline
        var analyses: [DocumentAnalysisResult] = []
        for url in persistentURLs {
            let analysis = try await analyzer.analyze(imageURL: url, hints: options.hints)
            analyses.append(analysis)
        }

        let combinedOCR = analyses.map(\.ocrText).joined(separator: "\n\n")
        let combinedFields = analyses.flatMap(\.fields)
        let combinedFaces = analyses.flatMap(\.faceClusters)
        let faceIDs = combinedFaces.map { $0.id }
        let docType = DocumentTypeClassifier.classify(
            ocrText: combinedOCR,
            fields: combinedFields,
            hinted: options.hints?.suggestedType ?? analyses.first?.docType,
            defaultType: .generic
        )

        // Generate cleaned text using LLM if available
        var cleanedText: String?
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

        document.docType = docType
        document.ocrText = combinedOCR
        document.cleanedText = cleanedText
        document.fields = combinedFields
        document.faceClusterIDs = faceIDs
        document.processingStatus = .completed
        document.lastProcessingError = nil

        let embedding = try await embeddingService.embedDocument(document)
        context.insert(embedding)
        document.embedding = embedding
        try context.save()

        if let libSQLStore {
            try? libSQLStore.upsertDocument(document, embedding: embedding)
            // Also store in new vector table
            try? libSQLStore.upsertDocumentEmbedding(
                documentID: document.id,
                vector: embedding.vector,
                modelVersion: "apple-embed-v1"
            )
        }

        return document
    }

    private func scheduleBackendProcessing(
        document: Document,
        assetURLs: [URL],
        options: DocumentIngestOptions,
        in context: ModelContext
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runBackendProcessing(
                document: document,
                assetURLs: assetURLs,
                options: options,
                in: context
            )
        }
    }

    @MainActor
    private func runBackendProcessing(
        document: Document,
        assetURLs: [URL],
        options: DocumentIngestOptions,
        in context: ModelContext
    ) async {
        let maxAttempts = 3
        var attempt = 0

        while attempt < maxAttempts {
            attempt += 1
            document.processingStatus = .processing
            document.lastProcessingError = nil

            do {
                var analyses: [DocumentAnalysisResult] = []
                for url in assetURLs {
                    let analysis = try await analyzer.analyze(imageURL: url, hints: options.hints)
                    analyses.append(analysis)
                }

                let combinedOCR = analyses.map(\.ocrText).joined(separator: "\n\n")
                let combinedFields = analyses.flatMap(\.fields)
                let combinedFaces = analyses.flatMap(\.faceClusters)
                let faceIDs = combinedFaces.map { $0.id }
                let docType = DocumentTypeClassifier.classify(
                    ocrText: combinedOCR,
                    fields: combinedFields,
                    hinted: options.hints?.suggestedType ?? analyses.first?.docType,
                    defaultType: .generic
                )

                var cleanedText: String?
                if let llmService = llmService, !combinedOCR.isEmpty {
                    do {
                        cleanedText = try await llmService.cleanText(combinedOCR)
                    } catch {
                        print("Text cleaning failed (backend processing): \(error.localizedDescription)")
                    }
                }

                combinedFields.forEach { context.insert($0) }
                combinedFaces.forEach { context.insert($0) }

                document.docType = docType
                document.ocrText = combinedOCR
                document.cleanedText = cleanedText

                document.fields.forEach { context.delete($0) }
                document.fields = combinedFields
                document.faceClusterIDs = faceIDs

                let embedding = try await embeddingService.embedDocument(document)
                if let existingEmbedding = document.embedding {
                    existingEmbedding.vector = embedding.vector
                    existingEmbedding.source = embedding.source
                    existingEmbedding.entityType = embedding.entityType
                    existingEmbedding.entityID = embedding.entityID
                } else {
                    context.insert(embedding)
                    document.embedding = embedding
                }

                document.processingStatus = .completed
                document.lastProcessingError = nil

                try context.save()

                if let libSQLStore {
                    try? libSQLStore.upsertDocument(document, embedding: document.embedding)
                    // Also store in new vector table
                    if let embedding = document.embedding {
                        try? libSQLStore.upsertDocumentEmbedding(
                            documentID: document.id,
                            vector: embedding.vector,
                            modelVersion: "apple-embed-v1"
                        )
                    }
                }

                return
            } catch {
                print("Backend processing attempt \(attempt) failed: \(error)")
                document.processingStatus = .failed
                document.lastProcessingError = error.localizedDescription
                try? context.save()

                if attempt < maxAttempts {
                    let delaySeconds = Double(attempt) * 3.0
                    try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                }
            }
        }
    }

    // MARK: - Asset Persistence

    private func cleanedLocation(_ location: String?) -> String? {
        guard let trimmed = location?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Copy an asset into a persistent shared container subdirectory and return its new URL.
    private func persistAsset(from url: URL) throws -> URL {
        let filename = storageManager.uniqueFilename(withExtension: url.pathExtension)
        return try storageManager.copy(from: url, to: .assets, filename: filename)
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

        print("🔄 Re-extracting document: \(document.title)")
        print("📄 Processing \(imageAssets.count) image(s)")

        var analyses: [DocumentAnalysisResult] = []
        for asset in imageAssets {
            let url = URL(fileURLWithPath: asset.fileURL)
            print("🖼️  Analyzing asset: \(asset.fileURL)")
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

        // Use the document type from the analyzer (which may be from backend or local)
        // If multiple assets, prefer non-generic types
        let docType = analyses.map(\.docType).first { $0 != .generic } ?? analyses.first?.docType ?? document.docType

        print("✅ Re-extraction complete: \(docType.displayName), \(combinedFields.count) fields")

        var cleanedText: String?
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

        if let libSQLStore {
            try? libSQLStore.upsertDocument(document, embedding: document.embedding)
            // Also store in new vector table
            if let embedding = document.embedding {
                try? libSQLStore.upsertDocumentEmbedding(
                    documentID: document.id,
                    vector: embedding.vector,
                    modelVersion: "apple-embed-v1"
                )
            }
        }

        return document
    }

    /// Schedule re-extraction in the background so the caller does not need to await.
    @MainActor
    func scheduleReextract(
        document: Document,
        in context: ModelContext
    ) {
        document.processingStatus = .processing
        document.lastProcessingError = nil
        try? context.save()

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let updated = try await self.reextract(document: document, in: context)
                updated.processingStatus = .completed
                updated.lastProcessingError = nil
                try? context.save()
            } catch {
                document.processingStatus = .failed
                document.lastProcessingError = error.localizedDescription
                try? context.save()
            }
        }
    }
}
