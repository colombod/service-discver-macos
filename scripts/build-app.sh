#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SCRATCH="${SWIFT_SCRATCH_PATH:-.build}"
IDENTITY="${SIGN_IDENTITY:--}"
swift build -c release --scratch-path "$SCRATCH"
BIN_DIR="$(swift build -c release --scratch-path "$SCRATCH" --show-bin-path)"
APP="dist/Service Discovery.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp -f "$BIN_DIR/ServiceDiscovery" "$APP/Contents/MacOS/ServiceDiscovery"
cp -f packaging/Info.plist "$APP/Contents/Info.plist"
ditto "$SCRATCH/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
swift scripts/make-icon.swift dist/AppIcon.iconset
iconutil -c icns dist/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
SIGN_ARGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != "-" ]]; then SIGN_ARGS+=(--options runtime --timestamp); fi
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
# Sign nested code first; preserve the XPC service entitlements shipped by Sparkle.
codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$FRAMEWORK/XPCServices/Downloader.xpc"
codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$FRAMEWORK/XPCServices/Installer.xpc"
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK/Autoupdate"
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK/Updater.app"
codesign "${SIGN_ARGS[@]}" "$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  bash scripts/notarize-app.sh
fi
echo "Built $APP"
