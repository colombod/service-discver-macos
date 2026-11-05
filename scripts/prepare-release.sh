#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="dist/Service Discovery.app"
SCRATCH="${SWIFT_SCRATCH_PATH:-.build}"
TOOLS="$SCRATCH/artifacts/sparkle/Sparkle/bin"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
codesign --verify --deep --strict "$APP"
CERT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/service-discovery-cert.XXXXXX")
trap 'rm -rf "$CERT_DIR"' EXIT
codesign --display --extract-certificates="$CERT_DIR/certificate-" "$APP"
openssl x509 -inform DER -in "$CERT_DIR/certificate-0" -noout -subject | rg -q 'CN=Developer ID Application:' || {
  echo 'Build with SIGN_IDENTITY set to your Developer ID Application identity before preparing a release.' >&2; exit 1;
}
PUBLIC_KEY=$("$TOOLS/generate_keys" --account service-discver-macos -p)
BUNDLE_KEY=$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$APP/Contents/Info.plist")
[[ "$PUBLIC_KEY" == "$BUNDLE_KEY" ]] || { echo 'The Keychain update key does not match this app.' >&2; exit 1; }
xcrun stapler validate "$APP"
spctl --assess --type execute "$APP"
mkdir -p dist/release
ARCHIVE="Service-Discovery-$VERSION.zip"
ditto -c -k --keepParent "$APP" "dist/release/$ARCHIVE"
SIGNATURE=$("$TOOLS/sign_update" --account service-discver-macos "dist/release/$ARCHIVE")
export RELEASE_VERSION="$VERSION" RELEASE_BUILD="$BUILD" RELEASE_ARCHIVE="$ARCHIVE" RELEASE_SIGNATURE="$SIGNATURE"
python3 scripts/write-appcast.py
python3 scripts/verify-release.py "$TOOLS/sign_update" "dist/release/$ARCHIVE"
"$TOOLS/sign_update" --account service-discver-macos dist/release/appcast.xml
"$TOOLS/sign_update" --account service-discver-macos --verify dist/release/appcast.xml
shasum -a 256 "dist/release/$ARCHIVE" dist/release/appcast.xml > dist/release/SHA256SUMS.txt
echo "Prepared dist/release/$ARCHIVE and dist/release/appcast.xml"
echo 'Publish only after reviewing the app and release notes. See docs/RELEASING.md.'
