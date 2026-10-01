# Kaji Distribution

## Current State

Kaji is **ad-hoc signed only — not Developer ID signed and not notarized**. This is an explicitly accepted testing-phase trade-off.

Each `v*` tag runs `.github/workflows/release.yml` on macOS: tag must equal `Info.plist` `CFBundleShortVersionString`, tests run, `KAJI_UNIVERSAL=1 scripts/build-app.sh` builds arm64 + x86_64 per arch and merges with `lipo`, the bundle is ad-hoc signed and verified, then `Kaji.app` is zipped with `ditto --keepParent`. The release is published only if every step succeeds.

Release asset contract:

- Exactly one `.zip` asset, `Kaji.app.zip`, for manual downloads and older updaters.
- The archive root contains only `Kaji.app`; the app is universal (Apple Silicon and Intel).
- A data-only `update.json` asset is served at `https://github.com/MisterBrookT/kaji/releases/latest/download/update.json`. Schema 1 contains the stable version/tag, build number, canonical release URL, full source commit and Markdown notes. `scripts/update-manifest.py` generates it from the verified bundle and tag.
- The current updater reads that static feed, not the GitHub REST API. A missing/unreachable feed may fall back to the public latest-release redirect; malformed metadata fails closed.
- Installation builds the approved tag locally and verifies the manifest commit when supplied. The running app remains open until staging and validation succeed. Replacement retains a rollback bundle and logs failures; it never silently installs a different `latest` version.
- The release stays draft during asset upload and is published only after both assets are uploaded.

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

Public users should use the install command until notarized builds exist.

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

- Apple Developer ID: https://developer.apple.com/developer-id/
- Apple notarization docs: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Apple notarization troubleshooting: https://developer.apple.com/documentation/security/resolving-common-notarization-issues
- Apple Developer Program enrollment: https://developer.apple.com/programs/enroll/
- Apple support, opening non-notarized apps: https://support.apple.com/en-us/102445
