import AppKit
import SwiftUI

private let log = LogService.shared

/// An NSView overlay that uses NSTrackingArea to reliably track mouse position
/// inside a custom NSPanel, bridging coordinates into SwiftUI via ScrollState.
class MouseTrackingNSView: NSView {
    var onMouseMove: ((NSPoint) -> Void)?
    var onMouseExit: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        onMouseMove?(location)
    }

    override func mouseExited(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            log.debug("Mouse", "Spurious mouseExited ignored (mouse still in bounds at \(Int(location.x)),\(Int(location.y)))", emoji: "🖱️")
            return
        }
        log.debug("Mouse", "Mouse exited tracking area at \(Int(location.x)),\(Int(location.y))", emoji: "🖱️")
        onMouseExit?()
    }

    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

/// SwiftUI wrapper for the NSTrackingArea-based mouse tracking.
struct MouseTrackingOverlay: NSViewRepresentable {
    let scrollState: ScrollState

    func makeNSView(context: Context) -> MouseTrackingNSView {
        let view = MouseTrackingNSView()
        view.onMouseMove = { [scrollState] point in
            scrollState.updateMousePosition(point.y, viewHeight: view.bounds.height)
            scrollState.selectByMousePosition(point.y, viewHeight: view.bounds.height)
        }
        view.onMouseExit = { [scrollState] in
            log.debug("Mouse", "Mouse exited → stopping scroll, clearing selection", emoji: "🖱️")
            scrollState.stopScrolling()
            scrollState.selectedIndex = nil
        }
        log.debug("Mouse", "MouseTrackingOverlay NSView created", emoji: "🖱️")
        return view
    }

    func updateNSView(_ nsView: MouseTrackingNSView, context: Context) {}
}
