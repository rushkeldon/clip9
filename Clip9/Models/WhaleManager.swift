import Foundation

private let log = LogService.shared

struct WhaleInfo: Codable {
    var remainingDisplays: Int
    var isZombie: Bool
}

/// Tracks whale state for oversized clipboard entries.
/// Whale metadata is separate from ClipboardEntry to keep the entry model clean.
@Observable
class WhaleManager {
    static let shared = WhaleManager()

    private(set) var whales: [UUID: WhaleInfo] = [:]

    private let fileManager = FileManager.default
    private let persistenceURL: URL

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let clip9Dir = appSupport.appendingPathComponent("Clip9", isDirectory: true)
        try? fileManager.createDirectory(at: clip9Dir, withIntermediateDirectories: true)
        persistenceURL = clip9Dir.appendingPathComponent("whales.json")
        load()
    }

    // MARK: - Queries

    func isWhale(_ id: UUID) -> Bool {
        whales[id] != nil
    }

    func info(for id: UUID) -> WhaleInfo? {
        whales[id]
    }

    func isZombie(_ id: UUID) -> Bool {
        whales[id]?.isZombie == true
    }

    var whaleIDs: Set<UUID> {
        Set(whales.keys)
    }

    var zombieIDs: [UUID] {
        whales.filter { $0.value.isZombie }.map { $0.key }
    }

    // MARK: - Registration

    func registerWhale(_ id: UUID) {
        whales[id] = WhaleInfo(remainingDisplays: 4, isZombie: false)
        save()
        log.info("Whale", "Registered whale \(id) with 4 display countdown", emoji: "🐋")
    }

    func removeWhale(_ id: UUID) {
        guard whales.removeValue(forKey: id) != nil else { return }
        save()
        log.info("Whale", "Removed whale tracking for \(id)", emoji: "🐋")
    }

    // MARK: - Display Countdown

    /// Called each time the history panel is presented.
    /// Decrements remaining displays for active whales and transitions expired ones to zombie.
    func decrementDisplayCounts() {
        var changed = false
        for (id, var info) in whales {
            if info.isZombie { continue }
            info.remainingDisplays = max(0, info.remainingDisplays - 1)
            if info.remainingDisplays == 0 {
                info.isZombie = true
                log.info("Whale", "Whale \(id) countdown expired — now zombie", emoji: "💀")
            } else {
                log.debug("Whale", "Whale \(id) countdown: \(info.remainingDisplays) displays remaining", emoji: "🐋")
            }
            whales[id] = info
            changed = true
        }
        if changed { save() }
    }

    // MARK: - Cascading Memory Suggestions

    /// Computes the suggested new storage cap if the user accepts the "Increase" option
    /// for a given whale, considering all preceding whales in history order as if accepted.
    func suggestedCapBytes(
        for whaleID: UUID,
        historyOrder: [UUID],
        currentCapBytes: Int,
        currentTotalBytes: Int
    ) -> Int? {
        var simulatedCap = currentCapBytes
        let simulatedTotal = currentTotalBytes

        for id in historyOrder {
            guard let info = whales[id], !info.isZombie else { continue }
            if simulatedTotal > simulatedCap {
                simulatedCap = roundUpTo250MB(simulatedTotal)
            }
            if id == whaleID {
                return simulatedTotal > simulatedCap ? roundUpTo250MB(simulatedTotal) : simulatedCap
            }
        }
        return roundUpTo250MB(simulatedTotal)
    }

    private func roundUpTo250MB(_ bytes: Int) -> Int {
        let chunk = 250 * 1_048_576
        return ((bytes + chunk - 1) / chunk) * chunk
    }

    // MARK: - Persistence

    private func save() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: whales.map { ($0.key.uuidString, $0.value) })
        guard let data = try? JSONEncoder().encode(stringKeyed) else { return }
        try? data.write(to: persistenceURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let stringKeyed = try? JSONDecoder().decode([String: WhaleInfo].self, from: data) else { return }
        whales = Dictionary(uniqueKeysWithValues: stringKeyed.compactMap { key, value in
            guard let uuid = UUID(uuidString: key) else { return nil }
            return (uuid, value)
        })
        if !whales.isEmpty {
            log.info("Whale", "Loaded \(whales.count) whale(s) from disk", emoji: "🐋")
        }
    }

    /// Removes whale entries whose IDs no longer exist in history (cleanup after deletion).
    func pruneOrphans(validIDs: Set<UUID>) {
        let orphans = whales.keys.filter { !validIDs.contains($0) }
        guard !orphans.isEmpty else { return }
        for id in orphans {
            whales.removeValue(forKey: id)
        }
        save()
        log.info("Whale", "Pruned \(orphans.count) orphaned whale(s)", emoji: "🧹")
    }

    // MARK: - Hard Backstop

    static func totalDiskSpaceBytes() -> Int {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ), let total = attrs[.systemSize] as? Int else { return 0 }
        return total
    }

    static func freeDiskSpaceBytes() -> Int {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ), let free = attrs[.systemFreeSize] as? Int else { return 0 }
        return free
    }

    /// The absolute maximum storage the app may use, even during ballooning.
    static func hardBackstopBytes(softCapBytes: Int) -> Int {
        let totalDisk = totalDiskSpaceBytes()
        let fiveGB = 5_368_709_120
        if softCapBytes <= fiveGB {
            return min(fiveGB, totalDisk / 10)
        } else {
            return totalDisk * 15 / 100
        }
    }

    /// Whether the disk has enough free space to persist the given number of bytes,
    /// maintaining a 500 MB safety margin.
    static func canFitOnDisk(bytes: Int) -> Bool {
        let safetyMargin = 500 * 1_048_576
        return freeDiskSpaceBytes() > bytes + safetyMargin
    }
}
