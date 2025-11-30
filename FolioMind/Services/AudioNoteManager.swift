//
//  AudioNoteManager.swift
//  FolioMind
//
//  Handles transcription and summarization for recorded audio notes.
//

import Foundation
import Speech

@MainActor
final class AudioNoteManager {
    enum AudioNoteError: LocalizedError {
        case recognizerUnavailable
        case permissionDenied
        case noAudioFile
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return "Speech recognition is not available for this locale."
            case .permissionDenied:
                return "Speech recognition permission was denied. Enable it in Settings."
            case .noAudioFile:
                return "Recording file is missing."
            case .transcriptionFailed(let message):
                return "Could not transcribe audio: \(message)"
            }
        }
    }

    private let llmService: LLMService?
    private let transcriber: AudioNoteTranscriber

    init(llmService: LLMService?, transcriber: AudioNoteTranscriber = AudioNoteTranscriber()) {
        self.llmService = llmService
        self.transcriber = transcriber
    }

    func transcribeIfNeeded(note: AudioNote) async throws -> String {
        if let transcript = note.transcript, !transcript.isEmpty {
            return transcript
        }

        let transcript = try await transcriber.transcribe(url: URL(fileURLWithPath: note.fileURL))
        note.transcript = transcript
        return transcript
    }

    func summarizeIfNeeded(note: AudioNote, transcript: String) async throws -> String {
        if let summary = note.summary, !summary.isEmpty {
            return summary
        }

        let summary = try await summarize(transcript: transcript)
        note.summary = summary
        return summary
    }

    private func summarize(transcript: String) async throws -> String {
        guard let llmService else {
            return fallbackSummary(from: transcript)
        }

        let prompt = """
        You are a concise assistant. Summarize this voice note into 2-3 short sentences highlighting the main points and any actions to take. Be brief.
        """
        do {
            let response = try await llmService.extract(prompt: prompt, text: transcript)
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return fallbackSummary(from: transcript)
        }
    }

    private func fallbackSummary(from transcript: String) -> String {
        let words = transcript.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let preview = words.prefix(80).joined(separator: " ")
        return preview.isEmpty ? "No content detected." : preview + (words.count > 80 ? "…" : "")
    }
}

// MARK: - Transcriber

struct AudioNoteTranscriber {
    func transcribe(url: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioNoteManager.AudioNoteError.noAudioFile
        }

        let authStatus = await requestAuthorization()
        guard authStatus == .authorized else {
            throw AudioNoteManager.AudioNoteError.permissionDenied
        }

        guard let recognizer = SFSpeechRecognizer() else {
            throw AudioNoteManager.AudioNoteError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = false

        return try await withCheckedThrowingContinuation { continuation in
            var hasCompleted = false
            let task = recognizer.recognitionTask(with: request) { result, error in
                guard !hasCompleted else { return }
                if let error {
                    continuation.resume(throwing: AudioNoteManager.AudioNoteError.transcriptionFailed(error.localizedDescription))
                    hasCompleted = true
                    return
                }

                guard let result, result.isFinal else { return }
                let text = result.bestTranscription.formattedString
                continuation.resume(returning: text)
                hasCompleted = true
            }

            // Safety timeout to avoid hanging tasks
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                guard !hasCompleted else { return }
                task.cancel()
                continuation.resume(throwing: AudioNoteManager.AudioNoteError.transcriptionFailed("Timed out"))
                hasCompleted = true
            }
        }
    }

    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
