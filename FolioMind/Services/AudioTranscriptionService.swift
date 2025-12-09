//
//  AudioTranscriptionService.swift
//  FolioMind
//
//  Handles background transcription of audio notes
//

import Foundation
import SwiftData

@MainActor
final class AudioTranscriptionService: ObservableObject {
    private let audioNoteManager: AudioNoteManaging
    private var processingQueue: [UUID] = []
    private var isProcessing: Bool = false

    init(audioNoteManager: AudioNoteManaging) {
        self.audioNoteManager = audioNoteManager
    }

    /// Schedule an audio note for background transcription
    func scheduleTranscription(for note: AudioNote, in context: ModelContext) {
        guard !processingQueue.contains(note.id) else {
            print("📋 Audio note \(note.id) already in transcription queue")
            return
        }

        print("📋 Scheduling transcription for audio note: \(note.title)")
        processingQueue.append(note.id)

        // Start processing if not already running
        if !isProcessing {
            Task {
                await processQueue(in: context)
            }
        }
    }

    /// Process all pending transcriptions in the queue
    private func processQueue(in context: ModelContext) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        while let noteID = processingQueue.first {
            // Remove from queue first
            processingQueue.removeFirst()

            // Fetch the note
            let descriptor = FetchDescriptor<AudioNote>(
                predicate: #Predicate { $0.id == noteID }
            )

            guard let note = try? context.fetch(descriptor).first else {
                print("⚠️ Could not find audio note \(noteID) for transcription")
                continue
            }

            // Skip if already transcribed
            if note.effectiveTranscriptionStatus == .completed && note.transcript != nil {
                print("✅ Audio note already transcribed: \(note.title)")
                continue
            }

            print("🎤 Processing transcription for: \(note.title)")
            note.transcriptionStatus = .processing
            note.lastTranscriptionError = nil
            try? context.save()

            do {
                // Transcribe
                let transcript = try await audioNoteManager.transcribeIfNeeded(note: note)
                note.transcript = transcript

                // Summarize
                let summary = try await audioNoteManager.summarizeIfNeeded(note: note, transcript: transcript)
                note.summary = summary

                // Mark as completed
                note.transcriptionStatus = .completed
                note.lastTranscriptionError = nil
                try? context.save()

                print("✅ Transcription completed for: \(note.title)")
            } catch {
                print("❌ Transcription failed for \(note.title): \(error.localizedDescription)")
                note.transcriptionStatus = .failed
                note.lastTranscriptionError = error.localizedDescription
                try? context.save()
            }
        }

        print("📋 Transcription queue empty")
    }

    /// Retry failed transcriptions
    func retryFailed(in context: ModelContext) async {
        let failedStatus = ProcessingStatus.failed
        let descriptor = FetchDescriptor<AudioNote>(
            predicate: #Predicate { $0.transcriptionStatus == failedStatus }
        )

        guard let failedNotes = try? context.fetch(descriptor) else { return }

        for note in failedNotes {
            scheduleTranscription(for: note, in: context)
        }
    }

    /// Process all pending transcriptions (for app startup)
    func processPending(in context: ModelContext) async {
        let processingStatus = ProcessingStatus.processing
        let descriptor = FetchDescriptor<AudioNote>(
            predicate: #Predicate { $0.transcriptionStatus == processingStatus }
        )

        guard let pendingNotes = try? context.fetch(descriptor) else { return }

        print("📋 Found \(pendingNotes.count) pending transcriptions")

        for note in pendingNotes {
            scheduleTranscription(for: note, in: context)
        }
    }
}
