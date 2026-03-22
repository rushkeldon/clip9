import Foundation
import QuartzCore

private let log = LogService.shared

/// Manages hover-to-scroll behavior: when the mouse hovers near the bottom
/// (or top) of the history list, scrolling begins automatically.
@Observable
class ScrollState {
    var scrollOffset: CGFloat = 0.0
    var contentHeight: CGFloat = 0.0
    var viewHeight: CGFloat = 400.0
    var scrollSpeed: CGFloat = 80.0

    var selectedIndex: Int? = nil
    var cardOffsets: [CGFloat] = []
    var cardHeights: [CGFloat] = []

    private(set) var isScrollingDown = false
    private(set) var isScrollingUp = false

    private var displayLink: Timer?
    private var lastTimestamp: TimeInterval = 0

    /// Trigger zone height at the bottom of the visible area (matches scroll arrow height).
    private let triggerZone: CGFloat = 30.0

    func updateMousePosition(_ mouseY: CGFloat, viewHeight: CGFloat) {
        self.viewHeight = viewHeight

        guard maxOffset > 0 else {
            stopScrolling()
            return
        }

        let bottomZone = mouseY < triggerZone
        let topZone = mouseY > (viewHeight - triggerZone)

        if bottomZone && scrollOffset < maxOffset {
            startScrollingDown()
        } else if topZone && scrollOffset > 0 {
            startScrollingUp()
        } else {
            stopScrolling()
        }
    }

    var maxOffset: CGFloat {
        max(contentHeight - viewHeight, 0)
    }

    var canScrollDown: Bool {
        scrollOffset < maxOffset
    }

    func applyScrollDelta(_ delta: CGFloat) {
        let newOffset = scrollOffset + delta
        scrollOffset = min(max(newOffset, 0), maxOffset)
    }

    func selectByMousePosition(_ mouseY: CGFloat, viewHeight: CGFloat) {
        guard !cardOffsets.isEmpty, cardOffsets.count == cardHeights.count else { return }
        let contentY = (viewHeight - mouseY) + scrollOffset
        for i in 0..<cardOffsets.count {
            if contentY >= cardOffsets[i] && contentY < cardOffsets[i] + cardHeights[i] {
                selectedIndex = i
                return
            }
        }
        selectedIndex = nil
    }

    func selectNext(count: Int) {
        guard count > 0 else { return }
        let current = selectedIndex ?? -1
        selectedIndex = min(current + 1, count - 1)
        snapToSelected()
    }

    func selectPrevious() {
        guard let current = selectedIndex else { return }
        if current <= 0 {
            selectedIndex = 0
        } else {
            selectedIndex = current - 1
        }
        snapToSelected()
    }

    func snapToSelected() {
        guard let index = selectedIndex,
              index < cardOffsets.count,
              index < cardHeights.count else {
            log.debug("Scroll", "snapToSelected: guard failed — selectedIndex=\(String(describing: selectedIndex)), offsets=\(cardOffsets.count), heights=\(cardHeights.count)", emoji: "⚠️")
            return
        }

        let cardTop = cardOffsets[index]
        let cardBottom = cardTop + cardHeights[index]

        if cardTop < scrollOffset {
            log.debug("Scroll", "snapToSelected: card \(index) above viewport, scrolling up to \(Int(cardTop))", emoji: "⬆️")
            scrollOffset = max(cardTop, 0)
        } else if cardBottom > scrollOffset + viewHeight {
            log.debug("Scroll", "snapToSelected: card \(index) below viewport, scrolling down to \(Int(cardBottom - viewHeight))", emoji: "⬇️")
            scrollOffset = min(cardBottom - viewHeight, maxOffset)
        }
    }

    func stopScrolling() {
        isScrollingDown = false
        isScrollingUp = false
        displayLink?.invalidate()
        displayLink = nil
    }

    private func startScrollingDown() {
        guard !isScrollingDown else { return }
        isScrollingUp = false
        isScrollingDown = true
        startDisplayLink()
    }

    private func startScrollingUp() {
        guard !isScrollingUp else { return }
        isScrollingDown = false
        isScrollingUp = true
        startDisplayLink()
    }

    private func startDisplayLink() {
        displayLink?.invalidate()
        lastTimestamp = CACurrentMediaTime()

        displayLink = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = now - lastTimestamp
        lastTimestamp = now

        if isScrollingDown {
            scrollOffset = min(scrollOffset + scrollSpeed * CGFloat(dt), maxOffset)
            if scrollOffset >= maxOffset { stopScrolling() }
        } else if isScrollingUp {
            scrollOffset = max(scrollOffset - scrollSpeed * CGFloat(dt), 0)
            if scrollOffset <= 0 { stopScrolling() }
        }
    }
}
