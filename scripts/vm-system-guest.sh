#!/bin/zsh
set -euo pipefail

SOURCE="/Volumes/My Shared Files/kaji-source"
ARTIFACTS="/Volumes/My Shared Files/kaji-artifacts"
DRIVER="/Applications/KajiVMTestDriver.app/Contents/MacOS/KajiVMTestDriver"
NONCE="$(uuidgen)-$(uuidgen)"
PORT=37842
BASE_URL="http://127.0.0.1:$PORT/v1"
STATE_FILE="$ARTIFACTS/state.json"

AUTHORIZATION_COUNT=0
fail() {
    print -u2 "VM-SYSTEM FAIL: $*"
    exit 1
}

state() {
    local temporary="${STATE_FILE}.tmp"
    if curl --silent --show-error "$BASE_URL/state" >"$temporary"; then
        /bin/mv "$temporary" "$STATE_FILE"
    else
        /bin/rm -f "$temporary"
        return 1
    fi
}

state_value() {
    state
    local value
    value="$(/usr/bin/plutil -extract "$1" raw -o - "$STATE_FILE" 2>>"$ARTIFACTS/state-value-errors.log")"
    case "$value" in
        0) print false ;;
        1) print true ;;
        *) print -r -- "$value" ;;
    esac
}

action() {
    local name="$1"
    local target="${2:-}"
    local body
    if [[ -n "$target" ]]; then
        body="{\"nonce\":\"$NONCE\",\"action\":\"$name\",\"target\":$target}"
    else
        body="{\"nonce\":\"$NONCE\",\"action\":\"$name\"}"
    fi
    curl --silent --show-error --fail \
        -H 'Content-Type: application/json' \
        -d "$body" "$BASE_URL/test/action" >>"$ARTIFACTS/actions.jsonl"
    print >>"$ARTIFACTS/actions.jsonl"
}

wait_for_value() {
    local path="$1"
    local expected="$2"
    for _ in {1..200}; do
        if [[ "$(state_value "$path" 2>/dev/null || true)" == "$expected" ]]; then return 0; fi
        /bin/sleep 0.1
    done
    fail "timed out waiting for $path=$expected"
}

wait_for_not_value() {
    local path="$1"
    local unwanted="$2"
    for _ in {1..200}; do
        if [[ "$(state_value "$path" 2>/dev/null || true)" != "$unwanted" ]]; then return 0; fi
        /bin/sleep 0.1
    done
    fail "timed out waiting for $path to change from $unwanted"
}

launch_kaji() {
    local suffix="${1:-initial}"
    /usr/bin/env \
        KAJI_UI_SMOKE_NONCE="$NONCE" \
        KAJI_UI_SMOKE_PORT="$PORT" \
        KAJI_UI_SMOKE_ARTIFACTS="$ARTIFACTS" \
        /Applications/Kaji.app/Contents/MacOS/Kaji \
        >"$ARTIFACTS/kaji-$suffix.stdout.log" 2>"$ARTIFACTS/kaji-$suffix.stderr.log" &
    KAJI_PID=$!
    for _ in {1..200}; do
        if curl --silent --fail "$BASE_URL/state" >"$STATE_FILE"; then break; fi
        kill -0 "$KAJI_PID" 2>/dev/null || fail "Kaji exited during $suffix launch"
        /bin/sleep 0.1
    done
    kill -0 "$KAJI_PID" 2>/dev/null || fail "Kaji is not running after $suffix launch"
}

handle_authorization_if_present() {
    local app
    for app in com.apple.SecurityAgent SecurityAgent com.apple.systempreferences; do
        if "$DRIVER" set-subrole-value "$app" AXSecureTextField admin 0.25 >/dev/null 2>&1; then
            "$DRIVER" dump "$app" >"$ARTIFACTS/authorization-$AUTHORIZATION_COUNT.ax.txt" 2>&1 || true
            if ! "$DRIVER" press-label "$app" Unlock 2 >/dev/null 2>&1 \
                && ! "$DRIVER" press-label "$app" OK 2 >/dev/null 2>&1 \
                && ! "$DRIVER" press-label "$app" Allow 2 >/dev/null 2>&1; then
                fail "authorization password field appeared without a semantic confirmation button"
            fi
            AUTHORIZATION_COUNT=$((AUTHORIZATION_COUNT + 1))
            return
        fi
    done
    return 1
}

cleanup() {
    /usr/bin/log show --last 10m --style compact \
        --predicate 'process == "Kaji" OR process == "KajiSleepHelper" OR process == "backgroundtaskmanagementd"' \
        >"$ARTIFACTS/system.log" 2>&1 || true
    action set-prevent-sleep false >/dev/null 2>&1 || true
    /bin/sleep 1
    pkill -x Kaji >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

[[ -x "$DRIVER" ]] || fail "base VM is not bootstrapped with KajiVMTestDriver"
[[ "$($DRIVER trusted)" == "true" ]] || fail "KajiVMTestDriver lacks Accessibility permission"
EXPECTED_DRIVER_HASH="$(cat /Applications/KajiVMTestDriver.app/Contents/Resources/source.sha256)"
CURRENT_DRIVER_HASH="$(shasum -a 256 "$SOURCE/scripts/vm-ui-driver.swift" | cut -d ' ' -f 1)"
[[ "$EXPECTED_DRIVER_HASH" == "$CURRENT_DRIVER_HASH" ]] || fail "base VM driver is stale; rerun vm-system-test.sh bootstrap"

pkill -x Kaji >/dev/null 2>&1 || true
sudo rm -rf /Applications/Kaji.app
sudo ditto "$SOURCE/dist/Kaji.app" /Applications/Kaji.app
sudo xattr -dr com.apple.quarantine /Applications/Kaji.app 2>/dev/null || true
codesign --verify --deep --strict /Applications/Kaji.app

launch_kaji initial
print "initial_busy=$(state_value sleep.busy)" >"$ARTIFACTS/state-values.log"

print 'ASSERT launch: PASS installed app is running' | tee "$ARTIFACTS/assertions.log"
action set-prevent-sleep true
for _ in {1..12}; do
    if handle_authorization_if_present; then break; fi
    /bin/sleep 0.25
done
wait_for_value sleep.busy false
GUIDANCE="$(state_value sleep.guidance 2>/dev/null || true)"

if [[ "$GUIDANCE" == "approval" ]]; then
    action perform-sleep-guidance
    /bin/sleep 2
    "$DRIVER" dump com.apple.systempreferences >"$ARTIFACTS/system-settings-before.ax.txt"
    "$DRIVER" press-near-label com.apple.systempreferences Kaji 15
    handle_authorization_if_present || true
    /bin/sleep 1
    open -a Kaji
    wait_for_not_value sleep.guidance approval
    wait_for_value sleep.busy false
    "$DRIVER" dump com.apple.systempreferences >"$ARTIFACTS/system-settings-after.ax.txt" 2>&1 || true
elif [[ "$GUIDANCE" == "repair" ]]; then
    action perform-sleep-guidance
    wait_for_value sleep.busy false
fi

wait_for_value sleep.enabled true
print 'ASSERT first-enable: PASS helper enabled without a crash' | tee -a "$ARTIFACTS/assertions.log"
launchctl print system/dev.kaji.sleep-helper >"$ARTIFACTS/helper.launchctl.txt" 2>&1 || true
pmset -g custom >"$ARTIFACTS/pmset-enabled.txt"

action set-prevent-sleep false
wait_for_value sleep.enabled false
print 'ASSERT disable: PASS helper command completed' | tee -a "$ARTIFACTS/assertions.log"

action set-prevent-sleep true
wait_for_value sleep.busy false
wait_for_value sleep.enabled true
[[ "$(state_value sleep.guidancePresented)" == "false" ]] || fail "second enable requested guidance again"
print 'ASSERT second-enable: PASS no second authorization guidance' | tee -a "$ARTIFACTS/assertions.log"

action set-prevent-sleep false
wait_for_value sleep.enabled false

kill "$KAJI_PID"
wait "$KAJI_PID" 2>/dev/null || true
/bin/sleep 1
sudo codesign --force --sign - --identifier dev.kaji.sleep-helper.vm-reinstall \
    /Applications/Kaji.app/Contents/Library/HelperTools/KajiSleepHelper
sudo codesign --force --sign - /Applications/Kaji.app
codesign --verify --deep --strict /Applications/Kaji.app
launch_kaji reinstalled

action set-prevent-sleep true
wait_for_value sleep.busy false
[[ "$(state_value sleep.guidance)" == "repair" ]] || fail "stale registered helper did not request repair"
print 'ASSERT stale-helper: PASS reinstall requests repair instead of crashing' | tee -a "$ARTIFACTS/assertions.log"
action perform-sleep-guidance
wait_for_value sleep.busy false
wait_for_value sleep.enabled true
[[ "$(state_value sleep.guidancePresented)" == "false" ]] || fail "helper repair requested another approval"
print 'ASSERT repair: PASS helper repaired without another approval' | tee -a "$ARTIFACTS/assertions.log"

action set-prevent-sleep false
wait_for_value sleep.enabled false
pmset -g custom >"$ARTIFACTS/pmset-restored.txt"
print \"authorization_count=$AUTHORIZATION_COUNT\" >\"$ARTIFACTS/authorization-count.txt\"
[[ "$AUTHORIZATION_COUNT" -le 1 ]] || fail "authorization appeared more than once"
print 'ASSERT restored: PASS Prevent Sleep is off after the journey' | tee -a "$ARTIFACTS/assertions.log"
state
