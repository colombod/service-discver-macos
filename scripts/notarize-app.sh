#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your existing notarytool Keychain profile}"
APP="dist/Service Discovery.app"
STATE=dist/notarization
mkdir -p "$STATE"
HASH=$(shasum -a 256 "$APP/Contents/MacOS/ServiceDiscovery" | awk '{print $1}')
if [[ -f "$STATE/executable.sha256" ]]; then
  [[ "$HASH" == "$(cat "$STATE/executable.sha256")" ]] || {
    echo 'The app changed since submission. Preserve the previous notarization directory before starting a new release.' >&2; exit 1;
  }
else
  printf '%s\n' "$HASH" > "$STATE/executable.sha256"
fi
codesign --verify --deep --strict "$APP"
if [[ ! -f "$STATE/submission.json" ]]; then
  ditto -c -k --keepParent "$APP" "$STATE/upload.zip"
  xcrun notarytool submit "$STATE/upload.zip" --keychain-profile "$NOTARY_PROFILE" --output-format json > "$STATE/submission.json"
fi
ID=$(python3 -c 'import json; print(json.load(open("dist/notarization/submission.json"))["id"])')
xcrun notarytool wait "$ID" --keychain-profile "$NOTARY_PROFILE" --timeout 60s --output-format json > "$STATE/result.json" || {
  echo "Notarization has not completed. Rerun this script to resume submission $ID; do not rebuild." >&2; exit 1;
}
python3 -c 'import json; d=json.load(open("dist/notarization/result.json")); assert d["status"] == "Accepted", d' 
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
