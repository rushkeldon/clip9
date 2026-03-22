import AppKit
import SwiftUI

private let log = LogService.shared

class FirstRunBubble {
    private var popover: NSPopover?
    private static let hasShownKey = "hasShownFirstRunBubble"

    var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: Self.hasShownKey)
    }

    func showIfNeeded(relativeTo button: NSStatusBarButton) {
        guard shouldShow else {
            log.debug("FirstRun", "First-run bubble already shown previously — skipping", emoji: "⏭️")
            return
        }

        UserDefaults.standard.set(true, forKey: Self.hasShownKey)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: FirstRunContent())
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
        log.info("FirstRun", "First-run bubble displayed", emoji: "👋")

        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.popover?.close()
            self?.popover = nil
            log.debug("FirstRun", "First-run bubble auto-dismissed", emoji: "🔽")
        }
    }
}

private struct FirstRunContent: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Clip9 lives here.")
                .font(.headline)
            Text("\u{2318}+ and \u{2318}\u{2212} to adjust size.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 240)
    }
}
