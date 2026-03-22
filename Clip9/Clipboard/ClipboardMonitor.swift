import AppKit
import Foundation

private let log = LogService.shared

/// Monitors NSPasteboard.general for changes and captures full-fidelity clipboard data.
@Observable
class ClipboardMonitor {
    private(set) var history: [ClipboardEntry] = []

    var maxHistorySize: Int = 100

    private var pollTimer: Timer?
    private var lastChangeCount: Int = 0
    private var selfChangeCount: Int = -1
    private let pasteboard = NSPasteboard.general

    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    func start() {
        log.info("Clipboard", "Loading history from disk...", emoji: "📂")
        history = StorageManager.shared.loadAllEntries()
        log.info("Clipboard", "Loaded \(history.count) entries from disk", emoji: "📚")

        lastChangeCount = pasteboard.changeCount
        log.debug("Clipboard", "Initial changeCount=\(lastChangeCount)")
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.pollClipboard()
        }
        log.info("Clipboard", "Monitoring started (250ms poll)", emoji: "✅")
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        log.info("Clipboard", "Monitoring stopped", emoji: "🛑")
    }

    // MARK: - Polling

    private func pollClipboard() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }

        log.debug("Clipboard", "changeCount changed: \(lastChangeCount) → \(currentChangeCount)", emoji: "🔄")
        lastChangeCount = currentChangeCount

        if currentChangeCount == selfChangeCount {
            log.debug("Clipboard", "Ignoring self-change (changeCount=\(currentChangeCount))", emoji: "⏭️")
            return
        }

        captureClipboard()
    }

    // MARK: - Capture

    private func captureClipboard() {
        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else {
            log.warn("Clipboard", "Pasteboard is empty or nil — nothing to capture")
            return
        }

        log.info("Clipboard", "Capturing clipboard: \(pasteboardItems.count) item(s) on pasteboard", emoji: "📋")

        let isConcealed = pasteboardItems.contains { item in
            item.types.contains(ClipboardMonitor.concealedType)
        }

        if isConcealed {
            let sentinel = ClipboardEntry(
                id: UUID(),
                timestamp: Date(),
                items: [],
                isConcealed: true
            )
            pushEntry(sentinel)
            log.info("Clipboard", "Concealed content detected — sentinel entry created (\(sentinel.id))", emoji: "🔐")
            return
        }

        var capturedItems: [PasteboardItemData] = []

        for (itemIndex, item) in pasteboardItems.enumerated() {
            let types = item.types
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]

            log.debug("Clipboard", "  Item[\(itemIndex)]: \(types.count) types: \(types.map { $0.rawValue }.joined(separator: ", "))")

            for type in types {
                if let data = item.data(forType: type) {
                    dataByType[type] = data
                    log.debug("Clipboard", "    \(type.rawValue): \(data.count) bytes")
                } else {
                    log.warn("Clipboard", "    \(type.rawValue): data(forType:) returned nil")
                }
            }

            if !dataByType.isEmpty {
                capturedItems.append(PasteboardItemData(types: types, dataByType: dataByType))
            }
        }

        guard !capturedItems.isEmpty else {
            log.warn("Clipboard", "All items had empty data — skipping capture")
            return
        }

        let candidateEntry = ClipboardEntry(
            id: UUID(),
            timestamp: Date(),
            items: capturedItems,
            isConcealed: false
        )

        // Check 1: Exact duplicate within last 10 — promote existing
        let dedupWindow = min(history.count, 10)
        for i in 0..<dedupWindow {
            if history[i].contentEquals(candidateEntry) {
                let existing = history.remove(at: i)
                let promoted = ClipboardEntry(
                    id: existing.id,
                    timestamp: Date(),
                    items: existing.items,
                    isConcealed: existing.isConcealed
                )
                history.insert(promoted, at: 0)
                log.info("Clipboard", "Duplicate detected — promoted existing entry \(existing.id) from position \(i) to top", emoji: "⏫")
                return
            }
        }

        // Check 2: Superset of most recent entry — replace with richer version
        if let mostRecent = history.first, mostRecent.isSubset(of: candidateEntry) {
            let oldTypes = mostRecent.items.first?.types.count ?? 0
            let newTypes = candidateEntry.items.first?.types.count ?? 0
            history[0] = ClipboardEntry(
                id: mostRecent.id,
                timestamp: Date(),
                items: candidateEntry.items,
                isConcealed: false
            )
            StorageManager.shared.save(history[0])
            log.info("Clipboard", "Superset coalesce — replaced entry \(mostRecent.id) (\(oldTypes) → \(newTypes) types, \(mostRecent.totalBytes) → \(candidateEntry.totalBytes) bytes)", emoji: "🔄")
            return
        }

        pushEntry(candidateEntry)

        let preview: String
        if let text = candidateEntry.plainText {
            preview = LogService.truncate(text.replacingOccurrences(of: "\n", with: "\\n"))
        } else if candidateEntry.hasImage {
            preview = "image"
        } else if candidateEntry.hasFileURLs {
            preview = "file: \(candidateEntry.fileURLs.first?.lastPathComponent ?? "?")"
        } else {
            preview = "binary data"
        }
        log.info("Clipboard", "Captured entry \(candidateEntry.id): \(capturedItems.count) item(s), \(candidateEntry.totalBytes) bytes — \(preview)", emoji: "✅")
    }

    private func pushEntry(_ entry: ClipboardEntry) {
        history.insert(entry, at: 0)
        let overflow = history.count - maxHistorySize
        if overflow > 0 {
            history.removeLast(overflow)
            log.debug("Clipboard", "Evicted \(overflow) entry(s) from in-memory history (max=\(maxHistorySize))", emoji: "🗑️")
        }
        StorageManager.shared.save(entry)
    }

    // MARK: - Restore

    func restore(_ entry: ClipboardEntry) {
        log.info("Clipboard", "▶ restore() called for entry \(entry.id)", emoji: "📋")

        guard !entry.isConcealed else {
            log.warn("Clipboard", "Cannot restore concealed entry \(entry.id)")
            return
        }

        log.info("Clipboard", "  Entry has \(entry.items.count) pasteboard item(s), \(entry.totalBytes) total bytes", emoji: "📋")

        log.debug("Clipboard", "  Calling pasteboard.clearContents()...")
        pasteboard.clearContents()

        var pasteboardItems: [NSPasteboardItem] = []

        for (itemIndex, itemData) in entry.items.enumerated() {
            let item = NSPasteboardItem()
            var typesWritten = 0
            for type in itemData.types {
                if let data = itemData.dataByType[type] {
                    item.setData(data, forType: type)
                    typesWritten += 1
                }
            }
            pasteboardItems.append(item)
            log.debug("Clipboard", "  Built NSPasteboardItem[\(itemIndex)]: \(typesWritten) types written")
        }

        let success = pasteboard.writeObjects(pasteboardItems)
        selfChangeCount = pasteboard.changeCount

        if success {
            log.info("Clipboard", "✅ Restore successful — wrote \(pasteboardItems.count) item(s) to pasteboard (new changeCount=\(selfChangeCount))", emoji: "✅")
        } else {
            log.error("Clipboard", "❌ pasteboard.writeObjects() returned false for entry \(entry.id)")
        }
    }

    // MARK: - Delete Single

    func deleteEntry(_ entry: ClipboardEntry) {
        guard let index = history.firstIndex(where: { $0.id == entry.id }) else {
            log.warn("Clipboard", "Delete requested but entry \(entry.id) not found in history")
            return
        }
        history.remove(at: index)
        StorageManager.shared.deleteEntry(uuidString: entry.id.uuidString)
        log.info("Clipboard", "Deleted entry \(entry.id) from position \(index)", emoji: "🗑️")
    }

    // MARK: - Clear

    func clearHistory() {
        let count = history.count
        history.removeAll()
        StorageManager.shared.deleteAllEntries()
        log.info("Clipboard", "History cleared (\(count) entries removed)", emoji: "🗑️")
    }
}
