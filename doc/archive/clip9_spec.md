# Clip9 — Product Specification

## Overview

Clip9 is a macOS clipboard history application. Its defining feature is **complete clipboard fidelity** — every item copied to the system clipboard is captured in full, across all data representations, and restored exactly as it was when the user selects it from the history.

<br />

The app name is one word: **Clip9** (capital C, the 9 tucked in).

***

## Core Principle

When something is placed on the macOS system clipboard, Clip9 saves a complete replica of that clipboard item — every UTI type, every data representation. When the user later selects that item from the Clip9 history, it is placed back on the clipboard in exactly the form it was originally captured. The consuming application sees no difference between the original copy and the Clip9 restore.

***

## Technical Architecture

### Clipboard Monitoring

Clip9 monitors `NSPasteboard.general` by polling the `changeCount` property on a 250ms timer. There is no delegate or notification mechanism for pasteboard changes in macOS — polling is the only option and is standard practice across all shipping clipboard managers. Comparing a single integer at 250ms intervals has negligible CPU cost.

### Capture

On each `changeCount` change, Clip9 immediately iterates through all `NSPasteboardItem` objects on the pasteboard. For each item, it reads the `types` array and calls `data(forType:)` on every type to materialize all data — including lazy/promised data — as concrete `Data` blobs. This eager resolution ensures all data is captured before the source application quits or the pasteboard changes again.

A single clipboard operation can contain multiple `NSPasteboardItem` objects (e.g., selecting multiple files in Finder). Clip9 captures the full array of items, not just the first.

### Restore

When the user selects a history item, Clip9 creates new `NSPasteboardItem` objects, calls `setData(_:forType:)` for each stored type/blob pair, then calls `clearContents()` and `writeObjects()` on the pasteboard. The item is placed back on the clipboard — the user then pastes manually via Cmd+V or right-click. Clip9 does not auto-paste into the frontmost app.

All data is restored as concrete blobs. There is no need to re-wrap data as lazy providers since the serialization cost has already been paid at capture time.

### Concealed / Sensitive Content

macOS 14+ allows apps to mark clipboard content as concealed (e.g., password managers, Safari autofill). Clip9 does **not** persist concealed or sensitive clipboard items and **does not** add a history row for those events. The content never appears in the list; clipboard fidelity applies only to non-concealed captures.

### Empty Text–Only Clipboard

If the pasteboard change contains **no payload bytes** (for example, only an empty plain-text representation and no other data), Clip9 does not add a history entry.

### Previews: Whitespace and Non-Text Types

When plain text is only whitespace or includes invisible Unicode characters, the card preview uses visible stand-ins (similar to “show invisibles” in editors) so the entry is not a blank bubble; restore still uses the original data.

When there is no plain or rich text preview but other types are present (e.g. PDF, URL, proprietary paste types), the card shows a template SF Symbol and a short plain-English label describing the kind of content—not raw pasteboard type strings.

### Secure Input Mode

When a password field activates secure text input, clipboard monitoring is blocked at the OS level. This is an accepted limitation — there is nothing to capture and no workaround.

### File References

When files are copied in Finder, the clipboard contains `file://` URLs. Clip9 stores a **copy of the actual file data** in its own application storage rather than just the URL reference. This ensures the clipboard item remains valid even if the original file is moved or deleted.

Note: In the sandboxed App Store version, reading arbitrary file paths from clipboard URLs may be restricted by the sandbox.

***

## Storage

### History Limit

Clip9 maintains a history of up to **100 items** (configurable in settings). The default is 100.

### Storage Cap

A soft storage cap of approximately **1GB** across all entries (configurable in settings). Most entries will be small (text snippets), so this cap is rarely hit with only 100 slots.

### Eviction

Oldest entries are evicted first as new items are captured. If the storage cap is reached before 100 entries, the oldest entries are evicted early to stay within the cap.

### Format

Storage uses simple file-based persistence (not SQLite). Each history entry stores the array of pasteboard items with their type/data pairs as binary blobs. History persists across app restarts and system reboots.

***

## User Interface

### Menu Bar App

Clip9 runs as a menu bar application with a persistent icon in the macOS menu bar.

### Left Click — Clipboard History

Left-clicking the menu bar icon displays a vertical menu of clipboard history items, newest at the top, oldest at the bottom.

* The list shows a fixed number of visible items at all times.

* If the history contains more items than can be displayed, a scroll indicator appears at the bottom.

* Hovering the mouse on the bottom item triggers scrolling — the list moves vertically beneath the cursor like a conveyor belt while the visible window size remains constant.

* Clicking an item places it back on the clipboard. The user then pastes manually wherever they choose.

### Right Click — Application Menu

Right-clicking the menu bar icon displays a conventional short menu with application controls:

* **Settings** — opens the settings window

* **About** — version number and app info

* **Clear History** — wipes all stored clipboard entries

* **Support** — opens the support page in the browser

* **Quit**

### Magnification Effect

The clipboard history menu features a **dock-style magnification wave**. This is the same interaction model as the macOS dock magnification:

* The item directly under the mouse cursor scales to full magnification.

* Adjacent items scale proportionally less based on distance from the cursor, creating a smooth gaussian falloff — a wave or lens effect.

* The magnification applies uniformly to all item types (text and images alike).

* The entire item scales, not just its content.

**Magnification origin:** Right edge, vertically centered on each item. Items grow **leftward** into the screen. The right edge of the menu remains fixed. This mirrors how the dock anchors magnification to the bottom edge.

**Magnification is always active** whenever the mouse is over any history item, whether the list is stationary or scrolling. During scrolling, the wave stays in place relative to the visible window — the item under the cursor always receives full magnification.

**Purpose:** Thumbnails for image entries can be kept small in the default view, then become legible on hover. Visual identification of clipboard entries is critical when the selection criterion is visual.

Magnification can be toggled off in settings (on by default).

### Base Zoom (Accessibility)

**Cmd+** and **Cmd-** adjust the base size of all items in the history menu. The magnification wave still applies on top of the adjusted base size. Increasing the base zoom means fewer items are visible vertically, but everything is more legible. This is designed for users who need larger text and images.

The current zoom level is also adjustable via a slider in settings.

### First Run Experience

On first launch, a small speech bubble points at the Clip9 icon in the menu bar with a brief message:

> "Clip9 lives here. Cmd+ and Cmd- to adjust size."

No other onboarding is required. The app is discoverable by nature — click the icon, see your history.

***

## Settings Window

The settings window contains the following controls:

| Setting         | Type     | Default      | Description                                                                     |
| --------------- | -------- | ------------ | ------------------------------------------------------------------------------- |
| Launch at Login | Toggle   | On           | Start Clip9 automatically on login. Requests permission if not already granted. |
| Magnification   | Toggle   | On           | Enable/disable the dock-style magnification wave on the history menu.           |
| Base Zoom Level | Slider   | Default (1x) | Adjusts the base size of history items. Also controllable via Cmd+/Cmd-.        |
| History Size    | Number   | 100          | Maximum number of clipboard entries to retain.                                  |
| Storage Cap     | Number   | \~1 GB       | Maximum disk usage for stored clipboard data.                                   |
| Menu Bar Icon   | Selector | Default      | Choose between monochrome, color, or custom icon appearance.                    |
| Scroll Speed    | Slider   | Default      | Controls how fast the history list scrolls when hovering at the bottom.         |

***

## Distribution

### Clip9 (App Store)

* Sandboxed per App Store requirements.

* Full clipboard capture and restore for all pasteboard data types (text, rich text, HTML, images, etc.).

* Limitation: May not be able to read file data from `file://` URLs captured from Finder copies due to sandbox file access restrictions. Finder file copies are stored as URL references only.

***

## Explicit Non-Features

The following have been explicitly scoped out:

* **No search or filtering** of history items

* **No keyboard shortcuts** for selecting/pasting history items

* **No auto-paste** — items go on the clipboard, the user pastes manually

* **No pinned or favorite items**

* **No iCloud sync**

* **No SQLite or Core Data** — simple file-based storage

***


