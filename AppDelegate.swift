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
            button.image = Self.menuBarRocketImage()
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
        guard let id = sender.representedObject as? UUID,
              let snapshot = SnapshotStore.shared.snapshots.first(where: { $0.id == id }) else {
            return
        }

        let result = SnapshotRestore.restore(snapshot)

        if result.skippedAccessibility {
            SpaceManDialog.showMessage(
                title: "Accessibility required",
                body: "Grant SpaceMan Accessibility permission in System Settings → Privacy & Security → Accessibility, then try again."
            )
            return
        }

        let body = restoreSummary(for: result, snapshot: snapshot)
        SpaceManDialog.showMessage(title: "Restored '\(snapshot.name)'", body: body)
    }

    private func restoreSummary(for result: SnapshotRestore.Result, snapshot: Snapshot) -> String {
        var parts: [String] = []
        parts.append("Positioned \(result.matched) of \(snapshot.windows.count) window\(snapshot.windows.count == 1 ? "" : "s").")
        if result.skippedAppMissing > 0 {
            parts.append("\(result.skippedAppMissing) skipped — app not running (Phase 3).")
        }
        if result.skippedWindowMissing > 0 {
            parts.append("\(result.skippedWindowMissing) skipped — app has fewer windows than snapshot (Phase 4).")
        }
        return parts.joined(separator: "\n")
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

    @objc func openSettings() {
        JorvikSettingsView.showWindow(
            appName: "SpaceMan",
            updateChecker: updateChecker
        ) { [weak self] in
            SpaceManSettingsContent { [weak self] in
                self?.refreshPill()
            }
        }
    }

    func refreshPill() {
        guard let button = statusItem?.button else { return }
        JorvikMenuBarPill.apply(to: button)
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

    /// A monochrome rocket silhouette tilted 45° right, rendered as a
    /// template image so macOS tints it for the current menu-bar state.
    ///
    /// Drawn at 22×22: pointed nose cone, capsule body with a round
    /// porthole, two swept-back fins. A slight scale-down keeps the
    /// rotated shape within the canvas bounds.
    private static func menuBarRocketImage() -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            // Rotate 45° clockwise (negative angle in Y-up coords) about
            // the centre, then scale in slightly so fin tips don't clip.
            ctx.translateBy(x: 11, y: 11)
            ctx.rotate(by: -.pi / 4)
            ctx.scaleBy(x: 0.85, y: 0.85)
            ctx.translateBy(x: -11, y: -11)

            NSColor.black.setFill()

            // Body — vertical capsule (rounded-rect)
            let body = NSBezierPath(
                roundedRect: NSRect(x: 8, y: 4, width: 6, height: 12),
                xRadius: 3,
                yRadius: 3
            )
            body.fill()

            // Nose cone — sharp triangle on top
            let nose = NSBezierPath()
            nose.move(to: NSPoint(x: 11, y: 20.5))
            nose.line(to: NSPoint(x: 7.5, y: 14))
            nose.line(to: NSPoint(x: 14.5, y: 14))
            nose.close()
            nose.fill()

            // Left fin — swept-back triangle
            let leftFin = NSBezierPath()
            leftFin.move(to: NSPoint(x: 8, y: 9))
            leftFin.line(to: NSPoint(x: 2.5, y: 3))
            leftFin.line(to: NSPoint(x: 8, y: 5))
            leftFin.close()
            leftFin.fill()

            // Right fin — mirror of left
            let rightFin = NSBezierPath()
            rightFin.move(to: NSPoint(x: 14, y: 9))
            rightFin.line(to: NSPoint(x: 19.5, y: 3))
            rightFin.line(to: NSPoint(x: 14, y: 5))
            rightFin.close()
            rightFin.fill()

            // Exhaust flame — small downward trapezoid centred
            let flame = NSBezierPath()
            flame.move(to: NSPoint(x: 9.5, y: 4))
            flame.line(to: NSPoint(x: 11, y: 1))
            flame.line(to: NSPoint(x: 12.5, y: 4))
            flame.close()
            flame.fill()

            // Porthole — small circular cutout on the body
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let porthole = NSBezierPath(ovalIn: NSRect(x: 9.5, y: 11, width: 3, height: 3))
            porthole.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            ctx.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }
}
