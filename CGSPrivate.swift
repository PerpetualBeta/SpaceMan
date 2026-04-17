import CoreGraphics
import ApplicationServices

// MARK: - Private CoreGraphics / SkyLight bindings
//
// SpaceMan needs to identify the current Mission Control space so it can
// fingerprint a workspace. macOS exposes this via private CGS APIs. Calls
// are loaded via @_silgen_name (for statically-known symbols) or dlsym
// (for ones the linker can't locate at build time).

typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ conn: CGSConnectionID) -> CFArray?

/// Resolve an AXUIElement window reference to its CG window ID. Used to
/// cross-reference AX windows (which enumerate across all spaces) with
/// the CG on-screen list (which is current-space only) so snapshots only
/// capture windows the user can actually see right now.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError
