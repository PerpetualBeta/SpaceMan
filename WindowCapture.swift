import AppKit
import ApplicationServices

/// Captures the set of windows visible on the current Mission Control space,
/// across all regular apps. Needs Accessibility permission — without it the
/// state and precise frame lookups silently fall back to the CG window list.
enum WindowCapture {

    /// Returns true if AX is granted, prompting the user if not.
    static func ensureAccessibility() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Capture all windows currently on the active space, for every regular
    /// (user-facing) app. Windows are grouped per-app so `orderInApp` can be
    /// assigned by window-number ascending.
    static func captureCurrentSpace() -> [WindowRecord] {
        let axTrusted = AXIsProcessTrusted()

        // CG window list scoped to current-space + on-screen. This returns
        // visible, regular-layer windows. Minimised windows typically drop
        // from this list, so they're picked up via the per-app AX pass.
        let listOpts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let cgList = (CGWindowListCopyWindowInfo(listOpts, kCGNullWindowID) as? [[String: Any]]) ?? []

        // Group CG entries by pid
        var byPID: [pid_t: [[String: Any]]] = [:]
        for entry in cgList {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t else { continue }
            byPID[pid, default: []].append(entry)
        }

        var records: [WindowRecord] = []

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            let cgWindows = byPID[pid] ?? []

            // Sort CG windows by window number ascending (roughly creation order)
            let sortedCG = cgWindows.sorted {
                let a = ($0[kCGWindowNumber as String] as? Int) ?? 0
                let b = ($1[kCGWindowNumber as String] as? Int) ?? 0
                return a < b
            }

            // AX enumeration for minimised/hidden windows the CG list may miss
            let axWindows: [AXUIElement] = axTrusted ? axWindowList(for: pid) : []

            // Build records from AX windows if we can — richer data. Fall
            // back to CG-only records for anything AX doesn't expose.
            let appRecords = buildRecords(
                app: app,
                axWindows: axWindows,
                cgWindows: sortedCG
            )
            records.append(contentsOf: appRecords)
        }

        return records
    }

    // MARK: - AX helpers

    private static func axWindowList(for pid: pid_t) -> [AXUIElement] {
        let appEl = AXUIElementCreateApplication(pid)
        var value: AnyObject?
        let rc = AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &value)
        guard rc == .success, let arr = value as? [AXUIElement] else { return [] }
        return arr
    }

    private static func axFrame(_ window: AXUIElement) -> CGRect? {
        var posRef: AnyObject?
        var sizeRef: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)
    }

    private static func axTitle(_ window: AXUIElement) -> String {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &ref) == .success,
              let title = ref as? String else { return "" }
        return title
    }

    private static func axIsMinimised(_ window: AXUIElement) -> Bool {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &ref) == .success,
              let flag = ref as? Bool else { return false }
        return flag
    }

    private static func axIsHidden(app: NSRunningApplication) -> Bool {
        app.isHidden
    }

    // MARK: - Record building

    private static func buildRecords(
        app: NSRunningApplication,
        axWindows: [AXUIElement],
        cgWindows: [[String: Any]]
    ) -> [WindowRecord] {
        let hidden = axIsHidden(app: app)
        let bundleID = app.bundleIdentifier ?? "unknown"
        let name = app.localizedName ?? bundleID

        // Prefer AX walk — it surfaces minimised windows too. If AX is
        // empty (no permission, or app has no windows), fall back to CG.
        if !axWindows.isEmpty {
            return axWindows.enumerated().compactMap { idx, win in
                guard let frame = axFrame(win) else { return nil }
                let title = axTitle(win)
                let minimised = axIsMinimised(win)
                let state: WindowState = hidden ? .hidden : (minimised ? .minimised : .normal)
                let displayUUID = displayUUID(for: frame) ?? ""
                return WindowRecord(
                    bundleID: bundleID,
                    appName: name,
                    title: title,
                    frame: frame,
                    displayUUID: displayUUID,
                    state: state,
                    orderInApp: idx
                )
            }
        }

        return cgWindows.enumerated().compactMap { idx, entry in
            guard let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
            let frame = CGRect(
                x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0
            )
            let title = (entry[kCGWindowName as String] as? String) ?? ""
            let displayUUID = displayUUID(for: frame) ?? ""
            return WindowRecord(
                bundleID: bundleID,
                appName: name,
                title: title,
                frame: frame,
                displayUUID: displayUUID,
                state: hidden ? .hidden : .normal,
                orderInApp: idx
            )
        }
    }

    // MARK: - Display matching

    /// Find the NSScreen whose frame contains the centre of `rect`, then
    /// return that screen's display UUID string.
    private static func displayUUID(for rect: CGRect) -> String? {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        for screen in NSScreen.screens where screen.frame.contains(centre) {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let cgID = CGDirectDisplayID(number.uint32Value)
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(cgID)?.takeRetainedValue() else { continue }
            return CFUUIDCreateString(nil, uuid) as String?
        }
        return nil
    }
}
