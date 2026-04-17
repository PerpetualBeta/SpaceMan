import AppKit

/// Builds the dynamic menu-bar menu. Rebuilt every time the menu is about
/// to open so the list of snapshots always matches the current workspace.
final class MenuBuilder: NSObject, NSMenuDelegate {

    weak var appDelegate: AppDelegate?

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let fingerprint = WorkspaceFingerprint.current()
        let snapshots = fingerprint.map { SnapshotStore.shared.snapshots(matching: $0) } ?? []

        // About — first item, per Jorvik menu pattern
        let about = NSMenuItem(title: "About SpaceMan", action: #selector(AppDelegate.openAbout), keyEquivalent: "")
        about.target = appDelegate
        menu.addItem(about)

        menu.addItem(.separator())

        // Capture action
        let capture = NSMenuItem(title: "Snapshot current workspace…", action: #selector(AppDelegate.captureSnapshot), keyEquivalent: "")
        capture.target = appDelegate
        capture.isEnabled = (fingerprint != nil)
        menu.addItem(capture)

        menu.addItem(.separator())

        if snapshots.isEmpty {
            let empty = NSMenuItem(title: "No snapshots for current workspace", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for snapshot in snapshots {
                let item = NSMenuItem(
                    title: snapshot.name,
                    action: #selector(AppDelegate.restoreSnapshot(_:)),
                    keyEquivalent: ""
                )
                item.target = appDelegate
                item.representedObject = snapshot.id
                // Phase 2+ will flip this to enabled. For now the menu
                // lists them but doesn't act (restore is not yet built).
                item.isEnabled = false
                item.toolTip = "Restore not yet implemented (Phase 2)"
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let manage = NSMenuItem(title: "Manage snapshots…", action: #selector(AppDelegate.openManagement), keyEquivalent: "")
        manage.target = appDelegate
        manage.isEnabled = false
        manage.toolTip = "Coming in Phase 5"
        menu.addItem(manage)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit SpaceMan", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }
}
