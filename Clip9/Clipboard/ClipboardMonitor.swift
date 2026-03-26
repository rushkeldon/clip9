import AppKit
import Foundation
import UniformTypeIdentifiers

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
        let concealed = history.filter(\.isConcealed)
        if !concealed.isEmpty {
            for entry in concealed {
                StorageManager.shared.deleteEntry(uuidString: entry.id.uuidString)
            }
            history.removeAll { $0.isConcealed }
            log.info("Clipboard", "Removed \(concealed.count) legacy concealed placeholder(s) from history", emoji: "🧹")
        }
        log.info("Clipboard", "Loaded \(history.count) entries from disk", emoji: "📚")

        lastChangeCount = pasteboard.changeCount
        log.debug("Clipboard", "Initial changeCount=\(lastChangeCount)")
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.pollClipboard()
        }
        log.info("Clipboard", "Monitoring started (250ms poll)", emoji: "✅")
        preWarmDisplayCache()
    }

    private func preWarmDisplayCache() {
        let entriesToWarm = history
        log.info("Clipboard", "Pre-warming display cache for \(entriesToWarm.count) entries...", emoji: "🔥")
        for entry in entriesToWarm {
            DispatchQueue.main.async {
                DisplayStateCache.shared.warmIfNeeded(entry: entry)
            }
        }
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
            log.info("Clipboard", "Concealed content detected — not recording in history", emoji: "🔐")
            return
        }

        var capturedItems: [PasteboardItemData] = []

        for (itemIndex, item) in pasteboardItems.enumerated() {
            var types = item.types
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

            Self.fetchImageFileData(into: &dataByType, types: &types, log: log)

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
            isConcealed: false,
            displayCache: nil
        )

        if candidateEntry.totalBytes == 0 {
            log.info("Clipboard", "Skipping capture — pasteboard has no payload bytes (e.g. empty text only)", emoji: "⏭️")
            return
        }

        let cache = DisplayCache.compute(from: candidateEntry)
        let cachedCandidate = ClipboardEntry(
            id: candidateEntry.id,
            timestamp: candidateEntry.timestamp,
            items: candidateEntry.items,
            isConcealed: false,
            displayCache: cache
        )

        // Check 1: Exact duplicate anywhere in history — promote to top
        let candidateBytes = candidateEntry.totalBytes
        for i in 0..<history.count {
            if history[i].totalBytes == candidateBytes && history[i].contentEquals(candidateEntry) {
                let existing = history.remove(at: i)
                let promoted = ClipboardEntry(
                    id: existing.id,
                    timestamp: Date(),
                    items: existing.items,
                    isConcealed: existing.isConcealed,
                    displayCache: existing.displayCache
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
                isConcealed: false,
                displayCache: cache
            )
            StorageManager.shared.save(history[0])
            DisplayStateCache.shared.remove(id: mostRecent.id)
            DisplayStateCache.shared.warmIfNeeded(entry: history[0])
            log.info("Clipboard", "Superset coalesce — replaced entry \(mostRecent.id) (\(oldTypes) → \(newTypes) types, \(mostRecent.totalBytes) → \(candidateEntry.totalBytes) bytes)", emoji: "🔄")
            return
        }

        pushEntry(cachedCandidate)

        let preview: String
        if let text = cachedCandidate.plainText {
            preview = LogService.truncate(text.replacingOccurrences(of: "\n", with: "\\n"))
        } else if cachedCandidate.hasImage {
            preview = "image"
        } else if cachedCandidate.hasFileURLs {
            preview = "file: \(cachedCandidate.fileURLs.first?.lastPathComponent ?? "?")"
        } else {
            preview = "binary data"
        }
        log.info("Clipboard", "Captured entry \(cachedCandidate.id): \(capturedItems.count) item(s), \(cachedCandidate.totalBytes) bytes — \(preview)", emoji: "✅")
    }

    private func pushEntry(_ entry: ClipboardEntry) {
        history.insert(entry, at: 0)
        let overflow = history.count - maxHistorySize
        if overflow > 0 {
            history.removeLast(overflow)
            log.debug("Clipboard", "Evicted \(overflow) entry(s) from in-memory history (max=\(maxHistorySize))", emoji: "🗑️")
        }
        StorageManager.shared.save(entry)
        DisplayStateCache.shared.warmIfNeeded(entry: entry)
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
        DisplayStateCache.shared.remove(id: entry.id)
        log.info("Clipboard", "Deleted entry \(entry.id) from position \(index)", emoji: "🗑️")
    }

    // MARK: - Image File Fetch

    private static let maxImageFileFetchBytes = 50_000_000 // 50 MB

    /// If the item contains a public.file-url pointing to an image, read the file and
    /// store its bytes under the native UTI so the entry is self-contained.
    private static func fetchImageFileData(
        into dataByType: inout [NSPasteboard.PasteboardType: Data],
        types: inout [NSPasteboard.PasteboardType],
        log: LogService
    ) {
        let fileURLType = NSPasteboard.PasteboardType("public.file-url")
        guard let urlData = dataByType[fileURLType],
              let urlString = String(data: urlData, encoding: .utf8),
              let url = URL(string: urlString),
              let utType = UTType(filenameExtension: url.pathExtension),
              utType.conforms(to: .image) else { return }

        let imageType = NSPasteboard.PasteboardType(utType.identifier)
        guard dataByType[imageType] == nil else { return }

        guard let fileData = try? Data(contentsOf: url) else {
            log.warn("Clipboard", "Failed to read image file: \(url.lastPathComponent)")
            return
        }
        guard fileData.count <= maxImageFileFetchBytes else {
            log.info("Clipboard", "Skipping image file fetch — \(url.lastPathComponent) exceeds \(maxImageFileFetchBytes / 1_000_000)MB cap (\(fileData.count) bytes)")
            return
        }

        dataByType[imageType] = fileData
        types.append(imageType)
        log.info("Clipboard", "Fetched image file data: \(url.lastPathComponent) (\(fileData.count) bytes, \(utType.identifier))")
    }

    // MARK: - Clear

    func clearHistory() {
        let count = history.count
        history.removeAll()
        StorageManager.shared.deleteAllEntries()
        DisplayStateCache.shared.removeAll()
        log.info("Clipboard", "History cleared (\(count) entries removed)", emoji: "🗑️")
    }

    deinit {
        stop()
    }
}
