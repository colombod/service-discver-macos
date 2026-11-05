# Direct macOS releases

This app uses Developer ID distribution, outside the Mac App Store. Sparkle 2.10.1 checks a public, signed feed at `https://github.com/colombod/service-discver-macos/releases/download/updates/appcast.xml`. The app verifies the feed and the downloaded archive before extraction. Users choose when to install updates. Keep the bundle identifier and signing identity stable across releases.

## Credentials

- Developer ID Application certificate and private key: local macOS Keychain.
- Notarization: an existing `notarytool` Keychain profile for the same developer account.
- Sparkle private key: Keychain account `service-discver-macos`. The committed `SUPublicEDKey` is its public counterpart. Do not export or commit the private key.

The build script signs Sparkle helpers from the inside out, preserving XPC entitlements and framework symlinks, then signs the containing app. `codesign --deep` is used only for verification.

## Prepare a release

Increment the marketing version and the integer `CFBundleVersion` in `packaging/Info.plist`. Every new build must exceed previously published builds. Run the tests and use a clean, committed source tree for the final build.

```sh
swift test
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE="your-notarytool-profile" bash scripts/build-app.sh
bash scripts/prepare-release.sh
```

For a custom SwiftPM cache, pass the same `SWIFT_SCRATCH_PATH` to both scripts. The prepare step packages the notarized app, signs its ZIP and appcast, verifies both signatures, and writes SHA-256 checksums. It never retrieves private keys into command arguments or environment variables. The default build targets the current Mac’s architecture; the initial release is Apple silicon.

Notarization submissions are retained in `dist/notarization`. If Apple is still processing after 60 seconds, resume with `NOTARY_PROFILE=... bash scripts/notarize-app.sh` without rebuilding or resubmitting. After a completed release, preserve its artifacts before clearing `dist` for another release. A rejection requires inspection of Apple’s submission log.

## Publish

Review the exact artifacts and release notes. Merge source through a pull request, respecting main branch protection. Then publish those artifacts from the corresponding commit:

```sh
RELEASE_NOTES_FILE=docs/releases/0.1.0.md bash scripts/publish-release.sh
```

The command uploads the versioned ZIP first, then replaces the stable feed asset. It does not merge or change main. The `updates` release is a feed container, never the latest app release. Public feed/download URLs need no embedded GitHub token. Download the public ZIP and compare its hash against the prepared archive after publication.

The initial feed contains one version; Sparkle reports no newer update when the installed build equals that version. A real install-and-relaunch upgrade requires a later higher-build release and remains a separate acceptance check from signature verification.
