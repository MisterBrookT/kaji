#!/usr/bin/env bash
# Kaji — one-line installer (build from source).
#
#   curl -fsSL https://raw.githubusercontent.com/MisterBrookT/kaji/main/install.sh | bash
#
# Clones the latest release tag, builds Kaji.app locally, installs to
# /Applications, clears Gatekeeper quarantine (ad-hoc signed), and launches.
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
command -v curl >/dev/null 2>&1 || die "curl is required."

# Check that tools actually run, not just that a name resolves: on a fresh Mac
# /usr/bin/git and /usr/bin/swift are stubs until developer tools are installed.
MACOS_VERSION="$(sw_vers -productVersion 2>/dev/null || true)"
MACOS_MAJOR="${MACOS_VERSION%%.*}"
case "$MACOS_MAJOR" in ''|*[!0-9]*) die "could not determine the macOS version (sw_vers failed).";; esac
[ "$MACOS_MAJOR" -ge 13 ] || die "Kaji requires macOS 13 or newer (found ${MACOS_VERSION}). Nothing was changed."

DEVTOOLS_HINT="Install the developer tools with 'xcode-select --install' (or Xcode), then re-run this installer."
if ! GIT_VERSION_OUT="$(git --version 2>&1)"; then
  die "git is installed but not working (or missing): ${GIT_VERSION_OUT}. ${DEVTOOLS_HINT} Nothing was changed."
fi
if ! SWIFT_VERSION_OUT="$(swift --version 2>&1)"; then
  die "swift is installed but not working (or missing): ${SWIFT_VERSION_OUT}. ${DEVTOOLS_HINT} Nothing was changed."
fi
SWIFT_VERSION="$(printf '%s\n' "$SWIFT_VERSION_OUT" | sed -nE 's/.*Swift version ([0-9]+)\.([0-9]+).*/\1.\2/p' | head -n 1)"
[ -n "$SWIFT_VERSION" ] || die "could not determine the Swift version from 'swift --version'. ${DEVTOOLS_HINT}"
SWIFT_MAJOR="${SWIFT_VERSION%%.*}"
if [ "$SWIFT_MAJOR" -lt 6 ]; then
  MACOS_MINOR="$(printf '%s' "$MACOS_VERSION" | cut -d. -f2)"
  if [ "$MACOS_MAJOR" -lt 14 ] || { [ "$MACOS_MAJOR" -eq 14 ] && [ "${MACOS_MINOR:-0}" -lt 5 ] 2>/dev/null; }; then
    die "Kaji requires Swift 6.0 or newer (found ${SWIFT_VERSION}); building with standard Xcode 16 requires macOS 14.5 or newer; Kaji itself runs on macOS 13. A compatible custom Swift 6 toolchain may work. Nothing was changed."
  fi
  die "Kaji requires Swift 6.0 or newer (found ${SWIFT_VERSION}). Update Xcode or the command-line tools, then re-run. Nothing was changed."
fi

[ -d "$DEST" ] || die "install destination ${DEST} does not exist. Create it or set KAJI_INSTALL_DEST. Nothing was changed."
[ -w "$DEST" ] || die "install destination ${DEST} is not writable. Fix permissions or set KAJI_INSTALL_DEST. Nothing was changed."
# Later we cd into the clone; keep custom relative destinations anchored here.
DEST="$(cd "$DEST" && pwd)"

# The bundled reader needs a real python3. /usr/bin/python3 is only a stub until
# the Xcode command-line tools are installed. If Git and Swift already work but
# Python is missing, offer Apple's tools install dialog and wait for completion.
have_python() { /usr/bin/env python3 -c 'import sys' >/dev/null 2>&1; }
if ! have_python; then
  if xcode-select -p >/dev/null 2>&1; then
    die "python3 is not working. Install Python 3 or update your Xcode command-line tools, then re-run this installer. Nothing was changed."
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
./scripts/build-app.sh || die "Build failed (possibly network access or SwiftPM dependency fetch). The installed app was not touched; nothing was changed."
APP_PATH="$CLONE_DIR/dist/Kaji.app"
[ -d "$APP_PATH" ] || die "build finished but dist/Kaji.app is missing."

say "Installing to ${DEST}/Kaji.app"
# Stage next to the target (same volume) so the swap is a rename and a failed
# copy leaves the existing install untouched.
STAGE="$DEST/.Kaji.app.new.$$"
BACKUP="$DEST/.Kaji.app.old.$$"
rm -rf "$STAGE"
if ! cp -R "$APP_PATH" "$STAGE"; then
  rm -rf "$STAGE"
  die "could not copy Kaji.app into ${DEST}; the existing install was kept."
fi

app_is_running() {
  ps -axo comm= | grep -Fqx "$DEST/Kaji.app/Contents/MacOS/Kaji"
}
stop_app() {
  pkill -f "$DEST/Kaji.app/Contents/MacOS/Kaji" 2>/dev/null || true
  for _ in 1 2 3 4 5 6; do
    app_is_running || return 0
    sleep 1
  done
  return 1
}
say "Stopping old copies…"
if ! stop_app; then
  rm -rf "$STAGE"
  die "existing Kaji process did not exit; the installed app was not changed. Quit Kaji and retry."
fi
pkill -f "$DEST/KajiGauge.app/Contents/MacOS/KajiGauge" 2>/dev/null || true

if [ -e "$DEST/Kaji.app" ] && ! mv "$DEST/Kaji.app" "$BACKUP"; then
  rm -rf "$STAGE"
  die "could not move the old Kaji.app aside in ${DEST}; the existing install was kept."
fi
if ! mv "$STAGE" "$DEST/Kaji.app"; then
  if [ -e "$BACKUP" ] && ! mv "$BACKUP" "$DEST/Kaji.app"; then
    rm -rf "$STAGE"
    die "restore failed; your previous app is saved at ${BACKUP}. Move it back to ${DEST}/Kaji.app before retrying."
  fi
  rm -rf "$STAGE"
  die "could not install Kaji.app into ${DEST}; the existing install was kept."
fi
xattr -dr com.apple.quarantine "$DEST/Kaji.app" 2>/dev/null || true

rollback_launch() {
  if [ -e "$BACKUP" ]; then
    if ! stop_app; then
      die "$1; Kaji did not exit; your previous app is saved at ${BACKUP}. Quit Kaji before restoring it."
    fi
    # Never delete the only recovery copy if restoration fails.
    if ! mv "$DEST/Kaji.app" "$STAGE" || ! mv "$BACKUP" "$DEST/Kaji.app"; then
      die "$1; restore failed; your previous app is saved at ${BACKUP}."
    fi
    rm -rf "$STAGE"
    die "$1; the previous app was restored."
  fi
  die "$1; no previous app exists to restore."
}
say "Launching…"
open "$DEST/Kaji.app" || rollback_launch "could not launch Kaji"
LAUNCHED=0
for _ in 1 2 3 4 5 6; do
  if app_is_running; then LAUNCHED=1; break; fi
  sleep 1
done
[ "$LAUNCHED" -eq 1 ] || rollback_launch "could not verify Kaji launched"
# Catch a process that appears briefly and then crashes during initialization.
sleep 1
app_is_running || rollback_launch "Kaji exited immediately after launch"
if ! rm -rf "$BACKUP" "$DEST/KajiGauge.app"; then
  say "Warning: Kaji launched, but old backup cleanup failed in ${DEST}."
fi
say "Done — Kaji ${TAG} is in your menu bar."
