# Clip9

<p align="center">
  <img src="img/icon_clip9.png" alt="Clip9" />
</p>

**Never lose a copy again.**
A macOS clipboard history manager with complete fidelity — every format, every byte, restored exactly as it was.

---

## Why Clip9?

Your clipboard holds one thing at a time. Every time you copy, the previous item vanishes. Clip9 changes that — it quietly watches from the menu bar, captures everything you copy, and gives it back on demand. Text, images, rich formatting, videos, files — nothing is lost, nothing is altered.

## Complete Clipboard Fidelity

Most clipboard managers save only plain text. Clip9 captures **every** data representation on the macOS pasteboard and restores it byte-for-byte. The receiving app sees no difference from the original copy.

- **All content types** — plain text, rich text (RTF), HTML, images, animated GIFs, videos, audio, PDFs, Office documents, URLs, contacts, calendar events, archives, and arbitrary binary data
- **Multi-item support** — copy five files in Finder and all five are captured as a single entry
- **Image file embedding** — file-URL clipboard items pointing at images are fetched and stored directly, so previews and restores work even after the original file moves

## Rich, Instant Previews

Every card in the history panel shows a live preview tailored to its content — no generic icons, no guessing.

- **Rich text preservation** — formatting, syntax highlighting, font styles, and colors copied from any app render directly in the card
- **Adaptive card backgrounds** — Clip9 detects foreground brightness and adjusts the card background so dark-mode and light-mode content both look right
- **Proportional font scaling** — oversized fonts are scaled down proportionally with a sensible ceiling, preserving typographic hierarchy without overwhelming the card
- **Animated GIFs and APNGs** play inline with full animation
- **Videos** auto-play silently on loop, and intelligently pause when the panel is hidden to save resources
- **Audio and files** display with descriptive icons and filenames ("and 3 more" for multi-file copies)
- **Invisible characters** — whitespace-only content renders with visible symbols: `·` for spaces, `¶` for newlines, `→` for tabs, and labeled tokens for zero-width Unicode characters
- **Type-aware fallback** — when no text or image preview applies, cards show an SF Symbol and a plain-English description (e.g. "PDF document", "Contact info", "Spreadsheet")
- **Context menu** — right-click any card for quick Copy and Delete actions

## Instant Performance

Clip9 is designed to feel instantaneous. Hover a card and the preview is already there — no loading, no stutter.

- **Persistent display cache** — expensive rich-text parsing is done once at capture time and the results are saved to disk, surviving restarts
- **In-memory cache** — a secondary cache keeps rendered card state in memory for zero-cost lookups during scrolling and hover
- **Startup pre-warming** — when the app launches, all cached entries are loaded into memory in the background before you ever open the panel

## Smart Clipboard Handling

Clip9 keeps your history clean and duplicate-free without any effort on your part.

- **Full-history deduplication** — if you copy the same content again, the existing entry is promoted to the top instead of creating a duplicate, no matter how far back in history it sits
- **Superset coalescing** — if a new copy contains the same data plus additional formats, the existing entry is upgraded in place
- **Self-change filtering** — clipboard changes made by Clip9 itself (e.g. restoring an entry) are ignored
- **Empty capture filtering** — clipboard changes with no payload bytes are silently discarded

## Privacy First

- **Password manager safe** — clipboard items marked as concealed (the standard used by 1Password, Keychain, and others) are never recorded. Nothing is saved, nothing appears in history.
- **Sandboxed** — distributed through the Mac App Store with full App Sandbox protections

## Menu Bar App

Clip9 lives entirely in the macOS menu bar — no Dock icon, no window clutter.

- **Left-click** the icon to open the clipboard history panel
- **Right-click** for the application menu: Settings, About, Clear History, Support, and Quit
- The history panel is a floating, translucent frosted-glass overlay anchored below the menu bar icon
- The panel **dynamically sizes** to fit its content — no empty gaps, no wasted space — and resets scroll to the top each time it opens

## Navigation

Mouse and keyboard work seamlessly together. The keyboard picks up from the last mouse position, and moving the mouse takes over from the keyboard.

- **Hover** to highlight any card instantly
- **Scroll wheel** with native macOS physics
- **Hover-scroll zones** at the top and bottom edges of the panel for smooth, constant-speed scrolling through long histories
- **Up/Down arrows** to move the selection
- **Return or Space** to restore the selected entry
- **Escape** or **click outside** to dismiss
- A chevron indicator appears when more content is available below

## Zoom and Accessibility

- **Cmd+** and **Cmd-** scale everything from 0.5x to 3.0x — cards, text, spacing, and the panel itself
- **Cmd+0** resets to default
- Also adjustable via a slider in Settings
- The panel stays anchored to the menu bar icon and grows leftward as it scales up

## Persistent Storage

Your clipboard history survives app restarts, system reboots, and updates.

- **File-based storage** — simple, inspectable directory structure with no database dependencies
- **Atomic writes** — entries are written to a temporary directory and moved into place, so a crash can never corrupt your history
- **Self-healing index** — if the index file is ever lost or corrupted, it is automatically reconstructed from entry metadata
- **Configurable limits** — up to 500 entries and 10 GB of storage; oldest entries are evicted first when either limit is reached
- **Defaults** — 100 entries, 1 GB cap

## Settings

- Launch at Login
- Card size (zoom slider, 0.5x–3.0x)
- Maximum history items (10–500)
- Storage cap (0.1–10 GB)
- Show Logs — opens the diagnostics log directory in Finder

## Diagnostics

- **Structured logging** with subsystem tags, ISO 8601 timestamps, and severity levels
- **Daily log rotation** with automatic 7-day pruning
- **Non-blocking writes** on a dedicated background queue

## First Run

A one-time welcome popover appears near the menu bar icon — "Clip9 lives here." — with a tip about Cmd+/Cmd- for size adjustment. It auto-dismisses after a few seconds.

---

## Technical Details

- Built with **Swift**, **SwiftUI**, and **AppKit**
- Clipboard monitoring via `NSPasteboard.general` polling at 250ms intervals
- Floating `NSPanel` with `NSHostingView` bridge to SwiftUI
- Direct `NSScrollView` manipulation for deterministic hover-scroll
- `NSTrackingArea`-based mouse tracking for reliable hover detection in floating panels
- Three-tier display cache: persistent on-disk JSON, in-memory `NSCache`, and lazy `NSAttributedString` resolution
- Atomic file I/O on a dedicated serial `DispatchQueue`

---

<p align="center">
  Available on the <strong>Mac App Store</strong>
</p>
