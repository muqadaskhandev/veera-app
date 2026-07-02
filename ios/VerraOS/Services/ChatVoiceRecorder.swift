import AVFoundation
import Foundation

enum ChatVoiceRecorderError: LocalizedError {
    case permissionDenied
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access is required to record voice notes."
        case .failedToStart:
            return "Couldn't start recording."
        }
    }
}

@Observable
@MainActor
final class ChatVoiceRecorder {
    var isRecording = false
    var elapsedSeconds = 0

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var timer: Timer?

    func start() async throws {
        guard !isRecording else { return }

        let granted = await requestPermission()
        guard granted else { throw ChatVoiceRecorderError.permissionDenied }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else { throw ChatVoiceRecorderError.failedToStart }

        self.recorder = recorder
        fileURL = url
        isRecording = true
        elapsedSeconds = 0
        startTimer()
    }

    @discardableResult
    func stop() -> (url: URL, duration: Int)? {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        isRecording = false

        guard let url = fileURL else { return nil }
        let duration = max(1, elapsedSeconds)
        elapsedSeconds = 0
        recorder = nil
        fileURL = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return (url, duration)
    }

    func cancel() {
        guard let result = stop() else { return }
        try? FileManager.default.removeItem(at: result.url)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSeconds += 1
            }
        }
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
