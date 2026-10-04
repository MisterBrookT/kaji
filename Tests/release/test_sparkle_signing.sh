#!/bin/bash
# Real SDK signatures on an isolated app copy; never installs or runs Kaji.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
TOOLS=.build/artifacts/sparkle/Sparkle/bin
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
umask 077
mkdir -p "$WORK/dist"
ditto dist/Kaji.app "$WORK/dist/Kaji.app"
cat > "$WORK/key.swift" <<'SWIFT'
import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
print(key.publicKey.rawRepresentation.base64EncodedString())
SWIFT
PUBLIC_KEY="$(swift "$WORK/key.swift" "$WORK/private.key")"
PLIST="$WORK/dist/Kaji.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" "$PLIST"
codesign --force --sign - "$WORK/dist/Kaji.app" >/dev/null 2>&1
ditto -c -k --keepParent "$WORK/dist/Kaji.app" "$WORK/dist/Kaji.app.zip"
printf '### Fixed\n- Fixture signing test.\n' > "$WORK/dist/release-notes.md"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
python3 scripts/sparkle-appcast.py "v$VERSION" --dist "$WORK/dist" --plist "$PLIST" --tools "$TOOLS" --key-file "$WORK/private.key"
SIG="$(python3 - "$WORK/dist/appcast.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
print(ET.parse(sys.argv[1]).find('./channel/item/enclosure').get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'))
PY
)"
printf 'tampered' >> "$WORK/dist/Kaji.app.zip"
if "$TOOLS/sign_update" --verify --ed-key-file "$WORK/private.key" "$WORK/dist/Kaji.app.zip" "$SIG" >/dev/null 2>&1; then
  echo 'FAIL: tampered archive accepted' >&2; exit 1
fi
python3 - "$WORK/dist/appcast.xml" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text().replace('<title>', '<title>TAMPERED ', 1))
PY
if "$TOOLS/sign_update" --verify --ed-key-file "$WORK/private.key" "$WORK/dist/appcast.xml" >/dev/null 2>&1; then
  echo 'FAIL: tampered feed accepted' >&2; exit 1
fi
echo 'Sparkle signing: valid archive/feed accepted; tampered archive/feed rejected'
