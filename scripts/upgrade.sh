#!/usr/bin/env bash
# Doom's packages brought up to date, those packages.el pins too: each pin
# moved to its package's latest commit upstream, `doom sync -u' (the new pins
# checked out, the other packages updated), then the tests. They pass:
# packages.el committed, its new pins alone. One fails: the old pins put
# back and checked out again (`doom sync'), nothing committed. See README.md.
#
#   scripts/upgrade.sh          upgrade, test, commit the new pins
#   scripts/upgrade.sh --keep   a test failing: the new pins kept, uncommitted,
#                               to fix the config against them
#
# packages.el pins the packages whose internals the config changes: a new
# commit of theirs is taken once the tests pass with it. packages.el must
# have no uncommitted changes (the commit is its new pins alone). Restart
# Emacs after. Exit status: 0 done (the pins committed, or already the
# latest), 1 a step failed, 2 a wrong use.
#
# DOOM_BIN (default: ~/.config/emacs/bin/doom) and DOOMSCRIPT_BIN (default:
# doomscript beside it) run Doom; TESTS (default: all) is what tests/run.sh
# runs: all, unit or e2e.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scripts/ui.sh
. "$ROOT/scripts/ui.sh"
DOOM_BIN=${DOOM_BIN:-$HOME/.config/emacs/bin/doom}
DOOMSCRIPT_BIN=${DOOMSCRIPT_BIN:-$(dirname "$DOOM_BIN")/doomscript}
TESTS=${TESTS:-all}

keep=0
case "${1:-}" in
  -h|--help) sed -n '2,/^$/{s/^# \{0,1\}//;p;}' "$0"; exit 0 ;;
  --keep) keep=1 ;;
  '') ;;
  *) ui_error "upgrade.sh: no option $1 (--keep, --help)"; exit 2 ;;
esac
if [ $# -gt 1 ]; then
  ui_error "upgrade.sh: one option at most (--keep, --help)"
  exit 2
fi
for bin in "$DOOM_BIN" "$DOOMSCRIPT_BIN"; do
  if [ ! -x "$bin" ]; then
    ui_error "upgrade.sh: no $(basename "$bin") at $bin (DOOM_BIN names Doom's)"
    exit 1
  fi
done

cd "$ROOT"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ui_error "upgrade.sh: $ROOT isn't a git repository"
  exit 2
fi
if ! git diff --quiet HEAD -- packages.el; then
  ui_error "upgrade.sh: packages.el has uncommitted changes: commit or stash them first (the commit is the new pins alone)"
  exit 2
fi

# A template with X's: GNU's and BSD's mktemp both take it.
tmp_root=${TMPDIR:-/tmp}
tmp=$(mktemp -d "${tmp_root%/}/doom-upgrade.XXXXXXXXXX")
cp packages.el "$tmp/packages.el"
# Stopped midway (Ctrl+C, an error): packages.el as it was.
finished=0
# shellcheck disable=SC2329 # run by the trap below
cleanup() {
  if [ "$finished" -eq 0 ] && ! cmp -s "$tmp/packages.el" packages.el; then
    cp "$tmp/packages.el" packages.el
    ui_warn "stopped: packages.el's pins put back; \`doom sync' checks them out again"
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

# The old pins in packages.el again, and checked out.
restore() {
  cp "$tmp/packages.el" packages.el
  ui_step "The pins put back"
  ui_cmd "doom sync"
  if "$DOOM_BIN" sync; then
    ui_ok "packages.el's pins as they were, and checked out"
  else
    ui_fail "doom sync failed: run it again"
  fi
}

ui_step "The pins: each package's latest commit"
if ! "$DOOMSCRIPT_BIN" "$ROOT/scripts/upgrade.el" "$ROOT/packages.el" "$tmp/moved" </dev/null >"$tmp/pins.log" 2>&1; then
  ui_error "upgrade.sh: the pins couldn't be moved:"
  tail -20 "$tmp/pins.log" >&2
  exit 1
fi
names=() lines=()
while read -r name old new repo; do
  names+=("$name")
  lines+=("$name $old $new $repo")
  ui_ok "$name ${old:0:7} → ${new:0:7}"
done <"$tmp/moved"
if [ ${#names[@]} -eq 0 ]; then
  ui_info "each pin already its package's latest commit"
fi

ui_step "Doom's packages"
ui_cmd "doom sync -u"
if ! "$DOOM_BIN" sync -u; then
  ui_error "upgrade.sh: doom sync -u failed"
  [ ${#names[@]} -eq 0 ] || restore
  finished=1
  exit 1
fi

ui_step "The tests"
ui_cmd "tests/run.sh $TESTS"
if ! "$ROOT/tests/run.sh" "$TESTS"; then
  finished=1
  if [ ${#names[@]} -eq 0 ]; then
    ui_error "upgrade.sh: the tests fail with the pins as they were: the other packages' update, or the config"
  elif [ "$keep" -eq 1 ]; then
    ui_error "upgrade.sh: the tests fail with the new pins, kept in packages.el (uncommitted): fix the config, then tests/run.sh and commit packages.el; or put them back: git checkout packages.el && doom sync"
  else
    ui_error "upgrade.sh: the tests fail with the new pins: putting them back (scripts/upgrade.sh --keep keeps them, to fix the config)"
    restore
  fi
  exit 1
fi

finished=1
if [ ${#names[@]} -eq 0 ]; then
  ui_step "✔ Doom's packages up to date, the pins already the latest: nothing to commit. Restart Emacs."
  exit 0
fi

# "a, b and c"
list=${names[0]}
for ((i = 1; i < ${#names[@]}; i++)); do
  if [ "$i" -eq $((${#names[@]} - 1)) ]; then list+=" and ${names[$i]}"; else list+=", ${names[$i]}"; fi
done
body=""
for line in "${lines[@]}"; do
  read -r name old new repo <<<"$line"
  count=$(git -C "$repo" rev-list --count "$old..$new" 2>/dev/null || true)
  body+="- $name: ${old:0:7} → ${new:0:7}${count:+ ($count commits)}"$'\n'
done
if ! git commit -q -m "Packages: $list at their latest commits, the tests passing" -m "${body%$'\n'}" -- packages.el; then
  ui_error "upgrade.sh: the commit failed: the new pins are in packages.el, checked out and tested; commit it by hand"
  exit 1
fi
ui_ok "committed: $(git log -1 --format='%h %s')"
ui_step "✔ Doom's packages up to date. Restart Emacs."
