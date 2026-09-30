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
stub curl 'printf "{\n  \"tag_name\": \"v9.9.9\",\n}\n"'
stub git 'dir="${@: -1}"; echo "git $*" >> "'"$WORK"'/log"
mkdir -p "$dir/scripts"
printf "#!/bin/bash\nmkdir -p dist/Kaji.app\n" > "$dir/scripts/build-app.sh"
chmod +x "$dir/scripts/build-app.sh"'

OUT="$(PATH="$BIN:$PATH" LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 KAJI_INSTALL_DEST="$DEST" \
  /bin/bash "$INSTALLER" 2>&1)" || { echo "$OUT"; fail "installer exited non-zero"; }
grep -q 'Cloning MisterBrookT/kaji @v9.9.9' <<<"$OUT" || { echo "$OUT"; fail "tag not printed"; }
grep -q -- '--branch v9.9.9' "$WORK/log" || fail "git clone did not use tag"
[ -d "$DEST/Kaji.app" ] || fail "app not installed to dest"
grep -q "open $DEST/Kaji.app" "$WORK/log" || fail "app not launched"

# 3. Missing release fails with a clear message, not an unbound-variable crash.
stub curl 'echo "{}"'
if OUT="$(PATH="$BIN:$PATH" LC_ALL=en_US.UTF-8 KAJI_INSTALL_DEST="$DEST" /bin/bash "$INSTALLER" 2>&1)"; then
  fail "installer should fail without a release"
fi
grep -q 'no GitHub release found' <<<"$OUT" || { echo "$OUT"; fail "wrong error: $OUT"; }
echo "install.sh tests passed"
