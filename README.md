# Clip9

A macOS clipboard history manager with complete clipboard fidelity. Every item you copy is captured in full — every data representation, every format — and restored exactly as it was.

## Features

### Complete Clipboard Fidelity

- Captures every data type on the macOS pasteboard: plain text, rich text, HTML, images, animated GIFs, videos, audio files, generic files, and arbitrary binary data
- Multi-item clipboard support — when you copy multiple files in Finder, all of them are captured
- Restores entries to the clipboard with byte-for-byte accuracy — the receiving app sees no difference from the original copy

### Rich Previews

- Text entries show a multi-line preview with truncation
- Images display as fitted thumbnails
- Animated GIFs play inline with full animation
- Videos auto-play silently on loop directly in the history card
- Audio files show an icon with filename
- File copies show the filename and count ("and 3 more")
- Sensitive/concealed items (e.g. from password managers) display a privacy placeholder without storing the content

### Menu Bar App

- Lives entirely in the macOS menu bar — no Dock icon, no window clutter
- Left-click opens the clipboard history panel
- Right-click opens the application menu (Settings, About, Clear History, Support, Show Logs, Quit)
- The panel is a floating, translucent frosted-glass overlay anchored below the menu bar icon

### Navigation

- **Mouse hover** highlights the card under the cursor in real time
- **Scroll wheel** scrolls the history naturally with native macOS physics
- **Hover-scroll zone** — a chevron appears at the bottom of the panel when more content is available; hovering over it smoothly scrolls the list at a constant speed
- **Keyboard navigation** — Up/Down arrow keys move the selection through the history
- **Enter or Space** restores the selected entry to the clipboard
- **Escape** dismisses the panel
- **Click outside** the panel to dismiss it
- Mouse hover and keyboard selection work together — keyboard picks up from the last mouse position, and moving the mouse takes over from the keyboard

### Zoom and Accessibility

- **Cmd+** and **Cmd-** increase and decrease the base card size (0.5x to 3.0x)
- **Cmd+0** resets to default size
- The panel resizes dynamically, anchored to the upper-right corner of the menu bar icon, growing leftward
- Also adjustable via a slider in Settings

### Smart Clipboard Handling

- **Duplicate detection** — if you copy the same thing twice, the existing entry is promoted to the top instead of creating a duplicate
- **Superset coalescing** — if a new copy contains the same data plus additional types, the existing entry is upgraded in place
- **Self-change filtering** — clipboard changes made by Clip9 itself (e.g. restoring an entry) are ignored
- **Concealed content privacy** — entries marked as concealed by password managers (via `org.nspasteboard.ConcealedType`) are detected and excluded from storage

### Persistent Storage

- History is saved to disk and survives app restarts and system reboots
- Configurable maximum history size (10–500 entries, default 100)
- Configurable storage cap (0.1–10 GB, default 1 GB)
- Oldest entries are evicted first; storage cap is enforced independently of entry count
- Simple file-based storage — no SQLite or Core Data

### Settings

- Launch at Login
- Card size (zoom slider)
- Menu bar icon style (Monochrome, Color, Custom)
- Maximum history items
- Storage cap
- Scroll speed
- Open log folder (for diagnostics)

### First Run Experience

- A one-time welcome popover appears near the menu bar icon: "Clip9 lives here." with a tip about Cmd+/Cmd- for size adjustment
- Auto-dismisses after 6 seconds

### Distribution

- **Clip9** (Mac App Store) — sandboxed, full clipboard fidelity for all pasteboard data types
- **Clip9 Pro** (direct distribution) — notarized, unsandboxed, adds complete file data backup for Finder file copies

## Technical Details

- Built with Swift, SwiftUI, and AppKit
- Clipboard monitoring via `NSPasteboard.general` polling at 250ms intervals
- Floating `NSPanel` with `NSHostingView` bridge to SwiftUI
- Direct `NSScrollView` manipulation for smooth hover-scroll
- `NSTrackingArea`-based mouse tracking for reliable hover detection in floating panels
