import AppKit
import Foundation

/// Persists snapshots to disk. Flat list — each snapshot carries its own
/// fingerprint, so menus and settings filter by matching fingerprint at
/// query time rather than pre-grouping on disk.
///
/// Storage: ~/Library/Application Support/JorvikSpaceMan/snapshots.json
/// A `.bak` copy is written before every save as a safety net (same
/// pattern as JorvikReleaseManager after the 2026-04-16 data-loss fix).
final class SnapshotStore {

    static let shared = SnapshotStore()

    private(set) var snapshots: [Snapshot] = []

    private let configURL: URL
    private let backupURL: URL

    /// Max snapshots per workspace fingerprint. Taking a sixth evicts the
    /// oldest to keep the menu lean.
    static let maxPerWorkspace = 5

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("JorvikSpaceMan")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        configURL = dir.appendingPathComponent("snapshots.json")
        backupURL = dir.appendingPathComponent("snapshots.bak.json")
        load()
    }

    // MARK: - Query

    func snapshots(matching fingerprint: WorkspaceFingerprint) -> [Snapshot] {
        snapshots.filter { $0.fingerprint == fingerprint }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Mutation

    /// Add a snapshot. Evicts the oldest matching-workspace snapshot if
    /// that would exceed `maxPerWorkspace`.
    func add(_ snapshot: Snapshot) {
        let matching = snapshots(matching: snapshot.fingerprint)
        if matching.count >= Self.maxPerWorkspace, let oldest = matching.first {
            snapshots.removeAll { $0.id == oldest.id }
        }
        snapshots.append(snapshot)
        save()
    }

    func rename(id: UUID, to newName: String) {
        guard let idx = snapshots.firstIndex(where: { $0.id == id }) else { return }
        snapshots[idx].name = newName
        save()
    }

    func delete(id: UUID) {
        snapshots.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            snapshots = []
            return
        }
        do {
            let data = try Data(contentsOf: configURL)
            snapshots = try JSONDecoder().decode([Snapshot].self, from: data)
        } catch {
            NSLog("SpaceMan: failed to load snapshots — \(error)")
            // Preserve the corrupt file so nothing is lost silently.
            let stamp = DateFormatter.iso8601Compact.string(from: Date())
            let corrupt = configURL.deletingLastPathComponent()
                .appendingPathComponent("snapshots-corrupt-\(stamp).json")
            try? FileManager.default.copyItem(at: configURL, to: corrupt)
            snapshots = []
            DispatchQueue.main.async { Self.alertLoadFailure(backup: corrupt.path) }
        }
    }

    private func save() {
        // Rolling .bak before every write
        if FileManager.default.fileExists(atPath: configURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: configURL, to: backupURL)
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshots)
            try data.write(to: configURL, options: .atomic)
        } catch {
            NSLog("SpaceMan: failed to save snapshots — \(error)")
        }
    }

    private static func alertLoadFailure(backup path: String) {
        let alert = NSAlert()
        alert.messageText = "Could not read SpaceMan snapshots"
        alert.informativeText = "The snapshot file couldn't be decoded. A copy has been saved to:\n\n\(path)\n\nYour snapshot list has been reset for this session. Re-create them, or restore the backup manually."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private extension DateFormatter {
    static let iso8601Compact: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
