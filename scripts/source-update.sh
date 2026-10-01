#!/bin/bash
# source-update.sh — pinned source update for an installed Kaji.app.
#
#   source-update.sh prepare --tag vX.Y.Z --version X.Y.Z [--revision <40-hex>] \
#                            --dest-app /Applications/Kaji.app
#       Clones the fixed repo at exactly that tag, verifies the revision when
#       given, builds ad-hoc signed, validates the bundle and stages it in a
#       private directory beside the destination (same filesystem). The
#       installed app is never touched. Prints `STAGED=<path>` on success.
#
#   source-update.sh replace --staged <path> --version X.Y.Z \
#                            --dest-app /Applications/Kaji.app --host-pid <pid>
#       Waits for exactly <pid> to exit, re-validates the staged bundle, swaps
#       it in with renames, launches it, and rolls back (relaunching the old
#       app) if the swap or launch fails.
#
# Runs under the system bash 3.2. Every external tool is resolved via PATH so
# tests can stub them; the repository URL is fixed and never configurable.
set -euo pipefail

REPO_URL="https://github.com/MisterBrookT/kaji.git"
BUNDLE_ID="dev.kaji"
EXEC_NAME="Kaji"
WAIT_SECONDS="${KAJI_UPDATE_WAIT_SECONDS:-60}"

die() { echo "error: $*" >&2; exit 1; }

MODE="${1:-}"; [ $# -gt 0 ] && shift
TAG=""; VERSION=""; REVISION=""; DEST_APP=""; STAGED=""; HOST_PID=""; RESULT_FILE=""
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || die "missing value for $1"
  case "$1" in
    --tag) TAG="$2" ;;
    --version) VERSION="$2" ;;
    --revision) REVISION="$2" ;;
    --dest-app) DEST_APP="$2" ;;
    --staged) STAGED="$2" ;;
    --host-pid) HOST_PID="$2" ;;
    --result-file) RESULT_FILE="$2" ;;
    *) die "unknown argument: $1" ;;
  esac
  shift 2
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid version: '${VERSION}'"
case "$DEST_APP" in
  /*/Kaji.app) ;;
  *) die "destination must be an absolute path ending in /Kaji.app: '${DEST_APP}'" ;;
esac
DEST_PARENT="$(dirname "$DEST_APP")"

# validate_bundle <app>: identity, version, executable and a strict signature.
validate_bundle() {
  local app="$1" plist="$1/Contents/Info.plist" value
  [ -f "$plist" ] || { echo "error: missing Info.plist in ${app}" >&2; return 1; }
  value="$(plutil -extract CFBundleIdentifier raw -o - "$plist" 2>/dev/null || true)"
  [ "$value" = "$BUNDLE_ID" ] || { echo "error: bundle identifier '${value}' != ${BUNDLE_ID}" >&2; return 1; }
  value="$(plutil -extract CFBundleShortVersionString raw -o - "$plist" 2>/dev/null || true)"
  [ "$value" = "$VERSION" ] || { echo "error: bundle version '${value}' != ${VERSION}" >&2; return 1; }
  value="$(plutil -extract CFBundleExecutable raw -o - "$plist" 2>/dev/null || true)"
  [ "$value" = "$EXEC_NAME" ] || { echo "error: bundle executable '${value}' != ${EXEC_NAME}" >&2; return 1; }
  [ -x "$app/Contents/MacOS/$EXEC_NAME" ] || { echo "error: executable missing in ${app}" >&2; return 1; }
  codesign --verify --deep --strict "$app" || { echo "error: codesign verification failed for ${app}" >&2; return 1; }
}

prepare() {
  [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid tag: '${TAG}'"
  [ "$TAG" = "v${VERSION}" ] || die "tag ${TAG} does not match version ${VERSION}"
  if [ -n "$REVISION" ]; then
    [[ "$REVISION" =~ ^[0-9a-f]{40}$ ]] || die "invalid revision: '${REVISION}'"
  fi
  [ -d "$DEST_PARENT" ] || die "destination folder missing: ${DEST_PARENT}"
  [ -w "$DEST_PARENT" ] || die "destination folder not writable: ${DEST_PARENT}"

  local tool
  for tool in git swift python3 codesign plutil ditto xcode-select; do
    command -v "$tool" >/dev/null 2>&1 || die "missing prerequisite: ${tool}"
  done
  local developer_dir resolved
  developer_dir="$(xcode-select -p 2>/dev/null)" || die "missing prerequisite: Xcode Command Line Tools (run xcode-select --install)"
  [ -d "$developer_dir" ] || die "developer tools directory is missing; install command-line tools before updating"
  # Probe system developer-tool shims without executing them: a stale tools
  # selection must produce a log, not macOS's installation dialog.
  for tool in git swift python3; do
    resolved="$(command -v "$tool")"
    if [[ "$resolved" == /usr/bin/* ]]; then
      xcrun --find "$tool" >/dev/null 2>&1 || die "missing developer tool: $tool; install command-line tools before updating"
    fi
  done
  python3 -c 'import sys' >/dev/null 2>&1 || die "Python 3 is not working; install command-line tools before updating"

  WORK="$(mktemp -d "${TMPDIR:-/tmp}/kaji-source-update.XXXXXX")"
  STAGE_DIR=""
  trap 'rm -rf "$WORK"; [ -n "$STAGE_DIR" ] && [ "${STAGE_OK:-0}" != 1 ] && rm -rf "$STAGE_DIR"; true' EXIT

  echo "==> cloning ${REPO_URL} @ ${TAG}"
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TAG" \
    "$REPO_URL" "$WORK/src" || die "git clone of ${TAG} failed"
  local head
  head="$(git -C "$WORK/src" rev-parse HEAD)" || die "cannot read cloned revision"
  if [ -n "$REVISION" ] && [ "$head" != "$REVISION" ]; then
    die "tag ${TAG} resolved to ${head}, expected ${REVISION}"
  fi

  echo "==> building ${TAG} (${head}) with ad-hoc signing"
  ( cd "$WORK/src" && env -u KAJI_CODESIGN_IDENTITY KAJI_UNIVERSAL=0 /bin/bash scripts/build-app.sh ) \
    || die "build failed"
  local built="$WORK/src/dist/Kaji.app"
  [ -d "$built" ] || die "build produced no dist/Kaji.app"
  validate_bundle "$built" || die "built bundle failed validation"

  STAGE_DIR="$(mktemp -d "${DEST_PARENT}/.kaji-update.XXXXXX")" || die "cannot create staging folder"
  ditto "$built" "$STAGE_DIR/Kaji.app" || die "copy to staging failed"
  validate_bundle "$STAGE_DIR/Kaji.app" || die "staged bundle failed validation"
  xattr -dr com.apple.quarantine "$STAGE_DIR/Kaji.app" 2>/dev/null || true
  STAGE_OK=1
  echo "STAGED=${STAGE_DIR}/Kaji.app"
}

replace() {
  case "$STAGED" in
    "$DEST_PARENT"/.kaji-update.*/Kaji.app) ;;
    *) die "staged bundle must live in ${DEST_PARENT}/.kaji-update.*: '${STAGED}'" ;;
  esac
  [[ "$HOST_PID" =~ ^[0-9]+$ ]] || die "invalid host pid: '${HOST_PID}'"
  local stage_dir backup old_saved=0
  stage_dir="$(dirname "$STAGED")"
  backup="$stage_dir/Kaji.previous.app"
  # Replacement failures happen after the host may already have exited.
  # Persist the verdict before reopening the old app so it can show the log.
  trap 'status=$?; if [ "$status" -ne 0 ]; then
    if [ -n "$RESULT_FILE" ]; then printf "failure\n" > "$RESULT_FILE"; fi
    if [ "$old_saved" = 1 ] && [ -e "$backup" ]; then
      if [ -e "$DEST_APP" ]; then mv "$DEST_APP" "$stage_dir/Kaji.failed.app" || true; fi
      if ! mv "$backup" "$DEST_APP"; then
        echo "error: rollback failed; previous bundle retained at $backup" >&2
      fi
    fi
    if ! kill -0 "$HOST_PID" 2>/dev/null && [ -e "$DEST_APP" ]; then open "$DEST_APP" || true; fi
  fi' EXIT
  [ -d "$STAGED" ] || die "staged bundle missing: ${STAGED}"
  validate_bundle "$STAGED" || die "staged bundle failed validation; installed app untouched"

  echo "==> waiting for host pid ${HOST_PID} to exit"
  local waited=0
  while kill -0 "$HOST_PID" 2>/dev/null; do
    [ "$waited" -lt "$((WAIT_SECONDS * 5))" ] || die "host pid ${HOST_PID} still running; installed app untouched"
    sleep 0.2
    waited=$((waited + 1))
  done

  if [ -e "$DEST_APP" ]; then
    mv "$DEST_APP" "$backup" || die "cannot move installed app aside; installed app untouched"
    old_saved=1
  fi
  mv "$STAGED" "$DEST_APP" || die "swap failed; restoring previous app"
  # The new app must not clear the pending verdict until launch is verified.
  if [ -n "$RESULT_FILE" ]; then printf 'launching\n' > "$RESULT_FILE"; fi
  open "$DEST_APP" || die "launch of new app failed; rolling back"
  local started=0 attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if ps -axo comm= | grep -Fx -- "$DEST_APP/Contents/MacOS/Kaji" >/dev/null; then started=1; break; fi
    sleep 0.2
  done
  [ "$started" = 1 ] || die "new app did not start; rolling back"
  sleep 1
  ps -axo comm= | grep -Fx -- "$DEST_APP/Contents/MacOS/Kaji" >/dev/null || die "new app exited during launch; rolling back"
  if [ -n "$RESULT_FILE" ]; then printf 'success\n' > "$RESULT_FILE"; fi
  trap - EXIT
  echo "==> updated to ${VERSION}; rollback bundle retained at ${backup}"
}

case "$MODE" in
  prepare) prepare ;;
  replace) replace ;;
  *) die "usage: source-update.sh prepare|replace ..." ;;
esac
