#!/usr/bin/env bash
# Your main pushed: the github workflow's second step
# (.agent-workflow/workflows/github.yml), run in the issue's worktree (its
# branch: your main as the run started, and the fixes made since). Run
# again after each fix (github-watch.sh's retry-from), the fix with it.
#
# What origin's main hasn't, pushed to it; nothing to push (it has it all):
# said, on.
#
# Exit status: 0 pushed, or nothing to push; 2 it can't (a fetch failing, a
# push refused: origin's main has commits yours hasn't): the run asks you.

set -uo pipefail

remote=${GITHUB_REMOTE:-origin}
main=${MAIN_BRANCH:-main}

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
