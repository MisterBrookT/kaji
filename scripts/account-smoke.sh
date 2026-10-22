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
press() { "$OUT/ax" $PID press "$1" | grep -q "press $1 0" || { echo "FAIL press $1"; exit 1; }; sleep 0.6; }
shot() { screencapture -o -x -l "$("$OUT/wid" $PID)" "$OUT/$1.png"; }
check() { tree | grep -q -- "$1" && echo "PASS $2" || { echo "FAIL $2 (missing: $1)"; tree | grep kaji.quota; exit 1; }; }
mapfile -t CLAUDE < <(tree | grep -o 'kaji\.quota\.account\.[^ ]*\.toggle' | sed 's/kaji.quota.account.//;s/.toggle//' | grep -v '^codex' )
ACTIVE=$(tree | grep "in use" | grep -o 'kaji\.quota\.account\.[^ ]*\.toggle' | head -1 | sed 's/kaji.quota.account.//;s/.toggle//')
OTHER=""; for c in "${CLAUDE[@]}"; do [[ "$c" != "$ACTIVE" ]] && OTHER=$c && break; done
[[ -n "$ACTIVE" && -n "$OTHER" ]] || { echo "FAIL need 2 Claude accounts (active=$ACTIVE other=$OTHER)"; exit 1; }
check "Auto$" "header says Auto"; check "kaji.quota.account.$ACTIVE.use" "active row expanded initially"
tree | grep -q "kaji.quota.account.$OTHER.use" && { echo "FAIL other row should start collapsed"; exit 1; } || echo "PASS other row collapsed"
shot 1-initial
press "kaji.quota.account.$OTHER.toggle"; check "kaji.quota.account.$OTHER.use" "expand shows Use + 5h/7d"; shot 2-expanded
press "kaji.quota.account.$OTHER.use"
[[ "$(cat "$PIX/claude-route")" == "$OTHER" ]] && echo "PASS Use wrote route=$OTHER" || { echo "FAIL route"; exit 1; }
check "Pinned$" "header says Pinned"; check "kaji.quota.account.$OTHER.toggle .*, in use" "pinned account marked in use"; shot 3-pinned
press kaji.quota.account.auto
[[ "$(cat "$PIX/claude-route")" == "auto" ]] && echo "PASS Auto wrote route=auto" || { echo "FAIL auto"; exit 1; }
check "Auto$" "header back to Auto"
echo "$OTHER" > "$PIX/claude-route"; act refresh-quota; sleep 0.6
check "kaji.quota.account.$OTHER.toggle .*, in use" "refresh picks up external pin"; check "kaji.quota.account.$OTHER.use\|Pinned" "user expansion survives refresh"
press "kaji.quota.account.$OTHER.toggle"
tree | grep -q "kaji.quota.account.$OTHER.details" && { echo "FAIL collapse"; exit 1; } || echo "PASS collapse hides details"
shot 4-final
grep -q _active "$PIX/accounts-usage.json" && echo "PASS _active untouched"
tree | grep "toggle" | grep -v "left\|signed out\|unknown\|stale" && { echo "FAIL row without % left/state"; exit 1; } || echo "PASS every row shows % left or a state"
echo "ACCOUNT-SMOKE PASS; screenshots in $OUT"
