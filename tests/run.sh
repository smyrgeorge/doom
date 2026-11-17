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
# default it's off the screen but for a corner). JOBS (default: the CPUs)
# unit test Emacsen run at once, E2E_JOBS (default: 4, at most JOBS)
# end-to-end ones, the files' results shown in their order. A file with a
# line ";; run.sh: alone" runs with none beside it, before the others (PDF.js
# draws no page in a covered frame, and the end-to-end frames share a
# corner); one with ";; run.sh: slow" starts before the rest (its minute or
# two runs beside them, not after: the run ends sooner); one with ";; run.sh:
# split N" too, in N Emacsen at once, each a share of its tests (its minutes
# no longer the run's last ones), its result one line. On macOS the unit
# test files' folders are on a RAM disk made for the run (RAM_DISK MB at
# most, taken as they're written; default 4096, 0: on the disk): bd (Dolt)
# waits for each write to reach the disk, ~40% of a run's time there; a
# failed file's folder is copied beside its log, the disk gone once the run
# ends. Not the end-to-end ones': WebKit reads no page from another volume
# (PDF.js and Excalidraw, copied there, never loaded). TEST_LOGS
# (a folder): each failed file's log copied there too, as KIND-NAME.txt (CI
# keeps them). Exits 1 if a test failed.


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
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}
E2E_JOBS=${E2E_JOBS:-$((JOBS < 4 ? JOBS : 4))}
RAM_DISK=${RAM_DISK:-4096}
# A template with X's: GNU's and BSD's mktemp both take it.
TMP_ROOT=${TMPDIR:-/tmp}
RUN=$(mktemp -d "${TMP_ROOT%/}/doom-tests.XXXXXXXXXX")
# Where the unit test files' own folders go: the RAM disk, if there's one
# (below).
WORK=$RUN
RAM_DEV=''
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

alone() {  # alone FILE: FILE runs with no other beside it (see above)
  grep -q '^;; run\.sh: alone' "$1"
}

slow() {  # slow FILE: FILE starts before the others (a split one too)
  grep -qE '^;; run\.sh: (slow|split)' "$1"
}

parts() {  # parts FILE: how many Emacsen run FILE's tests (1 if it runs alone)
  local n=''
  alone "$1" || n=$(sed -nE 's/^;; run\.sh: split ([0-9]+).*/\1/p' "$1" | head -1)
  echo "${n:-1}"
}

folder() {  # folder ROOT KIND FILE PART PARTS: the folder of FILE's PART under ROOT
  local base
  base=$(basename "$3" .el)
  if [ "$5" -gt 1 ]; then echo "$1/$2-$base.$4"; else echo "$1/$2-$base"; fi
}

work_root() {  # work_root KIND: where KIND's files' Emacsen have their folders
  if [ "$1" = unit ]; then echo "$WORK"; else echo "$RUN"; fi
}

ran() {  # ran KIND FILE: each of FILE's parts done
  local parts part
  parts=$(parts "$2")
  for ((part = 1; part <= parts; part++)); do
    [ -e "$(folder "$RUN" "$1" "$2" "$part" "$parts")/status" ] || return 1
  done
}

# Each file (each part of a split one) has a folder for its run: its log
# (log.txt), its Emacs's pid while it runs (pid: `stop' kills it), its exit
# status once done (status), from which `report_file' shows its result; and
# one for its Emacs: its init folder (home), the files its tests make
# (TEST_TMP), a unit test file's on the RAM disk if there's one, else the
# same.
run_file() {  # run_file KIND FILE PART PARTS
  local kind=$1 file=$2 part=$3 parts=$4 tmp work log status pid waited select=()
  tmp=$(folder "$RUN" "$kind" "$file" "$part" "$parts")
  work=$(folder "$(work_root "$kind")" "$kind" "$file" "$part" "$parts")
  log="$tmp/log.txt"
  mkdir -p "$tmp" "$work/home"
  if [ "$kind" = unit ]; then
    select=(-f ert-run-tests-batch-and-exit)
    [ "$parts" -gt 1 ] && select=(--eval "(ert-run-tests-batch-and-exit (+test-part-selector $part $parts))")
    TEST_TMP="$work" "$EMACS" --batch -Q --init-directory="$work/home" \
      -l "$TESTS/helper.el" -l "$file" "${select[@]}" >"$log" 2>&1 &
    pid=$!
    echo "$pid" >"$tmp/pid"
    wait "$pid"
    status=$?
  else
    [ "$parts" -gt 1 ] && select=(--eval "(setq +test-selector (+test-part-selector $part $parts))")
    TEST_TMP="$work" "$EMACS_GUI" -Q --init-directory="$work/home" \
      -l "$TESTS/helper.el" -l "$file" "${select[@]}" -f +test-e2e-run >"$log" 2>&1 &
    pid=$!
    echo "$pid" >"$tmp/pid"
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
  rm -f "$tmp/pid"
  echo "$status" >"$tmp/status.part" && mv "$tmp/status.part" "$tmp/status"
}

report_file() {  # report_file KIND FILE: its result (its parts' together), once it ran
  local kind=$1 file=$2 base parts part tmp work log status=0 code summary counts
  local total=0 unexpected=0 skipped=0 secs='' any='' r u k t
  base=$(basename "$file" .el)
  parts=$(parts "$file")
  for ((part = 1; part <= parts; part++)); do
    tmp=$(folder "$RUN" "$kind" "$file" "$part" "$parts")
    code=$(cat "$tmp/status")
    [ "$code" -ne 0 ] && status=$code
    summary=$(grep -E '^Ran [0-9]+ tests?,' "$tmp/log.txt" | tail -1)
    # "Ran 74 tests, 73 results as expected, 0 unexpected, 1 skipped (DATE,
    # 1.19 sec)": 74|0|1|1.19. The parts' added up, the longest's time.
    counts=$(sed -E 's/^Ran ([0-9]+) tests?,.*[^0-9]([0-9]+) unexpected(, ([0-9]+) skipped)?.*, ([0-9.]+) sec\)$/\1|\2|\4|\5/' <<<"$summary")
    IFS='|' read -r r u k t <<<"$counts"
    case "$r" in ''|*[!0-9]*) continue ;; esac
    any=1
    total=$((total + r)) unexpected=$((unexpected + ${u:-0})) skipped=$((skipped + ${k:-0}))
    [ -n "$t" ] && secs=$(awk -v a="${secs:-0}" -v b="$t" 'BEGIN { print (b + 0 > a + 0 ? b : a) }')
  done
  local detail="$total tests"
  [ -n "$any" ] || detail="no tests"
  [ "$unexpected" != 0 ] && detail="$detail, $unexpected failed"
  [ "$skipped" != 0 ] && detail="$detail, $skipped skipped"
  [ -n "$secs" ] && detail="$detail · $(printf '%.1f' "$secs") s"
  [ "$parts" -gt 1 ] && detail="$detail, in $parts parts"
  [ -t 1 ] && printf '\r\033[K'
  local name
  name=$(printf '%-5s %-28s' "$kind" "$base")
  if [ "$status" -eq 0 ]; then
    ui_ok "$name $(ui_dim "$detail")"
    PASSED=$((PASSED + 1))
    return
  fi
  if [ -n "$any" ]; then
    ui_fail "$name $(ui_red FAIL) $(ui_dim "$detail")"
  else
    ui_fail "$name $(ui_red FAIL) $(ui_dim "(exit $status)")"
  fi
  FAILED+=("$kind/$base")
  if [ -n "${TEST_LOGS:-}" ]; then
    mkdir -p "$TEST_LOGS" && : >"$TEST_LOGS/$kind-$base.txt"
  fi
  for ((part = 1; part <= parts; part++)); do
    tmp=$(folder "$RUN" "$kind" "$file" "$part" "$parts")
    work=$(folder "$(work_root "$kind")" "$kind" "$file" "$part" "$parts")
    log="$tmp/log.txt"
    [ "$(cat "$tmp/status")" -ne 0 ] || continue
    # Each failure's condition and the list of them; or, if the file didn't
    # get as far as running its tests (it failed to load), the log's end.
    if grep -qE '^Ran [0-9]+ tests?,' "$log"; then
      awk '/^Test .* condition:/ {p = 1} p {print} /^ *FAILED / {p = 0}
           /unexpected results:/ {q = 1} q && /^ *(FAILED|SKIPPED|PASSED)/ {print}' "$log" |
        head -100 | sed 's/^/      /'
    else
      tail -20 "$log" | sed 's/^/      /'
    fi
    grep -h 'TIMED OUT' "$log" | sed 's/^/      /'
    # What its tests left, beside its log: the RAM disk goes with the run.
    [ "$work" = "$tmp" ] || cp -R "$work/." "$tmp/" 2>/dev/null
    echo "      full log: $log"
    [ -n "${TEST_LOGS:-}" ] && cat "$log" >>"$TEST_LOGS/$kind-$base.txt"
  done
}

run_files() {  # run_files KIND N FILE...: N Emacsen running at once, the files shown in their order
  local kind=$1 n=$2 next=0 shown=0 waiting="" base running solo="" file pass part parts
  shift 2
  local files=("$@") starts=() start_parts=() start_counts=()
  # Those running alone first, then the slow ones (each part of a split
  # one), then the others.
  for pass in alone slow rest; do
    for file in "${files[@]}"; do
      case $pass in
        alone) alone "$file" || continue ;;
        slow) { ! alone "$file" && slow "$file"; } || continue ;;
        rest) { alone "$file" || slow "$file"; } && continue ;;
      esac
      parts=$(parts "$file")
      for ((part = 1; part <= parts; part++)); do
        starts+=("$file") start_parts+=("$part") start_counts+=("$parts")
      done
    done
  done
  while [ "$shown" -lt ${#files[@]} ]; do
    # bash 3.2 (macOS) has no `wait -n': the jobs still running are counted.
    while [ "$next" -lt ${#starts[@]} ]; do
      running=$(jobs -rp | wc -l | tr -d ' ')
      [ "${running:-0}" -lt "$n" ] || break
      [ -n "$solo" ] && [ ! -e "$solo/status" ] && break  # one alone running
      if alone "${starts[$next]}"; then
        [ "${running:-0}" -eq 0 ] || break
        solo=$(folder "$RUN" "$kind" "${starts[$next]}" 1 1)
      fi
      run_file "$kind" "${starts[$next]}" "${start_parts[$next]}" "${start_counts[$next]}" &
      next=$((next + 1))
    done
    base=$(basename "${files[$shown]}" .el)
    if ran "$kind" "${files[$shown]}"; then
      report_file "$kind" "${files[$shown]}"
      shown=$((shown + 1))
    else
      # The name of the file waited for (a terminal: replaced by its result).
      if [ -t 1 ] && [ "$waiting" != "$base" ]; then
        printf '  %s %s %s' "$(ui_dim "…")" "$(ui_dim "$kind")" "$base"
        waiting=$base
      fi
      sleep 0.1
    fi
  done
  wait
}

# On macOS, the unit test files' folders on a RAM disk (see above), at
# $RUN/ram: hidden from the Finder, not indexed; on the disk if it can't be
# made.
ram_disk() {
  [ "$RAM_DISK" -gt 0 ] 2>/dev/null && command -v hdiutil >/dev/null 2>&1 || return 0
  RAM_DEV=$(hdiutil attach -nomount "ram://$((RAM_DISK * 2048))" 2>/dev/null | awk 'NR == 1 { print $1 }')
  if [ -n "$RAM_DEV" ] && mkdir -p "$RUN/ram" && newfs_hfs -v doom-tests "$RAM_DEV" >/dev/null 2>&1 &&
      diskutil mount nobrowse -mountPoint "$RUN/ram" "$RAM_DEV" >/dev/null 2>&1; then
    touch "$RUN/ram/.metadata_never_index"
    WORK=$RUN/ram
  else
    ram_disk_gone
    ui_warn "run.sh: no RAM disk (hdiutil): the tests' folders on the disk"
  fi
}

ram_disk_gone() {  # the RAM disk detached, its memory given back
  [ -n "$RAM_DEV" ] || return 0
  hdiutil detach "$RAM_DEV" -quiet 2>/dev/null || hdiutil detach "$RAM_DEV" -force -quiet 2>/dev/null
  RAM_DEV=''
}

# shellcheck disable=SC2329 # run by the trap below
stop() {  # Ctrl-C, or the script killed: the tests running stopped too
  trap - INT TERM
  local pidfile
  # Background jobs of a script ignore Ctrl-C: killed, the files' runs first
  # (their pid files then stay), then the Emacs they started.
  # shellcheck disable=SC2046 # one pid a word
  kill $(jobs -p) 2>/dev/null
  for pidfile in "$RUN"/*/pid; do
    [ -e "$pidfile" ] && kill "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null
  done
  [ -t 1 ] && printf '\r\033[K'
  ui_error "run.sh: stopped (logs: $RUN)"
  exit 130
}
trap stop INT TERM
trap ram_disk_gone EXIT

NAMES=("$@")
UNIT=()
E2E=()
if [ "$KIND" = unit ] || [ "$KIND" = all ]; then
  for file in "$TESTS"/unit/test-*.el; do
    [ -e "$file" ] && wanted "$file" && UNIT+=("$file")
  done
fi
if [ "$KIND" = e2e ] || [ "$KIND" = all ]; then
  for file in "$TESTS"/e2e/test-*.el; do
    [ -e "$file" ] && wanted "$file" && E2E+=("$file")
  done
fi
[ ${#UNIT[@]} -gt 0 ] && ram_disk
[ ${#UNIT[@]} -gt 0 ] && run_files unit "$JOBS" "${UNIT[@]}"
ram_disk_gone
[ ${#E2E[@]} -gt 0 ] && run_files e2e "$E2E_JOBS" "${E2E[@]}"

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
