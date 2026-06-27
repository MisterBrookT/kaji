#!/usr/bin/env bash
# Build a small README demo GIF from the same SwiftUI snapshot harness.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=Sources/Kaji
FILES=$(ls "$SRC"/*.swift | grep -v 'main.swift')
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> compiling snapshot harness"
swiftc -O $FILES scripts/snapshot.swift -o "$TMP/kaji-snap"

render_frame() {
  local name="$1"; shift
  "$TMP/kaji-snap" light "$@"
  cp /tmp/popover-light.png "$TMP/$name.png"
}

echo "==> rendering frames"
render_frame 00-mono blackWhite
render_frame 01-calm calm
render_frame 02-playful playful
render_frame 03-remaining blackWhite remaining

cat > "$TMP/frames.txt" <<EOF
file '$TMP/00-mono.png'
duration 1.2
file '$TMP/01-calm.png'
duration 1.0
file '$TMP/02-playful.png'
duration 1.0
file '$TMP/03-remaining.png'
duration 1.2
file '$TMP/00-mono.png'
duration 0.8
EOF

echo "==> encoding docs/demo.gif"
ffmpeg -y -v error \
  -f concat -safe 0 -i "$TMP/frames.txt" \
  -vf "fps=8,scale=720:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse=dither=bayer" \
  docs/demo.gif

echo "==> wrote docs/demo.gif"
