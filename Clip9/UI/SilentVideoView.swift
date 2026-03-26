import AVFoundation
import AppKit
import SwiftUI

private let log = LogService.shared

struct SilentVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> SilentVideoNSView {
        SilentVideoNSView(url: url)
    }

    func updateNSView(_ nsView: SilentVideoNSView, context: Context) {}

    static func dismantleNSView(_ nsView: SilentVideoNSView, coordinator: ()) {
        log.debug("Media", "SilentVideoView dismantled", emoji: "🎬")
        nsView.tearDown()
    }
}

class SilentVideoNSView: NSView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var loopObserver: NSObjectProtocol?
    private var visibilityObserver: NSObjectProtocol?
    private let filename: String

    init(url: URL) {
        self.filename = url.lastPathComponent
        super.init(frame: .zero)
        wantsLayer = true

        log.info("Media", "SilentVideoView loading: \(filename)", emoji: "🎬")

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = true
        player.actionAtItemEnd = .none
        self.player = player

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        self.layer?.addSublayer(layer)
        self.playerLayer = layer

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }

        player.play()
        log.info("Media", "SilentVideoView playing (muted, looping): \(filename)", emoji: "▶️")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SilentVideoNSView does not support init(coder:)") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let obs = visibilityObserver {
            NotificationCenter.default.removeObserver(obs)
            visibilityObserver = nil
        }

        guard let window = window else {
            player?.pause()
            return
        }

        visibilityObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let self, let window = notification.object as? NSWindow else { return }
            if window.occlusionState.contains(.visible) {
                self.player?.play()
                log.debug("Media", "Video resumed (window visible): \(self.filename)", emoji: "▶️")
            } else {
                self.player?.pause()
                log.debug("Media", "Video paused (window hidden): \(self.filename)", emoji: "⏸️")
            }
        }

        if window.occlusionState.contains(.visible) {
            player?.play()
        } else {
            player?.pause()
        }
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    func tearDown() {
        player?.pause()
        if let obs = loopObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = visibilityObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        loopObserver = nil
        visibilityObserver = nil
        player = nil
        log.debug("Media", "SilentVideoView torn down", emoji: "⏹️")
    }

    deinit {
        tearDown()
    }
}
