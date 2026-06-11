import AVFoundation
import Foundation

// MARK: - Audio Playback Service (TTS)

@MainActor
final class AudioPlaybackService: NSObject, ObservableObject, AVAudioPlayerDelegate {

    @Published var isPlaying = false
    @Published var audioLevel: Float = 0

    private var player: AVAudioPlayer?
    private var levelTimer: Timer?
    private var playbackContinuation: CheckedContinuation<Void, Error>?

    // MARK: Play TTS audio data

    func play(data: Data) async throws {
        stop()

        return try await withCheckedThrowingContinuation { continuation in
            do {
                let p = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.mp3.rawValue)
                p.delegate = self
                p.volume = 1.0
                p.isMeteringEnabled = true
                p.prepareToPlay()

                guard p.play() else {
                    continuation.resume(throwing: AudioPlaybackError.playbackFailed)
                    return
                }

                player = p
                playbackContinuation = continuation
                isPlaying = true
                startLevelMonitoring()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        audioLevel = 0
        stopLevelMonitoring()

        playbackContinuation?.resume(returning: ())
        playbackContinuation = nil
    }

    // MARK: Level monitoring

    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player, player.isPlaying else { return }
                player.updateMeters()
                let db = player.averagePower(forChannel: 0)
                let linear = pow(10.0, db / 20.0)
                self.audioLevel = min(max(Float(linear * 3.5), 0), 1)
            }
        }
    }

    private func stopLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    // MARK: AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isPlaying   = false
            self?.audioLevel  = 0
            self?.stopLevelMonitoring()
            self?.playbackContinuation?.resume(returning: ())
            self?.playbackContinuation = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            self?.isPlaying   = false
            self?.audioLevel  = 0
            self?.stopLevelMonitoring()
            if let error {
                self?.playbackContinuation?.resume(throwing: error)
            } else {
                self?.playbackContinuation?.resume(returning: ())
            }
            self?.playbackContinuation = nil
        }
    }
}

enum AudioPlaybackError: LocalizedError {
    case playbackFailed

    var errorDescription: String? {
        "Audio playback failed. Check system volume and output device."
    }
}
