//
//  BackendAudioNoteManager.swift
//  FolioMind
//
//  Handles audio transcription and summarization using the backend API.
//

import Foundation

@MainActor
final class BackendAudioNoteManager: AudioNoteManaging {
    enum AudioNoteError: LocalizedError {
        case noAudioFile
        case transcriptionFailed(String)
        case backendError(String)

        var errorDescription: String? {
            switch self {
            case .noAudioFile:
                return "Recording file is missing."
            case .transcriptionFailed(let message):
                return "Could not transcribe audio: \(message)"
            case .backendError(let message):
                return "Backend error: \(message)"
            }
        }
    }

    private let backendService: BackendAPIService

    init(backendService: BackendAPIService = BackendAPIService()) {
        self.backendService = backendService
    }

    func transcribeIfNeeded(note: AudioNote) async throws -> String {
        if let transcript = note.transcript, !transcript.isEmpty {
            return transcript
        }

        let transcript = try await transcribe(url: URL(fileURLWithPath: note.fileURL))
        note.transcript = transcript
        return transcript
    }

    func summarizeIfNeeded(note: AudioNote, transcript: String) async throws -> String {
        if let summary = note.summary, !summary.isEmpty {
            return summary
        }

        let summary = summarize(from: transcript)
        note.summary = summary
        return summary
    }

    // MARK: - Private Methods

    private func transcribe(url: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioNoteError.noAudioFile
        }

        print("🎤 Uploading audio to backend for transcription...")

        do {
            let response = try await backendService.uploadAudio(url)

            guard let transcription = response.transcription, !transcription.isEmpty else {
                throw AudioNoteError.transcriptionFailed("No transcription received from backend")
            }

            print("✅ Backend transcribed audio: \(transcription.prefix(100))...")
            return transcription
        } catch let error as BackendAPIService.APIError {
            print("❌ Backend transcription failed: \(error.localizedDescription)")
            throw AudioNoteError.backendError(error.localizedDescription)
        } catch {
            print("❌ Transcription error: \(error.localizedDescription)")
            throw AudioNoteError.transcriptionFailed(error.localizedDescription)
        }
    }

    private func summarize(from transcript: String) -> String {
        // Simple summarization - take first 80 words
        // The backend doesn't currently have a dedicated summarization endpoint
        let words = transcript.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let preview = words.prefix(80).joined(separator: " ")
        return preview.isEmpty ? "No content detected." : preview + (words.count > 80 ? "…" : "")
    }
}
