#!/bin/bash
# Non-ad-hoc signing must be rejected before builds or keychain operations.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/bin"
printf '#!/bin/bash\necho build-called > "$POLICY_LOG"\nexit 99\n' > "$WORK/bin/swift"
chmod +x "$WORK/bin/swift"
if OUT="$(PATH="$WORK/bin:$PATH" POLICY_LOG="$WORK/build.log" KAJI_CODESIGN_IDENTITY='Developer ID Application: Test' /bin/bash "$ROOT/scripts/build-app.sh" 2>&1)"; then
  echo 'FAIL: accepted Developer ID signing' >&2; exit 1
fi
if [ -e "$WORK/build.log" ]; then echo 'FAIL: started building before rejecting identity' >&2; exit 1; fi
printf '%s' "$OUT" | grep -q 'only ad-hoc signing' || { echo "$OUT"; exit 1; }
echo 'ad-hoc signing policy tests passed'
