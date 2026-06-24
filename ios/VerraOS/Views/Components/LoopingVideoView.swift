//
//  LoopingVideoView.swift
//  VerraOS
//

import SwiftUI
import AVFoundation

/// A muted, gaplessly looping video player used as a full-screen background.
/// Falls back gracefully (renders nothing) if the bundled resource is missing.
struct LoopingVideoView: UIViewRepresentable {
    let resourceName: String
    let fileExtension: String

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(resourceName: resourceName, fileExtension: fileExtension)
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {}
}

/// UIView backing the looping player; owns the player, looper, and layer so the
/// loop survives SwiftUI view updates.
final class LoopingPlayerUIView: UIView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    override static var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer? {
        layer as? AVPlayerLayer
    }

    init(resourceName: String, fileExtension: String) {
        super.init(frame: .zero)
        backgroundColor = .black
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) else {
            return
        }

        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        queuePlayer.isMuted = true
        queuePlayer.actionAtItemEnd = .advance

        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        playerLayer?.player = queuePlayer
        playerLayer?.videoGravity = .resizeAspectFill
        player = queuePlayer

        queuePlayer.play()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            player?.play()
        }
    }
}
