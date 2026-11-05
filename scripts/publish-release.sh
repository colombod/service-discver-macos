#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${RELEASE_NOTES_FILE:?Set RELEASE_NOTES_FILE to the reviewed Markdown release notes}"
APP="dist/Service Discovery.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
REPOSITORY=colombod/service-discver-macos
# This command publishes the previously prepared artifacts. It does not merge code.
gh release create "v$VERSION" "dist/release/Service-Discovery-$VERSION.zip" \
  dist/release/SHA256SUMS.txt \
  --repo "$REPOSITORY" --target "$(git rev-parse HEAD)" \
  --title "Service Discovery $VERSION" --notes-file "$RELEASE_NOTES_FILE"
# A stable feed release hosts the mutable, signed appcast. This release is never latest.
if ! gh release view updates --repo "$REPOSITORY" >/dev/null 2>&1; then
  gh release create updates --repo "$REPOSITORY" --target "$(git rev-parse HEAD)" \
    --title 'macOS update feed' --notes 'Signed Sparkle update feed. Download the app from a versioned release.' --latest=false
fi
gh release upload updates dist/release/appcast.xml --clobber --repo "$REPOSITORY"
