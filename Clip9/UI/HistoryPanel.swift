import AppKit
import SwiftUI

private let log = LogService.shared

class HistoryPanel: NSPanel {
    let scrollState = ScrollState()

    static let cardSpacing: CGFloat = 4
    static let panelPadding: CGFloat = 4

    private var zoomObserver: NSObjectProtocol?
    private var lastItemCount: Int = 0

    static var panelWidth: CGFloat {
        let zoom = CGFloat(UserDefaults.standard.object(forKey: "baseZoomLevel") as? Double ?? 1.0)
        return ClipboardEntryRow.baseWidth * zoom + panelPadding * 2 * zoom
    }

    init(monitor: ClipboardMonitor, onRestore: @escaping (ClipboardEntry) -> Void, onDelete: @escaping (ClipboardEntry) -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 200),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true

        let panelView = HistoryPanelView(
            monitor: monitor,
            scrollState: scrollState,
            onRestore: { entry in
                log.info("Panel", "▶ onRestore closure invoked for entry \(entry.id)", emoji: "📋")
                onRestore(entry)
            },
            onDelete: { entry in
                log.info("Panel", "▶ onDelete closure invoked for entry \(entry.id)", emoji: "🗑️")
                onDelete(entry)
            }
        )
        let hostingView = NSHostingView(rootView: AnyView(panelView))
        contentView = hostingView
        log.info("Panel", "HistoryPanel initialized (activating, floating)", emoji: "🏠")
    }

    func updateSize(itemCount: Int) {
        lastItemCount = itemCount
        let zoom = CGFloat(UserDefaults.standard.object(forKey: "baseZoomLevel") as? Double ?? 1.0)
        let width = Self.panelWidth

        let height: CGFloat
        if itemCount == 0 {
            height = 200
        } else {
            let cardsHeight = CGFloat(itemCount) * ClipboardEntryRow.baseHeight * zoom
            let spacingHeight = CGFloat(max(0, itemCount - 1)) * Self.cardSpacing * zoom
            height = cardsHeight + spacingHeight + Self.panelPadding * 2 * zoom
        }

        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let maxHeight = screenHeight - 8
        let finalHeight = min(height, maxHeight)

        setContentSize(NSSize(width: width, height: finalHeight))
        log.debug("Panel", "Panel resized for \(itemCount) items: \(Int(width))×\(Int(finalHeight))", emoji: "📐")
    }

    override func close() {
        log.debug("Panel", "Panel closing", emoji: "🔽")
        super.close()
        scrollState.stopScrolling()
        scrollState.scrollOffset = 0
        scrollState.selectedIndex = nil
    }
}
