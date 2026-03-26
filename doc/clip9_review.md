# Clip9 — Pre-Submission Review

Date: March 26, 2026

---

## 1. Logging Audit

**132 log statements across 12 files**, all routing through a custom `LogService` that writes to daily-rotated files at `~/Library/Application Support/Clip9/Logs/`.

### Infrastructure

- Custom `LogService` singleton with four levels: DEBUG, INFO, WARN, ERROR
- Daily log rotation (`clip9-YYYY-MM-DD.log`), 7-day auto-pruning
- Async serial write queue (`DispatchQueue`, `.utility` QoS)
- Subsystem categories: App, Clipboard, Storage, Panel, UI, Scroll, Mouse, Media, Settings, FirstRun, LogService

### What was fixed

Six noisy log statements were removed or deduplicated. These sat in hot paths (60fps scroll ticks, SwiftUI view body re-renders, video loop notifications) and could collectively emit 120+ lines/second.

| File | What | Rate | Fix |
|------|------|------|-----|
| `ScrollState.swift` | Card selection log in `applyMouseHitTest()` | ~60/sec during hover-scroll | Removed |
| `HistoryPanelView.swift` | Selection `onChange` handler (info level) | ~60/sec during hover-scroll | Removed |
| `HistoryPanelView.swift` | Scroll offset change log | ~60/sec during any scroll | Removed |
| `ClipboardEntryRow.swift` | File preview rendering log in SwiftUI body | Per re-render | Removed |
| `SilentVideoView.swift` | "Video looped" log | Every few seconds per video | Removed |
| `AppDelegate.swift` | "Settings synced" log | Every `UserDefaults` notification (slider drags) | Deduplicated — only logs when values change |

### What stays (~125 statements)

- **Startup/shutdown** (~10): App launch, monitoring start, cache warm, panel creation
- **Clipboard capture** (~15 per capture): Change detection, per-item type enumeration, dedup/coalesce decisions, final summary
- **Restore flow** (~8 per restore): Entry details, pasteboard write, success/failure
- **User actions** (~20): Tap, context menu, keyboard, settings toggle
- **Storage I/O** (~15): Save, load, eviction, index management
- **Panel/mouse lifecycle** (~10): Show/hide, mouse exit, scroll zone transitions
- **Error/warn paths** (~15): Guard failures, nil-data, load errors

---

## 2. Sandbox and Entitlements Audit

### Entitlements: Correct and Minimal

`Clip9/Clip9AppStore.entitlements` declares a single entitlement:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```

No additional entitlements are needed:

- **NSPasteboard.general** works under sandbox without entitlements
- **SMAppService.mainApp** (login items) works without extra entitlements
- **NSEvent.addGlobalMonitorForEvents** for mouse clicks works without accessibility permissions
- **NSWorkspace.shared.open** for URLs and the app's own container directory works without entitlements
- **FileManager Application Support** resolves to the sandboxed container automatically
- **No network calls** exist anywhere in the codebase
- **No file panels, keychain, hardware access, Apple Events, or accessibility APIs** are used

### Hardened Runtime: Correct

```
ENABLE_APP_SANDBOX = YES
ENABLE_HARDENED_RUNTIME = YES
ENABLE_USER_SCRIPT_SANDBOXING = YES
```

### What was fixed

| Item | Fix |
|------|-----|
| `REGISTER_APP_GROUPS = YES` in both Debug and Release | Removed — no app groups are used |
| `INFOPLIST_KEY_NSHumanReadableCopyright = ""` | Set to "Copyright © 2026 Keldon Rush, AppCloud9. All rights reserved." |

### macOS 16 Clipboard Privacy

macOS 16 introduces clipboard privacy prompts. Key implications:

- `pasteboard.changeCount` polling is safe — does NOT trigger the privacy alert
- Actual data reads (`pasteboard.pasteboardItems`, `item.data(forType:)`) trigger a system prompt
- Users must grant "always allow" access via System Settings > Privacy & Security > Pasteboard
- No programmatic API exists to request permanent access (open Apple Feedback: FB17587626)
- The app's poll-changeCount-then-read-data pattern is the standard approach all clipboard managers use

No code changes needed. The system handles the permission flow.

---

## 3. Code Quality Sweep

### Checklist — All Clean

- [x] Zero `print()` statements — all logging through `LogService`
- [x] Zero TODO / FIXME / HACK / XXX / TEMP / WORKAROUND comments
- [x] Zero `#if DEBUG` blocks — no debug-only code leaking into release
- [x] Zero `try!` or `as!` force casts — all `try` calls use `try?` or `do/catch`
- [x] Zero hardcoded test data, placeholder URLs, or localhost references
- [x] Zero deprecated API usage
- [x] Zero strong reference cycles — all closures use `[weak self]`
- [x] Zero array out-of-bounds risks — all index accesses are bounds-guarded
- [x] Zero NSPasteboard edge case gaps — nil items, empty data, concealed types all handled
- [x] Zero infinite loop risks — eviction loops bounded, resize recursion guarded
- [x] Deployment target (macOS 14.0) matches API floor (`@Observable` requires macOS 14+)
- [x] App icon uses modern Xcode single-source format (`AppIcon.icon/`)
- [x] Version `1.0` (build 1) — correct for initial submission
- [x] `LSUIElement = YES` — menu-bar agent app, no Dock icon

### What was fixed

| Item | File | Fix |
|------|------|-----|
| Missing `deinit` — `pollTimer` leak risk | `ClipboardMonitor.swift` | Added `deinit { stop() }` |
| Missing `deinit` — `scrollTimer` leak risk | `ScrollState.swift` | Added `deinit { scrollTimer?.invalidate() }` |
| Missing `deinit` — observer leak risk | `SilentVideoView.swift` | Added `deinit { tearDown() }` |
| Unused `zoomObserver` property (dead code) | `HistoryPanel.swift` | Removed |
| `NSScreen.screens.first!` force unwrap (2x) | `AppDelegate.swift` | Changed to `guard let ... else { return }` |
| `fatalError()` with no diagnostic message | `SilentVideoView.swift` | Added descriptive message |
| `.DS_Store` files tracked in git | `.gitignore` | Added `.DS_Store` and `DerivedData/` to gitignore, untracked existing files |

---

## 4. Remaining Non-Code Item

**Privacy Policy URL** — App Store Connect requires a publicly accessible privacy policy URL for all apps, even those that collect no data. Create a page at `https://clip9.app/privacy` (or similar) stating that Clip9 collects no personal data, makes no network requests, and stores all clipboard data locally on-device. Enter this URL in App Store Connect.

---

## Summary of All Changes Made

### Logging (6 changes across 5 files)

- Removed 5 noisy debug/info log statements from hot paths
- Deduplicated settings-synced log to only fire on actual value changes

### Sandbox (2 changes in project.pbxproj)

- Removed orphaned `REGISTER_APP_GROUPS = YES`
- Set proper copyright string

### Code Quality (7 changes across 5 files + .gitignore)

- Added `deinit` to `ClipboardMonitor`, `ScrollState`, `SilentVideoNSView`
- Removed unused `zoomObserver` from `HistoryPanel`
- Softened 2 `NSScreen.screens.first!` force unwraps in `AppDelegate`
- Added diagnostic message to `fatalError()` in `SilentVideoNSView`
- Updated `.gitignore` and untracked `.DS_Store` files
