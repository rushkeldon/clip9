import AppKit
import SwiftUI

private let log = LogService.shared

class HistoryPanel: NSPanel {
    let scrollState = ScrollState()
    var onClose: (() -> Void)?

    static let cardSpacing: CGFloat = 4
    static let panelPadding: CGFloat = 4
    static let arrowZoneHeight: CGFloat = 30

    private var lastItemCount: Int = 0

    static var panelWidth: CGFloat {
        let zoom = CGFloat(UserDefaults.standard.object(forKey: "baseZoomLevel") as? Double ?? 1.0)
        return ClipboardEntryRow.baseWidth * zoom + panelPadding * 2 * zoom
    }

    init(
        monitor: ClipboardMonitor,
        onRestore: @escaping (ClipboardEntry) -> Void,
        onDelete: @escaping (ClipboardEntry) -> Void,
        onIncreaseLimit: @escaping (ClipboardEntry) -> Void,
        onEvictForWhale: @escaping (ClipboardEntry) -> Void
    ) {
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
            },
            onIncreaseLimit: { entry in
                log.info("Panel", "▶ onIncreaseLimit closure invoked for entry \(entry.id)", emoji: "📈")
                onIncreaseLimit(entry)
            },
            onEvictForWhale: { entry in
                log.info("Panel", "▶ onEvictForWhale closure invoked for entry \(entry.id)", emoji: "🧹")
                onEvictForWhale(entry)
            }
        )
        let hostingView = NSHostingView(rootView: AnyView(panelView))
        contentView = hostingView
        scrollState.panelContentView = hostingView
        scrollState.onContentHeightChanged = { [weak self] contentHeight in
            self?.resizeToContentHeight(contentHeight)
        }
        log.info("Panel", "HistoryPanel initialized (activating, floating)", emoji: "🏠")
    }

    private func resizeToContentHeight(_ contentHeight: CGFloat) {
        guard isVisible else { return }
        let screenHeight = (screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let maxHeight = screenHeight - 8
        let newHeight = min(contentHeight, maxHeight)
        guard abs(newHeight - frame.height) > 1 else { return }
        let topY = frame.maxY
        setFrame(NSRect(x: frame.origin.x, y: topY - newHeight, width: frame.width, height: newHeight), display: true)
        log.debug("Panel", "Resized to fit content: \(Int(frame.width))x\(Int(newHeight))", emoji: "📐")
    }

    func updateSize(itemCount: Int) {
        lastItemCount = itemCount
        let width = Self.panelWidth

        if itemCount == 0 {
            setContentSize(NSSize(width: width, height: 200))
            log.debug("Panel", "Panel resized for 0 items: \(Int(width))×200", emoji: "📐")
            return
        }

        // Use measured content height when available; fall back to estimate
        let screenHeight = (screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        let maxHeight = screenHeight - 8

        if scrollState.contentHeight > 0 {
            let finalHeight = min(scrollState.contentHeight, maxHeight)
            setContentSize(NSSize(width: width, height: finalHeight))
            log.debug("Panel", "Panel resized for \(itemCount) items (measured): \(Int(width))×\(Int(finalHeight))", emoji: "📐")
        } else {
            let zoom = CGFloat(UserDefaults.standard.object(forKey: "baseZoomLevel") as? Double ?? 1.0)
            let cardsHeight = CGFloat(itemCount) * ClipboardEntryRow.baseHeight * zoom
            let spacingHeight = CGFloat(max(0, itemCount - 1)) * Self.cardSpacing * zoom
            let baseHeight = cardsHeight + spacingHeight + Self.panelPadding * 2 * zoom
            let height = baseHeight + (baseHeight > maxHeight ? Self.arrowZoneHeight : 0)
            let finalHeight = min(height, maxHeight)
            setContentSize(NSSize(width: width, height: finalHeight))
            log.debug("Panel", "Panel resized for \(itemCount) items (estimated): \(Int(width))×\(Int(finalHeight))", emoji: "📐")
        }
    }

    override func close() {
        log.debug("Panel", "Panel closing", emoji: "🔽")
        onClose?()
        super.close()
        scrollState.stopScrolling()
        scrollState.clearMouseHitTestState()
        scrollState.selectedIndex = nil
        scrollState.resetToTop()
    }
}
