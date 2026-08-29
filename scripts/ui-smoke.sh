#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS="$ROOT/.build/ui-smoke"
HELPER="$ARTIFACTS/ui-smoke-helper"
APP_EXECUTABLE="$ROOT/dist/Kaji.app/Contents/MacOS/Kaji"
KAJI_PID=""
PREFS_DOMAIN="dev.kaji"
NONCE="$(uuidgen)-$(uuidgen)"
PORT="$(jot -r 1 40000 59999)"
SMOKE_DOMAIN="dev.kaji.ui-smoke.$NONCE"
SEED_MODULES=(quota work system goals mailBrief launchd)
SEED_LANGUAGE=en
PAGE_IDS="quota|work|system|goals|mailBrief|launchd|launchd:application|launchd:appleSystem"
SETTINGS_SECTIONS="General|Modules|Work|Quota|Mail Brief|Permissions"

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
    defaults delete "$SMOKE_DOMAIN" >/dev/null 2>&1 || true
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
export KAJI_UI_SMOKE_AUDIT_LAUNCHD_REFRESH=1
APP_ARGS=(
    -enabledModules "$(seed_modules_plist_array)"
    -language "$SEED_LANGUAGE"
)
if [[ -n "${KAJI_UI_SMOKE_APPEARANCE:-}" ]]; then
    APP_ARGS+=(-AppleInterfaceStyle "$KAJI_UI_SMOKE_APPEARANCE")
fi

printf 'UI-SMOKE launch: owned Kaji process on control port %s\n' "$PORT"
"$APP_EXECUTABLE" "${APP_ARGS[@]}" \
    >"$ARTIFACTS/kaji.stdout.log" 2>"$ARTIFACTS/kaji.stderr.log" &
KAJI_PID=$!
if ! kill -0 "$KAJI_PID" 2>/dev/null; then
    printf 'UI-SMOKE FAIL: owned Kaji process exited during launch; inspect %s\n' "$ARTIFACTS/kaji.stderr.log" >&2
    exit 1
fi

"$HELPER" "$KAJI_PID" "$ARTIFACTS" "$NONCE" "$PORT" "$PAGE_IDS" "$SETTINGS_SECTIONS" \
    "$ROOT/scripts/ui-smoke.swift" "$ROOT/scripts/ui-smoke.sh"

if ! /usr/bin/grep -q 'KAJI_UI_SMOKE launchd-refresh' "$ARTIFACTS/kaji.stdout.log"; then
    printf '%s\n' 'UI-SMOKE FAIL: Background Tasks module never refreshed live launchd state' >&2
    exit 1
fi
printf '%s\n' 'ASSERT launchd-refresh: PASS live refresh ran in the owned app process'

PREFS_MD5_AFTER=$(defaults export "$PREFS_DOMAIN" - 2>/dev/null | md5 -q || echo "no-domain")
PREFS_ENABLED_AFTER=$(defaults read "$PREFS_DOMAIN" enabledModules 2>/dev/null || echo "<missing>")
PREFS_LANGUAGE_AFTER=$(defaults read "$PREFS_DOMAIN" language 2>/dev/null || echo "<missing>")

if [[ "$PREFS_MD5_BEFORE" != "$PREFS_MD5_AFTER" || \
      "$PREFS_ENABLED_BEFORE" != "$PREFS_ENABLED_AFTER" || \
      "$PREFS_LANGUAGE_BEFORE" != "$PREFS_LANGUAGE_AFTER" ]]; then
    printf '%s\n' 'UI-SMOKE FAIL: the real dev.kaji preferences domain changed' >&2
    exit 1
fi
printf 'ASSERT preferences-isolated: PASS dev.kaji unchanged (md5 %s)\n' "$PREFS_MD5_AFTER"
printf 'UI-SMOKE PASS: input devices/frontmost app untouched; real popover and settings views rendered offscreen; artifacts: %s\n' "$ARTIFACTS"
