import SwiftUI

/// Renders clipboard text previews with visible stand-ins for whitespace and invisible Unicode (preview only).
enum ClipboardInvisibles {

    /// True when the scalar should force “invisible mode” for the whole string (mixed with normal text).
    static func isInvisibleOrFormatOnly(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00AD: return true // soft hyphen
        case 0x034F: return true // combining grapheme joiner
        case 0x061C, 0x200E, 0x200F: return true // directional marks
        case 0x200B...0x200F: return true // ZWSP, ZWNJ, ZWJ, etc.
        case 0x2028, 0x2029: return true // line/paragraph sep (still show explicitly)
        case 0x202A...0x202E: return true // bidi embedding
        case 0x2060...0x2064: return true // word joiner, invisible plus, etc.
        case 0x2066...0x2069: return true // isolate marks
        case 0xFEFF: return true // BOM
        default:
            return scalar.properties.generalCategory == .format
        }
    }

    /// Entire string is only whitespace and newlines (no other characters).
    static func isWhitespaceOnly(_ string: String) -> Bool {
        !string.isEmpty && string.allSatisfy { $0.isWhitespace || $0.isNewline }
    }

    /// Use invisible-style preview for plain text when whitespace-only or when any invisible/format scalar appears.
    static func plainTextNeedsInvisiblesPreview(_ string: String) -> Bool {
        guard !string.isEmpty else { return false }
        if isWhitespaceOnly(string) { return true }
        return string.unicodeScalars.contains { isInvisibleOrFormatOnly($0) }
    }

    static func attributedPreview(
        for string: String,
        fontSize: CGFloat,
        normalColor: Color,
        mutedColor: Color
    ) -> AttributedString {
        var out = AttributedString()
        let limit = string.prefix(500)
        var i = limit.startIndex
        while i < limit.endIndex {
            let ch = limit[i]
            if ch == "\r" {
                let next = limit.index(after: i)
                if next < limit.endIndex, limit[next] == "\n" {
                    appendSymbol(&out, "↵", fontSize: fontSize, color: mutedColor)
                    i = limit.index(after: next)
                    continue
                }
                appendSymbol(&out, "↵", fontSize: fontSize, color: mutedColor)
                i = next
                continue
            }
            if ch == "\n" {
                appendSymbol(&out, "¶", fontSize: fontSize, color: mutedColor)
                i = limit.index(after: i)
                continue
            }
            if ch == "\t" {
                appendSymbol(&out, "→", fontSize: fontSize, color: mutedColor)
                i = limit.index(after: i)
                continue
            }
            if ch == " " {
                appendSymbol(&out, "·", fontSize: fontSize, color: mutedColor)
                i = limit.index(after: i)
                continue
            }
            if ch == "\u{00A0}" {
                appendTag(&out, "NBSP", fontSize: fontSize, color: mutedColor)
                i = limit.index(after: i)
                continue
            }

            let scalars = ch.unicodeScalars
            if scalars.count == 1, let s = scalars.first, isInvisibleOrFormatOnly(s) {
                appendTag(&out, label(for: s), fontSize: fontSize, color: mutedColor)
                i = limit.index(after: i)
                continue
            }

            var piece = AttributedString(String(ch))
            piece.font = .system(size: fontSize)
            piece.foregroundColor = normalColor
            out.append(piece)
            i = limit.index(after: i)
        }
        return out
    }

    private static func label(for scalar: Unicode.Scalar) -> String {
        switch scalar.value {
        case 0x200B: return "ZWSP"
        case 0x200C: return "ZWNJ"
        case 0x200D: return "ZWJ"
        case 0x200E: return "LRM"
        case 0x200F: return "RLM"
        case 0xFEFF: return "BOM"
        case 0x2060: return "WJ"
        case 0x00AD: return "SHY"
        default: return "·"
        }
    }

    private static func appendSymbol(_ out: inout AttributedString, _ s: String, fontSize: CGFloat, color: Color) {
        var a = AttributedString(s)
        a.font = .system(size: fontSize)
        a.foregroundColor = color
        out.append(a)
    }

    private static func appendTag(_ out: inout AttributedString, _ s: String, fontSize: CGFloat, color: Color) {
        var a = AttributedString("⟨\(s)⟩")
        a.font = .system(size: max(10, fontSize * 0.85))
        a.foregroundColor = color
        out.append(a)
    }
}
