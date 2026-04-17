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
            // Newest first
            for snapshot in snapshots.reversed() {
                let item = NSMenuItem(
                    title: snapshot.name,
                    action: #selector(AppDelegate.restoreSnapshot(_:)),
                    keyEquivalent: ""
                )
                item.target = appDelegate
                item.representedObject = snapshot.id
                item.attributedTitle = Self.titleWithTimestamp(name: snapshot.name, date: snapshot.createdAt)
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

        let settings = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
        settings.target = appDelegate
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit SpaceMan", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    // MARK: - Formatting

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    /// Two-line menu title: the snapshot name in the default menu font,
    /// then a secondary-colour timestamp line in a smaller font.
    private static func titleWithTimestamp(name: String, date: Date) -> NSAttributedString {
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 0)
        ]
        let timestampAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize - 1),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let result = NSMutableAttributedString(string: name, attributes: nameAttrs)
        result.append(NSAttributedString(string: "   " + timestampFormatter.string(from: date), attributes: timestampAttrs))
        return result
    }
}
