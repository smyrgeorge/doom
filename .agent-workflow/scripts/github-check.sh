#!/usr/bin/env bash
# Can the github workflow run at all: its first step
# (.agent-workflow/workflows/github.yml). gh (GitHub's command line)
# installed and logged in, your checkout on main ($MAIN_BRANCH), a remote to
# push to ($GITHUB_REMOTE, origin).
#
# Exit status: 0 it can; 3 it can't: the run fails at once, saying why (its
# last line).

set -uo pipefail

remote=${GITHUB_REMOTE:-origin}
main=${MAIN_BRANCH:-main}

if ! command -v gh >/dev/null 2>&1; then
  echo "github-check.sh: gh (GitHub's command line) isn't installed: brew install gh, then gh auth login" >&2
  exit 3
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "github-check.sh: gh isn't logged in to GitHub: gh auth login" >&2
  exit 3
fi
on=$(git -C "${MAIN:-.}" branch --show-current 2>/dev/null)
if [ "$on" != "$main" ]; then
  echo "github-check.sh: your checkout is on ${on:-a detached HEAD}, not $main: check out $main, then run it again" >&2
  exit 3
fi
if ! git remote get-url "$remote" >/dev/null 2>&1; then
  echo "github-check.sh: no remote $remote to push to" >&2
  exit 3
fi
echo "github-check.sh: gh logged in, your checkout on $main, $remote: $(git remote get-url "$remote")"
