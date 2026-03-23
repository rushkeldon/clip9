import AppKit

private let log = LogService.shared

@Observable
class ScrollState {
    var scrollOffset: CGFloat = 0.0
    var contentHeight: CGFloat = 0.0
    var viewHeight: CGFloat = 400.0

    var selectedIndex: Int? = nil
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
        guard !cardOffsets.isEmpty, cardOffsets.count == cardHeights.count else { return }
        let realOffset = cachedScrollView?.contentView.bounds.origin.y ?? scrollOffset
        let contentY = (viewHeight - mouseY) + realOffset
        for i in 0..<cardOffsets.count {
            if contentY >= cardOffsets[i] && contentY < cardOffsets[i] + cardHeights[i] {
                if selectedIndex != i {
                    log.debug("Mouse", "select card \(i) (mouseY=\(Int(mouseY)) offset=\(Int(realOffset)) contentY=\(Int(contentY)))", emoji: "👆")
                }
                selectedIndex = i
                return
            }
        }
        if selectedIndex != nil {
            log.debug("Mouse", "select NONE (mouseY=\(Int(mouseY)) offset=\(Int(realOffset)) contentY=\(Int(contentY)))", emoji: "👆")
        }
        selectedIndex = nil
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
}
