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

# KAJI_UNIVERSAL=1 builds one arm64+x86_64 bundle (release assets: the in-app
# updater installs the first .zip it finds, so it must run on every Mac).
# Each arch is built separately and merged with lipo into .build/universal.
if [[ "${KAJI_UNIVERSAL:-0}" == "1" ]]; then
	BIN_DIR=".build/universal"
	mkdir -p "$BIN_DIR"
	for arch in arm64 x86_64; do
		echo "==> swift build -c release --arch ${arch}"
		swift build -c release --arch "$arch"
	done
	ARM_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
	X86_DIR="$(swift build -c release --arch x86_64 --show-bin-path)"
	SPARKLE_SRC_DIR="$ARM_DIR"
	for product in "$EXEC_NAME" KajiSleepHelper; do
		lipo -create "${ARM_DIR}/${product}" "${X86_DIR}/${product}" \
			-output "${BIN_DIR}/${product}"
	done
else
	echo "==> swift build -c release"
	swift build -c release
	BIN_DIR="$(swift build -c release --show-bin-path)"
	SPARKLE_SRC_DIR="$BIN_DIR"
fi

BIN_PATH="${BIN_DIR}/${EXEC_NAME}"
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

# Sparkle.framework (universal binary artifact). ditto preserves the
# Versions/Current symlinks and the inner Autoupdate / Updater.app / XPC tools.
SPARKLE_FRAMEWORK="${SPARKLE_SRC_DIR}/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
	echo "error: Sparkle.framework not found at $SPARKLE_FRAMEWORK" >&2
	exit 1
fi
mkdir -p "${BUNDLE}/Contents/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "${BUNDLE}/Contents/Frameworks/Sparkle.framework"
if ! otool -l "${BUNDLE}/Contents/MacOS/${EXEC_NAME}" | grep -F "@executable_path/../Frameworks" >/dev/null; then
	install_name_tool -add_rpath "@executable_path/../Frameworks" \
		"${BUNDLE}/Contents/MacOS/${EXEC_NAME}"
fi

HELPER_PATH="${BIN_DIR}/KajiSleepHelper"
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
	<key>CFBundleShortVersionString</key><string>1.0.2</string>
	<key>CFBundleVersion</key><string>43</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSUIElement</key><true/>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
fi


# Bundle the pinned source updater: no remotely supplied shell commands.
test -f scripts/source-update.sh
cp scripts/source-update.sh "${BUNDLE}/Contents/Resources/source-update.sh"

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
SIGN_ARGS=(--force --sign "${KAJI_CODESIGN_IDENTITY}")
if [[ "$KAJI_CODESIGN_IDENTITY" != "-" ]]; then
	SIGN_ARGS+=(--options runtime --timestamp)
fi
xattr -cr "${BUNDLE}"
# Nested code is signed inside-out (no --deep): Sparkle's XPC services and
# helpers first, then the framework, then the helper tool, then the app.
SPARKLE_VERSION_DIR="${BUNDLE}/Contents/Frameworks/Sparkle.framework/Versions/Current"
for xpc in "${SPARKLE_VERSION_DIR}"/XPCServices/*.xpc; do
	[[ -e "$xpc" ]] && codesign "${SIGN_ARGS[@]}" "$xpc"
done
codesign "${SIGN_ARGS[@]}" "${SPARKLE_VERSION_DIR}/Autoupdate"
codesign "${SIGN_ARGS[@]}" "${SPARKLE_VERSION_DIR}/Updater.app"
codesign "${SIGN_ARGS[@]}" "${BUNDLE}/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN_ARGS[@]}" --identifier dev.kaji.sleep-helper \
	"${BUNDLE}/Contents/Library/HelperTools/KajiSleepHelper"
codesign "${SIGN_ARGS[@]}" --identifier dev.kaji "${BUNDLE}"
codesign --verify --strict --deep "${BUNDLE}"

echo "==> done: ${BUNDLE}"
echo "    run with: open ${BUNDLE}"
