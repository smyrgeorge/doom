#!/usr/bin/env bash
# GitHub Actions watched: the github workflow's third step
# (.agent-workflow/workflows/github.yml). The runs of origin's main (its last
# commit, as pushed) watched until they're all done: finished already, their
# verdict at once; none at all (GITHUB_APPEAR seconds), said, on.
#
# Exit status: 0 all passed (or none ran); 1 one failed: its failed jobs'
# logs printed (the workflow gives them to its ci agent, which fixes the
# code or its test and commits; then the job runs again from its push); 2 it
# can't (gh failing, a run cancelled): the run asks you.
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

if ! git fetch -q "$remote" "$main"; then
  echo "github-watch.sh: git fetch $remote $main failed" >&2
  exit 2
fi
target=$(git rev-parse "$remote/$main")

waited=0
while :; do
  runs=$(gh run list --commit "$target" --limit 50 --json databaseId,workflowName,status,conclusion \
           --jq '.[] | "\(.databaseId)\t\(.status)\t\(.conclusion)\t\(.workflowName)"' 2>&1) || {
    echo "github-watch.sh: gh run list failed: $runs" >&2
    exit 2
  }
  if [ -z "$runs" ]; then
    if [ "$waited" -ge "$appear" ]; then
      echo "github-watch.sh: no GitHub Actions run for ${target:0:7} after ${appear}s: nothing to check"
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
  echo "github-watch.sh: ${target:0:7} green: $(printf '%s\n' "$runs" | awk -F'\t' '{ printf "%s%s", sep, $4; sep = ", " }') passed"
  exit 0
fi
if printf '%s\n' "$failed" | awk -F'\t' '$3 == "cancelled" { found = 1 } END { exit !found }'; then
  printf '%s\n' "$failed" >&2
  echo "github-watch.sh: a run of ${target:0:7} was cancelled: run it again on GitHub (gh run rerun ID), then go on" >&2
  exit 2
fi
echo "GitHub Actions failed on $main (${target:0:7}):"
printf '%s\n' "$failed" | while IFS=$'\t' read -r id _status conclusion name; do
  echo
  echo "== $name: $conclusion (gh run view $id)"
  gh run view "$id" --log-failed 2>&1 | tail -n "$log_lines"
done
exit 1
