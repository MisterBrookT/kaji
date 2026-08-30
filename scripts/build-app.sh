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
mkdir -p "${BUNDLE}/Contents/Library/HelperTools"
mkdir -p "${BUNDLE}/Contents/Library/LaunchDaemons"

cp "$BIN_PATH" "${BUNDLE}/Contents/MacOS/${EXEC_NAME}"
chmod +x "${BUNDLE}/Contents/MacOS/${EXEC_NAME}"

HELPER_PATH="$(swift build -c release --show-bin-path)/KajiSleepHelper"
cp "$HELPER_PATH" "${BUNDLE}/Contents/Library/HelperTools/KajiSleepHelper"
chmod +x "${BUNDLE}/Contents/Library/HelperTools/KajiSleepHelper"
cp "Resources/dev.kaji.sleep-helper.plist" \
    "${BUNDLE}/Contents/Library/LaunchDaemons/dev.kaji.sleep-helper.plist"

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
	<key>CFBundleShortVersionString</key><string>0.8.0</string>
	<key>CFBundleVersion</key><string>28</string>
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

if [[ ! -f "Resources/break-window-rain.png" ]]; then
	echo "error: missing break scene Resources/break-window-rain.png" >&2
	exit 1
fi
cp "Resources/break-window-rain.png" "${BUNDLE}/Contents/Resources/break-window-rain.png"

# PkgInfo (harmless, conventional).
printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

# Local builds are always ad-hoc signed and must never touch a user keychain.
# Distribution signing is opt-in: CI or a release operator must pass the exact
# identity through KAJI_CODESIGN_IDENTITY in a non-interactive environment.
KAJI_CODESIGN_IDENTITY=${KAJI_CODESIGN_IDENTITY:--}
xattr -cr "${BUNDLE}"
codesign --force --sign "${KAJI_CODESIGN_IDENTITY}" --identifier dev.kaji.sleep-helper \
	"${BUNDLE}/Contents/Library/HelperTools/KajiSleepHelper"
xattr -cr "${BUNDLE}"
codesign --force --sign "${KAJI_CODESIGN_IDENTITY}" --identifier dev.kaji "${BUNDLE}"

echo "==> done: ${BUNDLE}"
echo "    run with: open ${BUNDLE}"
