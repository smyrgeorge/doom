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
# default it's off the screen but for a corner, each Emacs's its own: its
# slot, E2E_SLOT of E2E_SLOTS, tests/helper.el). JOBS (default: the CPUs)
# unit test Emacsen run at once, E2E_JOBS (default: 8, at most JOBS)
# end-to-end ones, each file's result shown as it ends (in a terminal, a
# line under them says how many are done and running). The longest start
# first, as long as each took in its last run (tests/.durations, kept out
# of git; written after each run), so the run ends once its longest file
# does, the short ones filling the slots left; with 4 slots or more, one
# takes the shortest first for the first 30 s, so results show from the
# start. A file with a line
# ";; run.sh: alone" runs with none beside it, before the others (a test
# timing itself by the clock); one with ";; run.sh: slow" starts first
# when no run timed it yet (a new clone, CI); one with ";; run.sh: split N"
# too, in N Emacsen at once, each a share of its tests (its minutes no
# longer the run's last ones), its result one
# line. On macOS the unit test files' folders are on a RAM disk made for the
# run (RAM_DISK MB at most, taken as they're written; default 4096, 0: on
# the disk): bd (Dolt) waits for each write to reach the disk, ~40% of a
# run's time there; a failed file's folder is copied beside its log, the
# disk gone once the run ends. Not the end-to-end ones': WebKit reads no
# page from another volume (PDF.js and Excalidraw, copied there, never
# loaded). TEST_LOGS (a folder): each failed file's log copied there too, as
# KIND-NAME.txt (CI keeps them). NICE (default 10): the test Emacsen's
# niceness, so the rest of the machine goes first. Exits 1 if a test failed.


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
E2E_JOBS=${E2E_JOBS:-$((JOBS < 8 ? JOBS : 8))}
RAM_DISK=${RAM_DISK:-4096}
# The test Emacsen's niceness (and their bd's, git's): the tests keep every
# CPU busy, your Emacs and apps go first (0: as any other).
NICE=${NICE:-10}
# How long each file (each part of a split one) took in its last run, a
# line each: KIND BASE PART SECONDS (see above).
TIMES=$TESTS/.durations
# A template with X's: GNU's and BSD's mktemp both take it.
TMP_ROOT=${TMPDIR:-/tmp}
RUN=$(mktemp -d "${TMP_ROOT%/}/doom-tests.XXXXXXXXXX")
# Whose run it is: a later run leaves its RAM disk alone while it runs
# (`ram_disks_left').
echo $$ >"$RUN/run.pid"
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

# Each file's markers (see above), read once, by one grep: a grep for each
# file and marker took 5 s before the first Emacs started, and the loop
# below forked them again ten times a second. MARK_KIND[i]: the i-th file's
# alone, split, slow or nothing; MARK_PARTS[i]: how many Emacsen run its
# tests (1 if it runs alone; a split one, its first split's N).
marks() {  # marks FILE...
  local found=() line file rest kind parts n i=0
  while IFS= read -r line; do
    found+=("$line")
  done < <(grep -H '^;; run\.sh: ' "$@" 2>/dev/null)
  MARK_KIND=() MARK_PARTS=()
  for file in "$@"; do
    kind='' parts=1
    for line in "${found[@]}"; do
      [ "${line%%:;; run.sh: *}" = "$file" ] || continue
      rest=${line#*:;; run.sh: }
      case $rest in
        alone*) kind=alone ;;
        split\ [0-9]*)
          if [ "$kind" != alone ] && [ "$kind" != split ]; then
            kind='split'
            n=${rest#split }
            parts=${n%%[!0-9]*}
          fi ;;
        slow*) [ -n "$kind" ] || kind=slow ;;
      esac
    done
    [ "$kind" = alone ] && parts=1
    MARK_KIND[i]=$kind MARK_PARTS[i]=$parts
    i=$((i + 1))
  done
}

folder_of() {  # folder_of VAR ROOT KIND FILE PART PARTS: VAR set to the folder of FILE's PART under ROOT
  local base=${4##*/}
  base=${base%.el}
  if [ "$6" -gt 1 ]; then
    printf -v "$1" '%s/%s-%s.%s' "$2" "$3" "$base" "$5"
  else
    printf -v "$1" '%s/%s-%s' "$2" "$3" "$base"
  fi
}

folder() {  # folder ROOT KIND FILE PART PARTS: the folder of FILE's PART under ROOT
  local dir
  folder_of dir "$@"
  echo "$dir"
}

work_root() {  # work_root KIND: where KIND's files' Emacsen have their folders
  if [ "$1" = unit ]; then echo "$WORK"; else echo "$RUN"; fi
}

ran() {  # ran KIND FILE PARTS: each of FILE's parts done
  local part dir
  for ((part = 1; part <= $3; part++)); do
    folder_of dir "$RUN" "$1" "$2" "$part" "$3"
    [ -e "$dir/status" ] || return 1
  done
}

# Each file (each part of a split one) has a folder for its run: its log
# (log.txt), its Emacs's pid while it runs (pid: `stop' kills it), its exit
# status once done (status), from which `report_file' shows its result; and
# one for its Emacs: its init folder (home), the files its tests make
# (TEST_TMP), a unit test file's on the RAM disk if there's one, else the
# same. Its Emacs reads nothing: stdin /dev/null, said, not left to bash
# (3.2, macOS's, gives a job started after a loop read from <<< or < <(...)
# the script's stdin: a test asking, y-or-n-p, waited on your terminal).
run_file() {  # run_file KIND FILE PART PARTS [SLOT SLOTS]: an end-to-end one's frame in SLOT
  local kind=$1 file=$2 part=$3 parts=$4 slot=${5:-0} slots=${6:-1} tmp work log status pid waited select=()
  local began=$SECONDS
  tmp=$(folder "$RUN" "$kind" "$file" "$part" "$parts")
  work=$(folder "$(work_root "$kind")" "$kind" "$file" "$part" "$parts")
  log="$tmp/log.txt"
  mkdir -p "$tmp" "$work/home"
  if [ "$kind" = unit ]; then
    select=(-f ert-run-tests-batch-and-exit)
    [ "$parts" -gt 1 ] && select=(--eval "(ert-run-tests-batch-and-exit (+test-part-selector $part $parts))")
    TEST_TMP="$work" nice -n "$NICE" "$EMACS" --batch -Q --init-directory="$work/home" \
      -l "$TESTS/helper.el" -l "$file" "${select[@]}" </dev/null >"$log" 2>&1 &
    pid=$!
    echo "$pid" >"$tmp/pid"
    wait "$pid"
    status=$?
  else
    [ "$parts" -gt 1 ] && select=(--eval "(setq +test-selector (+test-part-selector $part $parts))")
    TEST_TMP="$work" E2E_SLOT="$slot" E2E_SLOTS="$slots" nice -n "$NICE" "$EMACS_GUI" -Q --init-directory="$work/home" \
      -l "$TESTS/helper.el" -l "$file" "${select[@]}" -f +test-e2e-run </dev/null >"$log" 2>&1 &
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
  # How long it took, for the next run's order (`save_times').
  echo $((SECONDS - began)) >"$tmp/seconds"
  echo "$status" >"$tmp/status.part" && mv "$tmp/status.part" "$tmp/status"
}

report_file() {  # report_file KIND FILE PARTS: its result (its parts' together), once it ran
  local kind=$1 file=$2 parts=$3 base part tmp work log status=0 code summary counts
  local total=0 unexpected=0 skipped=0 secs='' any='' r u k t
  base=${file##*/}
  base=${base%.el}
  for ((part = 1; part <= parts; part++)); do
    folder_of tmp "$RUN" "$kind" "$file" "$part" "$parts"
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
    folder_of tmp "$RUN" "$kind" "$file" "$part" "$parts"
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
    # A wait failed with its page hidden (tests/helper.el's A PAGE HIDDEN):
    # the screen, not the config, most likely.
    grep -h 'A wait failed, its page hidden' "$log" | sed 's/^/      /'
    # What its tests left, beside its log: the RAM disk goes with the run.
    [ "$work" = "$tmp" ] || cp -R "$work/." "$tmp/" 2>/dev/null
    echo "      full log: $log"
    [ -n "${TEST_LOGS:-}" ] && cat "$log" >>"$TEST_LOGS/$kind-$base.txt"
  done
}

run_files() {  # run_files KIND N FILE...: N Emacsen running at once, each file's result shown as it ends
  local kind=$1 n=$2 shown=0 running solo='' i k part dir slot base order last='' el
  shift 2
  # slots: the folder of the file each slot's Emacs runs (an end-to-end
  # one's frame: its own corner of the screen, `+test-e2e-frame-place').
  # starts, start_parts, start_dirs: what starts, in order (a file's index,
  # its part, its folder); done_files: the files whose result is shown.
  local files=("$@") starts=() start_parts=() start_dirs=() slots=() done_files=() begun=$SECONDS
  marks "${files[@]}"
  # Those running alone first; then the longest first (each part of a split
  # one), as long as it took in its last run ($TIMES), else 60 s if it's
  # marked slow or split, 5 s if not: a file's order among those as long.
  order=$(
    { cat "$TIMES" 2>/dev/null
      echo '--'
      for i in "${!files[@]}"; do
        base=${files[i]##*/}
        for ((part = 1; part <= MARK_PARTS[i]; part++)); do
          echo "$i $part ${base%.el} ${MARK_KIND[i]:-none}"
        done
      done
    } | awk -v kind="$kind" '
      $0 == "--" { listed = 1; next }
      !listed { if ($1 == kind) took[$2 " " $3] = $4; next }
      { key = $3 " " $2
        took_it = (key in took) ? took[key] : ($4 == "slow" || $4 == "split" ? 60 : 5)
        print ($4 == "alone" ? 0 : 1), took_it, NR, $1, $2 }' |
      sort -k1,1n -k2,2nr -k3,3n
  )
  while read -r _ _ _ i part; do
    [ -n "$i" ] || continue
    folder_of dir "$RUN" "$kind" "${files[i]}" "$part" "${MARK_PARTS[i]}"
    starts+=("$i") start_parts+=("$part") start_dirs+=("$dir")
  done <<<"$order"
  # Two lanes: with 4 slots or more, one takes the shortest first for the
  # run's first 30 s, so results show from the start (every slot on a long
  # file, the first came after a minute); the others the longest first, and
  # it too after. Not longer: the short files left balance the run's end (a
  # lane to the end left files of 10 s there, the run 13 s longer). A file
  # running alone first, before either.
  local front=0 back=$((${#starts[@]} - 1)) quick='' launched=()
  while [ "$shown" -lt ${#files[@]} ]; do
    # Those running: started, not ended (bash 3.2, macOS's, has no `wait
    # -n'). Nothing forked while waiting: `jobs' piped to wc, basename, a
    # grep per file did, ten times a second.
    running=0
    for dir in "${launched[@]}"; do
      [ -e "$dir/status" ] || running=$((running + 1))
    done
    while [ "$front" -le "$back" ] && [ "$running" -lt "$n" ]; do
      k=$front
      if [ "$n" -ge 4 ] && [ $((SECONDS - begun)) -lt 30 ] && [ "${MARK_KIND[${starts[front]}]}" != alone ] &&
          { [ -z "$quick" ] || [ -e "$quick/status" ]; }; then
        k=$back
      fi
      i=${starts[k]}
      [ -n "$solo" ] && [ ! -e "$solo/status" ] && break  # one alone running
      if [ "${MARK_KIND[i]}" = alone ]; then
        [ "$running" -eq 0 ] || break
        solo=${start_dirs[k]}
      fi
      # A slot free: none running there, or its file done (its Emacs gone).
      slot=0
      while [ -n "${slots[slot]:-}" ] && [ ! -e "${slots[slot]}/status" ]; do
        slot=$((slot + 1))
      done
      slots[slot]=${start_dirs[k]}
      run_file "$kind" "${files[i]}" "${start_parts[k]}" "${MARK_PARTS[i]}" "$slot" "$n" &
      launched+=("${start_dirs[k]}")
      running=$((running + 1))
      if [ "$k" -ne "$front" ]; then
        quick=${start_dirs[k]}
        back=$((back - 1))
      else
        front=$((front + 1))
      fi
    done
    # Each file whose parts all ended: its result, now.
    for i in "${!files[@]}"; do
      [ -z "${done_files[i]:-}" ] || continue
      ran "$kind" "${files[i]}" "${MARK_PARTS[i]}" || continue
      report_file "$kind" "${files[i]}" "${MARK_PARTS[i]}"
      done_files[i]=1
      shown=$((shown + 1))
    done
    [ "$shown" -lt ${#files[@]} ] || break
    # A terminal: a line under the results says how many are done, how many
    # running, for how long (the next result replaces it).
    el=$((SECONDS - begun))
    if [ -t 1 ] && [ "$last" != "$shown $running $el" ]; then
      printf '\r\033[K  %s… %s: %d of %d done · %d running · %dm %02ds%s' "$UI_DIM" "$kind" \
        "$shown" ${#files[@]} "$running" $((el / 60)) $((el % 60)) "$UI_RESET"
      last="$shown $running $el"
    fi
    sleep 0.1
  done
  wait
  save_times "$kind" "${files[@]}"
}

save_times() {  # save_times KIND FILE...: how long each file (each part) took, in $TIMES; the others' kept
  local kind=$1 i part dir base seconds new
  new="$RUN/durations.$kind"
  shift
  : >"$new"
  for ((i = 1; i <= $#; i++)); do
    base=${!i}
    base=${base##*/}
    for ((part = 1; part <= MARK_PARTS[i - 1]; part++)); do
      folder_of dir "$RUN" "$kind" "${!i}" "$part" "${MARK_PARTS[i - 1]}"
      [ -e "$dir/seconds" ] || continue
      read -r seconds <"$dir/seconds"
      echo "$kind ${base%.el} $part $seconds" >>"$new"
    done
  done
  [ -s "$new" ] || return 0
  # Its lines, then those of the files it didn't run; written where it can
  # be (not in a read-only checkout: tests/linux/run.sh's).
  { cat "$TIMES" 2>/dev/null; } |
    awk 'NR == FNR { ran[$1 " " $2] = 1; print; next } !(($1 " " $2) in ran)' "$new" - >"$new.all" &&
    cp "$new.all" "$TIMES" 2>/dev/null
  return 0
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
    ram_disk_watch
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

# The RAM disk detached however the run ends. Its traps do (Ctrl-C, kill,
# the terminal closed: `stop', then EXIT); kill -9 runs none, and a run
# killed so left its disk mounted, its memory taken (doom-694). So a
# watcher of its own, from the disk's making: once the run is gone, its
# tests still running are stopped and the disk detached, by its mount point
# (its own: a later run's disk may have its device's name). Not a job of the
# run (forked twice): not waited for, not stopped with its jobs; deaf to
# what stops them. Its disk detached first (the run over), it ends too.
ram_disk_watch() {
  local run=$$ ram=$RUN/ram
  (
    ( trap '' INT TERM HUP QUIT
      while kill -0 "$run" 2>/dev/null && [ -e "$ram/.metadata_never_index" ]; do
        sleep 1
      done
      [ -e "$ram/.metadata_never_index" ] || exit 0
      for pidfile in "$RUN"/*/pid; do
        [ -e "$pidfile" ] && kill "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null
      done
      sleep 1
      hdiutil detach "$ram" -quiet 2>/dev/null || hdiutil detach "$ram" -force -quiet 2>/dev/null
    ) </dev/null >/dev/null 2>&1 &
  )
}

# RAM disks of runs over that weren't detached (a run killed before the
# watcher above, a crash), detached as a run starts: a run.sh's disk
# (mounted at doom-tests.*/ram) whose run.pid isn't a run.sh running, or,
# without one (made before it), whose run's folder hasn't changed for 6
# hours. Another run going on (another session's) keeps its disk.
ram_disks_left() {
  command -v hdiutil >/dev/null 2>&1 || return 0
  local mnt run pid
  mount | sed -nE 's|^/dev/disk[0-9]+ on (.*/doom-tests\.[A-Za-z0-9]+/ram) \(hfs.*|\1|p' |
    while read -r mnt; do
      run=${mnt%/ram}
      [ "$run" -ef "$RUN" ] && continue
      if [ -r "$run/run.pid" ]; then
        pid=''
        read -r pid <"$run/run.pid"
        [ -n "$pid" ] && ps -o command= -p "$pid" 2>/dev/null | grep -q 'run\.sh' && continue
      else
        [ -n "$(find "$run" -maxdepth 0 -mmin +360 2>/dev/null)" ] || continue
      fi
      hdiutil detach "$mnt" -quiet 2>/dev/null || hdiutil detach "$mnt" -force -quiet 2>/dev/null
    done
}

# shellcheck disable=SC2329 # run by the trap below
stop() {  # Ctrl-C, the script killed, its terminal closed: the tests running stopped too
  trap - INT TERM HUP QUIT
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
trap stop INT TERM HUP QUIT
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
ram_disks_left
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
