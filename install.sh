#!/usr/bin/env bash
# Kaji — one-line installer.
#
#   curl -fsSL https://raw.githubusercontent.com/blackblue-labs/kaji/main/install.sh | bash
#
# Downloads the latest released .app, drops it in /Applications, clears the
# Gatekeeper quarantine (the app is unsigned for now), and launches it. The app
# is a menu-bar agent — no dock icon; look for the rings in your menu bar.
set -euo pipefail

REPO="blackblue-labs/kaji"
DEST="/Applications"

say() { printf '\033[1;38;5;208m==>\033[0m %s\n' "$1"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || die "Kaji is macOS only."

# The bundled reader needs a real python3. /usr/bin/python3 is only a stub until
# the Xcode command-line tools are installed — trigger that install (Apple's GUI
# prompt) and wait, so a fresh Mac works out of the box.
have_python() { /usr/bin/env python3 -c 'import sys' >/dev/null 2>&1; }
if ! have_python; then
  if xcode-select -p >/dev/null 2>&1; then
    die "python3 not working though the command-line tools are present. Reinstall: 'sudo rm -rf \$(xcode-select -p) && xcode-select --install'."
  fi
  say "Installing the Xcode command-line tools (needed for python3)…"
  xcode-select --install >/dev/null 2>&1 || true
  say "Finish the macOS install dialog that just opened — this resumes automatically…"
  # Poll until the tools land (or the user cancels). ~20 min ceiling.
  for _ in $(seq 1 240); do
    if xcode-select -p >/dev/null 2>&1 && have_python; then break; fi
    sleep 5
  done
  have_python || die "command-line tools not installed. Run 'xcode-select --install', finish the dialog, then re-run this installer."
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say "Finding the latest release…"
URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*\.zip"' \
        | head -1 | cut -d'"' -f4)"
[ -n "$URL" ] || die "no release asset found. Build from source instead (see README)."

say "Downloading…"
curl -fsSL "$URL" -o "$TMP/kaji.zip"

say "Unpacking…"
unzip -q "$TMP/kaji.zip" -d "$TMP"
APP_PATH="$(find "$TMP" -maxdepth 2 -name '*.app' -print -quit)"
[ -n "$APP_PATH" ] || die "no .app found in the downloaded archive."
APP_NAME="$(basename "$APP_PATH")"

say "Stopping old copies…"
pkill -f "/Applications/Kaji.app/Contents/MacOS/Kaji" 2>/dev/null || true
pkill -f "/Applications/KajiGauge.app/Contents/MacOS/KajiGauge" 2>/dev/null || true
sleep 1

say "Installing to $DEST/$APP_NAME"
rm -rf "$DEST/$APP_NAME"
rm -rf "$DEST/KajiGauge.app"
cp -R "$APP_PATH" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true

say "Launching…"
open "$DEST/$APP_NAME"
say "Done — Kaji is now in your menu bar."
