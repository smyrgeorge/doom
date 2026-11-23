#!/usr/bin/env bash
# Your main on GitHub, green: the github workflow's step
# (.agent-workflow/workflows/github.yml), run in the issue's worktree (its
# branch: your main as the run started, and the fixes made since).
#
# 1. gh (GitHub's command line), logged in: else it fails at once.
# 2. Your checkout on main ($MAIN_BRANCH): else it fails.
# 3. Pushed: what origin's main hasn't (the worktree's HEAD: your main's
#    commits, the fixes); nothing to push, on.
# 4. GitHub Actions' runs of origin's main (its last commit) watched until
#    they're all done: finished already, their verdict at once; none at all
#    (GITHUB_APPEAR seconds), said, on.
#
# Exit status: 0 all passed (or none ran); 1 one failed: its failed jobs'
# logs printed (the workflow gives them to its ci agent, which fixes the code
# or its test and commits; then this runs again: pushed, watched again); 2 it
# can't (no gh, not on main, a push refused, a run cancelled): the run asks
# you.
#
# GITHUB_REMOTE (origin), GITHUB_POLL (30: seconds between looks),
# GITHUB_APPEAR (300: seconds a pushed commit's runs have to show up),
# GITHUB_LOG_LINES (150: a failed job's last lines printed).

set -uo pipefail

remote=${GITHUB_REMOTE:-origin}
poll=${GITHUB_POLL:-30}
appear=${GITHUB_APPEAR:-300}
log_lines=${GITHUB_LOG_LINES:-150}
main=${MAIN_BRANCH:-main}

# 1. gh, logged in.
if ! command -v gh >/dev/null 2>&1; then
  echo "github.sh: gh (GitHub's command line) isn't installed: brew install gh, then gh auth login" >&2
  exit 2
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "github.sh: gh isn't logged in to GitHub: gh auth login" >&2
  exit 2
fi

# 2. Your checkout on main.
on=$(git -C "${MAIN:-.}" branch --show-current 2>/dev/null)
if [ "$on" != "$main" ]; then
  echo "github.sh: your checkout is on ${on:-a detached HEAD}, not $main: check out $main, then run it again" >&2
  exit 2
fi

# 3. Pushed.
if ! git fetch -q "$remote" "$main"; then
  echo "github.sh: git fetch $remote $main failed" >&2
  exit 2
fi
head=$(git rev-parse HEAD)
if git merge-base --is-ancestor "$head" "$remote/$main"; then
  echo "github.sh: nothing to push: $remote/$main has ${head:0:7}"
else
  count=$(git rev-list --count "$remote/$main..$head" 2>/dev/null || echo some)
  if ! git push -q "$remote" "HEAD:$main"; then
    echo "github.sh: git push $remote HEAD:$main refused ($remote/$main has commits your main hasn't): pull them, then go on" >&2
    exit 2
  fi
  echo "github.sh: pushed $count commit(s): $remote/$main now ${head:0:7}"
  git fetch -q "$remote" "$main"
fi
target=$(git rev-parse "$remote/$main")

# 4. Its runs watched.
waited=0
while :; do
  runs=$(gh run list --commit "$target" --limit 50 --json databaseId,workflowName,status,conclusion \
           --jq '.[] | "\(.databaseId)\t\(.status)\t\(.conclusion)\t\(.workflowName)"' 2>&1) || {
    echo "github.sh: gh run list failed: $runs" >&2
    exit 2
  }
  if [ -z "$runs" ]; then
    if [ "$waited" -ge "$appear" ]; then
      echo "github.sh: no GitHub Actions run for ${target:0:7} after ${appear}s: nothing to check"
      exit 0
    fi
  elif ! printf '%s\n' "$runs" | awk -F'\t' '$2 != "completed" { found = 1 } END { exit !found }'; then
    break
  fi
  sleep "$poll"
  waited=$((waited + poll))
done

failed=$(printf '%s\n' "$runs" | awk -F'\t' '$3 != "success" && $3 != "skipped" && $3 != "neutral"')
if [ -z "$failed" ]; then
  echo "github.sh: ${target:0:7} green: $(printf '%s\n' "$runs" | awk -F'\t' '{ printf "%s%s", sep, $4; sep = ", " }') passed"
  exit 0
fi
if printf '%s\n' "$failed" | awk -F'\t' '$3 == "cancelled" { found = 1 } END { exit !found }'; then
  echo "github.sh: a run of ${target:0:7} was cancelled: run it again on GitHub (gh run rerun ID), then go on" >&2
  printf '%s\n' "$failed" >&2
  exit 2
fi
echo "GitHub Actions failed on $main (${target:0:7}):"
printf '%s\n' "$failed" | while IFS=$'\t' read -r id _status conclusion name; do
  echo
  echo "== $name: $conclusion (gh run view $id)"
  gh run view "$id" --log-failed 2>&1 | tail -n "$log_lines"
done
exit 1
