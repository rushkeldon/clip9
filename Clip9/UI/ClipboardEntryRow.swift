import SwiftUI

private let log = LogService.shared

struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let zoom: CGFloat
    var isSelected: Bool = false

    static let baseWidth: CGFloat = 225
    static let baseHeight: CGFloat = floor(225 / (16.0 / 9.0))  // 16:9 ≈ 127

    var cardWidth: CGFloat { Self.baseWidth * zoom }
    var cardHeight: CGFloat { Self.baseHeight * zoom }

    private var centerContent: Bool {
        entry.hasImage || (entry.hasFileURLs && entry.mediaFileType != .other)
    }

    private var fixedHeight: Bool { centerContent }

    private var cardFillColor: Color {
        if let bg = entry.richTextBackgroundColor {
            let base = Color(nsColor: bg)
            return isSelected ? base.opacity(0.6) : base.opacity(0.5)
        }
        return isSelected ? Color.primary.opacity(0.15) : Color.primary.opacity(0.05)
    }

    var body: some View {
        entryPreview
            .frame(maxWidth: .infinity, maxHeight: fixedHeight ? .infinity : nil,
                   alignment: fixedHeight ? .center : .topLeading)
            .padding(9 * zoom)
            .frame(width: cardWidth, height: fixedHeight ? cardHeight : nil)
            .background(
                RoundedRectangle(cornerRadius: 10 * zoom)
                    .fill(cardFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10 * zoom)
                    .stroke(Color.white, lineWidth: isSelected ? 3 * zoom : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10 * zoom))
    }

    @ViewBuilder
    private var entryPreview: some View {
        if entry.isConcealed {
            concealedPreview
        } else if entry.hasImage {
            imagePreview
        } else if entry.hasFileURLs {
            mediaFilePreview
        } else if entry.richTextIsWhitespaceOnlyForPreview, let rich = entry.richText {
            invisiblesTextPreview(rich.string)
        } else if entry.hasSignificantRichTextPreview, let rich = entry.richText {
            richTextPreview(rich)
        } else if entry.hasRenderablePlainText, let text = entry.plainText {
            if ClipboardInvisibles.plainTextNeedsInvisiblesPreview(text) {
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
        let _ = log.debug("UI", "Rendering file preview: \(entry.mediaFileURL?.lastPathComponent ?? "?") → \(entry.mediaFileType)", emoji: "📎")
        switch entry.mediaFileType {
        case .image:
            if let url = entry.mediaFileURL {
                AnimatedImageView(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: 4 * zoom))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                genericFilePreview
            }
        case .video:
            if let url = entry.mediaFileURL {
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
        truncated.enumerateAttribute(.font, in: NSRange(location: 0, length: truncated.length)) { value, range, _ in
            if let font = value as? NSFont {
                let scaled = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * zoom)
                if let scaled { truncated.addAttribute(.font, value: scaled, range: range) }
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
        if let nsImage = entry.image {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
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
