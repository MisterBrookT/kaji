#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${KAJI_TART_BASE:-kaji-system-base}"
MODE="${1:-run}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
VM="kaji-system-$RUN_ID"
ARTIFACTS="${KAJI_VM_ARTIFACTS:-$HOME/.dev/kaji/runs/vm-system/$RUN_ID}"
DRIVER_BUILD="$ROOT/.build/vm-system-driver/KajiVMTestDriver.app"
RUN_PROCESS=""
KEEP_FAILURE="${KAJI_VM_KEEP_FAILURE:-0}"
KEEP_RUNNING="${KAJI_VM_KEEP_RUNNING:-0}"
FAILED=1

phase() {
    printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"
}

build_driver() {
    rm -rf "$DRIVER_BUILD"
    mkdir -p "$DRIVER_BUILD/Contents/MacOS" "$DRIVER_BUILD/Contents/Resources"
    xcrun swiftc "$ROOT/scripts/vm-ui-driver.swift" -o "$DRIVER_BUILD/Contents/MacOS/KajiVMTestDriver"
    shasum -a 256 "$ROOT/scripts/vm-ui-driver.swift" | cut -d ' ' -f 1 \
        >"$DRIVER_BUILD/Contents/Resources/source.sha256"
    cat >"$DRIVER_BUILD/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>KajiVMTestDriver</string>
  <key>CFBundleIdentifier</key><string>dev.kaji.vm-test-driver</string>
  <key>CFBundleName</key><string>KajiVMTestDriver</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
    codesign --force --deep --sign - "$DRIVER_BUILD" >/dev/null
}

wait_for_guest() {
    for _ in $(seq 1 180); do
        if tart exec "$1" /usr/bin/true >/dev/null 2>&1; then return 0; fi
        sleep 1
    done
    echo "VM-SYSTEM FAIL: guest agent did not become ready" >&2
    return 1
}


wait_for_gui() {
    for _ in $(seq 1 180); do
        if tart exec "$1" /usr/bin/pgrep -x Finder >/dev/null 2>&1; then return 0; fi
        sleep 1
    done
    echo "VM-SYSTEM FAIL: guest GUI session did not become ready" >&2
    return 1
}
start_vm() {
    local name="$1"
    shift
    phase "BOOT starting $name"
    tart run --no-audio --no-clipboard "$@" "$name" >"$ARTIFACTS/tart.log" 2>&1 &
    RUN_PROCESS=$!
    wait_for_guest "$name"
    phase "LOGIN guest agent ready; waiting for Finder"
    wait_for_gui "$name"
    phase "LOGIN ready"
}

stop_running_vm() {
    local name="$1"
    tart stop "$name" >/dev/null 2>&1 || true
    if [[ -n "$RUN_PROCESS" ]]; then
        wait "$RUN_PROCESS" >/dev/null 2>&1 || true
        RUN_PROCESS=""
    fi
}

cleanup() {
    if [[ "$FAILED" == "1" && "$KEEP_RUNNING" == "1" ]]; then
        printf 'VM-SYSTEM retained running VM: %s\n' "$VM" >&2
        printf 'VM-SYSTEM rerun: tart exec %s /bin/zsh \"/Volumes/My Shared Files/kaji-source/scripts/vm-system-guest.sh\"\n' "$VM" >&2
        wait "$RUN_PROCESS" >/dev/null 2>&1 || true
        return
    fi
    phase "CLEANUP stopping and removing ephemeral VM"
    stop_running_vm "$VM"
    if [[ "$MODE" == "run" || "$MODE" == "run-visible" ]]; then
        if [[ "$FAILED" == "1" && "$KEEP_FAILURE" == "1" ]]; then
            printf 'VM-SYSTEM retained failed clone: %s\n' "$VM" >&2
        else
            tart delete "$VM" >/dev/null 2>&1 || true
        fi
    fi
}
trap cleanup EXIT INT TERM

mkdir -p "$ARTIFACTS"
printf '%s\n' "run_id=$RUN_ID" "base=$BASE" "mode=$MODE" >"$ARTIFACTS/run.env"
tart get "$BASE" --format json >"$ARTIFACTS/base.json"
phase "PREPARE building VM UI driver"
build_driver

case "$MODE" in
bootstrap)
    VM="$BASE"
    start_vm "$BASE" \
        --dir="kaji-driver:$ROOT/.build/vm-system-driver:ro"
    tart exec "$BASE" /bin/zsh -lc \
        'sudo rm -rf /Applications/KajiVMTestDriver.app && sudo ditto "/Volumes/My Shared Files/kaji-driver/KajiVMTestDriver.app" /Applications/KajiVMTestDriver.app'
    tart exec "$BASE" /Applications/KajiVMTestDriver.app/Contents/MacOS/KajiVMTestDriver request-trust || true
    echo "Grant KajiVMTestDriver Accessibility in the VM window; this one-time bootstrap is the only interactive step."
    for _ in $(seq 1 300); do
        if [[ "$(tart exec "$BASE" /Applications/KajiVMTestDriver.app/Contents/MacOS/KajiVMTestDriver trusted 2>/dev/null || true)" == "true" ]]; then
            FAILED=0
            tart exec "$BASE" /usr/bin/sudo /sbin/shutdown -h now >/dev/null 2>&1 || true
            wait "$RUN_PROCESS" >/dev/null 2>&1 || true
            RUN_PROCESS=""
            echo "VM-SYSTEM bootstrap complete"
            exit 0
        fi
        sleep 1
    done
    echo "VM-SYSTEM FAIL: Accessibility bootstrap timed out" >&2
    exit 1
    ;;
run|run-visible)
    phase "BUILD assembling Kaji.app"
    "$ROOT/scripts/build-app.sh"
    phase "CLONE creating ephemeral VM from $BASE"
    tart clone "$BASE" "$VM"
    if [[ "$MODE" == "run-visible" ]]; then
        phase "BOOT visible mode; Tart VM window will open"
        start_vm "$VM" \
            --dir="kaji-source:$ROOT:ro" \
            --dir="kaji-artifacts:$ARTIFACTS"
    else
        start_vm "$VM" --no-graphics --no-pointer --no-keyboard \
            --dir="kaji-source:$ROOT:ro" \
            --dir="kaji-artifacts:$ARTIFACTS"
    fi
    VM_RSS_KB="$(ps -o rss= -p "$RUN_PROCESS" | tr -d ' ')"
    printf 'vm_rss_kb=%s\n' "$VM_RSS_KB" >>"$ARTIFACTS/run.env"
    phase "JOURNEY exercising install, normal toggles, and repair"
    if [[ "$KEEP_RUNNING" == "1" ]]; then
        tart exec "$VM" /usr/bin/env KAJI_VM_DEBUG_KEEP_APP=1 \
            /bin/zsh "/Volumes/My Shared Files/kaji-source/scripts/vm-system-guest.sh"
    else
        tart exec "$VM" /bin/zsh "/Volumes/My Shared Files/kaji-source/scripts/vm-system-guest.sh"
    fi
    FAILED=0
    phase "PASS journey complete; artifacts $ARTIFACTS"
    ;;
*)
    echo "usage: $0 [bootstrap|run|run-visible]" >&2
    exit 2
    ;;
esac
