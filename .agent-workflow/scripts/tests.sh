#!/usr/bin/env bash
# The unit tests of what an issue's branch changed, run by the tested
# workflow (.agent-workflow/workflows/tested.yml) in the job's place (the
# issue's worktree): a test file changed (tests/unit/test-NAME.el), or a part
# of this config (config/NAME.el, config/NAME/...: its tests,
# tests/unit/test-NAME.el and test-NAME-*.el). What it changed: its commits
# since the main branch ($MAIN_BRANCH), and what isn't committed yet.
#
# Exit status: 0 they pass, or none is about what it changed; 1 one failed
# (its output goes to the job's agent, which fixes it); 2 they couldn't run.

set -uo pipefail

base=${MAIN_BRANCH:-main}
names=""
add() {
  case " $names " in
    *" $1 "*) ;;
    *) names="${names:+$names }$1" ;;
  esac
}

while IFS= read -r file; do
  case "$file" in
    tests/unit/test-*.el)
      if [ -e "$file" ]; then
        name=${file#tests/unit/test-}
        add "${name%.el}"
      fi ;;
    config/*)
      part=${file#config/}
      part=${part%%/*}
      part=${part%.el}
      for test in "tests/unit/test-$part.el" tests/unit/test-"$part"-*.el; do
        if [ -e "$test" ]; then
          name=${test#tests/unit/test-}
          add "${name%.el}"
        fi
      done ;;
  esac
done < <(git diff --name-only "$base"...HEAD; git diff --name-only HEAD)

if [ -z "$names" ]; then
  echo "tests.sh: no unit tests about what changed: none run"
  exit 0
fi

echo "tests.sh: tests/run.sh unit $names"
# shellcheck disable=SC2086 # the names, a word each
tests/run.sh unit $names
case $? in
  0) exit 0 ;;
  1) exit 1 ;;
  *) exit 2 ;;
esac
