#!/usr/bin/env bash
# Real-app account interaction check. Launches dist/Kaji.app with an isolated
# PIX_HOME (copy of ~/.pix/accounts-usage.json; the real route file is never
# touched), opens the real popover via the test control hook (works even when
# Ice/Bartender hides the status item), then presses the real SwiftUI buttons
# through the accessibility API (AXPress) and asserts on the route file and
# on-screen text. Screenshots: .build/account-smoke/*.png
# Needs Accessibility permission for the calling terminal. Quit any other Kaji first.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/account-smoke"; PIX="$OUT/pix"
rm -rf "$OUT"; mkdir -p "$PIX"
cp "$HOME/.pix/accounts-usage.json" "$PIX/" 2>/dev/null || echo '{}' > "$PIX/accounts-usage.json"
cp "$HOME/.pix/accounts.json" "$PIX/" 2>/dev/null || true
echo auto > "$PIX/claude-route"
swiftc "$ROOT/scripts/account-smoke-ax.swift" -o "$OUT/ax"
swiftc "$ROOT/scripts/account-smoke-wid.swift" -o "$OUT/wid"
NONCE=$(uuidgen); PORT=$(jot -r 1 40000 59999)
KAJI_UI_SMOKE_NONCE=$NONCE KAJI_UI_SMOKE_PORT=$PORT KAJI_UI_SMOKE_ARTIFACTS="$OUT" PIX_HOME="$PIX" \
  "$ROOT/dist/Kaji.app/Contents/MacOS/Kaji" -enabledModules '(quota)' >"$OUT/kaji.log" 2>&1 &
PID=$!; trap 'kill $PID 2>/dev/null || true' EXIT
act() { curl -sf -XPOST "localhost:$PORT/v1/test/action" -H 'Content-Type: application/json' -d "{\"nonce\":\"$NONCE\",\"action\":\"$1\"}" >/dev/null; }
for _ in $(seq 60); do act refresh-quota 2>/dev/null && break; sleep 1; done
# wait for quota.py to deliver accounts
act open-popover
for _ in $(seq 60); do "$OUT/ax" $PID dump | grep -q "kaji.quota.using" && break; sleep 1; act open-popover || true; done
tree() { "$OUT/ax" $PID dump | awk '!s[$0]++'; }
press() { "$OUT/ax" $PID press "$1" | grep -q "press $1 0" || { echo "FAIL press $1"; tree | grep kaji.quota; exit 1; }; sleep 0.6; }
shot() { sleep 0.5; screencapture -o -x -l "$("$OUT/wid" $PID)" "$OUT/$1.png"; }
render_status() { curl -sf -XPOST "localhost:$PORT/v1/test/render" -H 'Content-Type: application/json' -d "{\"nonce\":\"$NONCE\",\"surface\":\"status\",\"selection\":\"status\",\"outputPath\":\"$OUT/$1.png\"}" >/dev/null && echo "PASS status render $1"; }
has() { tree | grep -q -- "$1"; }
check() { has "$1" && echo "PASS $2" || { echo "FAIL $2 (missing: $1)"; tree | grep kaji.quota; exit 1; }; }
route() { tr -d '\n' < "$PIX/claude-route"; }
for _ in $(seq 30); do has "kaji.quota.account.*.active" && break; sleep 1; act open-popover || true; done
sleep 1
ACTIVE=$(tree | grep -o 'kaji\.quota\.account\.[^ ]*\.active' | head -1 | sed 's/kaji.quota.account.//;s/.active//')
OTHER=$(tree | grep -o 'kaji\.quota\.account\.[^ ]*\.use' | head -1 | sed 's/kaji.quota.account.//;s/.use//')
[[ -n "$ACTIVE" && -n "$OTHER" ]] || { echo "FAIL need active + switchable Claude accounts"; tree | grep kaji; exit 1; }
echo "PASS active=$ACTIVE other=$OTHER"
has "kaji.quota.account.$ACTIVE.use" && { echo "FAIL active row offers Use"; exit 1; } || echo "PASS no Use on active row"
render_status before-status; shot 1-initial
press "kaji.quota.account.$OTHER.use"
if has "kaji.quota.account.$OTHER.confirm"; then
    [[ "$(route)" == auto ]] || { echo "FAIL warning changed route"; exit 1; }
    shot exhausted-warning; press "kaji.quota.account.$OTHER.cancel"
    [[ "$(route)" == auto ]] || { echo "FAIL cancel changed route"; exit 1; }
    echo "PASS exhausted Use + Cancel leave route auto"
    press "kaji.quota.account.$OTHER.use"; press "kaji.quota.account.$OTHER.confirm"; echo "PASS deliberate confirm"
elif [[ "${KAJI_REQUIRE_EXHAUSTED_WARNING:-0}" == 1 ]]; then echo "FAIL expected exhausted warning"; exit 1; fi
[[ "$(route)" == "$OTHER" ]] && echo "PASS Use wrote route=$OTHER" || { echo "FAIL route=$(route)"; exit 1; }
check "kaji.quota.account.$OTHER.toggle\|kaji.quota.account.auto" "Auto offered on pinned row"
check "kaji.quota.account.$ACTIVE.use" "previous account now offers Use"
shot 2-pinned; render_status pinned-status
press kaji.quota.account.auto
[[ "$(route)" == auto ]] && echo "PASS Auto wrote route=auto" || { echo "FAIL auto"; exit 1; }
check "kaji.quota.account.$ACTIVE.active" "auto pick active again"
echo "$OTHER" > "$PIX/claude-route"; act refresh-quota; sleep 0.6
check "kaji.quota.account.auto" "refresh picks up external pin"
echo auto > "$PIX/claude-route"; act refresh-quota; sleep 0.6
grep -q _active "$PIX/accounts-usage.json" && echo "PASS _active untouched"
shot 3-final
echo "ACCOUNT-SMOKE PASS; screenshots in $OUT"
