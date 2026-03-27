# Clip9 Memory Limit Spec

## Overview

Clip9 is a macOS menu bar clipboard history app. There is no per-item size limit. A single overall memory limit governs history retention. When a copied item causes the history to exceed that limit, the app uses an elastic overflow system with user-facing resolution options rather than silently evicting older entries.

## Core Concepts

### The Balloon Model

The memory limit is a balloon:

- **Resting size** — user-configured limit (default: 1GB)
- **Stretched** — temporarily over-inflated by an oversized item ("whale"), countdown ticking
- **Resized** — user explicitly increases the limit via context menu action
- **Hard backstop** — free disk space is the absolute ceiling; the balloon cannot inflate beyond what the disk allows

### Normal Eviction vs. Whale Behavior

There is a **per-copy size limit** (configurable in Settings). This is the dividing line between two behaviors:

- **Below the per-copy limit:** Normal clipboard behavior. As the overall memory limit fills, the oldest history items are silently evicted (FIFO garbage collection). No flags, no countdowns, no user intervention required. This is expected, invisible housekeeping.
- **Above the per-copy limit:** The item is a **whale**. It is still copied into history, but it triggers the elastic overflow system — the balloon stretches, the item is flagged with a countdown icon, and the user is given a window of 4 menu displays to resolve it before auto-deletion.

The per-copy limit is what triggers whale behavior, not the overall memory limit being exceeded.

### Hard Backstop

Free disk space (minus a safety margin) is the absolute upper bound. When the disk limit is reached:

- The "Increase memory limit" option is no longer offered
- Only "Delete this item" and "Delete other items to make room" remain
- The app never risks starving the system of disk space

> **TODO:** Define safety margin — fixed floor (e.g., always keep 5GB free) or percentage-based.

> **TODO:** Consider auto-adjusting the default memory limit on first launch based on machine specs (e.g., 2% of total disk, floor of 1GB).

## Whale Handling Flow

### 1. Copy

- Item is copied into history as usual — never blocked, never deferred
- If the item pushes total usage over the memory limit, it is flagged as a whale
- The memory limit is temporarily exceeded (elastic overflow)

### 2. Visual Flag

- Whale items display a **red pie chart icon** on their history card
- The pie starts as a full red circle
- One quarter of the pie is removed each time the history menu is displayed
- Progression: full → ¾ → ½ → ¼ → gone (deleted)
- The user gets **4 menu displays** to resolve the whale before auto-deletion
- The countdown is interaction-time, not wall-clock time — fair to the user

### 3. Context Menu (Right-Click)

Standard context menu options, plus these below a separator:

- **Increase memory limit to `${roundedUpCurrentMemoryUsed}`?**
  - Rounds up to nearest 250MB chunk
  - Permanently resizes the balloon
  - Whale flag is removed; item becomes a normal history entry
- **Delete this item**
  - Removes the whale immediately
  - Memory usage drops back within the resting limit
- **Delete other items to make room**
  - Evicts oldest non-whale items first (FIFO)
  - No picker, no confirmation — bone simple
  - Continues until the whale fits within the current memory limit

## Back-to-Back Whales

Multiple whales can coexist in elastic overflow simultaneously. Each whale has its own independent 4-display countdown.

### Cascading Memory Suggestions

- The **first** whale's "Increase" option reflects the current memory setting
- The **second** whale's "Increase" option reflects what the limit *would be* if the user accepted the first whale's increase
- Subsequent whales continue cascading — each reflects the cumulative reality of accepting all preceding whales

This ensures the user sees a realistic memory figure at every decision point.

### Eviction Order

If a whale's countdown expires (auto-deletion) or the user chooses "Delete other items to make room," eviction is oldest-first across all non-whale items. No picker, no weighting.

## Settings

| Setting | Default | Notes |
|---|---|---|
| Memory limit | 1 GB | Adjustable in Settings; also adjustable via whale context menu |
| Per-copy size limit | 50 MB | Items above this threshold trigger whale behavior (elastic overflow + countdown) |

## Open Questions

- Safety margin for hard backstop: fixed floor vs. percentage of free disk?
- Should the default memory limit auto-scale based on machine specs at first launch?
- Should the countdown urgency escalate visually (e.g., yellow at 4, orange at 2, red at 1) or is the shrinking pie sufficient on its own?
- When a whale is auto-deleted after countdown expiry, should a brief notification or toast confirm it?
