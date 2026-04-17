# SpaceMan

User-driven workspace snapshots for macOS. Take a named snapshot of the windows on the current Mission Control space, then restore it later — even after plugging into a different display configuration.

A "workspace" is `(display count, sorted display UUIDs, current space ID)`. Snapshots are filtered by that fingerprint, so the menu only shows the ones applicable to where you are right now.

## Status

Phase 1: capture and list. Restore is not yet implemented — the menu lists matching snapshots but the items are disabled.

## Build

```
bash build.sh
```

Runs `swiftc` and produces `SpaceMan.app` alongside the source. The build is Developer ID signed with the Jorvik identity.

## Permissions

SpaceMan needs Accessibility permission to read window positions, sizes, and minimised state. It prompts on first launch; grant it in System Settings → Privacy & Security → Accessibility.

## Design notes

- Per-app window order at capture time is preserved as `orderInApp` so a future restore phase can match windows back to their source slot.
- Storage is a flat JSON list at `~/Library/Application Support/JorvikSpaceMan/snapshots.json`; a `.bak` is written before every save.
- Up to 5 snapshots per workspace. Exceeding the cap evicts the oldest.
