# Scripts, Lisp, the merge

Part of the agent-workflow skill: read [SKILL.md](../SKILL.md) first.

## run:

Its text is a script, run by its `shell` (bash by default), in the job's place: the issue's worktree, or a reading
job's snapshot of the branch. One line naming a file of `.agent-workflow/` runs the user's checkout's copy, never the
branch's: an agent can't change the check it's run against (a file elsewhere is warned about by the check).

Its environment: `ISSUE`, `BRANCH`, `MAIN` (the user's checkout), `MAIN_BRANCH`, `WORKTREE`, `JOB`, `ROUND`, `TRY`,
`BEADS_DIR`, `BEADS_ACTOR` (`ISSUE/JOB`). Its output is kept in the run's `logs/`.

| It returns | Then |
|---|---|
| 0 | the next step |
| 1 | the work is wrong: its output goes to the job's agent (or one with the step's `on-fail` agent, in a job with none), which fixes it and says done; the step runs again (from its `retry-from` step), up to its `retries` |
| 3 | it can't go on: the run failed (its last line why), its agents stopped, its issue open again: for what no agent can fix (a tool missing, the wrong branch) |
| another code, or past its `timeout` | it broke: no agent is sent; the run asks the user (run it again, skip it, stop) |

Retries used up, the run asks the user: go on (with a note for the agent fixing it), skip the step, or stop.

An `on-fail` script (`on-fail: {run: SCRIPT}`, or `{run: SCRIPT, agent: AGENT}`) runs first on an exit 1, where
the step ran, with `FAILED_STEP` (its name, else its number) and `FAILED_OUTPUT` (its output's last 200 lines) in its
environment: 0, it fixed it (the step runs again, its try counted, no agent); 1, it couldn't (to the job's agent, else
the `on-fail` one, told the step's output and the script's; none, the run asks the user); another code, or past the
step's `timeout`, it broke (the run asks). For a fix with no judgement in it: rerunning a flaky CI run, regenerating
a file, clearing a cache.

`retry-from: STEP` (an earlier step of its job: its `name`, or its number from 1): its fix runs the job again from
there, those steps too, its retries counted on it. For a check of what an earlier step made: a push, then CI watched.

```yaml
- run: make test
  timeout: 15m
  retries: 3
- shell: python3
  run: |
    import json, sys
    sys.exit(0 if json.load(open("coverage.json"))["percent"] >= 80 else 1)
- name: push
  run: .agent-workflow/scripts/push.sh
- name: watch
  run: .agent-workflow/scripts/watch.sh
  retries: 5
  retry-from: push
```

## elisp:

Lisp in the user's Emacs, `if`'s helpers bound, in the job's place: returning is 0; `(signal 'agent-workflow-fail
'("why"))` is 1; `(signal 'agent-workflow-abort '("why"))` is 3; any other error, it broke. Quick: it blocks Emacs.

## uses: merge

The issue's branch into the main branch (origin's HEAD, else `main`, else `master`), never pushed:

1. Merged already: done. Its branch changing `.agent-workflow/`: it waits for the user's go.
2. Tried in a worktree of its own. A conflict: rebased onto the main branch if that goes cleanly, and tried again; else
   the `on-fail` agent rebases it, resolving, and the run goes back to its first job that edits (the checks and the
   review run again).
3. Its `with: {suite: ...}` runs there, on the merge: 1 goes to the `on-fail` agent, as a script's.
4. Into the main branch: in the user's checkout if it's there and none of the files it changes has a change of the
   user's (else it waits, naming them); not checked out anywhere: the branch moved, no tree touched.
5. The issue closed (a workflow's own run, no ticket: none).
