import AppKit
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let menuBuilder = MenuBuilder()
    private var isRestoring = false

    let userDriverDelegate = SpaceManUserDriverDelegate()
    lazy var sparkleUpdater = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: userDriverDelegate
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLegacyPillColorKey()

        NSApp.setActivationPolicy(.accessory)

        _ = WindowCapture.ensureAccessibility()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.menuBarRocketImage()
        }

        menuBuilder.appDelegate = self
        statusItem.menu = menuBuilder.makeMenu()

        // Redraw the status icon when the display configuration changes — the
        // menu bar's effective thickness can shrink (e.g. moving from a notched
        // display to an external one) and leave the pre-rendered pill cropped.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPill() }
        }

        _ = sparkleUpdater  // touch lazy to start the updater
    }

    @objc func checkForUpdates(_ sender: Any?) {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        sparkleUpdater.checkForUpdates(sender)
    }

    // One-shot removal of the user-chosen pill colour key from the old design.
    // The new pill uses fixed grey/light colours; the key is dead weight.
    private func migrateLegacyPillColorKey() {
        let migrated = "didMigratePillColorV2"
        if UserDefaults.standard.bool(forKey: migrated) { return }
        UserDefaults.standard.removeObject(forKey: "menuBarPillColor")
        UserDefaults.standard.set(true, forKey: migrated)
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
        guard !isRestoring else { return }
        guard let id = sender.representedObject as? UUID,
              let snapshot = SnapshotStore.shared.snapshots.first(where: { $0.id == id }) else {
            return
        }

        isRestoring = true
        Task { @MainActor in
            defer { isRestoring = false }
            let result = await SnapshotRestore.restore(snapshot)

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
    }

    private func restoreSummary(for result: SnapshotRestore.Result, snapshot: Snapshot) -> String {
        var parts: [String] = []
        parts.append("Positioned \(result.matched) of \(snapshot.windows.count) window\(snapshot.windows.count == 1 ? "" : "s").")
        if result.launched > 0 {
            parts.append("Launched \(result.launched) app\(result.launched == 1 ? "" : "s") that weren't running.")
        }
        if result.spawned > 0 {
            parts.append("Spawned \(result.spawned) extra window\(result.spawned == 1 ? "" : "s").")
        }
        if result.skippedAppUninstalled > 0 {
            parts.append("\(result.skippedAppUninstalled) skipped — app not installed.")
        }
        if result.skippedLaunchTimeout > 0 {
            parts.append("\(result.skippedLaunchTimeout) skipped — app didn't surface a window in time.")
        }
        if result.skippedSpawnFailed > 0 {
            parts.append("\(result.skippedSpawnFailed) skipped — couldn't spawn more windows (app may not support it).")
        }
        return parts.joined(separator: "\n")
    }

    @objc func openManagement() {
        SnapshotManagementWindowHost.show()
    }

    @objc func openAbout() {
        JorvikAboutView.showWindow(
            appName: "SpaceMan",
            repoName: "SpaceMan",
            productPage: "utilities/spaceman"
        )
    }

    @objc func openSettings() {
        JorvikSettingsView.showWindow(appName: "SpaceMan") { [weak self] in
            SpaceManSettingsContent { [weak self] in
                self?.refreshPill()
            }
        }
    }

    func refreshPill() {
        statusItem?.button?.image = Self.menuBarRocketImage()
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
        // When the pill is enabled, give the rocket a wider canvas so the
        // pill wraps it with horizontal padding (canonical pattern).
        // When disabled, the rocket renders square as a template image.
        let pillEnabled = JorvikMenuBarPill.isEnabled
        let size: NSSize = pillEnabled
            ? NSSize(width: 30, height: 22)
            : NSSize(width: 22, height: 22)

        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // Pill background (read appearance per-paint so light/dark
            // and wallpaper-tint changes track without an observer).
            let rocketColor: NSColor
            if pillEnabled {
                let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let pillColor: NSColor = isDark
                    ? NSColor(white: 0.85, alpha: 1.0)
                    : NSColor(white: 0.20, alpha: 0.85)
                let path = NSBezierPath(
                    roundedRect: rect,
                    xRadius: rect.height / 2,
                    yRadius: rect.height / 2
                )
                pillColor.setFill()
                path.fill()
                rocketColor = isDark
                    ? NSColor(white: 0.10, alpha: 1.0)
                    : .white
            } else {
                rocketColor = .black  // template handling tints in/out of dark mode
            }

            ctx.saveGState()
            // Centre the 22×22 rocket coordinate system within the (possibly
            // wider) image rect, then rotate/scale about that centre. The
            // rocket's bezier paths below are still authored in their
            // original 0–22 coordinates.
            let cx = rect.width / 2
            let cy = rect.height / 2
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: -.pi / 4)
            ctx.scaleBy(x: 0.85, y: 0.85)
            ctx.translateBy(x: -11, y: -11)

            rocketColor.setFill()

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
        // Pill mode owns its colours end-to-end (no template tinting);
        // bare-glyph mode uses template behaviour for light/dark adaptation.
        image.isTemplate = !pillEnabled
        return image
    }
}

// MARK: - Sparkle User Driver Delegate

/// Keeps Sparkle's update UI visible across the whole session, including
/// when the user switches to another app mid-download. See KB:
/// `conventions/sparkle-integration.md` §6 for the rationale.
final class SpaceManUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    private var sessionObserver: NSObjectProtocol?
    private var elevatedWindows: [(window: NSWindow, originalLevel: NSWindow.Level)] = []

    func standardUserDriverWillShowModalAlert() {
        bringForward()
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        startFocusGuard()
        bringForward()
    }

    func standardUserDriverWillFinishUpdateSession() {
        stopFocusGuard()
    }

    private func bringForward() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        elevateAllWindows()
    }

    private func startFocusGuard() {
        guard sessionObserver == nil else { return }
        sessionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.bringForward()
        }
    }

    private func stopFocusGuard() {
        if let obs = sessionObserver {
            NotificationCenter.default.removeObserver(obs)
            sessionObserver = nil
        }
        for entry in elevatedWindows {
            entry.window.level = entry.originalLevel
        }
        elevatedWindows.removeAll()
    }

    private func elevateAllWindows() {
        for window in NSApp.windows where window.isVisible && window.level == .normal {
            elevatedWindows.append((window, window.level))
            window.level = .floating
        }
    }
}
