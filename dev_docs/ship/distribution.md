# Kaji Distribution

## Current State

Kaji is **ad-hoc signed only — not Developer ID signed and not notarized**. This is an explicitly accepted testing-phase trade-off.

Each `v*` tag runs `.github/workflows/release.yml` on macOS: tag must equal `Info.plist` `CFBundleShortVersionString`, tests run, `KAJI_UNIVERSAL=1 scripts/build-app.sh` builds arm64 + x86_64 per arch and merges with `lipo`, the bundle is ad-hoc signed and verified, then `Kaji.app` is zipped with `ditto --keepParent`. The release is published only if every step succeeds.

Release asset contract:

- One primary update archive, `Kaji.app.zip`, for manual downloads and updaters. Explicitly archived historical builds may have separately named assets; they are never the update target.
- The archive root contains only `Kaji.app`; the app is universal (Apple Silicon and Intel).
- A data-only `update.json` asset is served at `https://github.com/MisterBrookT/kaji/releases/latest/download/update.json`. Schema 1 contains the stable version/tag, build number, canonical release URL, full source commit and Markdown notes. `scripts/update-manifest.py` generates it from the verified bundle and tag.
- The current updater reads that static feed, not the GitHub REST API. A missing/unreachable feed may fall back to the public latest-release redirect; malformed metadata fails closed.
- Configured app bundles use Sparkle 2.10 for user-initiated binary updates. `appcast.xml` is served alongside the JSON at the same public GitHub release. Both the feed and archive are Ed25519-signed; the embedded `SUPublicEDKey` verifies them before extraction. No GitHub account/token is required by the app.
- Sparkle is initialized lazily on an explicit check, with automatic checks/downloads and system-profile submission disabled. It owns confirmation, installation, quit and relaunch. The lightweight JSON check remains the passive version cue.
- Legacy/unconfigured hosts keep the pinned source fallback: build the approved tag and verify its manifest commit, stage/validate before quitting, retain a rollback bundle and expose failure logs. Source installation also bootstraps existing clients that do not yet contain Sparkle.
- The release stays draft during upload and is published only after the ZIP, JSON and signed appcast are verified and uploaded.

Release notes come from `scripts/release-notes.sh` (tested by `Tests/release/test_release_notes.sh`): commit subjects since the previous tag are grouped into Fixed / Added / Removed / Changed by leading verb or conventional-commit type; merge/release/bump/chore commits are dropped; an unsigned/unnotarized install notice is always appended. Notes quality depends on commit subjects starting with a clear verb. Per-release working notes live in `.dev/`, not `dev_docs/`.

Source install remains available:

```sh
curl -fsSL https://raw.githubusercontent.com/MisterBrookT/kaji/main/install.sh | bash
```

Browser-downloaded zips may show `Kaji is damaged and can't be opened…` (Gatekeeper + quarantine). The source updater builds with ad-hoc signing and clears quarantine before replacement. It requires working Git, Swift and Python 3; missing prerequisites are reported without opening an installation or administrator prompt.

## Temporary Internal Fix

For trusted testers only:

```sh
xattr -dr com.apple.quarantine /Applications/Kaji.app
open /Applications/Kaji.app
```

Public users should use the install command until notarized builds exist. Sparkle does not remove this **first-install** limitation: packaging the same app as a DMG instead of ZIP does not confer Gatekeeper trust.

## Sparkle Signing (Independent of Apple Signing)

Sparkle's Ed25519 key authenticates updates, not Apple's first-launch trust. Ad-hoc-signed hosts can receive properly signed Sparkle updates without an Apple Developer membership. Developer ID and notarization remain necessary for warning-free browser-downloaded first installation.

The public update key is committed in `Info.plist`. The private key is stored outside the repository and as the repository's `KAJI_SPARKLE_PRIVATE_KEY` GitHub Actions secret. Never commit it, emit it to logs, or use Sparkle tools' implicit login-Keychain lookup. `scripts/sparkle-appcast.py` requires an explicit nonempty key file, uses SDK tools, and checks version/build, canonical download URL, length, archive signature and feed signature before publication. The release job creates a mode-0600 temporary file and removes it on exit. Keep an independent secure backup: losing this key without a Developer ID trust chain prevents normal key rotation.

The manually assembled SwiftPM app embeds the universal Sparkle framework and its helper/XPC code, preserves framework symlinks, supplies a Frameworks rpath and signs nested code inside-out. Local builds stay ad-hoc and non-interactive; no keychain is discovered, created or unlocked.

## Proper Release Path

1. Join Apple Developer Program.
   - Individual is enough for a personal OSS app.
   - Organization requires legal entity details and D-U-N-S.
   - Apple lists membership as 99 USD per year, or local currency where available.

2. Create certificates in Apple Developer account:
   - `Developer ID Application`: sign `Kaji.app` for outside-Mac-App-Store distribution.
   - Optional `Developer ID Installer`: only needed if shipping `.pkg`.

3. Update bundle identity before first signed release:
   - Current: `dev.kaji`.
   - Better: `com.misterbrookt.kaji` or another stable domain-style identifier.

4. Sign app with hardened runtime:

```sh
codesign --force --deep --options runtime --timestamp \
  --sign "Developer ID Application: <Name> (<TeamID>)" \
  dist/Kaji.app
```

5. Notarize:

```sh
ditto -c -k --keepParent dist/Kaji.app dist/Kaji.app.zip
xcrun notarytool submit dist/Kaji.app.zip \
  --apple-id "<apple-id>" \
  --team-id "<team-id>" \
  --password "<app-specific-password>" \
  --wait
```

6. Staple ticket:

```sh
xcrun stapler staple dist/Kaji.app
```

7. Verify:

```sh
codesign --verify --deep --strict --verbose=2 dist/Kaji.app
spctl -a -vvv -t execute dist/Kaji.app
```

8. Zip the stapled app and upload it as the GitHub Release asset.

## CI Secrets Needed Later

For GitHub Actions notarized releases:

- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

Safer alternative: App Store Connect API key for `notarytool`.


## References

- Sparkle setup/security: https://sparkle-project.org/documentation/
- Sparkle installer security: https://github.com/sparkle-project/Sparkle/blob/2.x/Documentation/Installation.md
- Apple Developer ID: https://developer.apple.com/developer-id/
- Apple notarization docs: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Apple notarization troubleshooting: https://developer.apple.com/documentation/security/resolving-common-notarization-issues
- Apple Developer Program enrollment: https://developer.apple.com/programs/enroll/
- Apple support, opening non-notarized apps: https://support.apple.com/en-us/102445
