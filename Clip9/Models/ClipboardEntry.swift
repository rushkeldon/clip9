import AppKit
import Foundation
import UniformTypeIdentifiers

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

/// Pre-computed display-cascade decisions persisted as display_cache.json.
/// Avoids expensive RTF/HTML parsing on every card render.
struct DisplayCache: Codable, Sendable {
    let foregroundIsLight: Bool?
    let isOnlyObjectReplacements: Bool
    let attachmentImageData: Data?
    let isWhitespaceOnly: Bool
    let hasSignificantPreview: Bool
    let hasRenderablePlainText: Bool
    let plainTextAppearsToBeHTMLMarkup: Bool
    let version: Int

    static let currentVersion = 2

    /// Compute all display decisions from a ClipboardEntry in a single pass.
    static func compute(from entry: ClipboardEntry) -> DisplayCache {
        let rt = entry.richText

        var foregroundIsLight: Bool? = nil
        var isOnlyObj = false
        var attachData: Data? = nil
        var wsOnly = false
        var hasSigPreview = false

        if let attr = rt {
            let s = attr.string

            let onlyObj = !s.isEmpty && s.contains("\u{FFFC}") &&
                          s.allSatisfy { $0 == "\u{FFFC}" || $0.isWhitespace }
            isOnlyObj = onlyObj

            if onlyObj {
                var data: Data?
                attr.enumerateAttribute(.attachment,
                    in: NSRange(location: 0, length: attr.length)
                ) { value, _, stop in
                    guard let attachment = value as? NSTextAttachment else { return }
                    if let d = attachment.contents ?? attachment.fileWrapper?.regularFileContents {
                        data = d; stop.pointee = true
                    } else if let tiff = attachment.image?.tiffRepresentation {
                        data = tiff; stop.pointee = true
                    }
                }
                attachData = data
            }

            if attr.length > 0 {
                let sampleLen = min(attr.length, 500)
                let sampleRange = NSRange(location: 0, length: sampleLen)
                var totalLuminance: CGFloat = 0
                var sampledChars = 0
                var coloredIndices = IndexSet()

                attr.enumerateAttribute(.foregroundColor, in: sampleRange) { value, range, _ in
                    guard let color = value as? NSColor,
                          let srgb = color.usingColorSpace(.sRGB) else { return }
                    let lum = 0.2126 * srgb.redComponent + 0.7152 * srgb.greenComponent + 0.0722 * srgb.blueComponent
                    totalLuminance += lum * CGFloat(range.length)
                    sampledChars += range.length
                    coloredIndices.insert(integersIn: range.location..<(range.location + range.length))
                }

                let linkBlueLuminance: CGFloat = 0.07
                attr.enumerateAttribute(.link, in: sampleRange) { value, range, _ in
                    guard value != nil else { return }
                    for i in range.location..<(range.location + range.length) {
                        if !coloredIndices.contains(i) {
                            totalLuminance += linkBlueLuminance
                            sampledChars += 1
                        }
                    }
                }

                foregroundIsLight = sampledChars > 0
                    ? (totalLuminance / CGFloat(sampledChars)) > 0.6
                    : nil
            }

            let isWS = !s.isEmpty && s.allSatisfy(\.isWhitespace)
            wsOnly = isWS
            hasSigPreview = !s.isEmpty && !isWS
        }

        let hasRenderable: Bool
        let looksLikeHTML: Bool
        if let text = entry.plainText, !text.isEmpty {
            hasRenderable = true
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20).lowercased()
            looksLikeHTML = trimmed.hasPrefix("<meta ") ||
                            trimmed.hasPrefix("<!doctype") ||
                            trimmed.hasPrefix("<html")
        } else {
            hasRenderable = false
            looksLikeHTML = false
        }

        return DisplayCache(
            foregroundIsLight: foregroundIsLight,
            isOnlyObjectReplacements: isOnlyObj,
            attachmentImageData: attachData,
            isWhitespaceOnly: wsOnly,
            hasSignificantPreview: hasSigPreview,
            hasRenderablePlainText: hasRenderable,
            plainTextAppearsToBeHTMLMarkup: looksLikeHTML,
            version: currentVersion
        )
    }
}

struct ClipboardEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let items: [PasteboardItemData]
    let isConcealed: Bool
    let displayCache: DisplayCache?

    var totalBytes: Int {
        items.reduce(0) { total, item in
            total + item.dataByType.values.reduce(0) { $0 + $1.count }
        }
    }

    var primaryType: NSPasteboard.PasteboardType? {
        items.first?.types.first
    }

    /// Rich text (RTF or HTML) as an NSAttributedString, if available.
    var richText: NSAttributedString? {
        guard let item = items.first else { return nil }
        if let rtfData = item.dataByType[.rtf],
           let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil),
           attributed.length > 0 {
            return attributed
        }
        if let htmlData = item.dataByType[.html],
           let attributed = NSAttributedString(html: htmlData, documentAttributes: nil),
           attributed.length > 0 {
            return attributed
        }
        return nil
    }

    /// Best-effort plain text extraction from the first item.
    var plainText: String? {
        guard let item = items.first else { return nil }
        if let data = item.dataByType[.string] {
            return String(data: data, encoding: .utf8)
        }
        if let data = item.dataByType[.rtf],
           let attributed = NSAttributedString(rtf: data, documentAttributes: nil) {
            return attributed.string
        }
        if let data = item.dataByType[.html],
           let attributed = NSAttributedString(html: data, documentAttributes: nil) {
            let text = attributed.string
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return nil
    }

    /// Whether the first item contains image data (any UTI conforming to public.image).
    var hasImage: Bool {
        guard let item = items.first else { return false }
        return item.types.contains { UTType($0.rawValue)?.conforms(to: .image) == true }
    }

    /// Raw image bytes from the first item, if any type conforms to public.image.
    var imageData: Data? {
        guard let item = items.first else { return nil }
        for type in item.types {
            guard UTType(type.rawValue)?.conforms(to: .image) == true else { continue }
            if let data = item.dataByType[type] { return data }
        }
        return nil
    }

    /// Extract an NSImage from the first item, if possible.
    var image: NSImage? {
        guard let data = imageData else { return nil }
        return NSImage(data: data)
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

extension ClipboardEntry {

    private static func isWhitespaceOnlyString(_ string: String) -> Bool {
        !string.isEmpty && string.allSatisfy(\.isWhitespace)
    }

    /// Non-empty rich text that should use the attributed preview (not whitespace-only).
    var hasSignificantRichTextPreview: Bool {
        guard let r = richText else { return false }
        let s = r.string
        guard !s.isEmpty else { return false }
        return !Self.isWhitespaceOnlyString(s)
    }

    /// Rich text that is only whitespace — use invisible-style preview on the string.
    var richTextIsWhitespaceOnlyForPreview: Bool {
        guard let r = richText else { return false }
        return Self.isWhitespaceOnlyString(r.string)
    }

    /// Rich text whose visible characters are only object replacement chars (\u{FFFC}) and whitespace,
    /// indicating the content is embedded attachments (e.g. stickers) with no readable text.
    var richTextIsOnlyObjectReplacements: Bool {
        guard let r = richText else { return false }
        let s = r.string
        guard !s.isEmpty else { return false }
        return s.contains("\u{FFFC}") &&
               s.allSatisfy { $0 == "\u{FFFC}" || $0.isWhitespace }
    }

    /// Image data extracted from the first NSTextAttachment in the rich text, if any.
    var richTextAttachmentImageData: Data? {
        guard let attr = richText else { return nil }
        var result: Data?
        attr.enumerateAttribute(.attachment,
            in: NSRange(location: 0, length: attr.length)
        ) { value, _, stop in
            guard let attachment = value as? NSTextAttachment else { return }
            if let data = attachment.contents ?? attachment.fileWrapper?.regularFileContents {
                result = data; stop.pointee = true
            } else if let tiff = attachment.image?.tiffRepresentation {
                result = tiff; stop.pointee = true
            }
        }
        return result
    }

    var hasRenderablePlainText: Bool {
        guard let t = plainText else { return false }
        return !t.isEmpty
    }

    /// True when the `.string` pasteboard type itself contains raw HTML markup
    /// (some apps duplicate HTML onto the string type). These should not be shown as text.
    var plainTextAppearsToBeHTMLMarkup: Bool {
        guard let text = plainText else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20).lowercased()
        return trimmed.hasPrefix("<meta ") ||
               trimmed.hasPrefix("<!doctype") ||
               trimmed.hasPrefix("<html")
    }

    /// Log-friendly line when the user highlights an entry (mouse or keyboard).
    var selectionDebugSummary: String {
        let firstItemTypes = items.first?.types.map(\.rawValue).joined(separator: ", ") ?? ""
        let plainSnippet: String
        if let t = plainText {
            let oneLine = t.replacingOccurrences(of: "\n", with: "\\n")
            plainSnippet = oneLine.count > 200 ? String(oneLine.prefix(200)) + "…" : oneLine
        } else {
            plainSnippet = "nil"
        }
        return "items=\(items.count) totalBytes=\(totalBytes) firstItemTypes=[\(firstItemTypes)] plainText=\(plainSnippet)"
    }
}
