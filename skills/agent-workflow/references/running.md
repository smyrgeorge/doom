# Running workflows

Part of the agent-workflow skill: read [SKILL.md](../SKILL.md) first. All of this is the user's to do: an agent of a run
is refused, but an agent the user asks (in its own session) does it.

## Starting

`agent-workflow run ISSUE...` (an epic's id: its open issues): each with its `workflow:NAME` label's workflow, else the
one whose `for` has its type, else `--workflow NAME`. Refused (the others started): closed, a run already, no workflow
or several fitting, a project whose workflows the user doesn't trust. Blocked: queued until its blockers close. The
queue: priority, then the order started.

## A run

Its jobs start once their `needs` are done; those that don't need each other at once, within the pool
(`agent-workflow-pool`), the workflow's and the job's `concurrency`. A job that can't start says why (`build: waiting:
feature at its limit, 3 of 3 agents`). An agent step ends with the agent's `cmd/agent-workflow done OUTCOME "notes"`;
a turn ending without it, the run waits for the user.

States: `queued`, `running`, `waiting` (for the user, saying why), `done`, `cancelled`.

## Its questions

| It asks | Answers (`agent-workflow confirm ISSUE ANSWER`) |
|---|---|
| a job sent the work back too often, or a round changed nothing | `go` (with `--note-to JOB NOTE`), `accept`, `stop` |
| a script's retries used up | `go` (`--note-to JOB NOTE` for its fixer), `skip`, `stop` |
| a step broke, or was interrupted (Emacs stopped, paused) | `go`, `skip`, `stop` |
| its merge waits (your changes, its branch changing `.agent-workflow/`) | `go`, `stop` |
| its budget is used up | `go` (`--more-cost N`, `--more-tokens N`, `--more-time 1h`), `stop` |
| its issue was closed by hand | `go`, `cancel` |
| its branch lost a job's commits | `go`, `stop` |

A result waiting for the user's OK (`approve: true`): `agent-workflow approve ISSUE`, or `reject ISSUE "note"` (an agent
step back to its agent; a script's stops the run).

## Going back, loops

`agent-workflow back ISSUE JOB[.STEP] "note"`: that job and those that need it run again, the work kept, its agent's
session resumed and told the note; `--discard`: the work since the job's round started gone. An outcome's `rerun JOB`
does the same, sent by the job: counted, past `max-rounds` (10) or after a round that changed nothing, the run asks.

## Stopping, continuing

`agent-workflow pause` (nothing new starts; `--now`: running steps stopped, interrupted), `unpause`, `cancel ISSUE`,
`continue [ISSUE] [--current]` (interrupted ones on again: agents' sessions resumed, scripts again; `--current`: with
the workflow as it is now). Runs not over are read back as Emacs starts, waiting for `continue`.

## Its files

`.agent-shell/agent-workflow/runs/ISSUE/N/`: `journal.jsonl` (every event, a JSON line), `state.json` (the run as it
stands), `workflow.yml` (as it started), `logs/`. On the issue: in progress, its metadata (`workflow`, `workflow_run`,
`workflow_state`, `workflow_jobs`), the running job as a label (`job:review`), each job's notes.
