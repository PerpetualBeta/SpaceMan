import AppKit
import CoreGraphics

/// A stable identifier for "the current physical display arrangement + the
/// Mission Control space you're on". Two workspaces with the same
/// fingerprint are treated as equivalent for snapshot matching.
///
/// Built from:
///  - display count
///  - sorted list of physical display UUID strings
///  - the active Mission Control space ID on the main display (macOS CGS)
///
/// Space IDs are stable while the space exists; delete + recreate a space
/// and the ID changes. That's an accepted limitation per the SpaceMan
/// design — snapshots tied to a deleted space are expected to invalidate.
struct WorkspaceFingerprint: Codable, Equatable, Hashable {
    let displayCount: Int
    let displayUUIDs: [String]     // sorted ascending
    let managedSpaceID: UInt64

    var displaySignature: String {
        "\(displayCount):\(displayUUIDs.joined(separator: ","))"
    }

    /// Compute the fingerprint for the current machine state.
    static func current() -> WorkspaceFingerprint? {
        let uuids = displayUUIDs()
        guard !uuids.isEmpty else { return nil }
        guard let spaceID = currentManagedSpaceID() else { return nil }
        return WorkspaceFingerprint(
            displayCount: uuids.count,
            displayUUIDs: uuids,
            managedSpaceID: spaceID
        )
    }

    // MARK: - Display UUIDs

    private static func displayUUIDs() -> [String] {
        var uuids: [String] = []
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let cgID = CGDirectDisplayID(number.uint32Value)
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(cgID)?.takeRetainedValue() else { continue }
            guard let uuidStr = CFUUIDCreateString(nil, uuid) as String? else { continue }
            uuids.append(uuidStr)
        }
        return uuids.sorted()
    }

    // MARK: - Current space

    /// Walk the CGS managed-display-spaces structure, find the main display,
    /// return its `Current Space.ManagedSpaceID`. Returns nil if the shape
    /// changes in a future macOS (defensive coding — private API).
    private static func currentManagedSpaceID() -> UInt64? {
        let conn = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [[String: Any]] else { return nil }

        // Main display UUID — compare against each entry's "Display Identifier"
        let mainDisplayUUID: String? = {
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())?.takeRetainedValue() else { return nil }
            return CFUUIDCreateString(nil, uuid) as String?
        }()

        for display in displays {
            let identifier = display["Display Identifier"] as? String
            // On some macOS versions the main display is identified as
            // "Main" rather than a UUID. Treat both as acceptable matches.
            let isMain = (identifier == mainDisplayUUID) || (identifier == "Main")
            guard isMain else { continue }
            if let current = display["Current Space"] as? [String: Any],
               let id = current["ManagedSpaceID"] as? UInt64 {
                return id
            }
            if let current = display["Current Space"] as? [String: Any],
               let id = current["ManagedSpaceID"] as? Int {
                return UInt64(id)
            }
        }
        return nil
    }
}
