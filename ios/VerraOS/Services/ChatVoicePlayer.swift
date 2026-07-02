import AVFoundation
import Foundation

@Observable
@MainActor
final class ChatVoicePlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = ChatVoicePlayer()

    var playingMessageID: UUID?

    private var player: AVAudioPlayer?

    func isPlaying(messageID: UUID) -> Bool {
        playingMessageID == messageID && player?.isPlaying == true
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
            return true
        } catch {
            return false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingMessageID = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.player = nil
            self.playingMessageID = nil
        }
    }
}
