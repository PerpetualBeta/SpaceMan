import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let menuBuilder = MenuBuilder()
    let updateChecker = JorvikUpdateChecker(repoName: "SpaceMan")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        _ = WindowCapture.ensureAccessibility()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "SpaceMan")
            JorvikMenuBarPill.apply(to: button)
        }

        menuBuilder.appDelegate = self
        statusItem.menu = menuBuilder.makeMenu()

        updateChecker.checkOnSchedule()
    }

    // MARK: - Menu actions

    @objc func captureSnapshot() {
        guard let fingerprint = WorkspaceFingerprint.current() else {
            showAlert(title: "Can't snapshot", message: "Couldn't identify the current workspace. Is macOS set up normally?", style: .warning)
            return
        }

        guard let name = promptForName() else { return }

        let windows = WindowCapture.captureCurrentSpace()
        let snapshot = Snapshot(name: name, fingerprint: fingerprint, windows: windows)
        SnapshotStore.shared.add(snapshot)

        showAlert(
            title: "Snapshot saved",
            message: "Captured \(windows.count) window\(windows.count == 1 ? "" : "s") as '\(name)'.",
            style: .informational
        )
    }

    @objc func restoreSnapshot(_ sender: NSMenuItem) {
        // Phase 2 target. Stub for now.
        NSSound.beep()
    }

    @objc func openManagement() {
        // Phase 5 target.
        NSSound.beep()
    }

    @objc func openAbout() {
        JorvikAboutView.showWindow(
            appName: "SpaceMan",
            repoName: "SpaceMan",
            productPage: "utilities/spaceman"
        )
    }

    // MARK: - Helpers

    private func promptForName() -> String? {
        let alert = NSAlert()
        alert.messageText = "Name this snapshot"
        alert.informativeText = "A short label shown in the menu. Up to 5 snapshots can be kept per workspace — the oldest is evicted when you exceed that."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        input.placeholderString = "e.g. Coding, Focus, Comms"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
