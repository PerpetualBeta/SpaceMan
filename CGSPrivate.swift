import CoreGraphics

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
