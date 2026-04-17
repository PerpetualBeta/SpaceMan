import AppKit
import ApplicationServices

/// Applies a snapshot to the live system.
///
/// Phases:
///   1. (none — capture only)
///   2. Position existing windows of already-running apps.
///   3. Launch apps that aren't running, wait for their windows to
///      appear, then position. This file is Phase 3.
///   4. (future) Spawn extra windows when the snapshot has more
///      records than the app currently has windows.
enum SnapshotRestore {

    struct Result {
        var matched: Int = 0
        var launched: Int = 0
        var spawned: Int = 0
        var skippedAppUninstalled: Int = 0
        var skippedLaunchTimeout: Int = 0
        var skippedSpawnFailed: Int = 0
        var skippedAccessibility: Bool = false
    }

    /// Per-app launch timeout. Apps that don't surface at least one
    /// window within this many seconds get counted as a launch timeout.
    private static let launchTimeout: TimeInterval = 6.0

    /// Restore a snapshot. Must be driven from the main actor — AX and
    /// NSWorkspace calls require main-thread / main-actor context.
    @MainActor
    static func restore(_ snapshot: Snapshot) async -> Result {
        var result = Result()

        guard AXIsProcessTrusted() else {
            result.skippedAccessibility = true
            return result
        }

        // Build a set of CG window IDs on the CURRENT Mission Control
        // space. AX enumerates windows across all spaces, so we use this
        // set to scope the restore to the space the user is on now.
        // Without this, a snapshot with (say) one Finder window could
        // silently "match" a Finder window that's on a different space
        // and AX would no-op the move — user sees nothing.
        let onScreenIDs = currentSpaceWindowIDs()

        // Group records by bundle ID so we open each running app's AX
        // window list once.
        let groups = Dictionary(grouping: snapshot.windows, by: { $0.bundleID })

        // Track which apps had a hidden record — they get NSRunningApplication.hide() at the end.
        var hideTargets: Set<String> = []

        for (bundleID, records) in groups {
            let sorted = records.sorted { $0.orderInApp < $1.orderInApp }

            // Find, or launch, the app.
            var app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            var didLaunch = false

            if app == nil {
                guard let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                    result.skippedAppUninstalled += sorted.count
                    continue
                }
                if let launched = await launch(url: bundleURL) {
                    app = launched
                    didLaunch = true
                    result.launched += 1
                } else {
                    result.skippedLaunchTimeout += sorted.count
                    continue
                }
            }

            guard let runningApp = app else { continue }

            // If the app is currently hidden, un-hide it so its windows
            // accept geometry changes. We re-hide at the end if needed.
            if runningApp.isHidden {
                runningApp.unhide()
            }

            // Count live windows on the current space. If we just
            // launched, poll until the first one appears (or timeout).
            // Otherwise take a snapshot of what's there now.
            var windows: [AXUIElement]
            if didLaunch {
                windows = await waitForWindowsOnCurrentSpace(
                    pid: runningApp.processIdentifier,
                    minimumCount: 1,
                    onScreenIDs: onScreenIDs,
                    timeout: launchTimeout
                )
                if windows.isEmpty {
                    result.skippedLaunchTimeout += sorted.count
                    continue
                }
            } else {
                windows = axWindowList(for: runningApp.processIdentifier)
                    .filter { isOnSpace($0, onScreenIDs: onScreenIDs) }
            }

            // Spawn additional windows until we have enough (or the
            // app refuses to give us more).
            while windows.count < sorted.count {
                let spawned = WindowSpawner.spawnWindow(for: runningApp)
                guard spawned else { break }

                // Wait for the window count to actually increase.
                let target = windows.count + 1
                windows = await waitForWindowsOnCurrentSpace(
                    pid: runningApp.processIdentifier,
                    minimumCount: target,
                    onScreenIDs: currentSpaceWindowIDs(),
                    timeout: 3.0
                )
                if windows.count < target {
                    // Menu press reported success but the window never
                    // materialised — give up and count the rest.
                    break
                }
                result.spawned += 1
            }

            for record in sorted {
                guard record.orderInApp < windows.count else {
                    result.skippedSpawnFailed += 1
                    continue
                }
                apply(record, to: windows[record.orderInApp])
                if record.state == .hidden { hideTargets.insert(bundleID) }
                result.matched += 1
            }
        }

        // Apply app-level hide for any snapshot that asked for it.
        for bundleID in hideTargets {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { continue }
            app.hide()
        }

        return result
    }

    // MARK: - Launch

    /// Launch an app in the background (no focus steal) and return the
    /// NSRunningApplication instance the system creates for it.
    @MainActor
    private static func launch(url: URL) async -> NSRunningApplication? {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
                continuation.resume(returning: app)
            }
        }
    }

    /// Poll the AX window list for a PID, filtered to the current
    /// Mission Control space, until it has at least `minimumCount`
    /// windows or `timeout` elapses.
    @MainActor
    private static func waitForWindowsOnCurrentSpace(
        pid: pid_t,
        minimumCount: Int,
        onScreenIDs: Set<CGWindowID>,
        timeout: TimeInterval
    ) async -> [AXUIElement] {
        let deadline = Date().addingTimeInterval(timeout)
        // The on-screen set reflects the space at call time — refresh
        // between iterations in case the user's space or window
        // topology changes while we're waiting.
        var currentIDs = onScreenIDs
        while Date() < deadline {
            let windows = axWindowList(for: pid).filter { isOnSpace($0, onScreenIDs: currentIDs) }
            if windows.count >= minimumCount {
                return windows
            }
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            currentIDs = currentSpaceWindowIDs()
        }
        return axWindowList(for: pid).filter { isOnSpace($0, onScreenIDs: currentIDs) }
    }

    // MARK: - AX helpers

    private static func axWindowList(for pid: pid_t) -> [AXUIElement] {
        let appEl = AXUIElementCreateApplication(pid)
        var value: AnyObject?
        let rc = AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &value)
        guard rc == .success, let arr = value as? [AXUIElement] else { return [] }
        return arr
    }

    /// True if the given AX window has a CG window ID on the current
    /// space (i.e. its ID appears in the on-screen set).
    private static func isOnSpace(_ element: AXUIElement, onScreenIDs: Set<CGWindowID>) -> Bool {
        var windowID: CGWindowID = 0
        let rc = _AXUIElementGetWindow(element, &windowID)
        guard rc == .success else { return false }
        return onScreenIDs.contains(windowID)
    }

    /// CG window IDs currently on-screen (== current Mission Control space),
    /// regular layer only.
    private static func currentSpaceWindowIDs() -> Set<CGWindowID> {
        let listOpts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = (CGWindowListCopyWindowInfo(listOpts, kCGNullWindowID) as? [[String: Any]]) ?? []
        var ids = Set<CGWindowID>()
        for entry in list {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let id = entry[kCGWindowNumber as String] as? CGWindowID else { continue }
            ids.insert(id)
        }
        return ids
    }

    /// Apply a single record to a live AX window: un-minimise, set
    /// position and size, then apply the target state.
    private static func apply(_ record: WindowRecord, to window: AXUIElement) {
        setBool(window, attribute: kAXMinimizedAttribute, value: false)

        var origin = record.frame.origin
        var size = record.frame.size
        if let posValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }

        if record.state == .minimised {
            setBool(window, attribute: kAXMinimizedAttribute, value: true)
        }
    }

    private static func setBool(_ window: AXUIElement, attribute: String, value: Bool) {
        AXUIElementSetAttributeValue(window, attribute as CFString, value as CFBoolean)
    }
}
