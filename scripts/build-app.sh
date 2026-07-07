#!/usr/bin/env bash
# Build Kaji.app — a menubar agent bundle (LSUIElement, no dock icon).
#
#   swift build -c release  ->  assemble dist/Kaji.app
#
# Run from anywhere; paths are resolved relative to the repo root.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Kaji"
BUNDLE="dist/${APP_NAME}.app"
EXEC_NAME="Kaji"

echo "==> swift build -c release"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${EXEC_NAME}"
if [[ ! -x "$BIN_PATH" ]]; then
	echo "error: built executable not found at $BIN_PATH" >&2
	exit 1
fi

echo "==> assembling ${BUNDLE}"
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

cp "$BIN_PATH" "${BUNDLE}/Contents/MacOS/${EXEC_NAME}"
chmod +x "${BUNDLE}/Contents/MacOS/${EXEC_NAME}"

# Prefer the tracked Info.plist; fall back to generating one if absent.
if [[ -f "Info.plist" ]]; then
	cp "Info.plist" "${BUNDLE}/Contents/Info.plist"
else
	cat > "${BUNDLE}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>Kaji</string>
	<key>CFBundleIdentifier</key><string>dev.kaji</string>
	<key>CFBundleExecutable</key><string>Kaji</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.3.3</string>
	<key>CFBundleVersion</key><string>6</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
fi

# App icon (Finder / Applications / installer — the agent has no dock icon).
if [[ -f "Resources/AppIcon.icns" ]]; then
	cp "Resources/AppIcon.icns" "${BUNDLE}/Contents/Resources/AppIcon.icns"
else
	echo "warning: Resources/AppIcon.icns missing — run scripts/make-icon.sh" >&2
fi

# Bundle the self-contained quota reader so the shipped app needs no external
# repo / hardcoded path — it reads the user's own ~/.claude, ~/.codex, etc.
if [[ -f "Resources/quota.py" ]]; then
	cp "Resources/quota.py" "${BUNDLE}/Contents/Resources/quota.py"
else
	echo "warning: Resources/quota.py missing — app will fall back to a dev path" >&2
fi

if [[ -f "Resources/navi-panda.png" ]]; then
	cp "Resources/navi-panda.png" "${BUNDLE}/Contents/Resources/navi-panda.png"
fi

# PkgInfo (harmless, conventional).
printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

echo "==> done: ${BUNDLE}"
echo "    run with: open ${BUNDLE}"
