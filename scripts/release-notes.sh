#!/usr/bin/env bash
# Print categorized Markdown release notes for one tag.
#
#   scripts/release-notes.sh <tag> [previous-tag]
#
# Commits between the previous tag and <tag> are grouped by their subject's
# leading verb (or conventional-commit type), so notes never depend on PR labels:
#   Fixed   — fix, repair, harden, restore, resolve, correct
#   Added   — add, feat, introduce, support, new, show
#   Removed — remove, drop, retire, delete, trim
#   Changed — everything else except release/version-bump/merge noise
# Deterministic: same git history in, same text out.
set -euo pipefail

TAG="${1:?usage: release-notes.sh <tag> [previous-tag]}"
PREV="${2:-$(git describe --tags --abbrev=0 "${TAG}^" 2>/dev/null || true)}"
RANGE="${PREV:+${PREV}..}${TAG}"

fixed=(); added=(); removed=(); changed=()
while IFS= read -r subject; do
	[[ -z "$subject" ]] && continue
	lower="$(printf '%s' "$subject" | tr '[:upper:]' '[:lower:]')"
	# Strip a conventional-commit prefix like "fix(menubar): " for the verb test.
	verb="${lower%%[ :(]*}"
	case "$verb" in
		merge|release|bump|chore) continue ;;
	esac
	case "$verb" in
		fix|fixes|fixed|repair|harden|restore|resolve|correct) fixed+=("$subject") ;;
		add|adds|added|feat|introduce|support|new|show) added+=("$subject") ;;
		remove|removes|removed|drop|retire|delete|trim) removed+=("$subject") ;;
		*) changed+=("$subject") ;;
	esac
done < <(git log --no-merges --reverse --format=%s "$RANGE")

section() {
	local title="$1"; shift
	[[ $# -eq 0 ]] && return 0
	printf '### %s\n\n' "$title"
	printf -- '- %s\n' "$@"
	printf '\n'
}

printf '## Kaji %s\n\n' "$TAG"
section Fixed "${fixed[@]+"${fixed[@]}"}"
section Added "${added[@]+"${added[@]}"}"
section Removed "${removed[@]+"${removed[@]}"}"
section Changed "${changed[@]+"${changed[@]}"}"
if [[ ${#fixed[@]} -eq 0 && ${#added[@]} -eq 0 && ${#removed[@]} -eq 0 && ${#changed[@]} -eq 0 ]]; then
	printf 'No user-facing changes.\n\n'
fi
cat <<'NOTICE'
### Install notice

`Kaji.app.zip` is a universal (Apple Silicon + Intel) build that is **ad-hoc
signed only — not Developer ID signed and not notarized**. Browsers may report
it as "damaged". Update from inside Kaji, or install with:

```sh
curl -fsSL https://raw.githubusercontent.com/MisterBrookT/kaji/main/install.sh | bash
```

Manual download: `xattr -dr com.apple.quarantine /Applications/Kaji.app`.
NOTICE
