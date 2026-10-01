#!/bin/bash
# Regression tests for scripts/source-update.sh. Runs under the system bash with
# git, swift, codesign, open and xcode-select stubbed; plutil/ditto are real.
# Never touches /Applications: the destination is a temp folder.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/scripts/source-update.sh"
fail() { echo "FAIL: $1" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; DEST="$WORK/Applications"; APP="$DEST/Kaji.app"
mkdir -p "$BIN"
REV=0123456789abcdef0123456789abcdef01234567
stub() { printf '#!/bin/bash\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }

stub swift 'exit 0'
stub python3 '[ -z "${PYTHON_FAIL:-}" ]'
mkdir -p "$WORK/Developer"
stub xcode-select 'echo "${DEVELOPER_PATH:-'"$WORK"'/Developer}"'
stub codesign 'echo "codesign $*" >> "'"$WORK"'/log"; [ -z "${CODESIGN_FAIL:-}" ]'
stub open 'echo "open $*" >> "'"$WORK"'/log"; [ -z "${OPEN_FAIL:-}" ]'
stub ps 'count=$(cat "'"$WORK"'/ps-count" 2>/dev/null || echo 0)
count=$((count + 1)); echo "$count" > "'"$WORK"'/ps-count"
[ -n "${LAUNCH_CRASH:-}" ] && exit 0
[ -n "${LAUNCH_EXITS:-}" ] && [ "$count" -gt 1 ] && exit 0
echo "'"$APP"'/Contents/MacOS/Kaji"'
# git stub: clone writes a build script producing a bundle of $BUILD_VERSION;
# rev-parse reports $GIT_HEAD.
stub git 'echo "git $*" >> "'"$WORK"'/log"
case "$*" in
  *rev-parse*) echo "${GIT_HEAD}"; exit 0 ;;
esac
[ -n "${GIT_FAIL:-}" ] && exit 128
dir="${@: -1}"; mkdir -p "$dir/scripts"
cat > "$dir/scripts/build-app.sh" <<EOF
#!/bin/bash
echo "identity=\${KAJI_CODESIGN_IDENTITY:-unset}" >> "'"$WORK"'/log"
[ -n "\${BUILD_FAIL:-}" ] && exit 1
mkdir -p dist/Kaji.app/Contents/MacOS
printf "#!/bin/bash\n" > dist/Kaji.app/Contents/MacOS/Kaji; chmod +x dist/Kaji.app/Contents/MacOS/Kaji
plutil -create xml1 dist/Kaji.app/Contents/Info.plist
plutil -insert CFBundleIdentifier -string "\${BUILD_ID:-dev.kaji}" dist/Kaji.app/Contents/Info.plist
plutil -insert CFBundleExecutable -string Kaji dist/Kaji.app/Contents/Info.plist
plutil -insert CFBundleShortVersionString -string "\${BUILD_VERSION}" dist/Kaji.app/Contents/Info.plist
EOF'

reset_app() {
  rm -rf "$DEST"; rm -f "$WORK/result" "$WORK/ps-count"; mkdir -p "$APP/Contents"; echo old > "$APP/Contents/marker"; : > "$WORK/log"
}
old_intact() { [ "$(cat "$APP/Contents/marker" 2>/dev/null)" = old ] || fail "old app not preserved ($1)"; }
no_leftovers() { ls -A "$DEST" | grep -q '^\.kaji-update' && fail "staging leftovers ($1)"; return 0; }
run() { PATH="$BIN:$PATH" GIT_HEAD="${GIT_HEAD:-$REV}" BUILD_VERSION="${BUILD_VERSION:-1.2.3}" \
  KAJI_CODESIGN_IDENTITY="Developer ID Application: Someone" KAJI_UPDATE_WAIT_SECONDS=1 \
  /bin/bash "$SCRIPT" "$@" 2>&1; }
prepare() { run prepare --tag v1.2.3 --version 1.2.3 --revision "$REV" --dest-app "$APP" "$@"; }
expect_prepare_fail() { # $1 message, $2.. extra args
  local msg="$1"; shift; reset_app
  if OUT="$(prepare "$@")"; then echo "$OUT"; fail "prepare should fail: $msg"; fi
  grep -q "$msg" <<<"$OUT" || { echo "$OUT"; fail "wrong error, want: $msg"; }
  old_intact "$msg"; no_leftovers "$msg"
  grep -q '^open ' "$WORK/log" && fail "launched during failed prepare ($msg)"
  return 0
}

# 1. Successful staging: exact tag pin, revision check, ad-hoc build, untouched app.
reset_app
OUT="$(prepare)" || { echo "$OUT"; fail "prepare failed"; }
STAGED="$(sed -n 's/^STAGED=//p' <<<"$OUT")"
case "$STAGED" in "$DEST"/.kaji-update.*/Kaji.app) ;; *) fail "staged path wrong: $STAGED";; esac
[ -x "$STAGED/Contents/MacOS/Kaji" ] || fail "staged bundle incomplete"
grep -q -- '--branch v1.2.3 https://github.com/MisterBrookT/kaji.git' "$WORK/log" || fail "tag not pinned to fixed repo"
grep -q 'identity=unset' "$WORK/log" || fail "signing identity leaked into build"
grep -q 'codesign --verify --deep --strict' "$WORK/log" || fail "no strict codesign check"
grep -qi 'latest' "$WORK/log" && fail "must not resolve latest"
old_intact "prepare success"

# 2. Successful replacement with the host already gone.
: > "$WORK/log"
sleep 30 & HOST=$!
( sleep 0.5; kill "$HOST" ) &
OUT="$(run replace --staged "$STAGED" --version 1.2.3 --dest-app "$APP" --host-pid "$HOST" --result-file "$WORK/result")" \
  || { echo "$OUT"; fail "replace failed"; }
[ -x "$APP/Contents/MacOS/Kaji" ] || fail "new app not installed"
grep -q "open $APP" "$WORK/log" || fail "new app not launched"
[ "$(cat "$(dirname "$STAGED")/Kaji.previous.app/Contents/marker")" = old ] || fail "rollback backup not retained"
[ "$(cat "$WORK/result")" = success ] || fail "success result not persisted"

# 3. Prepare failure paths preserve the old app and clean staging.
expect_prepare_fail "invalid tag" --tag latest
expect_prepare_fail "does not match version" --tag v1.2.4
expect_prepare_fail "invalid revision" --revision abc
GIT_HEAD=ffffffffffffffffffffffffffffffffffffffff expect_prepare_fail "expected $REV"
GIT_FAIL=1 expect_prepare_fail "git clone of v1.2.3 failed"
BUILD_FAIL=1 expect_prepare_fail "build failed"
PYTHON_FAIL=1 expect_prepare_fail "Python 3 is not working"
DEVELOPER_PATH="$WORK/missing-tools" expect_prepare_fail "developer tools directory is missing"
mv "$BIN/python3" "$BIN/python3.off"
stub xcrun 'exit 1'
PATH_SAVE="$PATH"; PATH=/usr/bin:/bin:/usr/sbin:/sbin
expect_prepare_fail "missing developer tool: python3"
PATH="$PATH_SAVE"; rm "$BIN/xcrun"; mv "$BIN/python3.off" "$BIN/python3"
BUILD_VERSION=9.9.9 expect_prepare_fail "bundle version '9.9.9' != 1.2.3"
BUILD_ID=evil.app expect_prepare_fail "bundle identifier"
CODESIGN_FAIL=1 expect_prepare_fail "codesign verification failed"
stub ditto 'exit 1'
expect_prepare_fail "copy to staging failed"
rm "$BIN/ditto"
mv "$BIN/swift" "$BIN/swift.off"
# swift may also exist on the real PATH; hide it with a failing lookup shim.
PATH_SAVE="$PATH"; PATH="$BIN:/usr/bin:/bin:/usr/sbin:/sbin"
if command -v swift >/dev/null 2>&1; then PATH="$PATH_SAVE"; else
  expect_prepare_fail "missing prerequisite: swift"; fi
PATH="$PATH_SAVE"; mv "$BIN/swift.off" "$BIN/swift"
OUT="$(run prepare --tag v1.2.3 --version 1.2.3 --dest-app "$WORK/Elsewhere/Foo.app")" && fail "bad dest accepted"
grep -q "ending in /Kaji.app" <<<"$OUT" || fail "bad dest message"

stage() { reset_app; OUT="$(prepare)" || { echo "$OUT"; fail "stage failed"; }; STAGED="$(sed -n 's/^STAGED=//p' <<<"$OUT")"; : > "$WORK/log"; }
replace_dead() { run replace --staged "$STAGED" --version 1.2.3 --dest-app "$APP" --host-pid 999999 --result-file "$WORK/result"; }

# 4. Launch failure: roll back and relaunch the old app.
stage
OPEN_FAIL=1 replace_dead >/dev/null && fail "replace should fail on open"
old_intact "open fail"
[ "$(cat "$WORK/result")" = failure ] || fail "failure result not persisted"
[ "$(grep -c "^open $APP" "$WORK/log")" -ge 2 ] || fail "old app not relaunched after failed open"

# Startup failure after open accepted the request must also roll back.
stage
LAUNCH_CRASH=1 replace_dead >/dev/null && fail "replace should fail if new app never starts"
old_intact "new app never starts"
[ "$(cat "$WORK/result")" = failure ] || fail "launch failure verdict missing"
stage
LAUNCH_EXITS=1 replace_dead >/dev/null && fail "replace should fail if new app exits immediately"
old_intact "new app exits"

# 5. Signature invalid at replace time: never stops/moves the old app.
stage
CODESIGN_FAIL=1 replace_dead >/dev/null && fail "replace should fail on codesign"
old_intact "replace codesign"
[ "$(cat "$WORK/result")" = failure ] || fail "validation failure result missing"
grep -q "^open $APP" "$WORK/log" || fail "old app not reopened after late validation failure"

# 6. Wrong version at replace time.
stage
OUT="$(run replace --staged "$STAGED" --version 1.2.4 --dest-app "$APP" --host-pid 999999)" && fail "wrong version accepted"
old_intact "replace version"

# 7. Host never exits: time out, old app untouched (waits only on that pid).
stage
sleep 30 & HOST=$!
OUT="$(run replace --staged "$STAGED" --version 1.2.3 --dest-app "$APP" --host-pid "$HOST")" && fail "should time out"
kill "$HOST" 2>/dev/null || true
grep -q "still running" <<<"$OUT" || { echo "$OUT"; fail "timeout message"; }
old_intact "host alive"

# 8. Swap failure (staged move fails): old app restored and relaunched.
stage
cat > "$BIN/mv" <<EOF
#!/bin/bash
[ "\$1" = "$STAGED" ] && exit 1
exec /bin/mv "\$@"
EOF
chmod +x "$BIN/mv"
replace_dead >/dev/null && fail "replace should fail on swap"
rm "$BIN/mv"
old_intact "swap fail"
grep -q "^open $APP" "$WORK/log" || fail "old app not relaunched after swap failure"

# 9. Staged path outside destination parent is refused.
OUT="$(run replace --staged "$WORK/Kaji.app" --version 1.2.3 --dest-app "$APP" --host-pid 1)" && fail "foreign staged accepted"
grep -q "must live in" <<<"$OUT" || fail "foreign staged message"

# 10. No global kill in the script.
grep -qE '\b(pkill|killall)\b' "$SCRIPT" && fail "script must not use pkill/killall"

echo "source-update tests passed"
