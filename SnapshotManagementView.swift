import AppKit
import SwiftUI

/// Management window for the full snapshot library. Groups snapshots by
/// display configuration (count + display UUIDs) and shows the space ID
/// on each row. Inline rename via TextField; delete is confirmed.
struct SnapshotManagementView: View {
    @State private var snapshots: [Snapshot] = SnapshotStore.shared.snapshots
    @State private var pendingDeletion: Snapshot?

    var body: some View {
        VStack(spacing: 0) {
            Text("Manage Snapshots")
                .font(.headline)
                .padding(.top, 16)
                .padding(.bottom, 8)

            if snapshots.isEmpty {
                Spacer()
                Text("No snapshots saved yet.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(groups, id: \.signature) { group in
                        Section(header: Text(group.label)) {
                            ForEach(group.snapshots) { snapshot in
                                row(for: snapshot)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            Divider()

            HStack {
                Text("\(snapshots.count) snapshot\(snapshots.count == 1 ? "" : "s") total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                // Zero-size escape-action button — registers the Esc
                // key as "close window" without needing a visible Cancel.
                Button("") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
            )
        }
        .frame(minWidth: 520, minHeight: 380)
        .alert(item: $pendingDeletion) { snapshot in
            Alert(
                title: Text("Delete '\(snapshot.name)'?"),
                message: Text("This snapshot will be permanently removed. This can't be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    SnapshotStore.shared.delete(id: snapshot.id)
                    refresh()
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for snapshot: Snapshot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: Binding(
                    get: { snapshot.name },
                    set: { newName in
                        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        SnapshotStore.shared.rename(id: snapshot.id, to: trimmed)
                        refresh()
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(.body, weight: .medium))

                HStack(spacing: 8) {
                    Text(Self.timestampFormatter.string(from: snapshot.createdAt))
                    Text("·")
                    Text("\(snapshot.windows.count) window\(snapshot.windows.count == 1 ? "" : "s")")
                    Text("·")
                    Text("Space #\(snapshot.fingerprint.managedSpaceID)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                pendingDeletion = snapshot
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete snapshot")
        }
        .padding(.vertical, 2)
    }

    // MARK: - Grouping

    private struct Group {
        let signature: String
        let label: String
        let snapshots: [Snapshot]
    }

    private var groups: [Group] {
        let byDisplay = Dictionary(grouping: snapshots) { $0.fingerprint.displaySignature }
        return byDisplay
            .map { (signature, shots) in
                let count = shots.first?.fingerprint.displayCount ?? 0
                let label = "\(count) display\(count == 1 ? "" : "s")"
                let sorted = shots.sorted { $0.createdAt > $1.createdAt }
                return Group(signature: signature, label: label, snapshots: sorted)
            }
            .sorted { $0.label < $1.label }
    }

    // MARK: - Helpers

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    private func refresh() {
        snapshots = SnapshotStore.shared.snapshots
    }
}

// MARK: - Window host

enum SnapshotManagementWindowHost {
    static var existingWindow: NSWindow?
    static let delegate = AutoCloseWindowDelegate()

    @MainActor
    static func show() {
        if let window = existingWindow {
            // Refresh content in case snapshots changed while closed
            let controller = NSHostingController(rootView: SnapshotManagementView())
            window.contentViewController = controller
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: SnapshotManagementView())
        controller.view.layoutSubtreeIfNeeded()

        let window = NSWindow(contentViewController: controller)
        window.title = "Manage Snapshots"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 420))
        window.delegate = delegate
        JorvikWindowHelper.centreOnActiveDisplay(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        existingWindow = window
    }
}

/// Closes the window as soon as it loses key status. Used to give the
/// Manage Snapshots window popover-like behaviour — click outside and it
/// disappears.
final class AutoCloseWindowDelegate: NSObject, NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        (notification.object as? NSWindow)?.close()
    }
}

