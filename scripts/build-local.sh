#!/usr/bin/env bash
# build-local.sh — build + install Kaji.app for local tryouts.
#
# Uses SwiftPM (`swift build`) so `KajiCore` resolves correctly.
# (Raw `swiftc Sources/**/*.swift` fails on `import KajiCore` because that
# needs a built module, not a flat file list.)
#
#   ./scripts/build-local.sh           # build, install to /Applications, relaunch
#   ./scripts/build-local.sh --no-open # build + install, don't relaunch
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

./scripts/build-app.sh
APP="dist/Kaji.app"

echo "==> md5 quota.py (source vs bundle — must match)"
md5 -q Resources/quota.py "$APP/Contents/Resources/quota.py"

echo "==> install to /Applications"
pkill -f KajiGauge 2>/dev/null || true
pkill -f "/Applications/Kaji.app/Contents/MacOS/Kaji" 2>/dev/null || true
sleep 1
rm -rf /Applications/Kaji.app
rm -rf /Applications/KajiGauge.app
cp -R "$APP" /Applications/

if [[ "${1:-}" != "--no-open" ]]; then
  echo "==> launch"
  open /Applications/Kaji.app
fi
echo "==> done"
