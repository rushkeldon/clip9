import AppKit
import Foundation

struct PasteboardItemData: Sendable {
    let types: [NSPasteboard.PasteboardType]
    let dataByType: [NSPasteboard.PasteboardType: Data]

    /// Order-independent byte-level content equality: same set of types, identical data blobs.
    func contentEquals(_ other: PasteboardItemData) -> Bool {
        let myTypes = Set(types.map { $0.rawValue })
        let otherTypes = Set(other.types.map { $0.rawValue })
        guard myTypes == otherTypes else { return false }
        for type in types {
            guard dataByType[type] == other.dataByType[type] else { return false }
        }
        return true
    }

    /// Returns true if `other` is a superset of `self`: all of self's types exist
    /// in other with identical data, and other has at least one additional type.
    func isSubset(of other: PasteboardItemData) -> Bool {
        guard other.types.count > types.count else { return false }
        for type in types {
            guard let myData = dataByType[type],
                  let otherData = other.dataByType[type],
                  myData == otherData else {
                return false
            }
        }
        return true
    }
}

enum MediaFileType: CustomStringConvertible {
    case image
    case video
    case audio
    case other

    var description: String {
        switch self {
        case .image: return "image"
        case .video: return "video"
        case .audio: return "audio"
        case .other: return "other"
        }
    }

    private static let imageExtensions: Set<String> = [
        "gif", "png", "jpg", "jpeg", "webp", "tiff", "tif", "bmp",
        "heic", "heif", "apng", "svg", "ico", "icns"
    ]
    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "webm", "m4v", "avi", "mkv"
    ]
    private static let audioExtensions: Set<String> = [
        "mp3", "wav", "aac", "m4a", "flac", "ogg", "aiff", "wma", "caf"
    ]

    init(fileExtension ext: String) {
        let lower = ext.lowercased()
        if Self.imageExtensions.contains(lower) {
            self = .image
        } else if Self.videoExtensions.contains(lower) {
            self = .video
        } else if Self.audioExtensions.contains(lower) {
            self = .audio
        } else {
            self = .other
        }
    }
}

struct ClipboardEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let items: [PasteboardItemData]
    let isConcealed: Bool

    var totalBytes: Int {
        items.reduce(0) { total, item in
            total + item.dataByType.values.reduce(0) { $0 + $1.count }
        }
    }

    var primaryType: NSPasteboard.PasteboardType? {
        items.first?.types.first
    }

    /// Best-effort plain text extraction from the first item.
    var plainText: String? {
        guard let item = items.first else { return nil }
        let textTypes: [NSPasteboard.PasteboardType] = [.string, .rtf, .html]
        for type in textTypes {
            if let data = item.dataByType[type] {
                if type == .string {
                    return String(data: data, encoding: .utf8)
                }
                if let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
                    return attributed.string
                }
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }

    /// Whether the first item contains image data.
    var hasImage: Bool {
        guard let item = items.first else { return false }
        let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
        return item.types.contains(where: imageTypes.contains)
    }

    /// Extract an NSImage from the first item, if possible.
    var image: NSImage? {
        guard let item = items.first else { return nil }
        for type in [NSPasteboard.PasteboardType.tiff, .png] {
            if let data = item.dataByType[type] {
                return NSImage(data: data)
            }
        }
        return nil
    }

    /// Whether the first item contains file URL references.
    var hasFileURLs: Bool {
        guard let item = items.first else { return false }
        return item.types.contains(NSPasteboard.PasteboardType("public.file-url"))
    }

    var fileURLs: [URL] {
        items.compactMap { item in
            let fileURLType = NSPasteboard.PasteboardType("public.file-url")
            guard let data = item.dataByType[fileURLType],
                  let urlString = String(data: data, encoding: .utf8),
                  let url = URL(string: urlString) else { return nil }
            return url
        }
    }

    var mediaFileURL: URL? {
        fileURLs.first
    }

    var mediaFileType: MediaFileType {
        guard let url = mediaFileURL else { return .other }
        return MediaFileType(fileExtension: url.pathExtension)
    }

    /// Strict byte-level content equality: same items count, each item content-equal.
    func contentEquals(_ other: ClipboardEntry) -> Bool {
        guard items.count == other.items.count else { return false }
        for (a, b) in zip(items, other.items) {
            guard a.contentEquals(b) else { return false }
        }
        return true
    }

    /// Returns true if `other` is a superset of `self`: same item count,
    /// and each item in self is a subset of the corresponding item in other
    /// (same types with identical data, plus other has additional types).
    func isSubset(of other: ClipboardEntry) -> Bool {
        guard items.count == other.items.count else { return false }
        var anyItemIsSubset = false
        for (a, b) in zip(items, other.items) {
            if a.isSubset(of: b) {
                anyItemIsSubset = true
            } else if !a.contentEquals(b) {
                return false
            }
        }
        return anyItemIsSubset
    }
}
