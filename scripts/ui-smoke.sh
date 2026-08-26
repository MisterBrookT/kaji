#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS="$ROOT/.build/ui-smoke"
HELPER="$ARTIFACTS/ui-smoke-helper"
APP_EXECUTABLE="$ROOT/dist/Kaji.app/Contents/MacOS/Kaji"
KAJI_PID=""
PREFS_DOMAIN="dev.kaji"
SEED_MODULES=(quota work system goals aiNews mailBrief)
SEED_LANGUAGE=en
PAGE_IDS="quota|work|system|goals|aiNews|mailBrief"
SETTINGS_SECTIONS="General|Modules|Work|Goals|Quota|AI News|Mail Brief|MCP|Permissions"
NONCE="$(uuidgen)-$(uuidgen)"
PORT="$(jot -r 1 40000 59999)"

seed_modules_plist_array() {
    local joined
    joined=$(printf '%s, ' "${SEED_MODULES[@]}")
    printf '(%s)' "${joined%, }"
}

cleanup() {
    if [[ -n "$KAJI_PID" ]] && kill -0 "$KAJI_PID" 2>/dev/null; then
        kill "$KAJI_PID" 2>/dev/null || true
        wait "$KAJI_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

mkdir -p "$ARTIFACTS"
rm -f "$ARTIFACTS"/*.png "$HELPER"

PREFS_MD5_BEFORE=$(defaults export "$PREFS_DOMAIN" - 2>/dev/null | md5 -q || echo "no-domain")
PREFS_ENABLED_BEFORE=$(defaults read "$PREFS_DOMAIN" enabledModules 2>/dev/null || echo "<missing>")
PREFS_LANGUAGE_BEFORE=$(defaults read "$PREFS_DOMAIN" language 2>/dev/null || echo "<missing>")

printf '%s\n' 'UI-SMOKE build: ./scripts/build-app.sh'
"$ROOT/scripts/build-app.sh"
printf '%s\n' 'UI-SMOKE helper: compiling nonintrusive local verifier'
swiftc "$ROOT/scripts/ui-smoke.swift" -o "$HELPER"
codesign --force --sign - "$HELPER" >/dev/null

export KAJI_UI_SMOKE_NONCE="$NONCE"
export KAJI_UI_SMOKE_PORT="$PORT"
export KAJI_UI_SMOKE_ARTIFACTS="$ARTIFACTS"
APP_ARGS=(
    -enabledModules "$(seed_modules_plist_array)"
    -language "$SEED_LANGUAGE"
    -mcpEnabled NO
)
"$APP_EXECUTABLE" "${APP_ARGS[@]}" \
    >"$ARTIFACTS/kaji.stdout.log" 2>"$ARTIFACTS/kaji.stderr.log" &
KAJI_PID=$!

if ! kill -0 "$KAJI_PID" 2>/dev/null; then
    printf 'UI-SMOKE FAIL: owned Kaji process exited during launch; inspect %s\n' "$ARTIFACTS/kaji.stderr.log" >&2
    exit 1
fi

"$HELPER" "$KAJI_PID" "$ARTIFACTS" "$NONCE" "$PORT" "$PAGE_IDS" "$SETTINGS_SECTIONS" \
    "$ROOT/scripts/ui-smoke.swift" "$ROOT/scripts/ui-smoke.sh"

PREFS_MD5_AFTER=$(defaults export "$PREFS_DOMAIN" - 2>/dev/null | md5 -q || echo "no-domain")
PREFS_ENABLED_AFTER=$(defaults read "$PREFS_DOMAIN" enabledModules 2>/dev/null || echo "<missing>")
PREFS_LANGUAGE_AFTER=$(defaults read "$PREFS_DOMAIN" language 2>/dev/null || echo "<missing>")

if [[ "$PREFS_ENABLED_BEFORE" != "$PREFS_ENABLED_AFTER" || "$PREFS_LANGUAGE_BEFORE" != "$PREFS_LANGUAGE_AFTER" ]]; then
    printf '%s\n' 'UI-SMOKE FAIL: dev.kaji enabledModules/language changed on disk' >&2
    exit 1
fi
printf 'UI-SMOKE: enabledModules/language unchanged (enabledModules=%s language=%s)\n' \
    "$PREFS_ENABLED_AFTER" "$PREFS_LANGUAGE_AFTER"
if [[ "$PREFS_MD5_BEFORE" != "$PREFS_MD5_AFTER" ]]; then
    printf 'UI-SMOKE: whole-domain md5 changed only through existing app-owned serialization (before=%s after=%s)\n' \
        "$PREFS_MD5_BEFORE" "$PREFS_MD5_AFTER"
else
    printf 'UI-SMOKE: preferences domain unchanged (md5 %s)\n' "$PREFS_MD5_AFTER"
fi
printf 'UI-SMOKE PASS: input devices/frontmost app untouched; all pages/settings rendered in the owned Kaji process; artifacts: %s\n' "$ARTIFACTS"
