#!/usr/bin/env bash
# Runs this config's tests, each test file in a throwaway Emacs of its own
# (emacs -Q, its own init and temp folders: Doom's profile, its state and a
# running Emacs aren't touched). See docs/tests.md.
#
#   tests/run.sh               unit tests (emacs --batch)
#   tests/run.sh e2e           end-to-end tests (a GUI Emacs: WebKit, frames)
#   tests/run.sh all           both
#   tests/run.sh unit tiling   only tests/unit/test-tiling.el (names, any kind)
#
# EMACS (default: emacs) runs the unit tests, EMACS_GUI (default: macOS's
# Emacs.app if there's one, else emacs) the end-to-end ones; E2E_TIMEOUT (default 180) seconds per
# end-to-end file; E2E_WINDOW=front shows their frame whole, focused (by
# default it's off the screen but for a corner). Exits 1 if a test failed.


TESTS=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/ui.sh
. "$TESTS/../scripts/ui.sh"
KIND=${1:-unit}
[ $# -gt 0 ] && shift
case "$KIND" in
  unit|e2e|all) ;;
  *) set -- "$KIND" "$@"; KIND=all ;;
esac
EMACS=${EMACS:-emacs}
if [ -z "${EMACS_GUI:-}" ]; then
  EMACS_GUI=/Applications/Emacs.app/Contents/MacOS/Emacs
  [ -x "$EMACS_GUI" ] || EMACS_GUI=emacs
fi
E2E_TIMEOUT=${E2E_TIMEOUT:-180}
# A template with X's: GNU's and BSD's mktemp both take it.
TMP_ROOT=${TMPDIR:-/tmp}
RUN=$(mktemp -d "${TMP_ROOT%/}/doom-tests.XXXXXXXXXX")
FAILED=()
PASSED=0

wanted() {  # wanted FILE: no names given, or FILE's name among them
  [ ${#NAMES[@]} -eq 0 ] && return 0
  local base
  base=$(basename "$1" .el)
  for name in "${NAMES[@]}"; do
    [ "$base" = "test-$name" ] || [ "$base" = "$name" ] && return 0
  done
  return 1
}

run_file() {  # run_file KIND FILE
  local kind=$1 file=$2 base tmp log status pid waited
  base=$(basename "$file" .el)
  tmp="$RUN/$kind-$base"
  log="$tmp/log.txt"
  mkdir -p "$tmp/home"
  # The file's name while it runs (a terminal: replaced by its result).
  [ -t 1 ] && printf '  %s %s %s' "$(ui_dim "…")" "$(ui_dim "$kind")" "$base"
  if [ "$kind" = unit ]; then
    TEST_TMP="$tmp" "$EMACS" --batch -Q --init-directory="$tmp/home" \
      -l "$TESTS/helper.el" -l "$file" -f ert-run-tests-batch-and-exit >"$log" 2>&1
    status=$?
  else
    TEST_TMP="$tmp" "$EMACS_GUI" -Q --init-directory="$tmp/home" \
      -l "$TESTS/helper.el" -l "$file" -f +test-e2e-run >"$log" 2>&1 &
    pid=$!
    waited=0
    while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt $((E2E_TIMEOUT * 10)) ]; do
      sleep 0.1
      waited=$((waited + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      echo "TIMED OUT after ${E2E_TIMEOUT}s" >>"$log"
      status=124
    else
      wait "$pid"
      status=$?
    fi
  fi
  local summary counts
  summary=$(grep -E '^Ran [0-9]+ tests' "$log" | tail -1)
  # "Ran 74 tests, 73 results as expected, 0 unexpected, 1 skipped (DATE,
  # 1.19 sec)": "74 tests, 1 skipped · 1.2 s".
  counts=$(sed -E 's/^Ran ([0-9]+) tests?,.*[^0-9]([0-9]+) unexpected(, ([0-9]+) skipped)?.*, ([0-9.]+) sec\)$/\1 tests|\2|\4|\5/' <<<"$summary")
  IFS='|' read -r ran unexpected skipped secs <<<"$counts"
  local detail="${ran:-no tests}"
  [ "${unexpected:-0}" != 0 ] && detail="$detail, $unexpected failed"
  [ -n "${skipped:-}" ] && detail="$detail, $skipped skipped"
  [ -n "${secs:-}" ] && detail="$detail · $(printf '%.1f' "$secs") s"
  [ -t 1 ] && printf '\r\033[K'
  local name
  name=$(printf '%-5s %-28s' "$kind" "$base")
  if [ "$status" -eq 0 ]; then
    ui_ok "$name $(ui_dim "$detail")"
    PASSED=$((PASSED + 1))
  else
    if [ -n "$summary" ]; then
      ui_fail "$name $(ui_red FAIL) $(ui_dim "$detail")"
    else
      ui_fail "$name $(ui_red FAIL) $(ui_dim "(exit $status)")"
    fi
    FAILED+=("$kind/$base")
    # Each failure's condition and the list of them; or, if the file didn't
    # get as far as running its tests (it failed to load), the log's end.
    if [ -n "$summary" ]; then
      awk '/^Test .* condition:/ {p = 1} p {print} /^ *FAILED / {p = 0}
           /unexpected results:/ {q = 1} q && /^ *(FAILED|SKIPPED|PASSED)/ {print}' "$log" |
        head -100 | sed 's/^/      /'
    else
      tail -20 "$log" | sed 's/^/      /'
    fi
    grep -h 'TIMED OUT' "$log" | sed 's/^/      /'
    echo "      full log: $log"
  fi
}

NAMES=("$@")
if [ "$KIND" = unit ] || [ "$KIND" = all ]; then
  for file in "$TESTS"/unit/test-*.el; do
    [ -e "$file" ] && wanted "$file" && run_file unit "$file"
  done
fi
if [ "$KIND" = e2e ] || [ "$KIND" = all ]; then
  for file in "$TESTS"/e2e/test-*.el; do
    [ -e "$file" ] && wanted "$file" && run_file e2e "$file"
  done
fi

if [ $((PASSED + ${#FAILED[@]})) -eq 0 ]; then
  ui_error "run.sh: no test file${NAMES[*]:+ named ${NAMES[*]}} ($KIND)"
  exit 2
fi
echo
if [ ${#FAILED[@]} -eq 0 ]; then
  ui_step "$(ui_green "✔ All $PASSED test files passed") $(ui_dim "(logs: $RUN)")"
  exit 0
fi
ui_step "$(ui_red "✖ ${#FAILED[@]} failed:") ${FAILED[*]}; $PASSED passed $(ui_dim "(logs: $RUN)")"
exit 1
