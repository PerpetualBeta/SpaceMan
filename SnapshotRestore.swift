import AppKit
import ApplicationServices

/// Applies a snapshot to the live system.
///
/// Phase 2 scope: only acts on apps that are already running and whose
/// window list already contains enough windows to match the snapshot's
/// `orderInApp` indices. Missing apps and missing windows are counted
/// and reported, but not launched / spawned — that's Phases 3 and 4.
enum SnapshotRestore {

    struct Result {
        var matched: Int = 0
        var skippedAppMissing: Int = 0
        var skippedWindowMissing: Int = 0
        var skippedAccessibility: Bool = false

        var total: Int { matched + skippedAppMissing + skippedWindowMissing }
    }

    /// Restore a snapshot. Must be called on the main thread — AX calls
    /// and window manipulation are main-thread only.
    @MainActor
    static func restore(_ snapshot: Snapshot) -> Result {
        var result = Result()

        guard AXIsProcessTrusted() else {
            result.skippedAccessibility = true
            return result
        }

        // Group records by bundle ID so we open each running app's AX
        // window list once.
        let groups = Dictionary(grouping: snapshot.windows, by: { $0.bundleID })

        // Track which apps had a hidden record — those get NSRunningApplication.hide() at the end.
        var hideTargets: Set<String> = []

        for (bundleID, records) in groups {
            let sorted = records.sorted { $0.orderInApp < $1.orderInApp }

            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
                result.skippedAppMissing += sorted.count
                continue
            }

            // If the app is currently hidden, un-hide it so its windows
            // accept geometry changes. We re-hide at the end if needed.
            if app.isHidden {
                app.unhide()
            }

            let windows = axWindowList(for: app.processIdentifier)

            for record in sorted {
                guard record.orderInApp < windows.count else {
                    result.skippedWindowMissing += 1
                    continue
                }
                apply(record, to: windows[record.orderInApp])
                if record.state == .hidden { hideTargets.insert(bundleID) }
                result.matched += 1
            }
        }

        // Apply app-level hide for any snapshot that asked for it. If AX
        // won't hide the app (rare), NSRunningApplication.hide() still
        // works because it posts the standard hide notification.
        for bundleID in hideTargets {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { continue }
            app.hide()
        }

        return result
    }

    // MARK: - AX helpers

    private static func axWindowList(for pid: pid_t) -> [AXUIElement] {
        let appEl = AXUIElementCreateApplication(pid)
        var value: AnyObject?
        let rc = AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &value)
        guard rc == .success, let arr = value as? [AXUIElement] else { return [] }
        return arr
    }

    /// Apply a single record to a live AX window: un-minimise, set
    /// position and size, then apply the target state (minimised/normal).
    /// Hidden state is handled at the app level after all windows are
    /// processed.
    private static func apply(_ record: WindowRecord, to window: AXUIElement) {
        // Un-minimise first so AXPosition/AXSize can be set
        setBool(window, attribute: kAXMinimizedAttribute, value: false)

        var origin = record.frame.origin
        var size = record.frame.size
        if let posValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }

        // Apply target state. Hidden is an app-level operation handled
        // by the caller, so here we only honour .minimised explicitly.
        if record.state == .minimised {
            setBool(window, attribute: kAXMinimizedAttribute, value: true)
        }
    }

    private static func setBool(_ window: AXUIElement, attribute: String, value: Bool) {
        AXUIElementSetAttributeValue(window, attribute as CFString, value as CFBoolean)
    }
}
