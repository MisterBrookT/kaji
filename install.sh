#!/usr/bin/env bash
# Kaji — one-line installer (build from source).
#
#   curl -fsSL https://raw.githubusercontent.com/MisterBrookT/kaji/main/install.sh | bash
#
# Clones the latest release tag, builds Kaji.app locally, installs to
# /Applications, clears Gatekeeper quarantine (unsigned for now), and launches.
# Browser .zip downloads are not used — they trip Gatekeeper on unsigned apps.
set -euo pipefail

REPO="MisterBrookT/kaji"
DEST="/Applications"
CLONE_DIR=""

say() { printf '\033[1;38;5;208m==>\033[0m %s\n' "$1"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

cleanup() {
  [[ -n "$CLONE_DIR" && -d "$CLONE_DIR" ]] && rm -rf "$CLONE_DIR"
}
trap cleanup EXIT

[ "$(uname)" = "Darwin" ] || die "Kaji is macOS only."
command -v git >/dev/null 2>&1 || die "git is required."
command -v swift >/dev/null 2>&1 || die "swift is required (install Xcode or the Swift toolchain)."
command -v curl >/dev/null 2>&1 || die "curl is required."

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
  for _ in $(seq 1 240); do
    if xcode-select -p >/dev/null 2>&1 && have_python; then break; fi
    sleep 5
  done
  have_python || die "command-line tools not installed. Run 'xcode-select --install', finish the dialog, then re-run this installer."
fi

say "Finding the latest release tag…"
TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep -o '"tag_name": *"[^"]*"' \
        | head -1 | cut -d'"' -f4)"
[ -n "$TAG" ] || die "no GitHub release found. Clone the repo and run ./scripts/build-local.sh."

CLONE_DIR="$(mktemp -d)/kaji"
say "Cloning $REPO @$TAG…"
git clone --depth 1 --branch "$TAG" "https://github.com/$REPO.git" "$CLONE_DIR"
cd "$CLONE_DIR"

say "Building (release)…"
./scripts/build-app.sh
APP_PATH="$CLONE_DIR/dist/Kaji.app"
[ -d "$APP_PATH" ] || die "build finished but dist/Kaji.app is missing."

say "Stopping old copies…"
pkill -f "/Applications/Kaji.app/Contents/MacOS/Kaji" 2>/dev/null || true
pkill -f "/Applications/KajiGauge.app/Contents/MacOS/KajiGauge" 2>/dev/null || true
sleep 1

say "Installing to $DEST/Kaji.app"
rm -rf "$DEST/Kaji.app"
rm -rf "$DEST/KajiGauge.app"
cp -R "$APP_PATH" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/Kaji.app" 2>/dev/null || true

say "Launching…"
open "$DEST/Kaji.app"
say "Done — Kaji $TAG is in your menu bar."
