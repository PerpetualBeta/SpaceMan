#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="SpaceMan"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
SIGN_ID="Developer ID Application: Jonthan Hollin (EG86BCGUE7)"

echo "Building $APP_NAME..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks"

# Embed Sparkle.framework into the bundle
cp -R "$SCRIPT_DIR/Sparkle.framework" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

# Compile main binary, linking Sparkle from the framework dir.
# rpath @executable_path/../Frameworks lets the runtime find the embedded framework.
swiftc -O -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    "$SCRIPT_DIR/main.swift" \
    "$SCRIPT_DIR/AppDelegate.swift" \
    "$SCRIPT_DIR/CGSPrivate.swift" \
    "$SCRIPT_DIR/WorkspaceFingerprint.swift" \
    "$SCRIPT_DIR/SnapshotModel.swift" \
    "$SCRIPT_DIR/WindowCapture.swift" \
    "$SCRIPT_DIR/SnapshotStore.swift" \
    "$SCRIPT_DIR/SnapshotRestore.swift" \
    "$SCRIPT_DIR/WindowSpawner.swift" \
    "$SCRIPT_DIR/MenuBuilder.swift" \
    "$SCRIPT_DIR/DialogWindow.swift" \
    "$SCRIPT_DIR/SpaceManSettingsContent.swift" \
    "$SCRIPT_DIR/SnapshotManagementView.swift" \
    "$SCRIPT_DIR"/JorvikKit/*.swift \
    -F "$SCRIPT_DIR" \
    -framework Cocoa \
    -framework SwiftUI \
    -framework ServiceManagement \
    -framework ApplicationServices \
    -framework Sparkle \
    -Xlinker -rpath -Xlinker '@executable_path/../Frameworks'

cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Sign Sparkle's internals first (XPC services, helper apps, the framework
# binary itself). They each need to be re-signed under our Developer ID so
# the codesign chain matches when we sign the outer app.
SP="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B"

codesign --force --sign "$SIGN_ID" --options runtime --timestamp \
    "$SP/XPCServices/Downloader.xpc"
codesign --force --sign "$SIGN_ID" --options runtime --timestamp \
    "$SP/XPCServices/Installer.xpc"
codesign --force --sign "$SIGN_ID" --options runtime --timestamp \
    "$SP/Updater.app"
codesign --force --sign "$SIGN_ID" --options runtime --timestamp \
    "$SP/Autoupdate"
codesign --force --sign "$SIGN_ID" --options runtime --timestamp \
    "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

# Sign the main app last with our entitlements (library validation disabled
# so Sparkle's helper tools can load).
codesign --force --sign "$SIGN_ID" \
    --entitlements "$SCRIPT_DIR/$APP_NAME.entitlements" \
    --options runtime \
    --timestamp \
    "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
