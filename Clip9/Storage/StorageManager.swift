import AppKit
import Foundation

private let log = LogService.shared

/// File-based persistence for clipboard history.
class StorageManager {
    static let shared = StorageManager()

    var maxEntryCount: Int = 100
    var storageCapBytes: Int = 1_073_741_824  // ~1 GB

    private let fileManager = FileManager.default
    private let historyDirectory: URL
    private let indexURL: URL
    private let ioQueue = DispatchQueue(label: "com.appcloud9.Clip9.storage", qos: .utility)

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        historyDirectory = appSupport.appendingPathComponent("Clip9/history", isDirectory: true)
        indexURL = historyDirectory.appendingPathComponent("index.json")

        try? fileManager.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        log.info("Storage", "History directory: \(historyDirectory.path)", emoji: "📂")
    }

    // MARK: - Save

    func save(_ entry: ClipboardEntry) {
        ioQueue.async { [self] in
            do {
                try writeEntry(entry)
                try appendToIndex(entry.id)
                try enforceEvictionLimits()
                log.info("Storage", "Saved entry \(entry.id) (\(entry.totalBytes) bytes, \(entry.items.count) items)", emoji: "💾")
            } catch {
                log.error("Storage", "Failed to save entry \(entry.id): \(error.localizedDescription)")
            }
        }
    }

    private func writeEntry(_ entry: ClipboardEntry) throws {
        let entryDir = historyDirectory.appendingPathComponent(entry.id.uuidString, isDirectory: true)
        let tmpDir = historyDirectory.appendingPathComponent("tmp_\(entry.id.uuidString)", isDirectory: true)

        try fileManager.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let meta = EntryMetadata(
            uuid: entry.id.uuidString,
            timestamp: entry.timestamp.timeIntervalSince1970,
            itemCount: entry.items.count,
            totalBytes: entry.totalBytes,
            isConcealed: entry.isConcealed
        )
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: tmpDir.appendingPathComponent("meta.json"))

        for (itemIndex, item) in entry.items.enumerated() {
            let itemDir = tmpDir.appendingPathComponent("item_\(itemIndex)", isDirectory: true)
            try fileManager.createDirectory(at: itemDir, withIntermediateDirectories: true)

            let typeStrings = item.types.map { $0.rawValue }
            let manifestData = try JSONEncoder().encode(typeStrings)
            try manifestData.write(to: itemDir.appendingPathComponent("type_manifest.json"))

            for (typeIndex, type) in item.types.enumerated() {
                if let data = item.dataByType[type] {
                    try data.write(to: itemDir.appendingPathComponent("\(typeIndex).blob"))
                }
            }
        }

        if fileManager.fileExists(atPath: entryDir.path) {
            try fileManager.removeItem(at: entryDir)
        }
        try fileManager.moveItem(at: tmpDir, to: entryDir)
        log.debug("Storage", "Wrote entry directory: \(entryDir.lastPathComponent)")
    }

    // MARK: - Load

    func loadAllEntries() -> [ClipboardEntry] {
        let uuids = loadIndex()
        log.info("Storage", "Loading \(uuids.count) entries from index", emoji: "📂")

        var entries: [ClipboardEntry] = []
        var failedCount = 0
        for uuidString in uuids {
            if let entry = loadEntry(uuidString: uuidString) {
                entries.append(entry)
            } else {
                failedCount += 1
                log.warn("Storage", "Failed to load entry: \(uuidString)")
            }
        }

        if failedCount > 0 {
            log.warn("Storage", "\(failedCount) entries failed to load")
        }
        log.info("Storage", "Loaded \(entries.count)/\(uuids.count) entries successfully", emoji: "✅")
        return entries
    }

    func loadEntry(uuidString: String) -> ClipboardEntry? {
        let entryDir = historyDirectory.appendingPathComponent(uuidString, isDirectory: true)
        let metaURL = entryDir.appendingPathComponent("meta.json")

        guard let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(EntryMetadata.self, from: metaData),
              let uuid = UUID(uuidString: meta.uuid) else {
            return nil
        }

        if meta.isConcealed {
            return ClipboardEntry(
                id: uuid,
                timestamp: Date(timeIntervalSince1970: meta.timestamp),
                items: [],
                isConcealed: true
            )
        }

        var items: [PasteboardItemData] = []
        for itemIndex in 0..<meta.itemCount {
            let itemDir = entryDir.appendingPathComponent("item_\(itemIndex)", isDirectory: true)
            let manifestURL = itemDir.appendingPathComponent("type_manifest.json")

            guard let manifestData = try? Data(contentsOf: manifestURL),
                  let typeStrings = try? JSONDecoder().decode([String].self, from: manifestData) else {
                log.warn("Storage", "Missing manifest for item_\(itemIndex) in \(uuidString)")
                continue
            }

            let types = typeStrings.map { NSPasteboard.PasteboardType($0) }
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]

            for (typeIndex, type) in types.enumerated() {
                let blobURL = itemDir.appendingPathComponent("\(typeIndex).blob")
                if let data = try? Data(contentsOf: blobURL) {
                    dataByType[type] = data
                }
            }

            if !dataByType.isEmpty {
                items.append(PasteboardItemData(types: types, dataByType: dataByType))
            }
        }

        return ClipboardEntry(
            id: uuid,
            timestamp: Date(timeIntervalSince1970: meta.timestamp),
            items: items,
            isConcealed: false
        )
    }

    // MARK: - Index

    private func loadIndex() -> [String] {
        if let data = try? Data(contentsOf: indexURL),
           let uuids = try? JSONDecoder().decode([String].self, from: data) {
            log.debug("Storage", "Loaded index.json with \(uuids.count) entries")
            return uuids
        }
        return reconstructIndex()
    }

    private func reconstructIndex() -> [String] {
        log.warn("Storage", "index.json missing or corrupt — reconstructing from meta.json timestamps")

        guard let contents = try? fileManager.contentsOfDirectory(
            at: historyDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        var entries: [(uuid: String, timestamp: TimeInterval)] = []
        for dir in contents {
            let metaURL = dir.appendingPathComponent("meta.json")
            guard let data = try? Data(contentsOf: metaURL),
                  let meta = try? JSONDecoder().decode(EntryMetadata.self, from: data) else {
                continue
            }
            entries.append((uuid: meta.uuid, timestamp: meta.timestamp))
        }

        entries.sort { $0.timestamp > $1.timestamp }
        let uuids = entries.map { $0.uuid }

        try? saveIndex(uuids)
        log.info("Storage", "Reconstructed index with \(uuids.count) entries", emoji: "🔄")
        return uuids
    }

    private func appendToIndex(_ uuid: UUID) throws {
        var uuids = loadIndex()
        uuids.insert(uuid.uuidString, at: 0)
        try saveIndex(uuids)
    }

    private func saveIndex(_ uuids: [String]) throws {
        let data = try JSONEncoder().encode(uuids)
        try data.write(to: indexURL, options: .atomic)
    }

    // MARK: - Delete

    func deleteEntry(uuidString: String) {
        let entryDir = historyDirectory.appendingPathComponent(uuidString, isDirectory: true)
        try? fileManager.removeItem(at: entryDir)

        if var uuids = try? JSONDecoder().decode(
            [String].self,
            from: Data(contentsOf: indexURL)
        ) {
            uuids.removeAll { $0 == uuidString }
            try? saveIndex(uuids)
        }
        log.debug("Storage", "Deleted entry \(uuidString)", emoji: "🗑️")
    }

    func deleteAllEntries() {
        let uuids = loadIndex()
        for uuid in uuids {
            let entryDir = historyDirectory.appendingPathComponent(uuid, isDirectory: true)
            try? fileManager.removeItem(at: entryDir)
        }
        try? saveIndex([])
        log.info("Storage", "All entries deleted (\(uuids.count) removed)", emoji: "🗑️")
    }

    // MARK: - Eviction

    private func enforceEvictionLimits() throws {
        var uuids = loadIndex()
        var evictedCount = 0

        while uuids.count > maxEntryCount {
            let oldest = uuids.removeLast()
            let dir = historyDirectory.appendingPathComponent(oldest, isDirectory: true)
            try? fileManager.removeItem(at: dir)
            evictedCount += 1
        }

        var totalSize = computeTotalSize(uuids: uuids)
        while totalSize > storageCapBytes, !uuids.isEmpty {
            let oldest = uuids.removeLast()
            let dir = historyDirectory.appendingPathComponent(oldest, isDirectory: true)
            let entrySize = directorySize(at: dir)
            try? fileManager.removeItem(at: dir)
            totalSize -= entrySize
            evictedCount += 1
        }

        if evictedCount > 0 {
            try saveIndex(uuids)
            log.info("Storage", "Evicted \(evictedCount) entries (remaining=\(uuids.count), size=\(totalSize / 1024)KB)", emoji: "🧹")
        }
    }

    private func computeTotalSize(uuids: [String]) -> Int {
        uuids.reduce(0) { total, uuid in
            let dir = historyDirectory.appendingPathComponent(uuid, isDirectory: true)
            return total + directorySize(at: dir)
        }
    }

    private func directorySize(at url: URL) -> Int {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var size = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = values.fileSize {
                size += fileSize
            }
        }
        return size
    }

}

// MARK: - Metadata Codable

private struct EntryMetadata: Codable {
    let uuid: String
    let timestamp: TimeInterval
    let itemCount: Int
    let totalBytes: Int
    let isConcealed: Bool
}
