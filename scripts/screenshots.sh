#!/usr/bin/env bash
# Screenshots of the examples: each one (examples/NAME.el) shown in a GUI Emacs
# of its own with this config's look, captured into examples/NAME.png. See
# docs/examples.md.
#
#   scripts/screenshots.sh           every example
#   scripts/screenshots.sh merge     those named
#
# Its Emacs is a throwaway one (tests/helper.el's setup, its own temp
# folders): your Doom profile and a running Emacs aren't touched. Its frame is
# on top of the other windows while it's captured (macOS's screencapture, the
# frame's window alone: no shadow, its corners black, not what's behind
# it; a capture differing from the last screenshot only in the window's edge,
# which macOS draws a little differently each time, leaves it as it is: an
# unchanged example's screenshot isn't rewritten, with ImageMagick): the
# terminal running this needs the Screen Recording permission (System
# Settings > Privacy & Security > Screen & System Audio Recording), which
# macOS asks for the first time. Exit status: 0 each example captured, 1 not,
# 2 a wrong use.
#
# EMACS_GUI (default: the emacs-plus app) runs it; SCREENCAPTURE (default:
# screencapture) captures; SCREENSHOT_DIR (default: examples/) gets them.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scripts/ui.sh
. "$ROOT/scripts/ui.sh"
if [ -z "${EMACS_GUI:-}" ]; then
  EMACS_GUI=/Applications/Emacs.app/Contents/MacOS/Emacs
  [ -x "$EMACS_GUI" ] || EMACS_GUI=emacs
fi
SCREENSHOT_DIR=${SCREENSHOT_DIR:-$ROOT/examples}

case "${1:-}" in
  -h|--help) sed -n '2,/^$/{s/^# \{0,1\}//;p;}' "$0"; exit 0 ;;
esac

names=("$@")
if [ ${#names[@]} -eq 0 ]; then
  for file in "$ROOT"/examples/*.el; do
    [ -e "$file" ] && names+=("$(basename "$file" .el)")
  done
fi
if [ ${#names[@]} -eq 0 ]; then
  ui_error "screenshots.sh: no examples in examples/"
  exit 2
fi
for name in "${names[@]}"; do
  if [ ! -f "$ROOT/examples/$name.el" ]; then
    ui_error "screenshots.sh: no example $name (examples/$name.el)"
    exit 2
  fi
done

# A template with X's: GNU's and BSD's mktemp both take it.
tmp_root=${TMPDIR:-/tmp}
tmp=$(mktemp -d "${tmp_root%/}/doom-screenshots.XXXXXXXXXX")
trap 'rm -rf "$tmp"' EXIT

SCREENSHOT_EXAMPLES="${names[*]}" SCREENSHOT_DIR="$SCREENSHOT_DIR" TEST_TMP="$tmp" \
  "$EMACS_GUI" -Q --init-directory="$tmp/home" \
  -l "$ROOT/tests/helper.el" -l "$ROOT/scripts/screenshots.el" -f +my/screenshots-run \
  >"$tmp/log" 2>&1 &
pid=$!

# 10 minutes at most.
waited=0
while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 6000 ]; do
  sleep 0.1
  waited=$((waited + 1))
done
if kill -0 "$pid" 2>/dev/null; then
  kill "$pid" 2>/dev/null || true
  ui_error "screenshots.sh: Emacs didn't finish; its log:"
  tail -20 "$tmp/log" >&2
  exit 1
fi
status=0
wait "$pid" || status=$?

# Its progress: a screenshot's path (made), else what went wrong with one.
while IFS= read -r line; do
  line=${line#screenshots: }
  case "$line" in
    *.png) ui_ok "$line" ;;
    *) ui_fail "$line" ;;
  esac
done < <(grep '^screenshots: ' "$tmp/log" || true)
if [ "$status" -ne 0 ]; then
  ui_error "screenshots.sh: failed (exit $status); Emacs's log:"
  grep -v '^screenshots: ' "$tmp/log" | tail -20 >&2
fi
exit "$status"
