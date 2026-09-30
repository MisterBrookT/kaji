#!/bin/bash
# Deterministic test for scripts/release-notes.sh against a scratch repo.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
fail() { echo "FAIL: $1" >&2; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
git init -q
git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "Initial"
git tag v1.0.0
for m in "Fix Codex quota reading (#65)" "feat(menubar): show rings" \
         "Remove the System module (#64)" "Bump bundle version to 1.0.1" \
         "Use compact menu pickers" "Harden helper flow"; do
  git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$m"
done
git tag v1.0.1
OUT="$("$ROOT/scripts/release-notes.sh" v1.0.1)"
EXPECTED='## Kaji v1.0.1

### Fixed

- Fix Codex quota reading (#65)
- Harden helper flow

### Added

- feat(menubar): show rings

### Removed

- Remove the System module (#64)

### Changed

- Use compact menu pickers
'
[[ "$OUT" == "$EXPECTED"* ]] || { printf '%s\n' "$OUT"; fail "categorized notes mismatch"; }
grep -q "not notarized" <<<"$OUT" || fail "missing unsigned/unnotarized notice"
[[ "$OUT" != *"Bump bundle"* ]] || fail "version bump leaked into notes"
[[ "$("$ROOT/scripts/release-notes.sh" v1.0.1)" == "$OUT" ]] || fail "non-deterministic"
echo "release notes tests passed"
