#!/usr/bin/env bash
# Regenerate the README screenshots from the live SwiftUI views — reproducible,
# no manual capture. Renders the popover + menu-bar strip offscreen via
# ImageRenderer (Kaji runs as an LSUIElement agent, which screen-capture
# can't see), then drops the PNGs into dev_docs/assets/.
#
#   ./scripts/screenshots.sh          # English (what the README ships)
#   ./scripts/screenshots.sh zh       # 中文 variant (for spot-checking i18n)
set -euo pipefail
cd "$(dirname "$0")/.."

LANG_ARG="${1:-}"
TARGET="arm64-apple-macos13"
MOD=/tmp/kaji-snap-modules
mkdir -p "$MOD"

echo "==> compiling KajiCore module"
swiftc -O -parse-as-library Sources/KajiCore/*.swift \
  -module-name KajiCore \
  -emit-module -emit-module-path "$MOD/KajiCore.swiftmodule" \
  -emit-library -o /tmp/libKajiCore.dylib \
  -target "$TARGET"

# Compile every app source EXCEPT main.swift (its @main collides with the harness's).
FILES=$(ls Sources/Kaji/*.swift | grep -v 'main.swift')

echo "==> compiling snapshot harness"
swiftc -O $FILES scripts/snapshot.swift \
  -I "$MOD" -L /tmp -lKajiCore \
  -Xlinker -rpath -Xlinker /tmp \
  -framework AppKit -framework SwiftUI -framework ServiceManagement \
  -o /tmp/kaji-snap -target "$TARGET"

echo "==> rendering (light + dark${LANG_ARG:+, $LANG_ARG})"
/tmp/kaji-snap both $LANG_ARG

cp /tmp/popover-light.png dev_docs/assets/gauge-light.png
cp /tmp/popover-dark.png  dev_docs/assets/gauge-dark.png
cp /tmp/status-light.png  dev_docs/assets/menubar-light.png
cp /tmp/status-dark.png   dev_docs/assets/menubar-dark.png

echo "==> wrote dev_docs/assets/{gauge,menubar}-{light,dark}.png"
