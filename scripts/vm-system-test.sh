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
FAILED=1


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
    tart run --no-audio --no-clipboard "$@" "$name" >"$ARTIFACTS/tart.log" 2>&1 &
    RUN_PROCESS=$!
    wait_for_guest "$name"
    wait_for_gui "$name"
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
    stop_running_vm "$VM"
    if [[ "$MODE" == "run" ]]; then
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
run)
    if [[ "${KAJI_CODESIGN_IDENTITY:--}" == "-" ]]; then
        echo "VM-SYSTEM FAIL: Prevent Sleep requires a Team ID; set KAJI_CODESIGN_IDENTITY explicitly to a signing identity" >&2
        exit 1
    fi
    "$ROOT/scripts/build-app.sh"
    tart clone "$BASE" "$VM"
    start_vm "$VM" --no-graphics --no-pointer --no-keyboard \
        --dir="kaji-source:$ROOT:ro" \
        --dir="kaji-artifacts:$ARTIFACTS"
    VM_RSS_KB="$(ps -o rss= -p "$RUN_PROCESS" | tr -d ' ')"
    printf 'vm_rss_kb=%s\n' "$VM_RSS_KB" >>"$ARTIFACTS/run.env"
    tart exec "$VM" /bin/zsh "/Volumes/My Shared Files/kaji-source/scripts/vm-system-guest.sh"
    FAILED=0
    echo "VM-SYSTEM PASS: artifacts $ARTIFACTS"
    ;;
*)
    echo "usage: $0 [bootstrap|run]" >&2
    exit 2
    ;;
esac
