---
name: Whale memory limit system
overview: 'Implement the elastic overflow "whale" system: a per-item storage trigger, a soft storage cap with FIFO eviction, a hard backstop based on disk size, and a 5-display countdown on whale cards with context menu actions to help users adapt their limits to their workflow.'
todos:
  - id: whale-manager
    content: Create WhaleManager class with state tracking, persistence to whales.json, countdown logic, and cascade calculation
    status: completed
  - id: settings-per-item
    content: Add per-item trigger text field to SettingsView (default 500 MB), change storage cap default to 1 GB, wire up new AppStorage key
    status: completed
  - id: remove-fetch-cap
    content: Remove maxFileFetchBytes cap from ClipboardMonitor.fetchFileData() so all file data is always stored
    status: completed
  - id: whale-detection
    content: Add whale detection in ClipboardMonitor.captureClipboard() -- check both conditions, register with WhaleManager, skip FIFO eviction for whales
    status: completed
  - id: eviction-skip-whales
    content: Update StorageManager eviction to skip whale entries when doing FIFO cleanup
    status: completed
  - id: pie-chart-view
    content: Create WhalePieChart SwiftUI view (red arc shape) and overlay it on whale cards in ClipboardEntryRow
    status: completed
  - id: zombie-card
    content: Implement zombie card state in ClipboardEntryRow -- replaced content with removal message text after countdown expires
    status: completed
  - id: whale-context-menu
    content: "Add whale context menu items in HistoryPanelView: increase cap, delete other items to make room (with cascading suggestions)"
    status: completed
  - id: countdown-and-cleanup
    content: Wire up display countdown in AppDelegate.presentHistoryPanel() and silent zombie deletion in panel close
    status: completed
  - id: hard-backstop
    content: Implement hard backstop calculation based on disk size and soft cap, gate the increase-cap menu option
    status: completed
isProject: false
---

# Whale Memory Limit System

## Decision Matrix

When a new item is captured:

| Item > per-item trigger? | Total storage > soft cap? | Behavior                                               |
| ------------------------ | ------------------------- | ------------------------------------------------------ |
| No                       | No                        | Normal -- store it                                     |
| No                       | Yes                       | Normal FIFO -- evict oldest to make room               |
| Yes                      | No                        | Normal -- store it (cap has room)                      |
| Yes                      | Yes                       | **WHALE** -- elastic overflow, countdown, context menu |

## Settings (3 limits)

All three live in the "History" section of [SettingsView.swift](Clip9/UI/SettingsView.swift):

- **Max Items** -- stepper, default 100 (already exists)
- **Per-Item Trigger** -- editable text field (not a slider), default 500 MB. This is the threshold above which an item CAN become a whale (if it also pushes total over the soft cap)
- **Storage Cap (soft)** -- the existing slider, default changed from 5 GB to **1 GB**

New `@AppStorage` key: `"perItemTriggerMB"` (Int, default 500).

The hard backstop is NOT user-facing in Settings. It is computed:

- If soft cap <= 5 GB: hard limit = min(5 GB, 10% of total disk)
- If soft cap > 5 GB: hard limit = 15% of total disk

## Remove the 200 MB File Fetch Cap

In [ClipboardMonitor.swift](Clip9/Clipboard/ClipboardMonitor.swift), `fetchFileData()` currently skips files over `maxFileFetchBytes` (200 MB). Remove this cap entirely -- always store the file data. The whale system now handles oversized items gracefully.

## Whale State Tracking

Create a new `WhaleManager` class (or extend `ClipboardMonitor`) that tracks whale state. Whale metadata is separate from `ClipboardEntry` to keep the entry model clean:

- **WhaleState**: a dictionary `[UUID: WhaleInfo]` where `WhaleInfo` holds `remainingDisplays: Int` (starts at 4) and `isZombie: Bool`
- Persisted to `~/Library/Application Support/Clip9/whales.json` so state survives app restart
- When a whale's countdown reaches 0, it transitions to zombie (`isZombie = true`, `remainingDisplays = 0`)
- A whale is removed from tracking when: user resolves it (increase limit / delete / make room), or the zombie is dismissed

## Whale Detection (on capture)

In `ClipboardMonitor.captureClipboard()`, after creating the entry and before/during `pushEntry()`:

1. Compute `newTotalBytes = StorageManager.shared.currentStorageBytes + entry.totalBytes`
2. Read `perItemTriggerMB` from UserDefaults
3. If `entry.totalBytes > perItemTriggerMB * 1_048_576` AND `newTotalBytes > softCapBytes`:

- Register the entry as a whale in WhaleManager with `remainingDisplays = 4`
- Do NOT run normal FIFO eviction for this entry (it is allowed to exceed the soft cap)

1. If the entry is NOT a whale but `newTotalBytes > softCapBytes`:

- Normal FIFO eviction applies (delete oldest non-whale items until under soft cap)

1. Hard backstop check: if `newTotalBytes` would exceed the hard limit, do not offer "Increase limit" (but still store the item -- the whale system handles it)

## Display Countdown

In `AppDelegate.presentHistoryPanel()` (called every time the panel is shown):

1. Call `whaleManager.decrementDisplayCounts()`
2. For each whale with `remainingDisplays > 0`: decrement by 1
3. For any whale that hits 0: set `isZombie = true`
4. Persist updated state

## Visual Indicators on Cards

In [ClipboardEntryRow.swift](Clip9/UI/ClipboardEntryRow.swift), overlay a red pie chart badge when the entry is a whale:

- Query `WhaleManager` for the entry's whale state
- **Displays 1-4**: Red pie chart overlay in the top-right corner of the card. Pie fill: 4/4 full, 3/4, 2/4, 1/4 (based on `remainingDisplays`)
- **Zombie (display 5)**: Pie plays a "pop" animation, then the card content is replaced with centered text: "Item removed -- over storage limit" and a subtitle "Right-click to manage". The normal card preview is hidden
- All red, no color escalation
- The pie chart is a simple SwiftUI shape (arc in a circle)

## Context Menu for Whales

In [HistoryPanelView.swift](Clip9/UI/HistoryPanelView.swift), the existing `.contextMenu` on cards gains additional items below a `Divider()` when the entry is a whale or zombie:

- **"Increase storage cap to X"** -- rounds current total usage up to nearest 250 MB. Updates `storageCapGB` in UserDefaults. Removes whale flag. NOT offered if increasing would exceed the hard backstop
- **"Delete this item"** -- same as existing delete (already implemented)
- **"Delete other items to make room"** -- evicts oldest non-whale items (FIFO) until the whale fits within the soft cap. Removes whale flag after success

### Cascading Suggestions

When multiple whales exist, the "Increase storage cap to X" value for each whale reflects the cumulative total as if all preceding whales (by position in history) had their increases accepted. This is computed at display time, not stored.

## Zombie Dismissal (silent delete)

In `AppDelegate` or `HistoryPanel.close()`, when the panel is dismissed:

- Check WhaleManager for any zombies the user did not act on
- Silently delete those entries via `ClipboardMonitor.deleteEntry()`
- Remove from WhaleManager tracking
- No toast, no notification -- completely silent

## Hard Backstop

Add a utility function (on `StorageManager` or a new `DiskUtils`):

```swift
static func hardBackstopBytes(softCapBytes: Int) -> Int {
    let totalDisk = totalDiskSpaceBytes()
    if softCapBytes <= 5_368_709_120 { // 5 GB
        return min(5_368_709_120, totalDisk / 10)
    } else {
        return totalDisk * 15 / 100
    }
}
```

### Behavior at the hard limit

The hard backstop is enforced through aggressive eviction, **never by refusing a capture** -- with one exception: physical disk space.

- When a new item would push total storage above the hard limit, aggressively FIFO-evict oldest non-whale items to get back under
- If the item cannot fit even when it is the only item (single item > hard limit), **store it anyway** -- the whale system handles it with delete-only options
- The "Increase storage cap" context menu option is **hidden** when total usage is at or above the hard backstop (there is nowhere to grow)
- Only "Delete this item" and "Delete other items to make room" remain available
- The Settings slider/control for storage cap is capped so the user cannot set it above the hard backstop

### Physical disk space check

Before writing any entry to disk (in `StorageManager.save()`), check that the volume has enough free space to hold the entry's bytes plus a safety margin (e.g., 500 MB). If the disk literally cannot fit the data:

- Do **not** attempt the write
- The entry lives in memory only for the current session (displayed in the panel, usable for paste) but is not persisted
- Log a warning: "Insufficient disk space to persist entry"
- The entry is silently lost on next app launch -- this is acceptable because the alternative is crashing the user's system

## Files Changed

- [SettingsView.swift](Clip9/UI/SettingsView.swift) -- add per-item trigger text field, change default cap to 1 GB
- [ClipboardMonitor.swift](Clip9/Clipboard/ClipboardMonitor.swift) -- remove file fetch cap, add whale detection logic, integrate WhaleManager calls
- [ClipboardEntryRow.swift](Clip9/UI/ClipboardEntryRow.swift) -- pie chart overlay, zombie card state
- [HistoryPanelView.swift](Clip9/UI/HistoryPanelView.swift) -- whale/zombie context menu items
- [AppDelegate.swift](Clip9/App/AppDelegate.swift) -- countdown decrement on panel show, zombie cleanup on panel close
- [StorageManager.swift](Clip9/Storage/StorageManager.swift) -- eviction skips whales, hard backstop utility
- **NEW**: `Clip9/Models/WhaleManager.swift` -- whale state tracking, persistence, cascade logic
- **NEW**: `Clip9/UI/WhalePieChart.swift` -- red pie chart SwiftUI shape view
