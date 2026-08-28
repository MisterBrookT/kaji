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
DEBUG_KEEP_APP="${KAJI_VM_DEBUG_KEEP_APP:-0}"
WAIT_ATTEMPTS="${KAJI_VM_WAIT_ATTEMPTS:-200}"
fail() {
    print -u2 "VM-SYSTEM FAIL: $*"
    exit 1
}
phase() {
    print "[$(/bin/date -u +%H:%M:%S)] GUEST $*"
}

state() {
    local temporary="${STATE_FILE}.tmp"
    if curl --silent --show-error --max-time 2 "$BASE_URL/state" \
        >"$temporary" 2>>"$ARTIFACTS/state-curl-errors.log"; then
        /bin/mv "$temporary" "$STATE_FILE"
    else
        /bin/rm -f "$temporary"
        return 1
    fi
}

state_value() {
    state || return 1
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
    curl --silent --show-error --fail --max-time 2 \
        -H 'Content-Type: application/json' \
        -d "$body" "$BASE_URL/test/action" >>"$ARTIFACTS/actions.jsonl"
    print >>"$ARTIFACTS/actions.jsonl"
}

wait_for_value() {
    local key_path="$1"
    local expected="$2"
    local attempt value
    for ((attempt = 1; attempt <= WAIT_ATTEMPTS; attempt++)); do
        value="$(state_value "$key_path" 2>/dev/null || true)"
        if [[ "$value" == "$expected" ]]; then return 0; fi
        if (( attempt % 10 == 0 )); then
            print "[$(/bin/date -u +%H:%M:%S)] $key_path=${value:-unavailable}, expected=$expected" \
                >>"$ARTIFACTS/state-values.log"
        fi
        /bin/sleep 0.1
    done
    fail "timed out waiting for $key_path=$expected"
}


launch_kaji() {
    local suffix="${1:-initial}"
    local ready=0
    /bin/launchctl asuser 501 /usr/bin/sudo -u admin /usr/bin/env \
        KAJI_UI_SMOKE_NONCE="$NONCE" \
        KAJI_UI_SMOKE_PORT="$PORT" \
        KAJI_UI_SMOKE_ARTIFACTS="$ARTIFACTS" \
        /Applications/Kaji.app/Contents/MacOS/Kaji \
        >"$ARTIFACTS/kaji-$suffix.stdout.log" 2>"$ARTIFACTS/kaji-$suffix.stderr.log" &
    for _ in {1..200}; do
        if curl --silent --fail --max-time 2 "$BASE_URL/state" >"$STATE_FILE"; then
            ready=1
            break
        fi
        /bin/sleep 0.1
    done
    [[ "$ready" == "1" ]] || fail "Kaji control server did not start during $suffix launch"
    pgrep -x Kaji >/dev/null || fail "Kaji is not running after $suffix launch"
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
authorize_with_wait() {
    for _ in {1..120}; do
        if handle_authorization_if_present; then return 0; fi
        /bin/sleep 0.25
    done
    return 1
}

cleanup() {
    /bin/launchctl print system/dev.kaji.sleep-helper \
        >"$ARTIFACTS/helper-final.launchctl.txt" 2>&1 || true
    /usr/bin/stat -f '%Sp %Su:%Sg %z %N' \
        /Library/PrivilegedHelperTools/dev.kaji.sleep-helper \
        /Library/LaunchDaemons/dev.kaji.sleep-helper.plist \
        >"$ARTIFACTS/helper-files.txt" 2>&1 || true
    /usr/bin/log show --last 10m --style compact \
        --predicate 'process == "Kaji" OR process == "KajiSleepHelper" OR process == "backgroundtaskmanagementd"' \
        >"$ARTIFACTS/system.log" 2>&1 || true
    if [[ "$DEBUG_KEEP_APP" == "1" ]]; then
        print -u2 "VM-SYSTEM retained Kaji for live diagnosis"
        /bin/sleep 3600
        return
    fi
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

phase "INSTALL copying app into guest"
sudo launchctl bootout system/dev.kaji.sleep-helper >/dev/null 2>&1 || true
sudo rm -f /Library/PrivilegedHelperTools/dev.kaji.sleep-helper \
    /Library/LaunchDaemons/dev.kaji.sleep-helper.plist
sudo pmset -a disablesleep 0
pkill -x Kaji >/dev/null 2>&1 || true
sudo rm -rf /Applications/Kaji.app
sudo ditto "$SOURCE/dist/Kaji.app" /Applications/Kaji.app
sudo xattr -dr com.apple.quarantine /Applications/Kaji.app 2>/dev/null || true
codesign --verify --deep --strict /Applications/Kaji.app

launch_kaji initial
print "initial_busy=$(state_value sleep.busy)" >>"$ARTIFACTS/state-values.log"

print 'ASSERT launch: PASS installed app is running' | tee "$ARTIFACTS/assertions.log"
phase "FIRST ENABLE installing helper with administrator authorization"
action set-prevent-sleep true
authorize_with_wait || fail "initial helper install did not present an automatable administrator prompt"
wait_for_value sleep.busy false
GUIDANCE="$(state_value sleep.guidance 2>/dev/null || true)"
[[ -z "$GUIDANCE" ]] || fail "initial helper install left unexpected guidance: $GUIDANCE"

wait_for_value sleep.enabled true
[[ "$AUTHORIZATION_COUNT" == "1" ]] || fail "initial helper install should request one administrator authorization"
print 'ASSERT first-enable: PASS helper enabled without a crash' | tee -a "$ARTIFACTS/assertions.log"
launchctl print system/dev.kaji.sleep-helper >"$ARTIFACTS/helper.launchctl.txt" 2>&1 || true
pmset -g custom >"$ARTIFACTS/pmset-enabled.txt"

phase "NORMAL TOGGLES reusing installed helper without authorization"
action set-prevent-sleep false
wait_for_value sleep.enabled false
print 'ASSERT disable: PASS helper command completed' | tee -a "$ARTIFACTS/assertions.log"

action set-prevent-sleep true
wait_for_value sleep.busy false
wait_for_value sleep.enabled true
[[ "$(state_value sleep.guidancePresented)" == "false" ]] || fail "second enable requested guidance again"
print 'ASSERT second-enable: PASS no second authorization guidance' | tee -a "$ARTIFACTS/assertions.log"
[[ "$AUTHORIZATION_COUNT" == "1" ]] || fail "normal toggles requested another administrator authorization"

action set-prevent-sleep false
wait_for_value sleep.enabled false

phase "UPDATE forcing bundled helper mismatch"
pkill -x Kaji
/bin/sleep 1
sudo codesign --force --sign - --identifier dev.kaji.sleep-helper.vm-reinstall \
    /Applications/Kaji.app/Contents/Library/HelperTools/KajiSleepHelper
sudo codesign --force --sign - /Applications/Kaji.app
codesign --verify --deep --strict /Applications/Kaji.app
launch_kaji reinstalled

phase "REPAIR reinstalling helper with administrator authorization"
action set-prevent-sleep true
wait_for_value sleep.busy false
[[ "$(state_value sleep.guidance)" == "repair" ]] || fail "stale registered helper did not request repair"
print 'ASSERT stale-helper: PASS reinstall requests repair instead of crashing' | tee -a "$ARTIFACTS/assertions.log"
action perform-sleep-guidance
authorize_with_wait || fail "helper repair did not present an automatable administrator prompt"
wait_for_value sleep.busy false
wait_for_value sleep.enabled true
[[ "$(state_value sleep.guidancePresented)" == "false" ]] || fail "helper repair remained unresolved"
print 'ASSERT repair: PASS helper repaired after one explicit update authorization' | tee -a "$ARTIFACTS/assertions.log"

action set-prevent-sleep false
wait_for_value sleep.enabled false
pmset -g custom >"$ARTIFACTS/pmset-restored.txt"
print "authorization_count=$AUTHORIZATION_COUNT" >"$ARTIFACTS/authorization-count.txt"
[[ "$AUTHORIZATION_COUNT" == "2" ]] || fail "journey should authorize once for install and once for forced helper update"
print 'ASSERT restored: PASS Prevent Sleep is off after the journey' | tee -a "$ARTIFACTS/assertions.log"
phase "PASS full guest journey complete"
state
