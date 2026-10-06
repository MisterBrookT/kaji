#!/bin/bash
# Regression tests for install.sh. Runs the real installer under the system
# bash (3.2 on macOS) in a UTF-8 locale with every external command stubbed.
# Guards against `$VAR…` expansions: bash 3.2 treats the first byte of a
# multibyte character as part of the name and dies with "TAG?: unbound variable".
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALLER="$ROOT/install.sh"
fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. Static: every variable followed by a non-ASCII byte must use ${VAR}.
if LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' "$INSTALLER"; then
  fail "unbraced \$VAR directly followed by a non-ASCII character"
fi

# 2. Dynamic: run the installer end-to-end with stubs.
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
BIN="$WORK/bin"; DEST="$WORK/Applications"; mkdir -p "$BIN" "$DEST"
stub() { printf '#!/bin/bash\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }
stub uname 'echo Darwin'
stub swift '[ -n "${SWIFT_BROKEN:-}" ] && exit 1; echo "swift-driver version: 1.0 Apple Swift version ${SWIFT_VER:-6.1.2} (swift-6.1.2-RELEASE)"'
stub sw_vers 'echo "${MACOS_VER:-14.5}"'
stub python3 'exit 0'
stub xcode-select 'case "$1" in --install) echo "xcode-select $*" >> "'"$WORK"'/log";; *) [ -n "${NO_CLT:-}" ] && exit 2; echo /Library/Developer/CommandLineTools;; esac'
stub pkill 'echo "pkill $*" >> "'"$WORK"'/log"; [ -n "${OLD_STUCK:-}" ] || rm -f "'"$WORK"'/running"; exit 1'
stub sleep 'exit 0'
stub xattr 'exit 0'
stub open 'echo "open $*" >> "'"$WORK"'/log"; [ -z "${OPEN_FAIL:-}" ] || exit 1; touch "'"$WORK"'/running"'
stub ps 'if [ -n "${OLD_STUCK:-}" ] || { [ -e "'$WORK'/running" ] && [ -z "${LAUNCH_FAIL:-}" ]; }; then echo "'$DEST'/Kaji.app/Contents/MacOS/Kaji"; fi; exit 0'
# curl stub: logs args; public releases/latest redirect resolves to $CURL_URL,
# api.github.com returns 403 (unauth rate limit) to prove the API is not needed.
stub curl 'echo "curl $*" >> "'"$WORK"'/curl.log"
for a in "$@"; do case "$a" in *api.github.com*) echo "curl: (22) 403" >&2; exit 22;; esac; done
[ -n "${CURL_FAIL:-}" ] && { echo "curl: (22) The requested URL returned error: ${CURL_FAIL}" >&2; exit 22; }
printf "%s" "$CURL_URL"'
stub git '[ "$1" = --version ] && { [ -n "${GIT_BROKEN:-}" ] && { echo "${GIT_ERROR:-git failed}" >&2; exit 1; }; echo "git version 2.39"; exit 0; }
dir="${@: -1}"; echo "git $*" >> "'"$WORK"'/log"
mkdir -p "$dir/scripts"
printf "#!/bin/bash\nif [ -n \"\$BUILD_FAIL\" ]; then exit 1; fi; mkdir -p dist/Kaji.app; echo new > dist/Kaji.app/marker\n" > "$dir/scripts/build-app.sh"
chmod +x "$dir/scripts/build-app.sh"'

OUT="$(CURL_URL=https://github.com/MisterBrookT/kaji/releases/tag/v9.9.9 PATH="$BIN:$PATH" LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 KAJI_INSTALL_DEST="$DEST" \
  /bin/bash "$INSTALLER" 2>&1)" || { echo "$OUT"; fail "installer exited non-zero"; }
grep -q 'Cloning MisterBrookT/kaji @v9.9.9' <<<"$OUT" || { echo "$OUT"; fail "tag not printed"; }
grep -q -- '--branch v9.9.9' "$WORK/log" || fail "git clone did not use tag"
[ -d "$DEST/Kaji.app" ] || fail "app not installed to dest"
grep -q "open $DEST/Kaji.app" "$WORK/log" || fail "app not launched"
grep -q "pkill -f $DEST/Kaji.app/Contents/MacOS/Kaji" "$WORK/log" || fail "pkill did not use custom dest"
grep -q 'pkill -f /Applications/' "$WORK/log" && fail "pkill hit default /Applications"
ls -a "$DEST" | grep -q '^\.Kaji' && fail "staging leftovers in dest"

grep -q 'releases/latest' "$WORK/curl.log" || fail "did not use public releases/latest"
grep -q 'api.github.com' "$WORK/curl.log" && fail "should not call unauth API"
grep -qiE -- '(-u |--user|authorization|token)' "$WORK/curl.log" && fail "must not send credentials"

run_expect_fail() { # $1 = expected message; env set by caller; no clone allowed
  : > "$WORK/log"
  if OUT="$(PATH="$BIN:$PATH" LC_ALL=en_US.UTF-8 KAJI_INSTALL_DEST="${KAJI_INSTALL_DEST:-$DEST}" /bin/bash "$INSTALLER" 2>&1)"; then
    fail "installer should fail ($1)"
  fi
  grep -q "$1" <<<"$OUT" || { echo "$OUT"; fail "wrong error, want: $1"; }
  grep -q '^git ' "$WORK/log" && fail "cloned despite failure ($1)"
  return 0
}
# 3. No release: GitHub redirects releases/latest back to /releases.
export CURL_URL=https://github.com/MisterBrookT/kaji/releases
run_expect_fail 'no GitHub release found'
# 4. Network / rate-limit failure is reported as such, not as "no release".
CURL_FAIL=403 CURL_URL=x run_expect_fail 'could not reach GitHub'
# 5. Unexpected or unsafe redirect targets are rejected before cloning.
for u in 'https://evil.example/MisterBrookT/kaji/releases/tag/v1.2.3' \
         'https://github.com/MisterBrookT/kaji/releases/tag/v1.2.3;rm' \
         'https://github.com/MisterBrookT/kaji/releases/tag/--upload-pack=x' \
         'https://github.com/Other/kaji/releases/tag/v1.2.3'; do
  CURL_URL="$u" run_expect_fail 'unexpected release URL'
done
# 6. Prerequisites: broken/old tools fail early with actionable errors.
export CURL_URL=https://github.com/MisterBrookT/kaji/releases/tag/v9.9.9
MACOS_VER=12.7 run_expect_fail 'macOS 13 or newer'
SWIFT_VER=5.10 MACOS_VER=13.6 run_expect_fail 'building with standard Xcode 16 requires macOS 14.5 or newer; Kaji itself runs on macOS 13'
SWIFT_VER=5.10 run_expect_fail 'Swift 6.0 or newer'
MACOS_VER=13.6 PATH="$BIN:$PATH" KAJI_INSTALL_DEST="$DEST" /bin/bash "$INSTALLER" >/dev/null 2>&1 || fail 'custom Swift 6 on macOS 13 rejected'
grep -q 'xcode-select --install' "$WORK/log" && fail "triggered CLT GUI for old Swift"
SWIFT_BROKEN=1 run_expect_fail 'swift is installed but not working'
GIT_BROKEN=1 run_expect_fail 'git is installed but not working'
GIT_BROKEN=1 GIT_ERROR='Xcode license has not been accepted' run_expect_fail 'Xcode license has not been accepted'
SWIFT_VER=unknown run_expect_fail 'could not determine the Swift version'
MACOS_VER=unknown run_expect_fail 'could not determine the macOS version'
# 7. Destination problems fail before build and keep the existing app.
mkdir -p "$DEST/Kaji.app"; echo old > "$DEST/Kaji.app/marker"
KAJI_INSTALL_DEST="$WORK/missing" run_expect_fail 'does not exist'
chmod a-w "$DEST"
run_expect_fail 'not writable'
chmod u+w "$DEST"
[ "$(cat "$DEST/Kaji.app/marker")" = old ] || fail "existing app damaged"
# 8. Copy failure rolls back to the existing install.
stub cp 'exit 1'
run_expect_fail_after_clone() {
  if OUT="$(PATH="$BIN:$PATH" LC_ALL=en_US.UTF-8 KAJI_INSTALL_DEST="$DEST" /bin/bash "$INSTALLER" 2>&1)"; then fail "should fail on cp"; fi
  grep -q "$1" <<<"$OUT" || { echo "$OUT"; fail "wrong error, want: $1"; }
}
run_expect_fail_after_clone 'existing install was kept'
rm "$BIN/cp"
[ "$(cat "$DEST/Kaji.app/marker")" = old ] || fail "existing app lost on copy failure"
ls -a "$DEST" | grep -q '^\.Kaji' && fail "staging leftovers after failure"
# A stubborn existing process must not be accepted as the new app.
OLD_STUCK=1 run_expect_fail_after_clone 'existing Kaji process did not exit'
[ "$(cat "$DEST/Kaji.app/marker")" = old ] || fail 'stubborn old process lost its app'
# 9. Failure to move the old app aside leaves it untouched.
stub mv 'case "$1" in */Kaji.app) exit 1;; esac; /bin/mv "$@"'
run_expect_fail_after_clone 'could not move the old Kaji.app aside'
[ "$(cat "$DEST/Kaji.app/marker")" = old ] || fail "existing app lost on backup failure"
ls -a "$DEST" | grep -q '^\.Kaji' && fail "staging leftovers after backup failure"
# Failed promotion restores the old app; failed restoration keeps its backup.
stub mv 'case "$1" in
  */.Kaji.app.new.*) exit 1;;
  */.Kaji.app.old.*) [ -n "${RESTORE_FAIL:-}" ] && exit 1;;
esac
/bin/mv "$@"'
run_expect_fail_after_clone 'existing install was kept'
[ "$(cat "$DEST/Kaji.app/marker")" = old ] || fail "existing app lost on promotion failure"
ls -a "$DEST" | grep -q '^\.Kaji' && fail "staging leftovers after rollback"
RESTORE_FAIL=1 run_expect_fail_after_clone 'restore failed; your previous app is saved at'
BACKUP_PATH="$(find "$DEST" -name '.Kaji.app.old.*' -maxdepth 1)"
[ -n "$BACKUP_PATH" ] && [ "$(cat "$BACKUP_PATH/marker")" = old ] || fail "backup lost after failed restoration"
/bin/mv "$BACKUP_PATH" "$DEST/Kaji.app"
# Launch failures restore the old app; failed restoration preserves its backup.
stub mv 'case "$1" in */.Kaji.app.old.*) [ -n "${RESTORE_FAIL:-}" ] && exit 1;; esac; /bin/mv "$@"'
OPEN_FAIL=1 run_expect_fail_after_clone 'could not launch'
[ "$(cat "$DEST/Kaji.app/marker")" = old ] || fail 'open failure did not restore old app'
LAUNCH_FAIL=1 run_expect_fail_after_clone 'could not verify Kaji launched'
[ "$(cat "$DEST/Kaji.app/marker")" = old ] || fail 'early exit did not restore old app'
stub ps '[ -e "'$WORK'/running" ] || exit 0
if [ -n "${EARLY_EXIT:-}" ]; then
  [ -e "'$WORK'/ps-seen" ] && exit 0
  touch "'$WORK'/ps-seen"
fi
if [ -e "'$WORK'/running" ] && [ -z "${LAUNCH_FAIL:-}" ]; then echo "'$DEST'/Kaji.app/Contents/MacOS/Kaji"; fi; exit 0'
EARLY_EXIT=1 run_expect_fail_after_clone 'Kaji exited immediately after launch'
[ "$(cat "$DEST/Kaji.app/marker")" = old ] || fail 'brief launch did not restore old app'
OPEN_FAIL=1 RESTORE_FAIL=1 run_expect_fail_after_clone 'previous app is saved at'
BACKUP_PATH="$(find "$DEST" -maxdepth 1 -name '.Kaji.app.old.*' | head -n 1)"
[ -n "$BACKUP_PATH" ] && [ "$(cat "$BACKUP_PATH/marker")" = old ] || fail 'launch rollback destroyed recovery backup'
/bin/rm -rf "$DEST/Kaji.app"
/bin/mv "$BACKUP_PATH" "$DEST/Kaji.app"
rm "$BIN/mv"
# Build failures do not touch the installed app.
BUILD_FAIL=1 run_expect_fail_after_clone 'nothing was changed'
[ "$(cat "$DEST/Kaji.app/marker")" = old ] || fail 'build failure changed old app'
# 10. Successful upgrade replaces the old app.
PATH="$BIN:$PATH" LC_ALL=en_US.UTF-8 KAJI_INSTALL_DEST="$DEST" /bin/bash "$INSTALLER" >/dev/null 2>&1 || fail "upgrade failed"
[ "$(cat "$DEST/Kaji.app/marker")" = new ] || fail "upgrade did not replace app"
# 11. Relative destinations remain anchored after changing into the clone.
(cd "$WORK" && PATH="$BIN:$PATH" LC_ALL=en_US.UTF-8 KAJI_INSTALL_DEST=Applications /bin/bash "$INSTALLER" >/dev/null 2>&1) || fail "relative destination failed"
[ "$(cat "$DEST/Kaji.app/marker")" = new ] || fail "relative destination installed elsewhere"
echo "install.sh tests passed"
