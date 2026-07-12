import AVFoundation
import Foundation

@Observable
@MainActor
final class ChatVoicePlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = ChatVoicePlayer()

    var playingMessageID: UUID?
    /// 0...1 playback progress for the active message.
    var progress: Double = 0
    /// Seconds remaining on the active message (WhatsApp-style countdown).
    var remainingSeconds: Int = 0
    var durationSeconds: Int = 0

    private var player: AVAudioPlayer?
    private var tickTask: Task<Void, Never>?

    func isPlaying(messageID: UUID) -> Bool {
        playingMessageID == messageID && player?.isPlaying == true
    }

    func progress(for messageID: UUID) -> Double {
        guard playingMessageID == messageID else { return 0 }
        return progress
    }

    func remainingSeconds(for messageID: UUID, fallbackDuration: Int) -> Int {
        guard playingMessageID == messageID else { return fallbackDuration }
        return remainingSeconds
    }

    func toggle(messageID: UUID, path: String) async -> Bool {
        if playingMessageID == messageID, player?.isPlaying == true {
            stop()
            return false
        }

        stop()
        guard let url = await ChatAttachmentLoader.localAudioURL(for: path) else { return false }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()

            self.player = player
            playingMessageID = messageID
            durationSeconds = max(1, Int(ceil(player.duration)))
            remainingSeconds = durationSeconds
            progress = 0
            startTicking()
            return true
        } catch {
            return false
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        player?.stop()
        player = nil
        playingMessageID = nil
        progress = 0
        remainingSeconds = 0
        durationSeconds = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.tickTask?.cancel()
            self.tickTask = nil
            self.player = nil
            self.playingMessageID = nil
            self.progress = 0
            self.remainingSeconds = 0
            self.durationSeconds = 0
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { @MainActor in
            while !Task.isCancelled, let player, player.isPlaying {
                let duration = max(player.duration, 0.001)
                let current = min(max(player.currentTime, 0), duration)
                progress = current / duration
                let left = max(0, duration - current)
                remainingSeconds = max(0, Int(ceil(left)))
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
