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
stub swift 'exit 0'
stub python3 'exit 0'
stub xcode-select 'echo /Library/Developer/CommandLineTools'
stub pkill 'exit 1'
stub sleep 'exit 0'
stub xattr 'exit 0'
stub open 'echo "open $*" >> "'"$WORK"'/log"'
# curl stub: logs args; public releases/latest redirect resolves to $CURL_URL,
# api.github.com returns 403 (unauth rate limit) to prove the API is not needed.
stub curl 'echo "curl $*" >> "'"$WORK"'/curl.log"
for a in "$@"; do case "$a" in *api.github.com*) echo "curl: (22) 403" >&2; exit 22;; esac; done
[ -n "${CURL_FAIL:-}" ] && { echo "curl: (22) The requested URL returned error: ${CURL_FAIL}" >&2; exit 22; }
printf "%s" "$CURL_URL"'
stub git 'dir="${@: -1}"; echo "git $*" >> "'"$WORK"'/log"
mkdir -p "$dir/scripts"
printf "#!/bin/bash\nmkdir -p dist/Kaji.app\n" > "$dir/scripts/build-app.sh"
chmod +x "$dir/scripts/build-app.sh"'

OUT="$(CURL_URL=https://github.com/MisterBrookT/kaji/releases/tag/v9.9.9 PATH="$BIN:$PATH" LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 KAJI_INSTALL_DEST="$DEST" \
  /bin/bash "$INSTALLER" 2>&1)" || { echo "$OUT"; fail "installer exited non-zero"; }
grep -q 'Cloning MisterBrookT/kaji @v9.9.9' <<<"$OUT" || { echo "$OUT"; fail "tag not printed"; }
grep -q -- '--branch v9.9.9' "$WORK/log" || fail "git clone did not use tag"
[ -d "$DEST/Kaji.app" ] || fail "app not installed to dest"
grep -q "open $DEST/Kaji.app" "$WORK/log" || fail "app not launched"

grep -q 'releases/latest' "$WORK/curl.log" || fail "did not use public releases/latest"
grep -q 'api.github.com' "$WORK/curl.log" && fail "should not call unauth API"
grep -qiE -- '(-u |--user|authorization|token)' "$WORK/curl.log" && fail "must not send credentials"

run_expect_fail() { # $1 = expected message; env set by caller; no clone allowed
  : > "$WORK/log"
  if OUT="$(PATH="$BIN:$PATH" LC_ALL=en_US.UTF-8 KAJI_INSTALL_DEST="$DEST" /bin/bash "$INSTALLER" 2>&1)"; then
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
echo "install.sh tests passed"
