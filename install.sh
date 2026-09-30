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
DEST="${KAJI_INSTALL_DEST:-/Applications}"
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
# Use ${VAR} before non-ASCII text: macOS bash 3.2 in a UTF-8 locale otherwise
# reads the "…" lead byte as part of the name ("TAG?: unbound variable").
# Resolve the public releases/latest redirect instead of the unauthenticated
# REST API, which is rate-limited per IP (403) on shared/corporate networks.
LATEST_URL="https://github.com/${REPO}/releases/latest"
if ! RESOLVED_URL="$(curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 60 \
      -o /dev/null -w '%{url_effective}' "$LATEST_URL")"; then
  die "could not reach GitHub (${LATEST_URL}): network error or rate limit. Retry later."
fi
case "$RESOLVED_URL" in
  "https://github.com/${REPO}/releases"|"https://github.com/${REPO}/releases/")
    die "no GitHub release found. Clone the repo and run ./scripts/build-local.sh." ;;
esac
TAG="${RESOLVED_URL#https://github.com/${REPO}/releases/tag/}"
if [ "$TAG" = "$RESOLVED_URL" ] \
   || ! printf '%s' "$TAG" | grep -Eq '^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$'; then
  die "unexpected release URL from GitHub: ${RESOLVED_URL}"
fi

CLONE_DIR="$(mktemp -d)/kaji"
say "Cloning ${REPO} @${TAG}…"
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
say "Done — Kaji ${TAG} is in your menu bar."
