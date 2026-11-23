#!/usr/bin/env bash
# Your main brought to what was pushed, green: the github workflow's last
# step (.agent-workflow/workflows/github.yml), run on a snapshot of the
# issue's branch (its HEAD: your main as the run started, and the fixes
# pushed since). Your checkout on main ($MAIN_BRANCH), fast-forwarded to it.
#
# Exit status: 0 your main is it (fast-forwarded, or it was); 2 it can't
# (your main has commits it hasn't, made meanwhile; your checkout not on
# main): the run asks you.

set -uo pipefail

main=${MAIN_BRANCH:-main}
head=$(git rev-parse HEAD)
checkout=${MAIN:-.}
yours=$(git -C "$checkout" rev-parse "$main")

if [ "$yours" = "$head" ]; then
  echo "github-sync.sh: your $main is ${head:0:7}, what was pushed"
  exit 0
fi
if ! git -C "$checkout" merge-base --is-ancestor "$main" "$head"; then
  echo "github-sync.sh: your $main has commits the pushed one (${head:0:7}) hasn't, made meanwhile: run it again to push them" >&2
  exit 2
fi
if [ "$(git -C "$checkout" branch --show-current)" != "$main" ]; then
  echo "github-sync.sh: your checkout isn't on $main: check it out, then go on" >&2
  exit 2
fi
if ! git -C "$checkout" merge -q --ff-only "$head"; then
  echo "github-sync.sh: your $main couldn't fast-forward to ${head:0:7} (changes of yours in the files the fixes changed?): commit or stash them, then go on" >&2
  exit 2
fi
echo "github-sync.sh: your $main fast-forwarded to ${head:0:7}, with the fixes pushed"
