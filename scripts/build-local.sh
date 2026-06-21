#!/usr/bin/env bash
# build-local.sh — build + install KajiGauge.app with swiftc directly.
#
# Use this instead of scripts/build-app.sh on machines where SwiftPM's
# manifest fails to link (CommandLineTools-only, no full Xcode — the
# PackageDescription linker errors out). swiftc needs no manifest.
#
# Source order matters: main.swift MUST come last (top-level entry point);
# the glob below already sorts it after the type files alphabetically, but if
# that ever changes, list main.swift explicitly at the end.
#
#   ./scripts/build-local.sh           # build, install to /Applications, relaunch
#   ./scripts/build-local.sh --no-open # build + install, don't relaunch
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP="build/KajiGauge.app"
TARGET="arm64-apple-macos13"

echo "==> swiftc -O"
rm -rf build && mkdir -p build
swiftc -O Sources/KajiGauge/*.swift \
  -framework AppKit -framework SwiftUI \
  -o build/KajiGauge -target "$TARGET"

echo "==> assemble $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/KajiGauge "$APP/Contents/MacOS/KajiGauge"
cp Info.plist "$APP/Contents/Info.plist"
# Resources/quota.py is the single source of truth for the bundled reader.
# Always copy it so the .app never drifts from the repo (see the bundle-drift
# pitfall that hid MiniMax in v0.4.4).
cp Resources/quota.py "$APP/Contents/Resources/quota.py"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> md5 quota.py (source vs bundle — must match)"
md5 -q Resources/quota.py "$APP/Contents/Resources/quota.py"

echo "==> install to /Applications"
pkill -f KajiGauge 2>/dev/null || true
sleep 1
rm -rf /Applications/KajiGauge.app
cp -R "$APP" /Applications/

if [[ "${1:-}" != "--no-open" ]]; then
  echo "==> launch"
  open /Applications/KajiGauge.app
fi
echo "==> done"
