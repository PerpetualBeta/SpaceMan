import AppKit

@MainActor
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
            SpaceManDialog.showMessage(
                title: "Can't snapshot",
                body: "Couldn't identify the current workspace. Is macOS set up normally?"
            )
            return
        }

        guard let name = promptForName() else { return }

        let windows = WindowCapture.captureCurrentSpace()
        let snapshot = Snapshot(name: name, fingerprint: fingerprint, windows: windows)
        SnapshotStore.shared.add(snapshot)

        SpaceManDialog.showMessage(
            title: "Snapshot saved",
            body: "Captured \(windows.count) window\(windows.count == 1 ? "" : "s") as '\(name)'."
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
        SpaceManDialog.promptText(
            title: "Name this snapshot",
            body: "A short label shown in the menu. Up to 5 snapshots can be kept per workspace — the oldest is evicted when you exceed that.",
            placeholder: "e.g. Coding, Focus, Comms",
            confirmTitle: "Save"
        )
    }
}
