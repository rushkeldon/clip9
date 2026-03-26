import AppKit

private let log = LogService.shared

@Observable
class ScrollState {
    var scrollOffset: CGFloat = 0.0 {
        didSet {
            guard oldValue != scrollOffset else { return }
            reselectUnderMouseIfPossible()
        }
    }
    var contentHeight: CGFloat = 0.0 {
        didSet {
            guard contentHeight != oldValue, contentHeight > 0 else { return }
            onContentHeightChanged?(contentHeight)
        }
    }
    var onContentHeightChanged: ((CGFloat) -> Void)?
    var viewHeight: CGFloat = 400.0

    var selectedIndex: Int? = nil

    /// Last mouse Y in `MouseTrackingNSView` space (AppKit: origin bottom-left), for hit-test after scroll.
    private var lastMouseYInOverlay: CGFloat?
    private var lastOverlayHeight: CGFloat?
    var cardOffsets: [CGFloat] = []
    var cardHeights: [CGFloat] = []

    /// Used by keyboard navigation only; cleared by the view after executing.
    var scrollTargetIndex: Int? = nil

    /// Weak reference to the panel's content view, used to find the backing NSScrollView.
    weak var panelContentView: NSView?

    private(set) var isScrollingDown = false
    private(set) var isScrollingUp = false

    private var scrollTimer: Timer?
    private weak var cachedScrollView: NSScrollView?
    private let scrollInterval: TimeInterval = 0.016
    private let scrollPixelsPerTick: CGFloat = 9

    private let triggerZone: CGFloat = 30.0

    var maxOffset: CGFloat {
        max(contentHeight - viewHeight, 0)
    }

    var canScrollDown: Bool {
        scrollOffset < maxOffset - 1
    }

    func updateMousePosition(_ mouseY: CGFloat, viewHeight: CGFloat) {
        self.viewHeight = viewHeight
        lastMouseYInOverlay = mouseY
        lastOverlayHeight = viewHeight

        guard maxOffset > 0 else {
            if isScrollingDown || isScrollingUp {
                log.debug("Scroll", "stopScrolling: maxOffset=0", emoji: "⏹️")
            }
            stopScrolling()
            return
        }

        let bottomZone = mouseY < triggerZone
        let topZone = mouseY > (viewHeight - triggerZone)

        if bottomZone && canScrollDown {
            if !isScrollingDown {
                log.debug("Scroll", "Mouse entered bottom zone (mouseY=\(Int(mouseY))), starting smooth scroll down", emoji: "⬇️")
            }
            startScrollingDown()
        } else if topZone && scrollOffset > 0 {
            if !isScrollingUp {
                log.debug("Scroll", "Mouse entered top zone (mouseY=\(Int(mouseY))), starting smooth scroll up", emoji: "⬆️")
            }
            startScrollingUp()
        } else {
            if isScrollingDown || isScrollingUp {
                log.debug("Scroll", "Mouse left scroll zone (mouseY=\(Int(mouseY))), stopping", emoji: "⏹️")
            }
            stopScrolling()
        }
    }

    func selectByMousePosition(_ mouseY: CGFloat, viewHeight: CGFloat) {
        lastMouseYInOverlay = mouseY
        lastOverlayHeight = viewHeight
        applyMouseHitTest(mouseY: mouseY, viewHeight: viewHeight)
    }

    /// Re-run hit test after scroll (wheel or hover-scroll) without a new mouse event.
    private func reselectUnderMouseIfPossible() {
        guard let y = lastMouseYInOverlay, let h = lastOverlayHeight else { return }
        applyMouseHitTest(mouseY: y, viewHeight: h)
    }

    /// Maps overlay Y to document Y using the same scroll origin as `NSScrollView` (avoids desync with SwiftUI-only offset while hover-scrolling).
    private func applyMouseHitTest(mouseY: CGFloat, viewHeight: CGFloat) {
        if cachedScrollView == nil { _ = findScrollView() }
        guard !cardOffsets.isEmpty, cardOffsets.count == cardHeights.count else { return }

        let arrowH = HistoryPanel.arrowZoneHeight
        let viewportH = viewHeight - arrowH
        guard viewportH > 1 else { return }

        // AppKit: mouseY is from bottom of overlay. Distance from top of overlay downward:
        let fromTop = viewHeight - mouseY
        // Bottom strip is the hover-scroll arrow, not part of the card stack.
        guard fromTop < viewportH - 0.5 else {
            selectedIndex = nil
            return
        }

        let yInViewport = fromTop
        let scrollOriginY = cachedScrollView?.contentView.bounds.origin.y ?? scrollOffset
        let contentY = yInViewport + scrollOriginY

        // Prefer exact hit; spacing between cards has no rect — use nearest card by Y distance so highlight does not flicker off.
        var bestIndex = 0
        var bestDistance = CGFloat.infinity
        for i in 0..<cardOffsets.count {
            let lo = cardOffsets[i]
            let hi = lo + cardHeights[i]
            let distance: CGFloat
            if contentY < lo {
                distance = lo - contentY
            } else if contentY >= hi {
                distance = contentY - hi
            } else {
                distance = 0
            }
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = i
            }
        }

        selectedIndex = bestIndex
    }

    func selectNext(count: Int) {
        guard count > 0 else { return }
        let current = selectedIndex ?? -1
        selectedIndex = min(current + 1, count - 1)
        scrollTargetIndex = selectedIndex
    }

    func selectPrevious() {
        guard let current = selectedIndex else { return }
        selectedIndex = max(current - 1, 0)
        scrollTargetIndex = selectedIndex
    }

    func clearMouseHitTestState() {
        lastMouseYInOverlay = nil
        lastOverlayHeight = nil
    }

    func resetToTop() {
        scrollOffset = 0
        if let scrollView = findScrollView() {
            let clipView = scrollView.contentView
            clipView.setBoundsOrigin(.zero)
            scrollView.reflectScrolledClipView(clipView)
        }
    }

    func stopScrolling() {
        let wasScrolling = isScrollingDown || isScrollingUp
        isScrollingDown = false
        isScrollingUp = false
        scrollTimer?.invalidate()
        scrollTimer = nil
        if wasScrolling {
            log.debug("Scroll", "Scrolling stopped", emoji: "⏹️")
        }
    }

    // MARK: - Hover Scroll via NSScrollView

    private func startScrollingDown() {
        guard !isScrollingDown else { return }
        isScrollingUp = false
        isScrollingDown = true
        startScrollTimer()
    }

    private func startScrollingUp() {
        guard !isScrollingUp else { return }
        isScrollingDown = false
        isScrollingUp = true
        startScrollTimer()
    }

    private func startScrollTimer() {
        scrollTimer?.invalidate()
        log.debug("Scroll", "Starting scroll timer (\(Int(scrollInterval * 1000))ms, \(Int(scrollPixelsPerTick))px/tick)", emoji: "⏱️")
        scrollTimer = Timer.scheduledTimer(withTimeInterval: scrollInterval, repeats: true) { [weak self] _ in
            self?.scrollTick()
        }
    }

    private func scrollTick() {
        guard let scrollView = findScrollView() else {
            log.debug("Scroll", "NSScrollView not found, stopping", emoji: "⚠️")
            stopScrolling()
            return
        }

        let clipView = scrollView.contentView
        guard let documentView = scrollView.documentView else { return }

        var origin = clipView.bounds.origin
        let delta = isScrollingDown ? scrollPixelsPerTick : -scrollPixelsPerTick
        origin.y += delta

        let maxY = documentView.frame.height - clipView.bounds.height
        origin.y = max(0, min(origin.y, maxY))

        clipView.setBoundsOrigin(origin)
        scrollView.reflectScrolledClipView(clipView)
        scrollOffset = origin.y
        reselectUnderMouseIfPossible()
    }

    private func findScrollView() -> NSScrollView? {
        if let cached = cachedScrollView { return cached }
        guard let root = panelContentView else { return nil }
        let found = Self.findNSScrollView(in: root)
        if found != nil {
            cachedScrollView = found
            log.debug("Scroll", "Found backing NSScrollView", emoji: "🔍")
        }
        return found
    }

    private static func findNSScrollView(in view: NSView) -> NSScrollView? {
        if let sv = view as? NSScrollView { return sv }
        for subview in view.subviews {
            if let found = findNSScrollView(in: subview) { return found }
        }
        return nil
    }

    deinit {
        scrollTimer?.invalidate()
    }
}
