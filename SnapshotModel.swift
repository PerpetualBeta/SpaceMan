import Foundation

/// Visibility state of a captured window.
enum WindowState: String, Codable {
    case normal
    case minimised
    case hidden
}

/// Per-window record inside a snapshot. Order-within-app is preserved via
/// the `orderInApp` field so Phase 4 restore can match windows back to
/// their source slot even when an app has multiple windows.
struct WindowRecord: Codable, Equatable {
    let bundleID: String
    let appName: String
    let title: String
    let frame: CGRect
    /// UUID string of the display this window was on at capture. Match on
    /// restore so windows land on the right monitor in multi-display setups.
    let displayUUID: String
    let state: WindowState
    /// 0-based rank among this app's windows at capture time (by window
    /// number ascending — roughly creation order).
    let orderInApp: Int
}

/// A named snapshot belonging to a specific workspace fingerprint.
struct Snapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var fingerprint: WorkspaceFingerprint
    var windows: [WindowRecord]

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), fingerprint: WorkspaceFingerprint, windows: [WindowRecord]) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.fingerprint = fingerprint
        self.windows = windows
    }
}
