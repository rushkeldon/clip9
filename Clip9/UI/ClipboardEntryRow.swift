import AppKit
import SwiftUI

// MARK: - Display State Cache (internal singleton)

final class DisplayStateCache {
    static let shared = DisplayStateCache()

    private let cache = NSCache<NSUUID, CardDisplayStateBox>()

    private init() {
        cache.countLimit = 200
    }

    func get(_ id: UUID) -> CardDisplayState? {
        cache.object(forKey: id as NSUUID)?.state
    }

    func set(_ state: CardDisplayState, for id: UUID) {
        cache.setObject(CardDisplayStateBox(state), forKey: id as NSUUID)
    }

    func remove(id: UUID) {
        cache.removeObject(forKey: id as NSUUID)
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    /// Populate cache for an entry if not already present.
    func warmIfNeeded(entry: ClipboardEntry) {
        let key = entry.id as NSUUID
        guard cache.object(forKey: key) == nil else { return }
        let state = CardDisplayState(entry: entry)
        _ = state.richText
        cache.setObject(CardDisplayStateBox(state), forKey: key)
    }
}

private final class CardDisplayStateBox {
    let state: CardDisplayState
    init(_ state: CardDisplayState) { self.state = state }
}

// MARK: - Card Display State

/// Pre-computed rich-text display values with lazy richText resolution.
/// Uses DisplayCache (from disk) for the fast path, avoiding RTF/HTML parsing
/// until the display cascade actually needs the NSAttributedString.
final class CardDisplayState {
    let isOnlyObjectReplacements: Bool
    let attachmentImageData: Data?
    let foregroundIsLight: Bool?
    let isWhitespaceOnly: Bool
    let hasSignificantPreview: Bool
    let hasRenderablePlainText: Bool
    let plainTextAppearsToBeHTMLMarkup: Bool

    private var _richText: NSAttributedString??
    private let entry: ClipboardEntry

    var richText: NSAttributedString? {
        if let cached = _richText { return cached }
        let rt = entry.richText
        _richText = .some(rt)
        return rt
    }

    init(entry: ClipboardEntry) {
        self.entry = entry

        if let dc = entry.displayCache, dc.version == DisplayCache.currentVersion {
            self.isOnlyObjectReplacements = dc.isOnlyObjectReplacements
            self.attachmentImageData = dc.attachmentImageData
            self.foregroundIsLight = dc.foregroundIsLight
            self.isWhitespaceOnly = dc.isWhitespaceOnly
            self.hasSignificantPreview = dc.hasSignificantPreview
            self.hasRenderablePlainText = dc.hasRenderablePlainText
            self.plainTextAppearsToBeHTMLMarkup = dc.plainTextAppearsToBeHTMLMarkup
            return
        }

        let rt = entry.richText
        self._richText = .some(rt)

        guard let attr = rt else {
            self.isOnlyObjectReplacements = false
            self.attachmentImageData = nil
            self.foregroundIsLight = nil
            self.isWhitespaceOnly = false
            self.hasSignificantPreview = false
            self.hasRenderablePlainText = entry.hasRenderablePlainText
            self.plainTextAppearsToBeHTMLMarkup = entry.plainTextAppearsToBeHTMLMarkup
            return
        }

        let s = attr.string

        let onlyObj = !s.isEmpty && s.contains("\u{FFFC}") &&
                      s.allSatisfy { $0 == "\u{FFFC}" || $0.isWhitespace }
        self.isOnlyObjectReplacements = onlyObj

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
            self.attachmentImageData = data
        } else {
            self.attachmentImageData = nil
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

            self.foregroundIsLight = sampledChars > 0
                ? (totalLuminance / CGFloat(sampledChars)) > 0.6
                : nil
        } else {
            self.foregroundIsLight = nil
        }

        let wsOnly = !s.isEmpty && s.allSatisfy(\.isWhitespace)
        self.isWhitespaceOnly = wsOnly
        self.hasSignificantPreview = !s.isEmpty && !wsOnly
        self.hasRenderablePlainText = entry.hasRenderablePlainText
        self.plainTextAppearsToBeHTMLMarkup = entry.plainTextAppearsToBeHTMLMarkup
    }
}

struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let zoom: CGFloat
    var isSelected: Bool = false

    static let baseWidth: CGFloat = 225
    static let baseHeight: CGFloat = floor(225 / (16.0 / 9.0))  // 16:9 ≈ 127

    var cardWidth: CGFloat { Self.baseWidth * zoom }
    var cardHeight: CGFloat { Self.baseHeight * zoom }

    private static func fillColor(foregroundIsLight: Bool?, isSelected: Bool) -> Color {
        if let isLight = foregroundIsLight {
            let base: Color = isLight ? .black : .white
            return isSelected ? base.opacity(0.6) : base.opacity(0.5)
        }
        return isSelected ? Color.primary.opacity(0.15) : Color.primary.opacity(0.05)
    }

    var body: some View {
        let ds = DisplayStateCache.shared.get(entry.id) ?? {
            let state = CardDisplayState(entry: entry)
            DisplayStateCache.shared.set(state, for: entry.id)
            return state
        }()
        let whaleInfo = WhaleManager.shared.info(for: entry.id)
        let center = entry.hasImage ||
                     (entry.hasFileURLs && entry.mediaFileType != .other) ||
                     (ds.isOnlyObjectReplacements && ds.attachmentImageData != nil)
        let fill = Self.fillColor(foregroundIsLight: ds.foregroundIsLight, isSelected: isSelected)

        ZStack(alignment: .topTrailing) {
            Group {
                if let info = whaleInfo, info.isZombie {
                    zombiePreview
                } else {
                    entryPreview(ds: ds)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: (center && whaleInfo?.isZombie != true) ? .infinity : nil,
                   alignment: (center && whaleInfo?.isZombie != true) ? .center : .topLeading)
            .padding(9 * zoom)
            .frame(width: cardWidth, height: (center || whaleInfo?.isZombie == true) ? cardHeight : nil)
            .background(
                RoundedRectangle(cornerRadius: 10 * zoom)
                    .fill(fill)
            )

            if let info = whaleInfo, !info.isZombie, info.remainingDisplays > 0 {
                WhalePieChart(remainingDisplays: info.remainingDisplays, size: 20 * zoom)
                    .padding(6 * zoom)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10 * zoom)
                .stroke(Color.white, lineWidth: isSelected ? 3 * zoom : 0)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10 * zoom))
    }

    @ViewBuilder
    private func entryPreview(ds: CardDisplayState) -> some View {
        if entry.isConcealed {
            concealedPreview
        } else if entry.hasFileURLs {
            mediaFilePreview
        } else if entry.hasImage {
            imagePreview
        } else if ds.isOnlyObjectReplacements, let attachData = ds.attachmentImageData {
            AnimatedDataImageView(data: attachData)
                .clipShape(RoundedRectangle(cornerRadius: 4 * zoom))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if ds.isWhitespaceOnly, let rich = ds.richText {
            invisiblesTextPreview(rich.string)
        } else if ds.hasSignificantPreview, let rich = ds.richText {
            richTextPreview(rich)
        } else if ds.hasRenderablePlainText, let text = entry.plainText {
            if ds.plainTextAppearsToBeHTMLMarkup {
                typeAwareFallbackPreview
            } else if ClipboardInvisibles.plainTextNeedsInvisiblesPreview(text) {
                invisiblesTextPreview(text)
            } else {
                textPreview(text)
            }
        } else {
            typeAwareFallbackPreview
        }
    }

    @ViewBuilder
    private var mediaFilePreview: some View {
        switch entry.mediaFileType {
        case .image:
            if let data = entry.fileData {
                AnimatedDataImageView(data: data)
                    .clipShape(RoundedRectangle(cornerRadius: 4 * zoom))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let url = entry.mediaFileURL {
                AnimatedImageView(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: 4 * zoom))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                genericFilePreview
            }
        case .video:
            if let tempURL = entry.writeTempFile() {
                SilentVideoView(url: tempURL)
                    .clipShape(RoundedRectangle(cornerRadius: 4 * zoom))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let url = entry.mediaFileURL {
                SilentVideoView(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: 4 * zoom))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                genericFilePreview
            }
        case .audio:
            audioFilePreview
        case .other:
            genericFilePreview
        }
    }

    private var zombiePreview: some View {
        VStack(spacing: 6 * zoom) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 24 * zoom))
                .foregroundStyle(.red.opacity(0.8))
            Text("Item removed \u{2014} over storage limit")
                .font(.system(size: 13 * zoom, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text("Right-click to manage")
                .font(.system(size: 11 * zoom))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var concealedPreview: some View {
        HStack(spacing: 6 * zoom) {
            Image(systemName: "eye.slash")
                .font(.system(size: 16 * zoom))
                .foregroundStyle(.secondary)
            Text("Sensitive item — not saved")
                .font(.system(size: 16 * zoom))
                .foregroundStyle(.secondary)
                .italic()
        }
    }

    private func richTextPreview(_ nsAttr: NSAttributedString) -> some View {
        let truncated = NSMutableAttributedString(
            attributedString: nsAttr.attributedSubstring(from: NSRange(location: 0, length: min(nsAttr.length, 500)))
        )
        truncated.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: truncated.length))
        var maxFontSize: CGFloat = 0
        truncated.enumerateAttribute(.font, in: NSRange(location: 0, length: truncated.length)) { value, _, _ in
            if let font = value as? NSFont {
                maxFontSize = max(maxFontSize, font.pointSize)
            }
        }
        let fontScale: CGFloat = maxFontSize > 24 ? 24 / maxFontSize : 1
        let serifDefaults: Set<String> = ["Times New Roman", "Times", ".AppleSystemUIFontSerif"]
        truncated.enumerateAttribute(.font, in: NSRange(location: 0, length: truncated.length)) { value, range, _ in
            if let font = value as? NSFont {
                let pointSize = max(font.pointSize * fontScale, 12) * zoom
                if serifDefaults.contains(font.familyName ?? "") {
                    truncated.addAttribute(.font, value: NSFont.systemFont(ofSize: pointSize), range: range)
                } else {
                    let scaled = NSFont(descriptor: font.fontDescriptor, size: pointSize)
                    if let scaled { truncated.addAttribute(.font, value: scaled, range: range) }
                }
            } else {
                truncated.addAttribute(.font, value: NSFont.systemFont(ofSize: 14 * zoom), range: range)
            }
        }
        let swiftAttr = try? AttributedString(truncated, including: \.appKit)
        return Text(swiftAttr ?? AttributedString(truncated.string))
            .font(.system(size: 14 * zoom))
            .lineLimit(5)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textPreview(_ text: String) -> some View {
        Text(text.prefix(500))
            .font(.system(size: 14 * zoom))
            .lineLimit(5)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func invisiblesTextPreview(_ text: String) -> some View {
        let attr = ClipboardInvisibles.attributedPreview(
            for: String(text.prefix(500)),
            fontSize: 14 * zoom,
            normalColor: .primary,
            mutedColor: .secondary
        )
        return Text(attr)
            .lineLimit(5)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var typeAwareFallbackPreview: some View {
        let pair = ClipboardTypePreview.fallback(for: entry)
        return HStack(spacing: 8 * zoom) {
            Image(systemName: pair.symbol)
                .font(.system(size: 18 * zoom, weight: .medium))
                .foregroundStyle(.primary)
                .symbolRenderingMode(.hierarchical)
            Text(pair.label)
                .font(.system(size: 16 * zoom))
                .foregroundStyle(.primary)
                .italic()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let data = entry.imageData {
            AnimatedDataImageView(data: data)
                .clipShape(RoundedRectangle(cornerRadius: 4 * zoom))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            HStack(spacing: 6 * zoom) {
                Image(systemName: "photo")
                    .font(.system(size: 16 * zoom))
                    .foregroundStyle(.secondary)
                Text("Image")
                    .font(.system(size: 16 * zoom))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var audioFilePreview: some View {
        VStack(spacing: 6 * zoom) {
            Image(systemName: "music.note")
                .font(.system(size: 28 * zoom))
                .foregroundStyle(.secondary)
            Text(entry.mediaFileURL?.lastPathComponent ?? "Audio")
                .font(.system(size: 12 * zoom))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var genericFilePreview: some View {
        let urls = entry.fileURLs
        let name = urls.first?.lastPathComponent ?? "File"
        let count = urls.count
        return HStack(spacing: 8 * zoom) {
            Image(systemName: "doc.fill")
                .font(.system(size: 24 * zoom))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2 * zoom) {
                Text(name)
                    .font(.system(size: 14 * zoom))
                    .lineLimit(2)
                if count > 1 {
                    Text("and \(count - 1) more")
                        .font(.system(size: 12 * zoom))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

}
