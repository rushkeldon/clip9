import AppKit
import SwiftUI

private let log = LogService.shared

struct AnimatedImageView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.animates = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        if let image = NSImage(contentsOf: url) {
            imageView.image = image
            log.debug("Media", "AnimatedImageView loaded: \(url.lastPathComponent) (\(Int(image.size.width))×\(Int(image.size.height)), reps=\(image.representations.count))", emoji: "🖼️")
        } else {
            log.warn("Media", "AnimatedImageView failed to load: \(url.lastPathComponent)")
        }
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if nsView.image == nil, let image = NSImage(contentsOf: url) {
            nsView.image = image
            log.debug("Media", "AnimatedImageView retry loaded: \(url.lastPathComponent)", emoji: "🖼️")
        }
    }
}
