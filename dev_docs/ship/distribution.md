# Kaji Distribution

## Current State

Kaji is **unsigned and not notarized**. Releases publish **source + written notes** only — no `.app.zip` asset.

Install path:

```sh
curl -fsSL https://raw.githubusercontent.com/MisterBrookT/kaji/main/install.sh | bash
```

`install.sh` clones the latest release tag, builds with `scripts/build-app.sh`, copies to `/Applications`, and clears the quarantine xattr.

Browser `.app.zip` downloads used to show: `Kaji is damaged and can't be opened…` — Gatekeeper + unsigned binary. That asset is intentionally gone.

GitHub Release notes are generated from commits when a version tag is pushed; they are not duplicated under `dev_docs/`.

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
