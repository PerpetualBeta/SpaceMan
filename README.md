# SpaceMan

A macOS utility for user-driven workspace snapshots. Capture a named layout of the windows on a Mission Control space, then restore it — including launching missing apps and spawning extra windows — when you come back to that space on the same display configuration.

## Requirements

- macOS 14 (Sonoma) or later
- Accessibility permission (prompted on first launch)

## Installation

Two formats on every release — both signed and notarised, pick whichever suits:

- **[Installer (`.pkg`)](https://github.com/PerpetualBeta/SpaceMan/releases/latest/download/SpaceMan.pkg)** — recommended for first-time installs. Double-click to run; macOS Installer places the app in `/Applications` without quarantine or App Translocation.
- **[Download (`.zip`)](https://github.com/PerpetualBeta/SpaceMan/releases/latest)** — unzip and drag `SpaceMan.app` to your Applications folder.

After installation:

1. Launch SpaceMan — a rocket icon appears in your menu bar
2. Grant Accessibility permission when prompted (see [Permissions](#permissions) below)

## Why

macOS doesn't remember *how you arranged things* — just where each window currently sits. Plug into an external display, come home to a single-screen setup, or switch between spaces, and you're rearranging windows again.

SpaceMan lets you capture a layout as a named snapshot and apply it later. The menu bar only ever lists snapshots applicable to where you are right now.

## How It Works

A "workspace" is identified by `(display count, sorted display UUIDs, current Mission Control space)`. The same physical space number on different display configurations is treated as distinct — snapshots don't cross-contaminate.

Snapshots are named and manual. You choose when to capture and when to restore. No automatic captures, no auto-restore on display changes.

## Using SpaceMan

Click the rocket icon in the menu bar:

| Item | Action |
|---|---|
| **About SpaceMan** | Version and source links |
| **Snapshot current workspace…** | Prompts for a name, saves a snapshot |
| *(named snapshots)* | Click to restore; newest first; timestamp inline |
| **Manage snapshots…** | Opens the management window |
| **Settings… (⌘,)** | Permissions, menu bar pill, launch at login, updates |
| **Quit SpaceMan (⌘Q)** | — |

### Taking a snapshot

1. Arrange your windows the way you want on the current space
2. Open the menu and choose **Snapshot current workspace…**
3. Give it a short label

### Restoring a snapshot

1. Navigate to the target Mission Control space first
2. Plug in or unplug any displays needed for the target workspace
3. Open the menu — the snapshots listed are the ones captured on exactly this workspace fingerprint
4. Click one

SpaceMan will find each app in the snapshot, launch it in the background if it's not running, spawn extra windows if needed, and apply the captured position, size, and minimised/hidden state. A summary dialog reports what happened: how many positioned, how many launched, how many spawned, and any that were skipped (for example, if an app isn't installed).

## Full State Restoration

SpaceMan restores more than just window positions:

- **Apps already running** — existing windows are moved into place
- **Apps not running** — launched in the background, with no focus steal
- **Apps with fewer windows than the snapshot** — extra windows spawned via menu-bar driving
- **Minimised and hidden state** — preserved per-window; hidden falls back to minimised if AX can't re-hide an individual window

The management window lists every snapshot grouped by display configuration, with inline rename and delete.

## Storage

Snapshots live in `~/Library/Application Support/JorvikSpaceMan/snapshots.json`.

- A rolling `.bak` is written before every save
- Corrupt files are preserved to a timestamped copy rather than silently overwritten
- Five snapshots per workspace, maximum — exceeding the cap evicts the oldest

## Technical Details

### Workspace fingerprint

`WorkspaceFingerprint` is `(displayCount, sorted display UUIDs, managedSpaceID)`. Display UUIDs come from `CGDisplayCreateUUIDFromDisplayID`; the space ID is read from the private `CGSCopyManagedDisplaySpaces` API.

Space IDs are stable while a space exists but change if you delete and recreate one — an accepted limitation. Snapshots tied to a deleted space invalidate silently.

### Window capture

`CGWindowListCopyWindowInfo` with `optionOnScreenOnly` returns only windows on the current Mission Control space. `AXUIElementCopyAttributeValue(kAXWindowsAttribute)` enumerates windows across *all* spaces. SpaceMan cross-references the two — using the private `_AXUIElementGetWindow` to resolve AX windows to CG window IDs — so a snapshot captures exactly the windows visible on the current space and nothing more.

Each window record stores bundle ID, app name, title, frame, display UUID, state (`normal` | `minimised` | `hidden`), and `orderInApp` — the window's zero-based index within its app's AX list at capture time. This order is used to match records back to live windows at restore time.

### Restore

The restore pipeline is async and runs on the main actor:

1. Resolve each app (running | launch | uninstalled)
2. Wait for at least one window on the current space (6-second timeout per launch)
3. Spawn extra windows until count matches the snapshot (or the app stops yielding more)
4. Apply `{position, size, minimised}` to each window by `orderInApp` match
5. Hide at the app level for records with `.hidden` state

### Spawning windows

No universal AX action exists for "give this app another window". `WindowSpawner` walks the app's AX menu bar and presses the first enabled menu item whose title matches `New Window`, `New Finder Window`, `New Browser Window`, and so on — first against a set of exact preferred matches, then against a broader "starts with *New*, contains *Window*" heuristic. Document-based apps without a clear "new window" command will hit the broader heuristic or fail gracefully.

## Permissions

**Accessibility** is required. Without it, SpaceMan can't read window state or apply position changes. macOS will prompt on first launch. Grant in **System Settings → Privacy & Security → Accessibility**.

Permission status is visible in Settings alongside a direct-grant button.

## Settings

Right-click the rocket icon and choose **Settings…** to configure:

- **Permissions** — Accessibility status with grant button
- **Menu bar icon pill** — optional grey background for stronger contrast on busy or wallpaper-tinted menu bars (off by default)
- **Launch at Login** — start automatically when you log in
- **Auto-update** — check for new versions on a configurable schedule with optional automatic installation

## Building from Source

```bash
git clone https://github.com/PerpetualBeta/SpaceMan.git
cd SpaceMan
bash build.sh
open SpaceMan.app
```

`build.sh` compiles with `swiftc -O` and produces a Developer ID–signed `.app` bundle. JorvikKit files are compiled in from `JorvikKit/`.

To regenerate the app icon (astronaut helmet on the standard Jorvik-blue gradient tile):

```bash
swift generate_icon.swift
```

## Troubleshooting

### A snapshot doesn't appear in the menu

Snapshots only appear when the current workspace fingerprint matches the one captured. Switch to the correct space, or attach/detach displays to match the display configuration at capture time, and the snapshot will reappear.

### Restore positioned windows but didn't spawn new ones

Some apps don't expose a clear "new window" menu item via AX, or expose it under an unexpected name. SpaceMan's spawner uses a preferred-match list then a broader heuristic — apps that miss both will position the windows they already have but won't spawn more.

### Restore reported an app as skipped

The app isn't installed, or its bundle ID has changed since capture. Delete and re-create the snapshot with the current version installed.

## Relationship to Other Jorvik Tools

- **ActiveSpace** — menu-bar app that shows and switches Mission Control spaces. Use it to navigate *to* a workspace; use SpaceMan to arrange the windows on it.
- **WindowPin** — pins a single window "always on top". Complementary: SpaceMan arranges a whole space, WindowPin keeps one window above the arrangement.

---

SpaceMan is provided by [Jorvik Software](https://jorviksoftware.cc/). If you find it useful, consider [buying me a coffee](https://jorviksoftware.cc/donate).
