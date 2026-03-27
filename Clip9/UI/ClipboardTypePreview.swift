import AppKit

/// SF Symbol + user-facing label when plain/rich/file/image previews do not apply.
enum ClipboardTypePreview {

    private static let `default` = (symbol: "doc.on.clipboard", label: "Clipboard data")

    static func fallback(for entry: ClipboardEntry) -> (symbol: String, label: String) {
        guard let item = entry.items.first else { return `default` }

        var distinctFamilies = Set<String>()
        for uti in item.types.map(\.rawValue) {
            distinctFamilies.insert(familyKey(for: uti))
        }
        distinctFamilies.remove("other")

        for uti in item.types.map(\.rawValue) {
            if let pair = matchExact(uti) {
                return pair
            }
        }
        for uti in item.types.map(\.rawValue) {
            if let pair = matchPattern(uti) {
                return pair
            }
        }

        if distinctFamilies.count >= 2 {
            return ("square.stack", "Mixed content")
        }
        return `default`
    }

    private static func familyKey(for uti: String) -> String {
        if uti.contains("pdf") { return "pdf" }
        if uti.contains("image") || uti.contains("jpeg") || uti.contains("png") || uti.contains("gif") || uti.contains("tiff") || uti.contains("heic") || uti.contains("webp") || uti.contains("svg") || uti.contains("bmp") {
            return "image"
        }
        if uti.contains("video") || uti.contains("mpeg") || uti.contains("quicktime") || uti == "public.avi" { return "video" }
        if uti.contains("audio") || uti.contains("mp3") || uti.contains("wav") || uti.contains("aac") { return "audio" }
        if uti.contains("html") { return "html" }
        if uti.contains("rtf") || uti == "com.apple.flat-rtfd" { return "rtf" }
        if uti.contains("url") && uti != "public.file-url" { return "url" }
        if uti.contains("vcard") { return "vcard" }
        if uti.contains("calendar") || uti.hasSuffix(".ics") || uti.contains("ical") { return "calendar" }
        if uti.contains("comma-separated") || uti.contains("tab-separated") || uti.contains("csv") { return "tabular" }
        if uti.contains("zip") || uti.contains("archive") { return "archive" }
        if uti.contains("font") { return "font" }
        if uti.contains("color") { return "color" }
        return "other"
    }

    private static func matchExact(_ uti: String) -> (String, String)? {
        switch uti {
        case "com.adobe.pdf", "com.adobe.indesign-importPDF":
            return ("doc.fill", "PDF document")
        case "public.jpeg", "public.jpg", "public.jfif":
            return ("photo", "Image")
        case "public.heic", "public.heif":
            return ("photo", "Image")
        case "org.webmproject.webp", "public.webp":
            return ("photo", "Image")
        case "public.bmp", "com.microsoft.bmp":
            return ("photo", "Image")
        case "com.compuserve.gif":
            return ("photo.on.rectangle.angled", "GIF image")
        case "public.svg-image", "public.svg":
            return ("square.grid.3x3", "Vector graphic")
        case "public.html", "Apple HTML pasteboard type":
            return ("globe", "Web content")
        case "public.rtf", "NeXT Rich Text Format v1.0 pasteboard type":
            return ("doc.richtext", "Formatted text")
        case "public.url", "NSURLPboardType", "CorePasteboardFlavorType 0x75726C20":
            return ("link", "Web link")
        case "public.comma-separated-values-text":
            return ("tablecells", "Table data")
        case "public.tab-separated-values-text":
            return ("tablecells", "Table data")
        case "public.zip-archive", "com.pkware.zip-archive", "public.archive":
            return ("doc.zipper", "Archive")
        case "public.vcard":
            return ("person.crop.rectangle", "Contact info")
        case "com.apple.ical.ics":
            return ("calendar", "Calendar event")
        case "org.openxmlformats.wordprocessingml.document", "com.microsoft.word.doc":
            return ("doc.text", "Document")
        case "org.openxmlformats.spreadsheetml.sheet", "com.microsoft.excel.xls":
            return ("tablecells", "Spreadsheet")
        case "org.openxmlformats.presentationml.presentation", "com.microsoft.powerpoint.ppt":
            return ("play.rectangle", "Slides")
        case "public.truetype-ttf-font", "public.opentype-font", "com.apple.truetype-ttf-font":
            return ("textformat", "Font")
        case "com.apple.cocoa.pasteboard.color", "com.apple.pasteboard.color":
            return ("paintpalette", "Color")
        default:
            return nil
        }
    }

    private static func matchPattern(_ uti: String) -> (String, String)? {
        if uti.hasPrefix("com.apple.") && uti != "com.apple.cocoa.pasteboard.color" {
            if uti.contains("security") || uti.contains("pasteboard") { return nil }
        }
        if uti.contains("pdf") {
            return ("doc.fill", "PDF document")
        }
        if uti.contains("mpeg-4") || uti.contains("quicktime-movie") || uti == "public.avi" {
            return ("film", "Video")
        }
        if uti.hasPrefix("public.audio") || uti.contains(".mp3") || uti.contains(".wav") {
            return ("waveform", "Audio")
        }
        if uti.contains("wordprocessingml") {
            return ("doc.text", "Document")
        }
        if uti.contains("spreadsheetml") {
            return ("tablecells", "Spreadsheet")
        }
        if uti.contains("presentationml") {
            return ("play.rectangle", "Slides")
        }
        if uti.hasPrefix("com.") && !uti.hasPrefix("com.apple.") && !uti.hasPrefix("com.adobe.") {
            return ("square.on.square", "App content")
        }
        return nil
    }
}
