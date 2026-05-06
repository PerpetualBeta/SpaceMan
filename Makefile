# SpaceMan — workspace fingerprint + window restore across Spaces.
#
# Release pipeline delegated to the shared `release.mk` from
# PerpetualBeta/jorvik-release. swiftc project, embedded Sparkle,
# dual-ship (.zip + .pkg).

BUNDLE_NAME      := SpaceMan
BUNDLE_TYPE      := app
PRODUCT_NAME     := SpaceMan.app
BUNDLE_ID        := cc.jorviksoftware.SpaceMan
BUILD_SYSTEM     := swiftc

SWIFT_FRAMEWORKS := Cocoa SwiftUI ServiceManagement ApplicationServices
SWIFT_SOURCES    := main.swift \
                    AppDelegate.swift \
                    CGSPrivate.swift \
                    WorkspaceFingerprint.swift \
                    SnapshotModel.swift \
                    WindowCapture.swift \
                    SnapshotStore.swift \
                    SnapshotRestore.swift \
                    WindowSpawner.swift \
                    MenuBuilder.swift \
                    DialogWindow.swift \
                    SpaceManSettingsContent.swift \
                    SnapshotManagementView.swift

PACKAGE_TYPE     := zip
ALSO_SHIP_PKG    := true
EMBEDDED_FRAMEWORKS := Sparkle
ENTITLEMENTS     := SpaceMan.entitlements

include ../jorvik-release/release.mk
