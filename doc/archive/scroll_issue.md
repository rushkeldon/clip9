# Scroll-Wheel Hover Offset Bug

## Symptom

When the history panel is open and you scroll with the **scroll wheel** while the
mouse is hovering over the card list, the hover highlight drifts out of sync with
the actual mouse position.  The card that appears highlighted is *above* the card
the cursor is really over, and the offset grows proportionally to how far you
scroll.  After scrolling stops the offset remains — mousing over a card near the
bottom highlights a card several rows higher.

## What Works (no offset)

| Scroll method | Then mouse over cards | Result |
|---|---|---|
| **Keyboard arrows** (down arrow to scroll the list) | Move mouse onto cards | Correct highlight |
| **Hover-over-chevron** (mouse on the ▼ button at the bottom to auto-scroll) then move mouse away and back onto cards | Mouse over any card | Correct highlight |
| **No scroll at all** (panel just opened) | Mouse over cards | Correct highlight |

In every working case the mouse can be moved onto any card after scrolling and the
highlight is accurate.

## What Breaks

| Scroll method | Then mouse over cards | Result |
|---|---|---|
| **Scroll wheel** while cursor is over the card area | Continue mousing | Wrong card highlighted; offset grows with scroll distance |

This is the **only** broken case.

---

## View Hierarchy

```
NSPanel  (HistoryPanel)
 └─ NSHostingView  (rootView = HistoryPanelView)
     └─ ZStack (.bottom)
         ├─ GeometryReader            ← "cardList"
         │   └─ ScrollViewReader
         │       └─ ScrollView                    ← native NSScrollView under the hood
         │           └─ VStack (spacing: cardSpacing)   ← coordinateSpace("cardStack")
         │               ├─ ClipboardEntryRow [0]
         │               ├─ ClipboardEntryRow [1]
         │               ├─ ...
         │               └─ ClipboardEntryRow [n]
         │           (background GeometryReader → ScrollOffsetKey)
         │
         ├─ scrollArrow (chevron ▼)   ← bottom-aligned, arrowZoneHeight tall
         │
         └─ MouseTrackingOverlay      ← NSViewRepresentable, covers full ZStack
              └─ MouseTrackingNSView  ← NSTrackingArea, reports mouse Y
                  hitTest returns nil (pass-through)
```

Key points:

- `MouseTrackingNSView` sits on top of the entire panel and is transparent to
  clicks (`hitTest` returns `nil`).  It reports `mouseMoved` coordinates in its
  own local AppKit frame (origin bottom-left).
- The SwiftUI `ScrollView` is backed by a real `NSScrollView` at the AppKit
  level.  `ScrollState` finds and caches this via `findScrollView()`.
- `scrollState.scrollOffset` is kept in sync with the scroll position via the
  `ScrollOffsetKey` preference (SwiftUI → `scrollState.scrollOffset`).

---

## Three Scroll Paths — What Each One Does

### 1. Keyboard arrows

`ScrollState.selectNext(count:)` / `selectPrevious()` set `scrollTargetIndex`.
`HistoryPanelView.onChange(of: scrollState.scrollTargetIndex)` calls
`proxy.scrollTo(...)`.  SwiftUI drives the `NSScrollView`; the preference-key
pipeline updates `scrollState.scrollOffset`.  **No mouse position is involved.**
When the user later moves the mouse, `mouseMoved` fires with a fresh coordinate
and `selectByMousePosition` runs a clean hit-test using `cachedScrollView
.contentView.bounds.origin.y` as the scroll origin.

### 2. Hover-over-chevron auto-scroll

`updateMousePosition` detects the mouse is in the bottom trigger zone and starts
a timer (`scrollTick`).  Each tick calls `clipView.setBoundsOrigin(origin)` /
`scrollView.reflectScrolledClipView(clipView)` and sets `scrollState.scrollOffset
= origin.y`.  It also calls `reselectUnderMouseIfPossible()` which re-runs the
hit-test with the stored `lastMouseYInOverlay`.  When the user moves the mouse
back over the cards, `mouseMoved` fires again with a fresh coordinate.  Hit-test
uses `cachedScrollView.contentView.bounds.origin.y`.  **Works fine.**

### 3. Scroll wheel (BUG)

The scroll wheel is handled **by the native `NSScrollView` itself** — neither
`MouseTrackingNSView` nor `ScrollState` intercepts the wheel events.  The
`NSScrollView` scrolls its clip view internally.  SwiftUI's preference-key
pipeline eventually fires `onPreferenceChange(ScrollOffsetKey.self)` and updates
`scrollState.scrollOffset`.  The `scrollOffset` `didSet` calls
`reselectUnderMouseIfPossible()`.

**But here is the critical difference**: during scroll-wheel scrolling, macOS does
**not** generate `mouseMoved` events.  The physical mouse has not moved, so
`MouseTrackingNSView.mouseMoved(with:)` is never called.  That means
`lastMouseYInOverlay` retains its stale value from before the scroll began.

Meanwhile `cardOffsets` (the Y positions reported by `CardGeometryKey`) are
measured in the `coordinateSpace("cardStack")` — which is the **content
coordinate space inside the ScrollView**.  These values shift as the content
scrolls because the `GeometryReader` inside each card row reports `frame(in:
.named("cardStack"))`, and `"cardStack"` is attached to the VStack *inside* the
ScrollView.  So `cardOffsets` are **content-relative** and do **not** change as
the user scrolls — they remain stable.

The hit-test in `applyMouseHitTest` does:

```swift
let fromTop = viewHeight - mouseY          // overlay-local
let yInViewport = fromTop
let scrollOriginY = cachedScrollView?.contentView.bounds.origin.y ?? scrollOffset
let contentY = yInViewport + scrollOriginY  // convert to content space
```

It then compares `contentY` against `cardOffsets[i]` / `cardHeights[i]`.

**If `cardOffsets` are truly stable in content space and `scrollOriginY` is read
from `cachedScrollView.contentView.bounds.origin.y`, this math should be
correct.**  So the question becomes: is `cachedScrollView` actually the
NSScrollView that the scroll wheel is scrolling?  Or is the scroll wheel scrolling
a *different* scroll view / clip view, causing `scrollOriginY` to be stale or
wrong?

---

## The Core Question

**What is different about the scroll-wheel code path that produces the offset,
when the other two scroll methods (keyboard, hover-chevron) do not?**

The two working paths either:
- Don't use stored mouse position at all (keyboard), or
- Directly drive the NSScrollView via `clipView.setBoundsOrigin` and read back
  from the same object (hover-chevron).

The scroll-wheel path:
- Relies on `lastMouseYInOverlay` which is stale (mouse hasn't moved).
- Relies on `cardOffsets` from SwiftUI preferences.
- Relies on `cachedScrollView.contentView.bounds.origin.y` for the scroll origin.
- The actual scrolling is done by AppKit's native NSScrollView event handling.

---

## Hypotheses

### H1: `cachedScrollView` is not the scroll view being scrolled

SwiftUI's `ScrollView` may be backed by more than one `NSScrollView` in the view
hierarchy, or the cached reference might point to a parent/wrapper rather than the
one actually receiving wheel events.  If so, `bounds.origin.y` would be stale or
zero, and `contentY` would be wrong.

**How to test**: Log `cachedScrollView.contentView.bounds.origin.y` during a
scroll-wheel event and compare it to the `scrollOffset` reported by the
preference key.  If they diverge, this is the cause.

### H2: `cardOffsets` are not in stable content-space coordinates

`cardOffsets` are captured via `frame(in: .named("cardStack"))` where
`"cardStack"` is on the VStack *inside* the ScrollView.  If SwiftUI reports these
relative to the *viewport* rather than the *content*, they would shift as the user
scrolls, and the hit-test math (which adds `scrollOriginY`) would double-count
the scroll offset.

**How to test**: Log `cardOffsets[0]` and `cardOffsets[last]` before and after
scroll-wheel scrolling.  If they change, the coordinate space is viewport-relative
and we're double-counting.

### H3: The preference-key `scrollOffset` and `NSScrollView.bounds.origin.y` are out of sync

`applyMouseHitTest` reads `cachedScrollView?.contentView.bounds.origin.y ??
scrollOffset`.  If the cached scroll view exists, it uses the AppKit value.
During scroll-wheel events, the NSScrollView updates immediately but
`scrollState.scrollOffset` (from the SwiftUI preference) may lag.  The `didSet`
on `scrollOffset` triggers `reselectUnderMouseIfPossible()` — but at that moment,
the AppKit bounds may have already moved further.  This could cause a small but
accumulating error.

**How to test**: In `reselectUnderMouseIfPossible`, log both
`cachedScrollView?.contentView.bounds.origin.y` and `scrollOffset` side by side.

### H4: SwiftUI is scrolling a different internal view than the NSScrollView we cached

The `findScrollView()` function does a depth-first search and returns the first
`NSScrollView` it finds.  If SwiftUI nests multiple NSScrollViews (e.g. a wrapper
around the real one), we might have cached the wrong one.

**How to test**: Walk the full NSView hierarchy and print every NSScrollView found,
with its `bounds.origin` and `documentView.frame`.

---

## Suggested Debugging Steps

1. **Add logging to `reselectUnderMouseIfPossible`**: print `lastMouseYInOverlay`,
   `cachedScrollView?.contentView.bounds.origin.y`, `scrollOffset`, and a couple
   of `cardOffsets` values.

2. **Add logging to `onPreferenceChange(ScrollOffsetKey.self)`**: print the raw
   preference value and compare to `cachedScrollView?.contentView.bounds.origin.y`
   at the same moment.

3. **Add a `scrollWheel(with:)` override** to `MouseTrackingNSView`: even though
   `hitTest` returns nil, try overriding `scrollWheel` to see if it fires and to
   log the event's `scrollingDeltaY`.  If it does fire, we could use it to update
   `lastMouseYInOverlay` or trigger a fresh hit-test with the correct scroll
   origin.

4. **Dump the NSView hierarchy** once on panel open: print every subview's class
   name to see exactly how many NSScrollViews exist and which one is the "real"
   one.

5. **Try a simpler hit-test**: use `NSWindow.mouseLocationOutsideOfEventStream`
   to get the current absolute mouse position in window coordinates, convert to
   the NSScrollView's document view, and determine which card rect contains it.
   This avoids all stored offsets and coordinate math entirely.
