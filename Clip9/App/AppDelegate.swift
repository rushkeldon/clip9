import AppKit
import SwiftUI

private let log = LogService.shared

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var historyPanel: HistoryPanel?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var scrollEventMonitor: Any?
    private var firstRunBubble = FirstRunBubble()
    let clipboardMonitor = ClipboardMonitor()

    private var settingsWindow: NSWindow?
    private var settingsObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("App", "Clip9 launched", emoji: "🚀")
        setupStatusItem()
        setupHistoryPanel()
        setupGlobalEventMonitor()
        setupKeyboardShortcuts()
        setupScrollMonitor()
        clipboardMonitor.start()
        syncSettingsToComponents()
        observeSettingsChanges()
        log.markStartupComplete()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let button = self?.statusItem.button else { return }
            self?.firstRunBubble.showIfNeeded(relativeTo: button)
        }
        log.info("App", "Startup complete", emoji: "✅")
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem.button else {
            log.error("App", "Failed to get NSStatusBarButton")
            return
        }
        button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clip9")
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
        log.info("App", "Status item created", emoji: "📌")
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            log.warn("App", "Status item clicked but no current event")
            return
        }

        if event.type == .rightMouseUp {
            log.debug("App", "Right-click on status item", emoji: "🖱️")
            showApplicationMenu()
        } else {
            log.debug("App", "Left-click on status item", emoji: "🖱️")
            toggleHistoryPanel()
        }
    }

    // MARK: - History Panel

    private func setupHistoryPanel() {
        historyPanel = HistoryPanel(
            monitor: clipboardMonitor,
            onRestore: { [weak self] entry in
                log.info("App", "Restore requested for entry \(entry.id) (concealed=\(entry.isConcealed), items=\(entry.items.count), bytes=\(entry.totalBytes))", emoji: "📋")
                self?.clipboardMonitor.restore(entry)
                log.info("App", "Closing panel after restore", emoji: "🔽")
                self?.historyPanel?.close()
            },
            onDelete: { [weak self] entry in
                log.info("App", "Delete requested for entry \(entry.id)", emoji: "🗑️")
                self?.clipboardMonitor.deleteEntry(entry)
                if let panel = self?.historyPanel {
                    panel.updateSize(itemCount: self?.clipboardMonitor.history.count ?? 0)
                }
            }
        )
        log.info("App", "History panel created", emoji: "🏠")
    }

    private func toggleHistoryPanel() {
        guard let panel = historyPanel else {
            log.error("App", "History panel is nil")
            return
        }

        if panel.isVisible {
            log.debug("App", "Hiding history panel", emoji: "🔽")
            panel.close()
        } else {
            log.debug("App", "Showing history panel (history count=\(clipboardMonitor.history.count))", emoji: "🔼")
            panel.updateSize(itemCount: clipboardMonitor.history.count)
            positionPanelBelowStatusItem(panel)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func positionPanelBelowStatusItem(_ panel: NSPanel) {
        guard let button = statusItem.button,
              let buttonWindow = button.window else {
            log.warn("App", "Cannot position panel — button or window is nil")
            return
        }

        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)

        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarHeight = screenFrame.maxY - visibleFrame.maxY

        let titlebarHeight = panel.frame.height - panel.contentLayoutRect.height
        let contentSize = panel.contentView?.frame.size ?? .zero

        log.info("App", "=== PANEL POSITION DEBUG ===", emoji: "🔍")
        log.info("App", "Button bounds: \(button.bounds)", emoji: "🔍")
        log.info("App", "Button rect (window coords): \(buttonRect)", emoji: "🔍")
        log.info("App", "Button rect (screen coords): \(screenRect)", emoji: "🔍")
        log.info("App", "Screen frame: \(screenFrame)", emoji: "🔍")
        log.info("App", "Screen visibleFrame: \(visibleFrame)", emoji: "🔍")
        log.info("App", "Menu bar height (screen.maxY - visible.maxY): \(menuBarHeight)", emoji: "🔍")
        log.info("App", "Panel frame: \(panel.frame)", emoji: "🔍")
        log.info("App", "Panel contentLayoutRect: \(panel.contentLayoutRect)", emoji: "🔍")
        log.info("App", "Panel titlebar height (frame - contentLayout): \(titlebarHeight)", emoji: "🔍")
        log.info("App", "Panel contentView frame: \(contentSize)", emoji: "🔍")

        let idealX = screenRect.minX
        let x = min(idealX, visibleFrame.maxX - panel.frame.width)
        let y = max(screenRect.minY - panel.frame.height, visibleFrame.minY)

        log.info("App", "Computed X: idealX=\(Int(idealX)), clamped=\(Int(x))", emoji: "🔍")
        log.info("App", "Computed Y: screenRect.minY=\(Int(screenRect.minY)) - panel.frame.height=\(Int(panel.frame.height)) = \(Int(screenRect.minY - panel.frame.height)), clamped=\(Int(y))", emoji: "🔍")
        log.info("App", "Panel top edge will be at: \(Int(y + panel.frame.height))", emoji: "🔍")
        log.info("App", "Gap from screenRect.minY to panel top: \(Int(screenRect.minY - (y + panel.frame.height)))", emoji: "🔍")
        log.info("App", "=== END DEBUG ===", emoji: "🔍")

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Event Monitors

    private func setupGlobalEventMonitor() {
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            if self?.historyPanel?.isVisible == true {
                log.debug("App", "Click outside — dismissing panel", emoji: "🔽")
                self?.historyPanel?.close()
            }
        }
        log.debug("App", "Global event monitor installed", emoji: "👁️")
    }

    private func setupKeyboardShortcuts() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers {
                case "+", "=":
                    log.debug("App", "Cmd+ pressed — zoom in", emoji: "🔍")
                    self.adjustBaseZoom(by: 0.1)
                    return nil
                case "-":
                    log.debug("App", "Cmd- pressed — zoom out", emoji: "🔍")
                    self.adjustBaseZoom(by: -0.1)
                    return nil
                case "0":
                    log.debug("App", "Cmd+0 pressed — reset zoom", emoji: "🔍")
                    self.resetBaseZoom()
                    return nil
                default:
                    break
                }
            }

            guard self.historyPanel?.isVisible == true else { return event }

            switch event.keyCode {
            case 125: // Down arrow
                self.historyPanel?.scrollState.selectNext(count: self.clipboardMonitor.history.count)
                return nil
            case 126: // Up arrow
                self.historyPanel?.scrollState.selectPrevious()
                return nil
            case 36, 49: // Return/Enter or Spacebar
                self.restoreSelectedEntry()
                return nil
            case 53: // Escape
                self.historyPanel?.close()
                return nil
            default:
                return event
            }
        }
        log.debug("App", "Local keyboard monitor installed", emoji: "⌨️")
    }

    private func setupScrollMonitor() {
        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let panel = self.historyPanel, panel.isVisible else { return event }
            panel.scrollState.applyScrollDelta(-event.scrollingDeltaY)
            return nil
        }
        log.debug("App", "Scroll event monitor installed", emoji: "🖱️")
    }

    private func restoreSelectedEntry() {
        guard let panel = historyPanel,
              let selectedIndex = panel.scrollState.selectedIndex,
              selectedIndex < clipboardMonitor.history.count else { return }
        let entry = clipboardMonitor.history[selectedIndex]
        log.info("App", "Restore via keyboard for entry \(entry.id)", emoji: "⌨️")
        clipboardMonitor.restore(entry)
        panel.close()
    }

    private func adjustBaseZoom(by delta: CGFloat) {
        let current = UserDefaults.standard.object(forKey: "baseZoomLevel") as? Double ?? 1.0
        let newZoom = max(0.5, min(3.0, current + delta))
        UserDefaults.standard.set(newZoom, forKey: "baseZoomLevel")
        log.info("App", "Card size adjusted to \(String(format: "%.1f", newZoom))x", emoji: "🔍")
        resizePanelKeepingRightEdge()
    }

    private func resetBaseZoom() {
        UserDefaults.standard.set(1.0, forKey: "baseZoomLevel")
        log.info("App", "Card size reset to 1.0x", emoji: "🔍")
        resizePanelKeepingRightEdge()
    }

    private func resizePanelKeepingRightEdge() {
        guard let panel = historyPanel, panel.isVisible else { return }
        let oldMaxX = panel.frame.maxX
        let oldMinY = panel.frame.minY
        panel.updateSize(itemCount: clipboardMonitor.history.count)

        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = screen.visibleFrame
        let newWidth = panel.frame.width
        let newHeight = panel.frame.height
        let newX = max(oldMaxX - newWidth, visibleFrame.minX)
        let newY = max(oldMinY + panel.frame.height - newHeight, visibleFrame.minY)

        panel.setFrameOrigin(NSPoint(x: newX, y: newY))
        log.debug("App", "Panel repositioned after zoom: origin=(\(Int(newX)), \(Int(newY))), rightEdge=\(Int(oldMaxX))", emoji: "📐")
    }

    // MARK: - Settings Sync

    private func syncSettingsToComponents() {
        let defaults = UserDefaults.standard

        let historySize = defaults.object(forKey: "historySize") as? Int ?? 100
        let storageCap = defaults.object(forKey: "storageCapGB") as? Double ?? 1.0
        let scrollSpeed = defaults.object(forKey: "scrollSpeed") as? Double ?? 80.0

        historyPanel?.scrollState.scrollSpeed = CGFloat(scrollSpeed)
        clipboardMonitor.maxHistorySize = historySize
        StorageManager.shared.maxEntryCount = historySize
        StorageManager.shared.storageCapBytes = Int(storageCap * 1_073_741_824)

        log.debug("App", "Settings synced: history=\(historySize), cap=\(storageCap)GB, speed=\(scrollSpeed)", emoji: "⚙️")
    }

    private func observeSettingsChanges() {
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncSettingsToComponents()
        }
        settingsObservers.append(observer)
    }

    // MARK: - Right-Click Application Menu

    private func showApplicationMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "About Clip9", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let supportItem = NSMenuItem(title: "Support", action: #selector(openSupport), keyEquivalent: "")
        supportItem.target = self
        menu.addItem(supportItem)

        let logsItem = NSMenuItem(title: "Show Logs", action: #selector(showLogs), keyEquivalent: "")
        logsItem.target = self
        menu.addItem(logsItem)

        #if !CLIP9_PRO
        let proItem = NSMenuItem(title: "Get Pro", action: #selector(openGetPro), keyEquivalent: "")
        proItem.target = self
        menu.addItem(proItem)
        #endif

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Clip9", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    @objc private func openSettings() {
        log.info("App", "Opening settings", emoji: "⚙️")

        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Clip9 Settings"
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func showAbout() {
        log.info("App", "Showing about panel", emoji: "ℹ️")
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func clearHistory() {
        log.info("App", "Clear history requested", emoji: "🗑️")
        let alert = NSAlert()
        alert.messageText = "Clear Clipboard History?"
        alert.informativeText = "This will permanently delete all stored clipboard entries."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            clipboardMonitor.clearHistory()
            log.info("App", "History cleared by user", emoji: "🗑️")
        } else {
            log.debug("App", "Clear history cancelled", emoji: "🔙")
        }
    }

    @objc private func openSupport() {
        log.info("App", "Opening support URL", emoji: "🔗")
        if let url = URL(string: "https://clip9.app/support") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showLogs() {
        log.info("App", "Opening logs directory", emoji: "📂")
        LogService.shared.openLogsInFinder()
    }

    #if !CLIP9_PRO
    @objc private func openGetPro() {
        log.info("App", "Opening Get Pro URL", emoji: "🔗")
        if let url = URL(string: "https://clip9.app/pro") {
            NSWorkspace.shared.open(url)
        }
    }
    #endif

    deinit {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = scrollEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        for observer in settingsObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        log.info("App", "AppDelegate deinit", emoji: "🛑")
    }
}
