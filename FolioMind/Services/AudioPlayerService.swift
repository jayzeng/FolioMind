//
//  AudioPlayerService.swift
//  FolioMind
//
//  Centralized audio playback service with seeking, speed control, and skip functionality
//

import Foundation
import AVFoundation
import MediaPlayer

@MainActor
final class AudioPlayerService: NSObject, ObservableObject {
    enum PlayerError: LocalizedError {
        case fileNotFound
        case playbackFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "Audio file not found"
            case .playbackFailed(let message):
                return "Playback failed: \(message)"
            }
        }
    }

    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var playbackRate: Float = 1.0
    @Published private(set) var currentNoteID: UUID?

    private var player: AVAudioPlayer?
    private var playbackTimer: Timer?
    private let skipInterval: TimeInterval = 15.0

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    func play(url: URL, noteID: UUID) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PlayerError.fileNotFound
        }

        // Stop current playback if any
        stop()

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.enableRate = true
            player.rate = playbackRate
            player.prepareToPlay()
            player.play()

            self.player = player
            self.currentNoteID = noteID
            self.duration = player.duration
            self.isPlaying = true

            startProgressTimer()
            setupRemoteControls()
            updateNowPlaying(url: url)
        } catch {
            throw PlayerError.playbackFailed(error.localizedDescription)
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopProgressTimer()
        updateNowPlayingPlaybackState()
    }

    func resume() {
        player?.play()
        isPlaying = true
        startProgressTimer()
        updateNowPlayingPlaybackState()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        currentNoteID = nil
        stopProgressTimer()
        clearNowPlaying()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = max(0, min(time, player.duration))
        currentTime = player.currentTime
        updateNowPlayingElapsedTime()
    }

    func skipForward() {
        guard let player else { return }
        seek(to: player.currentTime + skipInterval)
    }

    func skipBackward() {
        guard let player else { return }
        seek(to: player.currentTime - skipInterval)
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = max(0.5, min(2.0, rate))
        player?.rate = playbackRate
        updateNowPlayingPlaybackRate()
    }

    private func startProgressTimer() {
        stopProgressTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let player = await self.player else { return }
                await self.updateCurrentTime(player.currentTime)
            }
        }
    }

    private func updateCurrentTime(_ time: TimeInterval) {
        self.currentTime = time
    }

    private func stopProgressTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    // MARK: - Now Playing / Lock Screen Controls

    private func setupRemoteControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward()
            return .success
        }

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: event.positionTime)
                return .success
            }
            return .commandFailed
        }
    }

    private func updateNowPlaying(url: URL) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = url.deletingPathExtension().lastPathComponent
        nowPlayingInfo[MPMediaItemPropertyMediaType] = MPMediaType.anyAudio.rawValue
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updateNowPlayingElapsedTime() {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updateNowPlayingPlaybackState() {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updateNowPlayingPlaybackRate() {
        guard var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlayerService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stop()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.stop()
        }
    }
}
