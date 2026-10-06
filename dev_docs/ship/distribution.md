# Kaji Distribution

## Current State

Kaji is **ad-hoc signed only — not Developer ID signed and not notarized**.

**Permanent decision: never use Developer ID signing for Kaji.** Do not plan Apple Developer enrollment, Developer ID certificates, notarization, or a future notarized release as the solution to installation failures. The first-install path is a local source build; improve its prerequisite checks and failure messages instead. Browser-download Gatekeeper warnings are an accepted distribution constraint, not temporary release debt.

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

## Trusted Manual Downloads

For trusted testers only:

```sh
xattr -dr com.apple.quarantine /Applications/Kaji.app
open /Applications/Kaji.app
```

Public users should use the source install command. Notarized builds are not planned. Sparkle does not remove this **first-install** limitation: packaging the same app as a DMG instead of ZIP does not confer Gatekeeper trust.

## Sparkle Signing (Independent of Apple Signing)

Sparkle's Ed25519 key authenticates updates, not Apple's first-launch trust. Ad-hoc-signed hosts can receive properly signed Sparkle updates without an Apple Developer membership. Warning-free browser-downloaded first installation would require Apple trust that Kaji deliberately does not obtain.

The public update key is committed in `Info.plist`. The private key is stored outside the repository and as the repository's `KAJI_SPARKLE_PRIVATE_KEY` GitHub Actions secret. Never commit it, emit it to logs, or use Sparkle tools' implicit login-Keychain lookup. `scripts/sparkle-appcast.py` requires an explicit nonempty key file, uses SDK tools, and checks version/build, canonical download URL, length, archive signature and feed signature before publication. The release job creates a mode-0600 temporary file and removes it on exit. Keep an independent secure backup: losing this key without a Developer ID trust chain prevents normal key rotation.

The manually assembled SwiftPM app embeds the universal Sparkle framework and its helper/XPC code, preserves framework symlinks, supplies a Frameworks rpath and signs nested code inside-out. Local builds stay ad-hoc and non-interactive; no keychain is discovered, created or unlocked.

## Source Installer Requirements

Running Kaji requires macOS 13 or newer. Building it also requires a working Swift 6.0 or newer toolchain, Git and Python 3. A supported macOS version alone does not guarantee suitable build tools.

The installer must check actual tool execution and versions, explain how to repair missing or outdated tools, and check destination permissions before building or replacing an existing installation. Prerequisite failures must leave the installed app untouched.

Release CI remains ad-hoc signed. Do not add Apple signing certificates, notarization credentials, or signing-keychain setup. Sparkle's independent update-signing key remains required.


## Cross-Machine Acceptance

A successful developer-machine build is not installation acceptance. Treat these as separate contracts:

- Runtime OS support versus the toolchain needed to build from source.
- Intel and Apple Silicon binary slices versus actual runtime tests on those machines.
- A shell's PATH versus Finder's minimal launch environment, especially Python resolution.
- Working-directory and install permissions versus administrator approval for the optional sleep helper.
- Package integrity and Sparkle update authenticity versus Apple's browser-download trust.

Use deterministic fixtures for missing/old tools, custom Python, failed replacement and malformed local input. Also do a short real-app smoke on a clean machine or VM, including Finder launch and a real status-item click. Testing only on `macos-latest` does not establish runtime support for macOS 13. Preserve the existing app on install failure and never discard its only recovery backup.

## References

- Sparkle setup/security: https://sparkle-project.org/documentation/
- Sparkle installer security: https://github.com/sparkle-project/Sparkle/blob/2.x/Documentation/Installation.md
- Apple Developer ID: https://developer.apple.com/developer-id/
- Apple notarization docs: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Apple notarization troubleshooting: https://developer.apple.com/documentation/security/resolving-common-notarization-issues
- Apple Developer Program enrollment: https://developer.apple.com/programs/enroll/
- Apple support, opening non-notarized apps: https://support.apple.com/en-us/102445
