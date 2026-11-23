#!/usr/bin/env bash
# Your main pushed: the github workflow's second step
# (.agent-workflow/workflows/github.yml), run in your checkout (runs-in:
# checkout): its HEAD, your main with the fixes and anything you committed
# meanwhile. Run again after each fix (github-watch.sh's retry-from), the
# fix with it.
#
# Your checkout still on main ($MAIN_BRANCH): else its HEAD isn't main's.
# What origin's main hasn't, pushed to it; nothing to push (it has it all):
# said, on.
#
# Exit status: 0 pushed, or nothing to push; 2 it can't (your checkout not
# on main any more, a fetch failing, a push refused: origin's main has
# commits yours hasn't): the run asks you.

set -uo pipefail

remote=${GITHUB_REMOTE:-origin}
main=${MAIN_BRANCH:-main}

on=$(git branch --show-current 2>/dev/null)
if [ "$on" != "$main" ]; then
  echo "github-push.sh: your checkout is on ${on:-a detached HEAD} now, not $main: check out $main, then go on" >&2
  exit 2
fi
if ! git fetch -q "$remote" "$main"; then
  echo "github-push.sh: git fetch $remote $main failed" >&2
  exit 2
fi
head=$(git rev-parse HEAD)
if git merge-base --is-ancestor "$head" "$remote/$main"; then
  echo "github-push.sh: nothing to push: $remote/$main has ${head:0:7}"
  exit 0
fi
count=$(git rev-list --count "$remote/$main..$head")
if ! git push -q "$remote" "HEAD:$main"; then
  echo "github-push.sh: git push $remote HEAD:$main refused ($remote/$main has commits your main hasn't): pull them, then go on" >&2
  exit 2
fi
echo "github-push.sh: pushed $count commit(s): $remote/$main now ${head:0:7}"
