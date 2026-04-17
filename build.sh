#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="SpaceMan"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"

echo "Building $APP_NAME..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

swiftc -O -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    "$SCRIPT_DIR/main.swift" \
    "$SCRIPT_DIR/AppDelegate.swift" \
    "$SCRIPT_DIR/CGSPrivate.swift" \
    "$SCRIPT_DIR/WorkspaceFingerprint.swift" \
    "$SCRIPT_DIR/SnapshotModel.swift" \
    "$SCRIPT_DIR/WindowCapture.swift" \
    "$SCRIPT_DIR/SnapshotStore.swift" \
    "$SCRIPT_DIR/SnapshotRestore.swift" \
    "$SCRIPT_DIR/MenuBuilder.swift" \
    "$SCRIPT_DIR/DialogWindow.swift" \
    "$SCRIPT_DIR/SpaceManSettingsContent.swift" \
    "$SCRIPT_DIR"/JorvikKit/*.swift \
    -framework Cocoa \
    -framework SwiftUI \
    -framework ServiceManagement \
    -framework ApplicationServices

cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign "Developer ID Application: Jonthan Hollin (EG86BCGUE7)" \
    --options runtime \
    --timestamp \
    "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
