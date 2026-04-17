# SpaceMan

**User-driven workspace snapshots for macOS.** Save named layouts of the windows on a Mission Control space, then restore them — including launching missing apps and spawning extra windows — when you come back to that space on the same display configuration.

## Why

macOS doesn't remember *how you arranged things* — just where each window currently sits. The moment you plug into an external display, come home to a single-screen setup, or switch spaces, you're rearranging windows again.

SpaceMan lets you capture a layout *as a named snapshot* and apply it later, with a menu bar that only ever shows snapshots applicable to where you are right now.

## Features

- **Per-workspace snapshots.** A "workspace" is identified by `(display count, sorted display UUIDs, current Mission Control space)`. The same physical space-number on different display configs is treated as distinct — snapshots don't cross-contaminate.
- **Named, manual snapshots.** You choose when to capture and when to restore. No automatic captures, no auto-restore on display changes.
- **Menu filters by current workspace.** The menu bar menu only lists snapshots matching the workspace you're on right now. Change space or plug in a display, the listing changes automatically.
- **Full state restoration**, not just repositioning:
  - Apps already running → existing windows are moved
  - Apps not running → launched in the background (no focus steal)
  - Apps with fewer windows than the snapshot → extra windows spawned via menu-bar driving
  - Minimised / hidden state → preserved (hidden falls back to minimised if AX can't re-hide)
- **Inline management.** Manage window shows every snapshot grouped by display configuration, with inline rename and delete.
- **Lean by design.** 5 snapshots per workspace, max. Exceeding the cap evicts the oldest.
- **Safe storage.** JSON in `~/Library/Application Support/JorvikSpaceMan/snapshots.json`. A rolling `.bak` is written before every save. Corrupt files are preserved to a timestamped copy rather than silently overwritten.

## Requirements

- macOS 13.0 or later
- Accessibility permission (prompted on first launch)

## Installation

Download the latest release from [GitHub Releases](https://github.com/PerpetualBeta/SpaceMan/releases), unzip, drag `SpaceMan.app` into `/Applications`, and launch.

On first launch grant Accessibility when prompted. Without it SpaceMan can't read window state or apply position changes.

## Usage

The menu bar icon is a rocket. Click it to open the menu:

| Item | Action |
|---|---|
| **About SpaceMan** | Version + source links |
| **Snapshot current workspace…** | Prompts for a name, saves a snapshot |
| *(named snapshots)* | Click to restore; newest first; each shows timestamp inline |
| **Manage snapshots…** | Opens the management window |
| **Settings… (⌘,)** | Permissions, menu bar pill, launch at login, updates |
| **Quit SpaceMan (⌘Q)** | — |

### Taking a snapshot

Arrange your windows the way you want on the current space. Open the menu, choose *Snapshot current workspace…*, give it a short label. That's it.

### Restoring a snapshot

Navigate to the target Mission Control space first. Plug in / unplug any displays needed for the target workspace. Open the menu — the snapshots listed are ones captured on exactly this workspace fingerprint. Click one. SpaceMan will:

1. For each app in the snapshot: find it running, launch it if needed (up to 6s timeout per app), spawn extra windows if needed
2. Apply the captured position, size, and minimised/hidden state to each window

A summary dialog reports what happened — how many positioned, how many launched, how many spawned, and any that were skipped (e.g. app not installed).

## Technical details

### Workspace fingerprint

`WorkspaceFingerprint` is `(displayCount, sorted display UUIDs, managedSpaceID)`. Display UUIDs are via `CGDisplayCreateUUIDFromDisplayID`; the space ID is read from the CGS private API `CGSCopyManagedDisplaySpaces`.

Space IDs are stable while a space exists but change if you delete and recreate one — an accepted limitation. Snapshots tied to a deleted space invalidate silently.

### Window capture

CG's `optionOnScreenOnly` window list is scoped to the current Mission Control space. AX (`AXUIElementCopyAttributeValue(kAXWindowsAttribute)`) enumerates windows across *all* spaces — so we cross-reference AX windows with the CG on-screen set via the private `_AXUIElementGetWindow`, keeping only those actually on the current space. Without this, snapshots over-capture windows from other spaces.

Each window record stores: bundle ID, app name, title, frame, display UUID, state (normal / minimised / hidden), and `orderInApp` — the window's zero-based index within its app's AX list at capture time. This order is used to match records back to live windows at restore time.

### Restore

The restore pipeline is async and runs on the main actor:

1. Resolve each app (running | launch | uninstalled)
2. Wait for at least one window on the current space (6s timeout per launch)
3. Spawn extra windows until count matches the snapshot (or the app stops giving us more)
4. Apply `{position, size, minimised}` to each window by `orderInApp` match
5. Hide at the app level for records with `.hidden` state

### Spawning windows

No universal AX action exists for "give this app another window". `WindowSpawner` walks the app's AX menu bar searching for an enabled menu item whose title matches `New Window`, `New Finder Window`, `New Browser Window`, etc. — first a set of exact preferred matches, then a broader "starts with New, contains Window" heuristic — and presses it via `AXPress`. Document-based apps without a clear "new window" command will hit the broader heuristic or fail gracefully.

### Storage

Flat list of snapshots, each carrying its own fingerprint. Filtered at query time rather than pre-grouped. Encoded with ISO-8601 dates. A `.bak` file is written before every save, and decode failures preserve the corrupt file as a timestamped copy before resetting in-memory state.

## Building

```bash
cd SpaceMan
bash build.sh
open SpaceMan.app
```

`build.sh` compiles with `swiftc -O` and produces a Developer ID–signed `.app` bundle. JorvikKit files are compiled in from `JorvikKit/`.

To regenerate the app icon (astronaut helmet on the standard Jorvik-blue gradient tile):

```bash
swift generate_icon.swift
```

## Relationship to other Jorvik tools

- **ActiveSpace** — menu-bar app that shows and switches Mission Control spaces. Use it to navigate *to* a workspace; use SpaceMan to arrange the windows on it.
- **WindowPin** — pins a single window "always on top". Complementary: SpaceMan arranges a whole space, WindowPin keeps one window above the arrangement.
- **WindowRecall** — the earlier approach, with periodic auto-save. Retired on 2026-04-17 and superseded by SpaceMan, whose user-driven, named-snapshot model proved to be the right shape of the problem.

---

SpaceMan is provided by [Jorvik Software](https://jorviksoftware.cc/). If you find it useful, consider [buying me a coffee](https://jorviksoftware.cc/donate).
