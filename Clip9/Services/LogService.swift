import Foundation
import AppKit

private let log = LogService.shared

nonisolated final class LogService: @unchecked Sendable {
    static let shared = LogService()
    private var isStartupComplete = false

    enum Level: String { case debug = "DEBUG", info = "INFO", warn = "WARN", error = "ERROR" }

    static var logsDirectory: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport
            .appendingPathComponent("Clip9", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let queue = DispatchQueue(label: "com.appcloud9.Clip9.logwriter", qos: .utility)
    private var handle: FileHandle?
    private var currentDay: String?

    private init() {
        _ = Self.logsDirectory
        queue.async { [weak self] in
            self?.pruneOldLogs(daysToKeep: 7)
        }
    }

    // MARK: - Public API

    func debug(_ subsystem: String, _ message: String, emoji: String = "📦") {
        write(.debug, subsystem, message, emoji: emoji)
    }

    func info(_ subsystem: String, _ message: String, emoji: String = "ℹ️") {
        write(.info, subsystem, message, emoji: emoji)
    }

    func warn(_ subsystem: String, _ message: String, emoji: String = "⚠️") {
        write(.warn, subsystem, message, emoji: emoji)
    }

    func error(_ subsystem: String, _ message: String, emoji: String = "❌") {
        write(.error, subsystem, message, emoji: emoji)
    }

    func openLogsInFinder() {
        guard isStartupComplete else { return }
        NSWorkspace.shared.open(Self.logsDirectory)
    }

    func markStartupComplete() {
        isStartupComplete = true
    }

    static func truncate(_ string: String, maxLength: Int = 100) -> String {
        guard string.count > maxLength else { return string }
        return String(string.prefix(maxLength)) + "..."
    }

    // MARK: - Core write

    private func write(_ level: Level, _ subsystem: String, _ message: String, emoji: String) {
        let line = formatLine(level: level, subsystem: subsystem, message: message, emoji: emoji)
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.rotateIfNeeded()
                guard let h = self.handle else { return }
                if let data = (line + "\n").data(using: .utf8) {
                    h.write(data)
                }
            } catch {
                // Best-effort: silently drop logging failures
            }
        }
    }

    private func formatLine(level: Level, subsystem: String, message: String, emoji: String) -> String {
        let ts = iso.string(from: Date())
        return "\(ts) \(emoji) \(level.rawValue) [\(subsystem)] \(message)"
    }

    // MARK: - File management

    private func rotateIfNeeded() throws {
        let today = dayFormatter.string(from: Date())
        if today != currentDay || handle == nil {
            try openForDay(today)
        }
    }

    private func openForDay(_ day: String) throws {
        try? handle?.close()
        handle = nil
        currentDay = day

        let fileURL = Self.logsDirectory.appendingPathComponent("clip9-\(day).log")
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            _ = fm.createFile(atPath: fileURL.path, contents: nil)
        }
        do {
            let h = try FileHandle(forWritingTo: fileURL)
            try h.seekToEnd()
            handle = h
        } catch {
            handle = nil
        }
    }

    // MARK: - Log pruning

    private func pruneOldLogs(daysToKeep: Int) {
        let logsDir = Self.logsDirectory
        let fm = FileManager.default

        guard let items = try? fm.contentsOfDirectory(
            at: logsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-Double(daysToKeep) * 24 * 60 * 60)
        var deletedCount = 0

        for url in items {
            guard url.lastPathComponent.hasPrefix("clip9-") && url.pathExtension == "log" else { continue }
            let attrs = (try? fm.attributesOfItem(atPath: url.path)) ?? [:]
            let modDate = (attrs[.modificationDate] as? Date) ?? Date()
            if modDate < cutoff {
                try? fm.removeItem(at: url)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            write(.info, "LogService", "Pruned \(deletedCount) old log file(s)", emoji: "🧹")
        }
    }
}
