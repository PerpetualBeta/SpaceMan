import AppKit
import ApplicationServices

/// Attempts to spawn extra windows for a running app via its menu bar.
///
/// There's no universal AX action for "make another window", so this
/// walks the app's menu bar searching for an enabled menu item with a
/// title like "New Window", "New Finder Window", "New Browser Window",
/// or broader "New …" / "New … Window" patterns, then triggers it via
/// `AXPress`.
///
/// The caller is responsible for waiting for the window count to
/// increase after each successful call.
enum WindowSpawner {

    /// Press the first matching "new window" menu item. Returns true if
    /// a candidate was found and AXPress reported success.
    @MainActor
    static func spawnWindow(for app: NSRunningApplication) -> Bool {
        let appEl = AXUIElementCreateApplication(app.processIdentifier)

        var mbRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appEl, kAXMenuBarAttribute as CFString, &mbRef) == .success,
              let menuBar = mbRef as! AXUIElement? else {
            return false
        }

        guard let item = findNewWindowItem(in: menuBar) else {
            return false
        }

        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    // MARK: - Search

    /// Preferred exact titles (fast path). These cover the common apps
    /// that have a specific "New X Window" label rather than the generic
    /// "New Window".
    private static let preferredTitles: Set<String> = [
        "New Window",
        "New Finder Window",
        "New Browser Window",
        "New Chrome Window",
        "New Safari Window",
        "New Private Window",
        "New Tab Group Window",
        "New Terminal Window",
    ]

    private static func findNewWindowItem(in root: AXUIElement) -> AXUIElement? {
        // First pass — exact preferred matches only.
        if let hit = search(in: root, matches: { preferredTitles.contains($0) }) {
            return hit
        }
        // Second pass — broader heuristic: "New " prefix and "Window" in
        // the title. This catches app-specific labels ("New Mail Window",
        // "New Script Editor Window", etc.) without matching "New File"
        // or "New Folder" which open documents rather than top-level windows.
        return search(in: root, matches: { title in
            title.hasPrefix("New ") && title.contains("Window")
        })
    }

    /// Depth-first search through AX menu structure. Only returns
    /// enabled menu items whose title matches `matches`.
    private static func search(in element: AXUIElement, matches: (String) -> Bool) -> AXUIElement? {
        let role = stringAttribute(element, kAXRoleAttribute)

        if role == (kAXMenuItemRole as String) {
            let title = stringAttribute(element, kAXTitleAttribute) ?? ""
            if matches(title), isEnabled(element) {
                return element
            }
        }

        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        for child in children {
            if let hit = search(in: child, matches: matches) {
                return hit
            }
        }
        return nil
    }

    private static func stringAttribute(_ el: AXUIElement, _ name: String) -> String? {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func isEnabled(_ el: AXUIElement) -> Bool {
        var ref: AnyObject?
        guard AXUIElementCopyAttributeValue(el, kAXEnabledAttribute as CFString, &ref) == .success,
              let flag = ref as? Bool else { return true } // assume enabled if unknown
        return flag
    }
}
