# Agent workflow

> **Status:** being built (epic `doom-38o`). For now: workflows and profiles, read and checked; the pool of agents;
> runs of agent steps, their jobs in parallel.

A **workflow** describes the work on an issue as GitHub Actions does: jobs, the order they run in, which run in
parallel, and their steps. A step is a script, Lisp, a built-in, or an **agent**: an LLM in agent-shell, with a
**profile** saying what it may do. Agents have no role and no name: the step brings its profile.

## Where they are

| Place | Committed | What |
|---|---|---|
| `config/agent-workflow/workflows/`, `profiles/` | with this config | the starters |
| `.agent-workflow/workflows/`, `profiles/` | yes | the project's, read from your checkout, never an agent's worktree |
| `.agent-shell/agent-workflow/workflows/`, `profiles/` | no | yours |

A workflow is `NAME.yml` (or `.yaml`), a profile `NAME.md`. One of the same name replaces the one before it: a starter,
then the project's, then yours.

## A workflow

```yaml
name: feature
description: A feature built with its tests, reviewed, merged.
for: [feature, task]
concurrency: 3
budget:
  cost: 15
  time: 3h

jobs:
  build:
    steps:
      - agent: build
        prompt: |
          Build {issue}: {issue.title}.
          {issue.acceptance}
      - run: .agent-workflow/scripts/check.sh
        timeout: 15m
        retries: 3

  coverage:
    needs: build
    steps:
      - run: make coverage
      - shell: python
        run: |
          import json, sys
          sys.exit(0 if json.load(open("coverage.json"))["percent"] >= 80 else 1)
        on-fail: build

  docs:
    needs: build
    if: (not (eq (issue-type) 'task))
    agent: docs

  review:
    needs: [build, docs]
    agent: review
    prompt: "The builder said: {jobs.build.notes}"
    approve: true
    outcomes:
      approved: continue
      changes: rerun build
    max-rounds: 10

  merge:
    needs: [review, coverage]
    concurrency: 1
    steps:
      - uses: merge
        on-fail: build
```

| Key | What |
|---|---|
| `name` | Its file's name, if given |
| `description` | What it's for |
| `for` | The issue types it's offered for |
| `concurrency` | How many agents work on its runs at once |
| `budget` | `cost` (dollars), `tokens`, `time` (`3h`) a run may spend |
| `jobs` | Its jobs, each a name (a lowercase letter, then lowercase letters, digits or `-`) |

A job:

| Key | What |
|---|---|
| `needs` | The jobs it runs after (a list too); jobs that don't need each other run in parallel |
| `if` | Lisp: the job runs only if it's true, evaluated as it's about to start |
| `steps` | Its steps, in order; or one step's keys on the job itself (`agent: docs`) |
| `approve` | `true`: its result waits for your OK |
| `outcomes` | What an agent's outcome does: `continue`, or `rerun JOB` (that job and every job after it again) |
| `max-rounds` | How many times it may send the work back before the run asks you (the workflow's too) |
| `concurrency` | How many of it run at once, across runs (`merge: 1`) |

A step does one thing:

| Key | What |
|---|---|
| `agent` | An LLM in agent-shell, with that profile; `prompt`: what it's told |
| `run` | A program, or a script (`run: \|`); `shell`: its interpreter (bash by default, `python`, `node`...) |
| `elisp` | Lisp in your Emacs (quick: it blocks it). Lisp with `: ` in it goes under `elisp: \|` |
| `uses` | A built-in: `merge` |

With `timeout` (`45s`, `10m`, `1h30m`), `retries` (a script's), `on-fail` (the profile of the agent a failing step
goes to, in a job with none) and `approve`.

### Variables

A prompt and a profile name them as `{issue}`:

| Variable | Is |
|---|---|
| `{issue}`, `{issue.title}`, `{issue.description}`, `{issue.acceptance}`, `{issue.notes}` | The issue |
| `{branch}`, `{main}`, `{main-branch}`, `{worktree}`, `{project}` | Where the work is |
| `{diff.stat}` | The branch's changes against main |
| `{jobs.JOB.outcome}`, `{jobs.JOB.notes}` | What an earlier job said |
| `{output}` | A failing script's output |
| `{note}` | Yours, when you send the work back or answer |
| `{round}`, `{try}` | How many times round, how many tries |

## A profile

```markdown
---
description: builds an issue with its tests
tools: Read, Edit, Bash(git commit:*)
deny: Bash(git push:*)
model: opus
mode: acceptEdits
icon: md-hammer ⚙
verb: building
colour: blue
---
Build it with its tests, commit on {branch}.
```

| Key | What |
|---|---|
| `description` | What it's for (needed) |
| `tools` | Allowed without asking |
| `deny` | Never available |
| `model` | `opus`, `sonnet`, `haiku`, a model's id; none: your default |
| `mode` | Claude Code's permission mode; none: auto |
| `icon`, `verb`, `colour` | How its steps are shown |

What's after the front matter is the agent's instructions.

## The pool

Agents run in agent-shell, as many at once as `agent-workflow-pool` says (3), in every project. An agent has no role and
no name: it does one job of an issue's run, and is known by them, `doom-a1b · review`, its session's buffer named so.
Its permissions, its questions and its usage are agent-shell's, as in any session.

- **Its profile** is its step's: its tools, deny, model and mode (none: `agent-workflow-mode`, auto). Variables in its
  tools are filled in as its session starts: `Bash(git -C {worktree} commit:*)`.
- **It's told** the job it does and where, that it never switches branches, pushes, or changes the issue, and how it
  ends its job: `cmd/agent-workflow done OUTCOME "notes"`. Then its profile's instructions.
- **Its `bd` commands** run as `ISSUE/JOB` (`doom-a1b/review`): Beads' history says which job did what.
- **Its canvas** opens no pane of its own.

Each issue's agents work in its worktree, one after another: `.agent-shell/agent-workflow/worktrees/ISSUE`, on the
issue's branch (`feat/doom-a1b-lexer-escapes`, `fix/` for a bug), made from your checkout's HEAD the first time a job
needs it. It's locked with the issue as its reason, and out of git.

A project whose [agent workspace](agent-workspace.md) crew runs has no agents of the pool: they'd take the same issues.

| Setting | Default | What |
|---|---|---|
| `agent-workflow-pool` | `3` | How many agents run at once |
| `agent-workflow-mode` | `"auto"` | The permission mode of an agent whose profile has none |
| `agent-workflow-max-rounds` | `10` | How many times a job may send the work back before the run asks you |

## Runs

`M-x agent-workflow-run` starts runs: it asks for the issues (several at once; an epic: its open issues), then each
one's workflow, asked only when several fit it. From the shell:

```sh
cmd/agent-workflow run doom-a1b doom-c3d          # each with its own workflow
cmd/agent-workflow run doom-epic --workflow quick  # an epic's open issues, with quick
```

An issue's workflow is its `workflow:NAME` label's, else the one whose `for` has its type. An issue is refused, the
others started, when it's closed, has a run already, or no workflow fits it (or several). One that's blocked is
queued until its blockers close, saying by what. Runs on different issues go at once, as the pool allows: a free agent
goes to the highest priority first, then to the run started first.

A run's jobs start once their `needs` are done; one whose `if` doesn't hold then is skipped. Jobs that don't need each
other run at once, as the pool allows. They share the issue's branch:

- **A job that edits** (one of its agents' profiles lets it) works in the issue's worktree, one at a time: the next one
  waits for it, saying so (`tests: waiting for docs, which edits the branch`).
- **A job that only reads** (its profiles deny `Edit` and `Write`, or it runs scripts) works on a snapshot of the
  branch, a worktree of its own detached at the commit the branch is at when it starts
  (`.agent-shell/agent-workflow/worktrees/ISSUE@JOB`), removed once it's over. It runs beside the others.

Each job's start in the journal says which commit it saw. A job's steps run in order, and a job with an agent step keeps its agent to its last step. The agent ends its
step itself, `cmd/agent-workflow done OUTCOME "notes"`, then its turn; a turn that ends without it leaves the run
waiting for you (tell the agent in its session). Its outcome must be `done` or one of its job's `outcomes`. Its job
over, its agent stops, and the next jobs start. Every job done or skipped, the run is, and its worktree goes (its
branch stays).

### Going back

`M-x agent-workflow-back` sends a run back to a job that has run (and a step of it), with your note, to refine what it
did. Nothing is reset: the branch and its commits stay, and changes not committed stay in the worktree. That job and
the jobs that need it, directly or not, run again, a round more; a step of theirs running is stopped first. The others
keep their results. The job's agent has its session resumed, told your note and what the branch has now (a fresh
session is told the same, if the agent can't resume). The journal keeps the earlier rounds.

With `C-u`, the work since the job's round started is discarded: its commits, and the changes not committed. What's
lost is said, and you're asked first.

```sh
cmd/agent-workflow back doom-a1b build "handle the empty list too"
cmd/agent-workflow back doom-a1b build.2 - < note.txt     # its second step; the note from stdin
cmd/agent-workflow back doom-a1b build --discard          # the work since, gone
```

### Loops

An agent's outcome can send the work back: `changes: rerun build` sends it to build as going back does, the outcome's
notes its note, and build and every job after it run again. Going back makes loops, so they're counted, per edge
(review to build) and in all:

- **Past `max-rounds`** (the job's, else the workflow's, else `agent-workflow-max-rounds`: 10), or past 3 times that
  in all, the run asks you.
- **A round that changed nothing** on the branch (no commit, no change not committed) asks you at once.

The question shows what each round said. Answer it with `M-x agent-workflow-confirm`, or from the shell:

| Answer | Does |
|---|---|
| go | On: the count starts again, with your note for the job that sends it back, the one it's sent to, or both |
| accept | It as it is: the run goes on as if the outcome had been `continue` |
| stop | The run waits |

```sh
cmd/agent-workflow confirm doom-a1b go --note-to review "only bugs from now on" --note-to build "use a table"
cmd/agent-workflow confirm doom-a1b accept
```

Your own going back isn't counted, and doesn't start the count again.

In `if`, these say what the issue is: `(issue-id)`, `(issue-type)` (a symbol: `'bug`), `(issue-labels)`,
`(issue-priority)`, `(issue-title)`, `(job-outcome 'review)`, `(job-status 'build)`.

| Where | What |
|---|---|
| `.agent-shell/agent-workflow/runs/ISSUE/N/journal.jsonl` | every event of run N of the issue, a JSON line each, as it happens |
| `state.json` beside it | the run as it stands |
| `workflow.yml` beside it | the workflow as the run started |
| The issue | in progress; its metadata (`workflow`, `workflow_run`, `workflow_state`, `workflow_jobs`), the job running as a label (`job:review`), what each job said in its notes. Written as `agent-workflow` |

## Checking them

`M-x agent-workflow-check` reads the project's workflows and profiles again and lists every problem, each line
taking you to its file and line. A file with an error is left out (a `needs` naming no job, needs going round, an
`agent` naming no profile, an `if` that isn't one Lisp form, a variable that isn't one); a warning keeps it. Neither
`if` nor `elisp` is run to check them.

From the shell, as JSON ([more](cmd.md#cmdagent-workflow)):

```sh
cmd/agent-workflow check                 # the project's
cmd/agent-workflow check draft.yml       # one file, anywhere
```
