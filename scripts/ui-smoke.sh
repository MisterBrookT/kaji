#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACTS="$ROOT/.build/ui-smoke"
HELPER="$ARTIFACTS/ui-smoke-helper"
APP_EXECUTABLE="$ROOT/dist/Kaji.app/Contents/MacOS/Kaji"
KAJI_PID=""
PREFS_DOMAIN="dev.kaji"

# The smoke run also exercises page navigation, which only renders header
# chevrons when more than one module is enabled (KajiPopoverView.header).
# We never write to the app's real `defaults` domain to get there — a crash
# or `kill -9` mid-run would leave the user's real dev.kaji preferences
# stuck in test state, which is exactly the pollution we're trying to avoid.
# Instead we pass `-key value` command-line arguments, which macOS populates
# into `NSArgumentDomain` — the highest-priority, read-only, never-persisted
# UserDefaults search layer (see `man defaults`/`NSUserDefaults` "argument
# domain"). Confirmed empirically with a standalone Foundation binary: an
# arg of `-enabledModules '(quota, work, goals)'` is readable via
# `UserDefaults.standard.array(forKey:)` with zero effect on the on-disk
# domain. `language` is pinned to `en` the same way so panelTitle assertions
# are deterministic regardless of what this machine's Kaji has persisted.
#
# mailBrief is included below: MailBriefCredentialStore's keychain probe was
# fixed to use kSecUseAuthenticationUIFail / LAContext noninteractive reads
# and to fall back to "not connected" instead of surfacing a system prompt
# on an ACL mismatch (with a one-shot v3 ACL migration). The
# `no-system-auth-prompt` assertion in ui-smoke.swift, exercised across the
# popover's Mail Brief page and the Settings > Mail Brief page, is the
# regression test for that fix — if it ever starts failing, that is a real
# regression, not a reason to re-exclude mailBrief from this list.
SEED_MODULES=(quota work goals aiNews mailBrief launchd)
SEED_LANGUAGE=en
EXPECTED_PAGE_TITLES="Quota|Work / Break|Goals|AI News|Mail Brief|Background Tasks"

# Old-style property-list array literal, e.g. "(quota, work, goals, aiNews)" —
# the format NSArgumentDomain parsing accepts for array-typed arguments.
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

# Proof that this run never persists into the user's real preferences
# domain. The whole-domain md5 is diagnostic only: DailyGoalStore /
# FixedPlanStore re-encode their own JSON-blob keys (scheduledGoalsV1,
# scheduledGoalCompletionV1, ...) via JSONEncoder on every single launch —
# same content, non-deterministic Codable field order — independent of
# anything this script does (a plain `open dist/Kaji.app` triggers the same
# diff). What this script must never move is the two keys it could have
# seeded via `defaults write`: enabledModules and language. Those are
# checked for byte-for-byte equality below and fail the run if touched.
PREFS_MD5_BEFORE=$(defaults export "$PREFS_DOMAIN" - 2>/dev/null | md5 -q || echo "no-domain")
PREFS_ENABLED_BEFORE=$(defaults read "$PREFS_DOMAIN" enabledModules 2>/dev/null || echo "<missing>")
PREFS_LANGUAGE_BEFORE=$(defaults read "$PREFS_DOMAIN" language 2>/dev/null || echo "<missing>")


printf '%s\n' 'UI-SMOKE build: ./scripts/build-app.sh'
"$ROOT/scripts/build-app.sh"

printf '%s\n' 'UI-SMOKE helper: compiling ad-hoc local verifier'
swiftc "$ROOT/scripts/ui-smoke.swift" -o "$HELPER"
codesign --force --sign - "$HELPER" >/dev/null

# The smoke run owns the only Kaji instance so AX lookup and window ownership
# cannot accidentally target an installed or previously launched copy.
pkill -x Kaji 2>/dev/null || true
for _ in {1..50}; do
    pgrep -x Kaji >/dev/null 2>&1 || break
    sleep 0.1
done
if pgrep -x Kaji >/dev/null 2>&1; then
    printf '%s\n' 'UI-SMOKE FAIL: stale Kaji process did not terminate' >&2
    exit 1
fi

APP_ARGS=(
    -enabledModules "$(seed_modules_plist_array)"
    -language "$SEED_LANGUAGE"
)
if [[ -n "${KAJI_UI_SMOKE_APPEARANCE:-}" ]]; then
    APP_ARGS+=(-AppleInterfaceStyle "$KAJI_UI_SMOKE_APPEARANCE")
fi
"$APP_EXECUTABLE" "${APP_ARGS[@]}" \
    >"$ARTIFACTS/kaji.stdout.log" 2>"$ARTIFACTS/kaji.stderr.log" &
KAJI_PID=$!

if ! kill -0 "$KAJI_PID" 2>/dev/null; then
    printf 'UI-SMOKE FAIL: Kaji exited during launch; inspect %s\n' "$ARTIFACTS/kaji.stderr.log" >&2
    exit 1
fi

shopt -s nullglob
USER_AGENT_PLISTS=("$HOME"/Library/LaunchAgents/*.plist)
export KAJI_UI_SMOKE_EXPECT_USER_AGENT_COUNT="${#USER_AGENT_PLISTS[@]}"
"$HELPER" "$KAJI_PID" "$ARTIFACTS" "$EXPECTED_PAGE_TITLES"

PREFS_MD5_AFTER=$(defaults export "$PREFS_DOMAIN" - 2>/dev/null | md5 -q || echo "no-domain")
PREFS_ENABLED_AFTER=$(defaults read "$PREFS_DOMAIN" enabledModules 2>/dev/null || echo "<missing>")
PREFS_LANGUAGE_AFTER=$(defaults read "$PREFS_DOMAIN" language 2>/dev/null || echo "<missing>")

if [[ "$PREFS_ENABLED_BEFORE" != "$PREFS_ENABLED_AFTER" || "$PREFS_LANGUAGE_BEFORE" != "$PREFS_LANGUAGE_AFTER" ]]; then
    printf 'UI-SMOKE FAIL: dev.kaji enabledModules/language were persisted by this run — the NSArgumentDomain seed must never touch disk\n' >&2
    printf '  enabledModules before: %s\n' "$PREFS_ENABLED_BEFORE" >&2
    printf '  enabledModules after:  %s\n' "$PREFS_ENABLED_AFTER" >&2
    printf '  language before: %s\n' "$PREFS_LANGUAGE_BEFORE" >&2
    printf '  language after:  %s\n' "$PREFS_LANGUAGE_AFTER" >&2
    exit 1
fi
printf 'UI-SMOKE: dev.kaji enabledModules and language are byte-for-byte unchanged (enabledModules=%s language=%s)\n' \
    "$PREFS_ENABLED_AFTER" "$PREFS_LANGUAGE_AFTER"

if [[ "$PREFS_MD5_BEFORE" != "$PREFS_MD5_AFTER" ]]; then
    printf 'UI-SMOKE: dev.kaji whole-domain md5 changed (before=%s after=%s) — expected: DailyGoalStore/FixedPlanStore re-encode their own JSON-blob keys with non-deterministic Codable field order on every Kaji launch, independent of this script (a plain `open dist/Kaji.app` reproduces the same diff). Not a regression in this harness; enabledModules/language above are the keys this script could pollute, and they are unchanged.\n' \
        "$PREFS_MD5_BEFORE" "$PREFS_MD5_AFTER"
else
    printf 'UI-SMOKE: dev.kaji preferences domain byte-for-byte unchanged (md5 %s)\n' "$PREFS_MD5_AFTER"
fi


printf 'UI-SMOKE PASS: menu-bar popover opened/closed, AX content verified, page navigation verified; artifacts: %s\n' "$ARTIFACTS"
