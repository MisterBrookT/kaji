#!/usr/bin/env bash
# Regenerate the README screenshots from the live SwiftUI views — reproducible,
# no manual capture. Renders the popover + menu-bar strip offscreen via
# ImageRenderer (Kaji Gauge runs as an LSUIElement agent, which screen-capture
# can't see), then drops the PNGs into docs/.
#
#   ./scripts/screenshots.sh          # English (what the README ships)
#   ./scripts/screenshots.sh zh       # 中文 variant (for spot-checking i18n)
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=Sources/KajiGauge
LANG_ARG="${1:-}"
# Compile every source EXCEPT main.swift (its @main collides with the harness's).
FILES=$(ls "$SRC"/*.swift | grep -v 'main.swift')

echo "==> compiling snapshot harness"
swiftc -O $FILES scripts/snapshot.swift -o /tmp/kaji-snap

echo "==> rendering (light + dark${LANG_ARG:+, $LANG_ARG})"
/tmp/kaji-snap both $LANG_ARG

# Hero pair = the full popover (dual rings + countdowns + toggles).
# Light LEFT, dark RIGHT in the README — day before night.
cp /tmp/popover-light.png docs/gauge-light.png
cp /tmp/popover-dark.png  docs/gauge-dark.png
cp /tmp/status-light.png  docs/menubar-light.png
cp /tmp/status-dark.png   docs/menubar-dark.png

echo "==> wrote docs/{gauge,menubar}-{light,dark}.png"
