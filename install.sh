#!/usr/bin/env bash
# Kaji Gauge — one-line installer.
#
#   curl -fsSL https://raw.githubusercontent.com/interesting-vibe-coding/kaji-gauge/main/install.sh | bash
#
# Downloads the latest released .app, drops it in /Applications, clears the
# Gatekeeper quarantine (the app is unsigned for now), and launches it. The app
# is a menu-bar agent — no dock icon; look for the rings in your menu bar.
set -euo pipefail

REPO="interesting-vibe-coding/kaji-gauge"
DEST="/Applications"

say() { printf '\033[1;38;5;208m==>\033[0m %s\n' "$1"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || die "Kaji Gauge is macOS only."
command -v python3 >/dev/null 2>&1 || \
  echo "note: python3 not found — install it (e.g. 'xcode-select --install') so the gauge can read your quota."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "Finding the latest release…"
URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*\.zip"' \
        | head -1 | cut -d'"' -f4)"
[ -n "$URL" ] || die "no release asset found. Build from source instead (see README)."

say "Downloading…"
curl -fsSL "$URL" -o "$TMP/kaji-gauge.zip"

say "Unpacking…"
unzip -q "$TMP/kaji-gauge.zip" -d "$TMP"
APP_PATH="$(find "$TMP" -maxdepth 2 -name '*.app' -print -quit)"
[ -n "$APP_PATH" ] || die "no .app found in the downloaded archive."
APP_NAME="$(basename "$APP_PATH")"

say "Installing to $DEST/$APP_NAME"
rm -rf "$DEST/$APP_NAME"
cp -R "$APP_PATH" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true

say "Launching…"
open "$DEST/$APP_NAME"
say "Done — Kaji Gauge is now in your menu bar."
