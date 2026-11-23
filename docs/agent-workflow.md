# Agent workflow

> **Status:** being built (epic `doom-38o`). For now: workflows and profiles, read and checked; the pool of agents;
> runs, their jobs in parallel, every kind of step, going back, loops, the merge, limits, approval, resuming,
> budgets, an issue changed by hand, the starters, the skills, a dry run, the progress pane and the logs. Not yet:
> triggers beyond you.

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
| `branch` | Its issue's branch once a run is done: `delete` (the default: once its work is in the main branch) or `keep` |
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
| `uses` | A built-in: `merge`, with `with: {suite: make test}` |

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

## The starters

These ship with this config; a project's or yours of the same name replaces one.

| Workflow | For | Jobs |
|---|---|---|
| feature | feature, task | build; docs; security (labelled `security`); review (changes: build again); merge |
| bugfix | bug | reproduce (a failing test); fix; review (changes: fix again); merge |
| quick | chore | build; review (changes: build again); merge |

Their merges run no suite: a project's own copy adds its tests with `with: {suite: make test}`.

| Profile | May |
|---|---|
| build | edit, commit; never push |
| test | edit `tests/`, commit; never push |
| docs | edit `docs/` and Markdown, commit; never push |
| review | read; no edits, no commits |
| investigate | read, search the web; no edits |
| security | read, search the web; no edits |

## This config's own

This config has two of its own in `.agent-workflow/`, samples to start a project's from. Neither has a `for`: an issue
gets one by its label (`workflow:tested`, `workflow:screenshots`), or by `--workflow` (`M-x agent-workflow-run` offers
it for any issue). They run once you trust this config (see [Trust](#trust)).

| Workflow | Jobs |
|---|---|
| tested | build, then its script (`.agent-workflow/scripts/tests.sh`: the unit tests of what the branch changed, a failure back to build's agent, twice at most); docs; review, its result waiting for your OK (changes: build again); merge |
| screenshots | capture: its script takes the examples' screenshots again (`.agent-workflow/scripts/screenshots.sh`, macOS: Emacs needs the Screen Recording permission; it broke, the run asks you), then an agent with the `screenshots` profile looks at each changed one and commits the good ones; review (changes: capture again); merge |

`tests.sh` runs a part's tests for a file of it (`config/beads/look.el`: `test-beads*`), a test file changed, what
isn't committed too; none about what changed, none run. The `screenshots` profile (`.agent-workflow/profiles/`) may
read, look at images and commit; it never takes them again, nor changes anything else.

```sh
bd label add doom-a1b workflow:tested
cmd/agent-workflow run doom-a1b
cmd/agent-workflow dry-run screenshots    # what it would do, nothing run
```

## The pool

Agents run in agent-shell, as many at once as `agent-workflow-pool` says (3), in every project. An agent has no role and
no name: it does one job of an issue's run, and is known by them, `doom-a1b · review`, its session's buffer named so.
Its permissions, its questions and its usage are agent-shell's, as in any session.

- **Its profile** is its step's: its tools, deny, model and mode (none: `agent-workflow-mode`, auto). Variables in its
  tools are filled in as its session starts: `Bash(git -C {worktree} commit:*)`.
- **It's told** the job it does and where, that it never switches branches, pushes, or changes the issue, and how it
  ends its job: `cmd/agent-workflow done OUTCOME "notes"`. Then its profile's instructions.
- **Its `bd` commands** run as `ISSUE/JOB` (`doom-a1b/review`): Beads' history says which job did what.
- **Its canvas** opens no pane of its own: it's shown in its section of the run's [pane](#following-a-run).

Each issue's agents work in its worktree, one after another: `.agent-shell/agent-workflow/worktrees/ISSUE`, on the
issue's branch (`feat/doom-a1b-lexer-escapes`, `fix/` for a bug), made from your checkout's HEAD the first time a job
needs it. It's locked with the issue as its reason, and out of git.

A project whose [agent workspace](agent-workspace.md) crew runs has no agents of the pool: they'd take the same issues.

| Setting | Default | What |
|---|---|---|
| `agent-workflow-pool` | `3` | How many agents run at once |
| `agent-workflow-mode` | `"auto"` | The permission mode of an agent whose profile has none |
| `agent-workflow-max-rounds` | `10` | How many times a job may send the work back before the run asks you |
| `agent-workflow-script-timeout` | `1800` | Seconds a script may run, unless its step's `timeout` says |
| `agent-workflow-continue-on-start` | `nil` | Runs read back as Emacs starts continue by themselves |
| `agent-workflow-budget` | `nil` | A run's budget when its workflow has none: `(:cost 15 :tokens 2000000 :time 10800)` |

## Runs

`M-x agent-workflow-run` starts runs: it asks for the issues (several at once; an epic: its open issues), then each
one's workflow, asked only when several fit it. The issues are shown as in [their list](issues.md): status,
priority and type before each, its labels after. `RET` picks one; for several, `TAB` adds one and a separator starts
the next: a comma, or `;` when a title has a comma (the prompt says which). From the shell:

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
over, its agent stops, and the next jobs start. Every job done or skipped, the run is, and its worktree goes (kept if
it has changes not committed). Its branch then goes too (`branch: delete`, the default), once its work is in the main
branch (merged by the run's merge, or before): never a commit lost. Not merged, or its worktree kept, the branch stays,
its log saying why (`its branch feat/doom-a1b-lexer kept: not merged into main`). `branch: keep` keeps it, always; a
cancelled run keeps both.

### Following a run

Started from Emacs, a run opens its **pane**, an [Agent UI](agent-ui.md) canvas named `ISSUE · WORKFLOW`, a pane per
run (tiling lays them out). Under the issue's title, its state in a line, then where its work is (git), then its
sections, each under its divider:

```text
doom-a1b: Lexer escapes
◆ needs you · 15m of 3h · $1.24 of $15 · 182k tokens

⎇ feat/doom-a1b-lexer-escapes   main@62651d7 → main
⏵ Worktree   ⏵ Magit
M lexer.el       +2 −0 not committed
A test-lexer.el  +1 −0
5f20fa9  Lexer: escapes tested
2b437d2  Lexer: string escapes

▾ Run ◆ ──────────────────────────────────────
[build ✓ r2] → [docs ✓ r2] → [review ◆ r2] → [merge ○]     (a graph)
✓ build      2m 34s  agent build · round 2
– security           its if: (member "security" (issue-labels))
◆ review    12m 56s  agent review · round 2 · needs you
○ merge
Rounds: build ▬▬ docs ▬ review → changes ▬ build · round 2 ▬ …   (a timeline)
▾ Needs you ◆ review ─────────────────────────
Unicode
review asks: Should the escape table also cover Unicode escapes?
 ( ) Yes, \u{…} and \U…  the table gets both forms
 ( ) No, not now         a ticket of its own for later
 ✎ Add a note
 ⏵ Answer   ⏵ Go to it
▸ build ✓ 2m 34s · 2 hidden ──────────────────
▾ Log ────────────────────────────────────────
13:10  build   done (2m 34s)
13:13  review  waits for you: its agent asks you: Should the escape table …
```

- **Its state**, a line coloured by it: ● running, ◆ needs you, ○ queued (why), ✓ done, ✗ cancelled; how long it ran,
  what it spent and its tokens, each against its budget if it has one.
- **Where its work is** (git): ⎇ its branch, the branch and commit of your checkout it started from → what its merge
  goes into (merged, deleted, once it is; its worktree removed, said; a reading job's snapshot); **Worktree** and
  **Magit** open its worktree. Under it, its files changed since it started (`RET` opens one; those not committed yet,
  said), and its latest commits. Started from a branch other than the main one, it says so: that branch's commits not
  in the main one are merged with it. Looked at again every 15 seconds while the pane is open
  (`agent-workflow-pane-where-every`); once the run is done, its worktree gone, its branch deleted or kept (above).
- **Run:** a graph of its jobs and their `needs`, each marked and coloured by its state, its round past 1; its
  checklist, each job a step, its steps under it (status, agent, round, try, time; a job waiting for you ◆, timed;
  one skipped, its `if`); its rounds as a timeline, each job's runs as bars, one sent back said (`review → changes`),
  the one running growing.
- **Needs you**, only while the run waits for you: what on, a line coloured, its answers buttons: an approval
  (Approve, or Reject…, which asks its note), retries used up, a step that broke (go on, skip it, stop; go on with a
  note…), a merge waiting, a turn that ended without `done` (run its step again, with a note…, or cancel the run); the
  loop guard and its budget used up, a form (a note for each agent; more budget). Its agent asking in its session
  (below): a permission, its own buttons; a question (its form), Agent UI's own, answered here as its Submit does (one
  with options a choice, its free answer the note; several a form), **Go to it** beside it opening its session there.
- **A section per agent:** its session's canvas, shown there: its plan, its progress, its questions; finished (its plan
  done), they stay (no countdown here). Its job over, it's folded (`▸ build ✓ 4m 12s`), what its agent showed kept
  there, its session gone. `RET` on its divider opens its session; `TAB` on any divider folds it.
- **Log:** its last events, shorter than its log.txt: no issue on each line, its job in a column, a job's agent step
  starting and ending left out, a job done how long it took; a wait a warning, what went wrong an error.

Emacs draws the run's sections from its journal, never an agent. A run done: its checklist finished, its pane closes
after Agent UI's countdown (**Keep** keeps it); a run waiting, failed or cancelled keeps it. Closing it (`q`) stops
nothing: it's made again when you look. Started from the shell, a run's pane is made when you look, and opens by itself
only after that, when the run needs you (its window closed, the same).

`M-x agent-workflow-runs` lists every run of the project, those not over first, those started from the shell and those
over too: its issue, workflow, state, time, what it spent, what it waits for. `RET` opens a run's pane, `gr` reads
them again.

An agent asking you in its session, for a permission (a tool its profile doesn't allow without asking) or with a
question (its form), holds its turn: its run waits for you, saying what (`build: its agent asks for your permission: npm
install`). Needs you shows it: a permission's own buttons (Allow, Reject...), pressed from there; a question, its form
as Agent UI's own, answered there (agent-shell's form gets the answer, as its Submit gives it); and **Go to it**, its
session shown at the question. Answered, there or in its session, the run goes on.

A run waiting for you is said by a notification while Emacs isn't in front (`agent-workflow-needs-you`, `SPC t N`),
however it was started; a click opens its pane. Its agents' sessions aren't said on their own (a turn over, a
permission, a question): their run says what needs you.

From the shell, `run` prints its runs' logs as they go, a line per event (time, issue, job, what happened), until
they all end: exit 0 when they're done, 1 when one was cancelled. What needs you says how to answer it from there.
Ctrl-C stops following, never the runs.

```sh
cmd/agent-workflow run doom-a1b            # followed to its end
cmd/agent-workflow run doom-a1b --detach   # started, the reply only
cmd/agent-workflow logs doom-a1b -f        # its log, followed until it ends
cmd/agent-workflow status                  # every run not over, as JSON (where its work is too)
```

```text
10:42:07  doom-a1b  build  waits for you: build: its result waits for your OK → agent-workflow approve doom-a1b, or reject doom-a1b NOTE
```

Each run keeps its log in `log.txt` beside its journal (made again from the journal if it's gone).

| Setting | Default | What |
|---|---|---|
| `agent-workflow-pane-log-lines` | `200` | How many of a run's last log lines its pane keeps |

### Limits

Under the pool's size (`agent-workflow-pool`), a workflow's `concurrency` is how many of the pool's agents work on its
runs at once, and a job's how many of it run at once across its workflow's runs (`merge: 1`, so merges never
overlap), its scripts too. A job held back by one waits, saying why: `build: waiting: feature at its limit, 3 of 3
agents`, `merge: waiting: merge at its limit, 1 of 1`. Runs of several workflows go side by side, each within its own.

### Budget

A workflow's `budget` (`agent-workflow-budget` for one without) caps each of its runs: its cost in dollars, its tokens,
its time (while it runs or waits for an agent, not while it waits for you). What it spent is its agents': those gone are
kept with the run, those working read from their sessions.

- **Its cost** is each agent's session's, as Claude Code says it: what its tokens would cost on the API, at its list
  prices (a running total). On a subscription, an estimate: nothing is billed by the run.
- **Its tokens** are every turn's of each agent, added up as each turn ends (cache reads, most of them, included).

- At 80% of any, it's said once, in its journal and as a message.
- At its budget, its running steps are stopped (their work kept, their agents' sessions kept to resume them), and the
  run asks you: go on with more, or stop.

```sh
cmd/agent-workflow confirm doom-a1b go --more-cost 5 --more-time 1h
```

### Steps that aren't an agent's

A `run:` step's text is a script, run by its `shell` (bash by default, or `python3`, `node`, any interpreter), in the
job's place: the issue's worktree, or a reading job's snapshot. One line naming a file of `.agent-workflow/` runs your
checkout's copy of it, never the branch's: an agent can't change the check it's run against. It gets these in its
environment: `ISSUE`, `BRANCH`, `MAIN` (your checkout), `MAIN_BRANCH`, `WORKTREE`, `JOB`, `ROUND`, `TRY`. Its output
is kept in the run's `logs/`.

| It returns | Then |
|---|---|
| 0 | The next step |
| 1 | The work is wrong: its output goes to the job's agent (or, in a job with none, one with the step's `on-fail` profile), which fixes it and says done; the step runs again, up to its `retries` (0 by default) |
| another code, or runs out of its `timeout` | It broke: no agent is sent |

Retries used up, or a step that broke, the run asks you (`M-x agent-workflow-confirm`, `cmd/agent-workflow confirm`):
go on (with a note for the agent fixing it; for one that broke, run it again), skip the step, or stop.

An `elisp:` step runs in your Emacs, the same helpers as `if` bound: returning is 0, `(signal 'agent-workflow-fail
'("why"))` is 1, any other error, it broke. It blocks Emacs while it runs: keep it quick.

`uses: merge` merges the issue's branch into the main branch (origin's HEAD, else `main`, else `master`), never
pushing:

1. Merged already: done.
2. Tried first in a worktree of its own. A conflict: the branch is rebased onto the main branch if that goes cleanly,
   and tried again; else the `on-fail` agent rebases it, resolving the conflicts, and the run goes back to its first
   job that edits, so its checks and its review run again on what was resolved.
3. Its suite (`with: {suite: make test}`) runs there, on the merge: 1 is as a script's, to the `on-fail` agent.
4. Into the main branch: in your checkout, if it's checked out there and none of the files it changes has a change of
   yours, else it waits for you, naming them (go: try again). Where it isn't checked out, the branch is moved to the
   merge, and no tree is touched.
5. The issue is closed.

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

### Approval

Every step's result is taken as it is, and the run goes on by itself. A step with `approve: true` (a job's: its last
step) waits, once it's done, for your OK: the run says so, with what to look at (its outcome and notes, what the branch
got since the job started, a script's output).

In its pane's Needs you: Approve, or Reject with a note. Or:

- `M-x agent-workflow-approve`: the run goes on.
- `M-x agent-workflow-reject`, with a note: an agent step goes back to its agent (in its session, or resumed), and its
  result waits for your OK again once it's done; a script's stops the run for you (run it again, skip it, or stop).

```sh
cmd/agent-workflow approve doom-a1b
cmd/agent-workflow reject doom-a1b "name it lexer-escapes.el"
```

The journal keeps who decided.

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

### Changed by hand

Each run not over is looked at again every 30 seconds (`agent-workflow-queue-check`), and with `M-x
agent-workflow-watch`:

- **Its issue closed or deferred:** its running steps stop (their work and their agents' sessions kept), and the run
  asks: go on (the issue in progress again), or cancel it.
- **Blocked by a new dependency:** no new job starts until it's unblocked, saying by what; jobs running finish.
- **Its type, or its `workflow:` label, changed:** the run keeps its workflow; its journal says so.
- **Its title, description, acceptance or notes edited:** the next steps read them anew.
- **Its branch:** your commits on it are work like any. A job's commits no longer on it (a reset, a force-push) stop
  the run, asking: go on as it is now, or stop.

### Stopped, then on again

A run's `state.json` holds all it needs to come back. When Emacs starts, the runs not over of the projects that had
some are read back, each with the workflow it started with; a job that was running is interrupted, and waits for you.

- `M-x agent-workflow-continue` continues every interrupted run of the project: an agent step's session is resumed
  in the same worktree and told it was interrupted and what the branch has now (a fresh one is told the same, if it
  can't be); a script runs again from its start. Steps already done never run again. With `C-u`, the run takes its
  workflow as it is now (its jobs kept by their names). `agent-workflow-continue-on-start` continues them by itself.
- Or skip the step (`confirm ISSUE skip`), go back to a job, or cancel the run.
- `M-x agent-workflow-cancel`: its agents stop, its scripts are killed, its issue is open again; its branch and
  worktree are kept.
- `M-x agent-workflow-pause`: nothing new starts, running steps finish; with `C-u`, they stop at once, interrupted.
  `M-x agent-workflow-unpause`: on again.

```sh
cmd/agent-workflow continue                 # every interrupted run of the project
cmd/agent-workflow continue doom-a1b --current
cmd/agent-workflow cancel doom-a1b
cmd/agent-workflow pause --now
cmd/agent-workflow unpause
```

In `if`, these say what the issue is: `(issue-id)`, `(issue-type)` (a symbol: `'bug`), `(issue-labels)`,
`(issue-priority)`, `(issue-title)`, `(job-outcome 'review)`, `(job-status 'build)`.

| Where | What |
|---|---|
| `.agent-shell/agent-workflow/runs/ISSUE/N/journal.jsonl` | every event of run N of the issue, a JSON line each, as it happens |
| `state.json` beside it | the run as it stands |
| `workflow.yml` beside it | the workflow as the run started |
| The issue | in progress; its metadata (`workflow`, `workflow_run`, `workflow_state`, `workflow_jobs`), the job running as a label (`job:review`), what each job said in its notes. Written as `agent-workflow` |

## A dry run

`M-x agent-workflow-dry-run` tries a workflow before it spends tokens: nothing runs and nothing changes (no worktree,
branch, issue or session). It walks the workflow as the engine would, wave by wave: what would run, what at once, what
would wait and why, what its `if` skips, what an outcome sends back (counted against `max-rounds`), a script fixed and
run again, and where the run would stop and ask you; or, once it ends, what happens to its branch. You choose the agents' outcomes, a round each
(`review=changes,approved`), and the scripts' exit codes, a try each (`build.2=1,0`); none chosen: done, and 0. Its
`if` reads the issue you give, or one of the first type the workflow is for.

```sh
cmd/agent-workflow dry-run feature --outcome review=changes,approved --exit build.2=1,0
```

## Trust

A workflow's scripts, `elisp` steps and `if` run as you, with all you may do. So a project's own workflows (its
`.agent-workflow/`) run only once you trust the project: the first time, you're asked to run it this once, trust the
project (remembered), or not. From the shell they're refused until you trust it with `M-x agent-workflow-trust`; `M-x
agent-workflow-forget-trust` stops trusting one. The starters and yours (out of git) are trusted.

Agents can't change what runs them:

- Every agent is denied editing `.agent-workflow/`.
- A branch that changes `.agent-workflow/` is merged only once you say so (`confirm ISSUE go`), whatever the workflow's
  `approve` says.
- The check warns about a `run:` naming a file elsewhere (`tests/run.sh`): an agent could change it to make it pass. One
  of `.agent-workflow/` runs your checkout's copy.

## For your agent

The [agent-workflow skill](../skills/agent-workflow/SKILL.md) teaches an agent to write, check and run workflows: ask
yours to "write a bugfix workflow", and it checks its draft with `cmd/agent-workflow check` before telling you where it
goes. Every agent-shell session is told where the skill is.

The agent doing a job of a run is told its job, where it works and how it ends its step, then pointed to the
[agent-workflow-step skill](../skills/agent-workflow-step/SKILL.md): reading the issue and what came before, its
canvas, being sent back, what its outcomes do.

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
