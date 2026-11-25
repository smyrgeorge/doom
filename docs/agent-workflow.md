# Agent workflow

> **Status:** being built. Everything below works, but a run starts only when you start it: there are
> no other triggers yet.

A **workflow** describes the work on an issue the way GitHub Actions does: jobs, the order they run in, which run in
parallel, and their steps. A step is a script, Lisp, a built-in, or an **agent**: an LLM in agent-shell with its own
tools, permissions and instructions.

![A run's pane: how it stands, its branch, its flow and jobs; beside it, what its jobs run now, its agents' notes, its Log](../examples/agent-workflow.png)

Try it: `M-x +my/example-agent-workflow`, a run's [pane](#following-a-run) as it runs, offline.

## Where they are

A workflow is a YAML file, `NAME.yml` (or `.yaml`). An agent is a Markdown file, `NAME.md`. Both come from three places:

| Place | Committed | What |
|---|---|---|
| `config/agent-workflow/workflows/`, `agents/` | with this config | The starters |
| `.agent-workflow/workflows/`, `agents/` | yes | The project's, read from your checkout (never from an agent's worktree) |
| `.agent-shell/agent-workflow/workflows/`, `agents/` | no | Yours |

A file replaces one of the same name from a place above it: the project's replace the starters, and yours replace both.

## A workflow

A workflow lists its jobs, and each job its steps. This one builds a feature with its tests, checks the coverage, writes
the docs, reviews the work and merges it:

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

A workflow's keys:

| Key | What |
|---|---|
| `name` | Its file's name; if given, it must match |
| `description` | What it's for |
| `ticket` | `false`: it runs only without a ticket ([Without a ticket](#without-a-ticket)). `true` by default |
| `runs-in` | Where its jobs work: `worktree` (the default: a worktree and branch of its own) or `checkout` (yours, on its branch: [In your checkout](#in-your-checkout)) |
| `for` | The issue types it's offered for |
| `concurrency` | How many agents work on its runs at once |
| `budget` | What a run may spend: `cost` (dollars), `tokens`, `time` (`3h`) |
| `branch` | The issue's branch once a run is done: `delete` (the default, once its work is in the main branch) or `keep` |
| `jobs` | Its jobs. A job's name is a lowercase letter, then lowercase letters, digits or `-` |

A job's keys:

| Key | What |
|---|---|
| `needs` | The jobs it runs after (one, or a list). Jobs that don't need each other run in parallel |
| `if` | Lisp: the job runs only if it's true, evaluated as the job is about to start |
| `steps` | Its steps, in order. Or one step's keys on the job itself (`agent: docs`) |
| `approve` | `true`: its result waits for your OK |
| `outcomes` | What an agent's outcome does: `continue`, or `rerun JOB` (that job and every job after it run again) |
| `max-rounds` | How many times it may send the work back before the run asks you. The workflow can set it too |
| `concurrency` | How many of it run at once, across runs (`merge: 1`) |

An `if` is one Lisp form. These functions tell it about the issue: `(issue-id)`, `(issue-type)` (a symbol: `'bug`),
`(issue-labels)`, `(issue-priority)`, `(issue-title)`, `(job-outcome 'review)` and `(job-status 'build)`. `elisp` steps
can use them too.

A step does one thing:

| Key | What |
|---|---|
| `agent` | An LLM in agent-shell, with that agent. `prompt`: what it's told. `kind`, `model`, `effort`: override its agent's |
| `run` | A program, or a script (`run: \|`). `shell`: its interpreter (bash by default, `python`, `node`...) |
| `elisp` | Lisp in your Emacs. Keep it quick: it blocks Emacs. Lisp containing `: ` goes under `elisp: \|` |
| `uses` | A built-in: `merge`, with `with: {suite: make test}` |

Any step can also have:

| Key | What |
|---|---|
| `name` | Its name, unique in its job. Its pane and its log use it |
| `timeout` | How long it may run: `45s`, `10m`, `1h30m` |
| `retries` | How many times a failing script is fixed and run again |
| `retry-from` | Where a retry starts again: an earlier step of its job, by name or number |
| `on-fail` | The agent a failing step goes to, in a job without one; or a script tried first ([below](#a-script-on-a-failure)) |
| `approve` | `true`: its result waits for your OK |

### A script on a failure

`on-fail` takes an agent that fixes the step, a script, or both:

```yaml
on-fail: ci                    # the ci agent

on-fail:                       # a script alone
  run: .agent-workflow/scripts/rerun-flaky.sh

on-fail:                       # the script first, then the agent if it couldn't
  run: .agent-workflow/scripts/rerun-flaky.sh
  agent: ci
```

The script runs where the step ran. Its environment is a step's, plus `FAILED_STEP` (the step's name, else its number)
and `FAILED_OUTPUT` (the last 200 lines of its output). Its output goes to a log of its own (`….on-fail.log`), and the
step's box in the pane shows it as it comes. What it returns decides what comes next:

| It returns | Then |
|---|---|
| 0 | It fixed it. The step runs again (from its `retry-from` step) without an agent, and the try counts |
| 1 | It couldn't. The step goes to the job's agent, else the `on-fail` one, told the step's output and the script's. With no agent, the run asks you |
| Another code, or past the step's `timeout` | It broke. The run asks you: run the step again, skip it, or stop |

### Variables

Prompts and agent files use these, written `{issue}`:

| Variable | Is |
|---|---|
| `{issue}`, `{issue.title}`, `{issue.description}`, `{issue.acceptance}`, `{issue.notes}` | The issue |
| `{branch}`, `{main}`, `{main-branch}`, `{worktree}`, `{project}` | Where the work is |
| `{diff.stat}` | The branch's changes against main |
| `{jobs.JOB.outcome}`, `{jobs.JOB.notes}` | What an earlier job said |
| `{output}` | A failing script's output |
| `{note}` | Your note, when you send the work back or answer |
| `{round}`, `{try}` | Which round, which try |

## An agent

An agent is a Markdown file in `agents/`: a step's `agent: review` is `agents/review.md`. Its front matter says what it
may do, and the text after it is its instructions:

```markdown
---
description: builds an issue with its tests
tools: Read, Edit, Bash(git commit:*)
deny: Bash(git push:*)
model: opus
effort: high
mode: acceptEdits
icon: md-hammer ⚙
verb: building
colour: blue
---
Build it with its tests, commit on {branch}.
```

| Key | What |
|---|---|
| `description` | What it's for (required) |
| `kind` | Which agent runs it: `claude-code`, `codex`, `gemini-cli`, `opencode`, `qwen-code`, `copilot`, `goose`, `cursor` (`agent-workflow-kinds`). Default: `agent-workflow-kind` (`claude-code`) |
| `tools` | Allowed without asking |
| `deny` | Never available |
| `model` | Claude Code's `fable`, `opus`, `sonnet`, `haiku` or a model's id; another agent's own. Default: your default model |
| `effort` | How hard it thinks (its ACP thought level): Claude Code's `low`, `medium`, `high`, `xhigh`, `max`; another agent's own. Default: its model's |
| `mode` | Its permission mode: Claude Code's (checked), or another agent's own. Default: auto for Claude Code, another agent's own default |
| `icon`, `verb`, `colour` | How its steps are shown |

## The starters

These workflows and agents ship with this config. A project's or yours with the same name replaces one.

| Workflow | For | Jobs |
|---|---|---|
| feature | feature, task | build; docs; security (labelled `security`); review (changes: build again); merge |
| bugfix | bug | reproduce (a failing test); fix; review (changes: fix again); merge |
| quick | chore | build; review (changes: build again); merge |

Their merges run no test suite. A project's own copy can add its tests with `with: {suite: make test}`.

| Agent | May |
|---|---|
| build | edit, commit; never push |
| test | edit `tests/`, commit; never push |
| docs | edit `docs/` and Markdown, commit; never push |
| review | read; no edits, no commits |
| investigate | read, search the web; no edits |
| security | read, search the web; no edits |

## This config's own

This config has two workflows of its own in `.agent-workflow/`, samples to start a project's from. They take no ticket
(`ticket: false`). They run once you trust this config (see [Trust](#trust)).

| Key | Action |
|---|---|
| `M-x agent-workflow-run` | Pick one and start it |
| `cmd/agent-workflow run --workflow screenshots` | Start screenshots from the shell |
| `cmd/agent-workflow run --workflow github` | Start github from the shell |
| `cmd/agent-workflow dry-run screenshots` | What it would do, nothing run |

| Workflow | Jobs |
|---|---|
| screenshots | **capture**: its script takes the examples' screenshots again (`.agent-workflow/scripts/screenshots.sh`), then the `screenshots` agent looks at each changed one and commits the good ones. **review** (changes: capture again). **merge** |
| github | Runs in your checkout (`runs-in: checkout`). **check**: gh is logged in and your checkout is on main (`.agent-workflow/scripts/github-check.sh`). **all-green**, after it: push your main (`github-push.sh`), then watch its GitHub Actions until they're done (`github-watch.sh`) |

**screenshots:**

- On macOS, Emacs needs the Screen Recording permission. Without it, the script breaks and the run asks you.
- The `screenshots` agent (`.agent-workflow/agents/`) may read, look at images and commit. It never takes the
  screenshots again, and changes nothing else.

**github:**

- It needs gh, logged in (`brew install gh`, `gh auth login`). Without it, the run fails at once (✗ failed) and says
  why. It fails the same way when your checkout isn't on main.
- It starts once your checkout has no uncommitted changes.
- The push sends your main's HEAD, so your own commits go too.
- When an Action fails, the `ci` agent reads its logs, fixes the code or its test, and commits on your main. The
  all-green job then runs again from its push (`retry-from`), 5 times at most.
- The `ci` agent may read, edit, run the tests and commit. It commits only the files it changed, since your checkout may
  have yours. It never pushes (the script does), and never runs the Actions again.
- With nothing to push (origin has your main already), it watches the Actions of origin's main. If they're done already,
  their verdict comes at once.
- If none show up within 5 minutes, it says so and goes on only when none was to run: the commit's message asks GitHub
  to skip them (`[skip ci]`...), or none of its `.github/workflows/` runs on a push. Otherwise GitHub didn't start one
  that should have run, and the run asks you, rather than passing with nothing checked.
- The run asks you when a run is cancelled on GitHub, when a push is refused (origin has commits you don't), when your
  checkout is off main at a push, or when no Actions run started for a push that should have started one.

Its scripts read these from Emacs's environment (`(setenv "GITHUB_POLL" "60")`):

| Variable | Default | What |
|---|---|---|
| `GITHUB_REMOTE` | `origin` | Where it pushes |
| `GITHUB_POLL` | 30 | Seconds between looks at the Actions |
| `GITHUB_APPEAR` | 300 | Seconds a pushed commit's Actions have to show up |
| `GITHUB_LOG_LINES` | 150 | How many of a failed job's last lines the agent gets |

## The pool

Agents run in agent-shell, at most `agent-workflow-pool` (3) at once across all your projects. An agent has no role or
name of its own. It does one job of an issue's run, and is known by the issue and the job: `doom-a1b · review`, also its
session buffer's name. Its permissions, questions and usage work as in any agent-shell session.

- **Its agent** is its step's: its tools, deny, model, effort and mode. An agent file with no `mode` gets
  `agent-workflow-mode` (auto). Variables in its tools are filled in as its session starts:
  `Bash(git -C {worktree} commit:*)`.
- **Its model and effort** are its agent's, unless its step sets them (`model: sonnet`, `effort: low`). So the same
  agent can run on a different model in another workflow. The effort is set after the model; an effort the model doesn't
  offer is skipped, and the session says so.
- **A job keeps its agent** from its first agent step to its end. A later agent step continues in the same session, as
  it started; a `model` or `effort` on that step only gets a warning.
- **It's told** its job and where it works. It's told never to switch branches, push, or change the issue, and how to
  end its job: `cmd/agent-workflow done OUTCOME "notes"`. Its agent's instructions follow.
- **Its `bd` commands** run as `ISSUE/JOB` (`doom-a1b/review`), so Beads' history says which job did what.
- **Its canvas** opens no pane of its own. It's shown in its section of the run's [pane](#following-a-run).

Each issue's agents work in its worktree, one after another: `.agent-shell/agent-workflow/worktrees/ISSUE`, on the
issue's branch (`feat/doom-a1b-lexer-escapes`, or `fix/` for a bug). The worktree is made from your checkout's HEAD the
first time a job needs it. It's locked, with the issue as the reason, and kept out of git.

A project where an [agent workspace](agent-workspace.md) crew runs gets no agents from the pool: they'd take the same
issues.

### Agents other than Claude Code

An agent of another kind (`kind:`) doesn't take Claude Code's options. Instead, its permission requests are answered
from its `tools` and `deny`, the command that ends its step, and the rule that guards `.agent-workflow/`:

- A `deny` rule that matches refuses. A `tools` rule that matches allows. With neither, it asks you.
- A command line is judged by each of its commands. `a && b` is refused if one is denied, and allowed only if each is
  allowed. A command with another inside it (`$(...)`) is asked.
- This is weaker than Claude Code: nothing is hidden from the agent, and in a mode that asks nothing, nothing is
  refused.
- A branch that changes `.agent-workflow/` still merges only once you say so.
- A workflow that runs in your checkout (`runs-in: checkout`) runs Claude Code only; another agent is an error.

## Runs

A run takes an issue through its workflow. Start runs from Emacs or from the shell. Runs on different issues go at once,
as the pool allows.

| Key | Action |
|---|---|
| `M-x agent-workflow-run-ticket` | Run workflows on one or more issues |
| `M-x agent-workflow-run` | Run a workflow that takes no ticket |
| `M-x agent-workflow-list` | The project's runs ([The runs' list](#the-runs-list)) |
| `cmd/agent-workflow run ISSUE...` | Start runs from the shell, each issue with its own workflow (`--workflow NAME`: with that one) |

```sh
cmd/agent-workflow run doom-a1b doom-c3d          # each with its own workflow
cmd/agent-workflow run doom-epic --workflow quick  # an epic's open issues, with quick
```

`M-x agent-workflow-run-ticket` asks for the issues, then each one's workflow:

- **The issues:** several at once, or an epic for its open issues. They're shown as in [their list](issues.md): status,
  priority and type before each, its labels after. `RET` picks one. For several, `TAB` adds one and a separator starts
  the next: a comma, or `;` when a title has a comma (the prompt says which).
- **Its workflow** is always asked. Every workflow that takes a ticket is listed, grouped by where it comes from (yours,
  the project's, the starters). Each row shows its description, its jobs and the types it's for.
- Those that fit the issue come first, marked ●, and the first of them is selected. A workflow fits when the issue's
  type is in its `for:`, or when the issue has its `workflow:NAME` label. The others are marked ○ and dimmed.
- From the shell, without `--workflow`, an issue's workflow is its `workflow:NAME` label's, else the one whose `for` has
  its type.
- An issue is refused, and the others started, when it's closed, already has a run, has no workflow that fits (or
  several), or its workflow takes no ticket.
- A run whose issue is blocked is queued until its blockers close, saying by what.
- A free agent goes to the highest-priority run first, then to the run started first.

### Without a ticket

`M-x agent-workflow-run` starts a workflow that takes no ticket (`ticket: false`). It asks which, showing each one's
description. From the shell: `cmd/agent-workflow run --workflow NAME`.

- The run is named by its workflow and its number: `github · run 3`. The workflow's name stands where an issue's id
  would: in its folder, its worktree, its log and `{issue}`.
- Its branch is its own, `run/github-3`, cut from your checkout's HEAD.
- It uses no Beads: no status, notes or labels, and its merge closes nothing. It runs in a project without Beads too.
- A workflow has one run at a time. If its last run's worktree is still there (cancelled, failed), it's removed first
  and its branch kept. If that worktree has uncommitted changes, the new run is refused, and nothing is lost.

### How its jobs run

A run's jobs start once their `needs` are done. A job whose `if` doesn't hold at that moment is skipped. Jobs that don't
need each other run at once, as the pool allows. They all share the issue's branch:

- **A job that edits** (one of its agents may edit) works in the issue's worktree, one at a time. The next one waits and
  says so: `tests: waiting for docs, which edits the branch`.
- **A job that only reads** (its agents deny `Edit` and `Write`, or it runs scripts) works on a snapshot of the branch:
  a worktree of its own, `.agent-shell/agent-workflow/worktrees/ISSUE@JOB`. It's detached at the branch's commit when
  the job starts, and removed when the job is over. It runs beside the others.
- Each job's start in the journal says which commit it saw.

A job's steps run in order. A job with an agent step keeps that agent to its last step.

- The agent ends its step itself with `cmd/agent-workflow done OUTCOME "notes"`, then ends its turn.
- A turn that ends without it leaves the run waiting for you: tell the agent in its session.
- The outcome must be `done` or one of its job's `outcomes`.
- When a job is over, its agent stops and the next jobs start.

### When it's done

The run is done when every job is done or skipped.

- Its worktree is removed, unless it has uncommitted changes.
- Its branch is deleted too (`branch: delete`, the default), once its work is in the main branch: merged by the run's
  merge, or before. No commit is ever lost.
- If it isn't merged, or its worktree was kept, the branch stays. Its log says why:
  `its branch feat/doom-a1b-lexer kept: not merged into main`.
- `branch: keep` always keeps it.
- A run that's cancelled or fails keeps its branch: see [Stopped, then on again](#stopped-then-on-again).

### In your checkout

A workflow about your branch itself (push it, keep its CI green) runs in your checkout: `runs-in: checkout`. It has no
worktree and no branch of its own.

- Its jobs that edit work in your checkout, on the branch it's on, and commit there. A job that only reads works on a
  snapshot of its HEAD.
- There's nothing to merge: the check refuses `uses: merge` there, and ignores `branch:`.
- A job that edits starts only while your checkout has no uncommitted changes, since its agent would commit them. Until
  then it waits: `build: waiting: your checkout has changes not committed`.
- A project's checkout has one run at a time.
- Going back with `C-u` is refused there: it would reset your checkout.
- On a ticket, the issue is closed once the run is done.
- Its pane's git line says where it works: `⎇ main   your checkout, from 881e46c · 1 commit of its`.
- Its commits are those made while one of its agents worked, from its step's (or its fix's) start to its `done`. Your
  commits before, between and after aren't listed as its, nor are their files. One you make while its agent works is
  counted as its: git can't tell them apart.
- Uncommitted changes are counted (`· 2 not committed`), not listed.

### Following a run

A run started from Emacs opens its **pane**: an [Agent UI](agent-ui.md) canvas named `ISSUE · WORKFLOW`, with `· run N`
added for the issue's later runs. Each run gets its own pane, and tiling lays them out. Emacs draws it from the run's
journal; no agent writes it.

| Key | Action |
|---|---|
| `TAB` (on a divider) | Fold or unfold its section |
| `RET` (on an agent's divider) | Open the agent's session |
| `RET` (on a file / a commit) | Open the file / show the commit |
| `RET` (on a note) | Show the note whole |
| `q` | Close the pane; the run goes on |
| `M-x +my/example-agent-workflow` | Try it: a run's pane, offline |

Under the issue's title come its state as tiles, then where its work is (git), then its sections, each under its
divider:

```text
doom-a1b: Lexer escapes
┌State──────────┐┌Time──────────┐┌Cost───────────┐┌Tokens────┐┌Jobs──────┐
│◆ needs you    ││15m     of 3h ││$1.24   of $15 ││182k      ││1 / 4 done│   (tiles)
└───────────────┘└──────────────┘└───────────────┘└──────────┘└──────────┘

⎇ feat/doom-a1b-lexer-escapes   main@62651d7 → main
⏵ Worktree   ⏵ Magit
M lexer.el       +2 −0 not committed
A test-lexer.el  +1 −0
5f20fa9  Lexer: escapes tested
2b437d2  Lexer: string escapes

▾ Run ◆ ──────────────────────────────────────
flow
[build ✓ r2] → [docs ✓ r2] → [review ◆ r2] → [merge ○]     (a graph)
4 jobs · 1 done
✓ build      2m 34s  agent build · round 2
– security           its if: (member "security" (issue-labels))
◆ review    12m 56s  agent review · round 2 · needs you
○ merge
rounds
build ▬▬ docs ▬ review → changes ▬ build · round 2 ▬ …   (a timeline)
◆  review  agent review · step 1 (review)       asks you
   │ ≡ Read lexer.el
   │ ? Should the escape table also cover Unicode escapes?
   ╰ 2 actions in this turn · waiting for your answer
⏵ Go to it
▾ Needs you ◆ review ─────────────────────────
Unicode
review asks: Should the escape table also cover Unicode escapes?
 ( ) Yes, \u{…} and \U…  the table gets both forms
 ( ) No, not now         a ticket of its own for later
 ✎ Add a note
 ⏵ Answer   ⏵ Go to it
▸ build ✓ 2m 34s · 2 hidden ──────────────────
▾ Log ────────────────────────────────────────
◆ 1 warning · 12 events          13:01 – 13:13 · 12m
13:10  ✓  build   done                     2m 34s
       ┊  3m
13:13  ◆  review  waits for you: its agent asks you: Should the …
```

From the top:

- **Tiles:**
  - **State**, coloured by it: ● running, ◆ needs you, ○ queued, ✓ done, ✗ cancelled, ✗ failed. What it's at, what it
    waits for and why it ended are further down: its checklist, Needs you, its Log.
  - **Time** it has run, **Cost** spent, and **Tokens** (shown when it has a token budget, or has spent some). Each is
    shown against its budget, if it has one. Near its budget, its Log says so.
  - **Jobs:** how many are done, of all.
- **Cancel**, under the tiles while the run isn't over (running, waiting, queued). It asks first, saying what it stops
  and what it keeps (its branch and worktree). It's the same as `M-x agent-workflow-cancel`.
- **Git**, where its work is:
  - Its first line shows ⎇ its branch, the branch and commit of your checkout it started from, and → the branch its
    merge goes into. Once merged or deleted, it says so; `no commit · deleted` means there was nothing to merge. It also
    says when its worktree is removed, and shows a reading job's snapshot.
  - **Worktree** and **Magit** open its worktree.
  - Its files changed since it started: `RET` opens one, and uncommitted ones are marked. Then its latest commits: `RET`
    shows one.
  - Started from a branch other than main, it says so: that branch's commits not in main are merged with it.
  - It's looked at again every 15 seconds while the pane is open (`agent-workflow-pane-where-every`). After the run, its
    worktree is gone and its branch deleted or kept ([When it's done](#when-its-done)).
- **Run**, each part under a caption:
  - `flow`: a graph of its jobs and their `needs`, each marked and coloured by its state, with its round past 1.
  - `4 jobs · 1 done`: its checklist. Each job has its steps under it: status, agent, round, try, time.
  - In the checklist, a job waiting for you is ◆, timed. A skipped job shows its `if`. A job that edits but committed
    nothing says `no commit`. The merge says `merged` or `nothing to merge`.
  - A failed step that an agent is fixing shows ✗, who and the try (`ci fixing it · try 1 of 6`), and its job says
    `fixing`.
  - A job stopped by the run's cancel or failure is grey and says `cancelled`; the graph shows it ⊘.
  - `rounds`: its rounds as a timeline, each job's runs as bars. A job sent back is labelled (`review → changes`), and
    the one running grows.
- **A box per running job**, under Run, redrawn every second. Its header shows ● running or ◆ waiting for you, the job
  in its Log colour, what it runs (the step and its try, muted), and how long it has run. Its last lines follow on a
  rail, and a footer closes them.
  - **A script's box:** its command (muted), then the last lines of its output. Errors are red and warnings yellow.
    Colour codes are removed, and a line redrawn in place shows its last state. Its footer says
    `the last 5 of 214 lines · 1 error`, with **Show output**.
  - **An agent's box:** what it runs on, as its session reports it:
    `agent build · Opus 5.5 · high effort · step 2 (implement)`. A default model is shown by its name; until the session
    reports, it shows what was asked.
  - Then the agent's last actions, each marked by its kind: ❯ a command, ≡ read, ◎ search, ↓ fetch, ± edit, ⊖ delete, →
    move, ∴ think. The latest is bright, the earlier ones muted.
  - Then what it last asked you (◆, `asks you`), `4 actions in this turn`, and **Show session** (**Go to it** while it
    asks).
- **Needs you**, only while the run waits for you. A coloured line says on what, and its answers are buttons:
  - An approval: **Approve**, or **Reject…**, which asks for a note.
  - Retries used up: **Go on**, **Go on, with a note…**, **Skip its step**, **Stop**. A step that broke: **Go on**,
    **Skip its step**, **Stop**.
  - A merge waiting: **Go on**, **Stop**.
  - A turn that ended without `done`: **Run its step again**, **Run it again, with a note…**, **Cancel the run**.
  - The loop guard: a form with a note for each agent. The budget used up: a form for more budget.
  - Its agent asking in its session: see [When an agent asks you](#when-an-agent-asks-you).
- **Notes:** each agent's verdict when it ended its step, one line each, in order. A line shows its job (with its round
  past 1), the time, its outcome (unless `done`) and its verdict. The verdict is the first line of its notes (agents are
  told to start with it, 80 characters at most), else their first sentence. `RET` shows a note whole.
- **A section per agent:** its session's canvas, with its plan, its progress and its questions. Finished views stay;
  nothing counts down here. Its notes appear in full once it ends its step, each round's under its own. When its job is
  over, the section folds (`▸ build ✓ 4m 12s`). What the agent showed stays there, and its session is gone. `RET` on its
  divider opens its session.
- **Log:** its last 12 events, shorter than its `log.txt`, one line each in columns:
  - Each line has the time (shown when it changes), a mark (below), the job in its own colour (none for the run's own
    events), what happened, and how long it took (a script, a fix, a job, the run).
  - A step's line starts with its name, muted except for what went wrong: `push exited 1`.
  - A pause of 5 minutes or more shows between two lines (`┊ 17m`).
  - A job's agent step starting and ending is left out: the job's own lines say it.
  - Above the lines: its errors and warnings counted, its events, and its span (`16:22 – 17:24 · 1h 2m`).

| Mark | In the Log |
|---|---|
| ▸ / › | Started / a step started |
| ✓ / ✗ | Done / failed |
| ↻ | An agent fixing it |
| ↺ | Run again from a step |
| ◆ | Waits for you |
| ↶ | Sent back |
| ⎇ | Merged |
| ⊘ | Cancelled |
| ★ | The run done |

The pane stays until you close it with `q`, whether the run is done or not. Nothing closes it by itself. A done run
shows ✓ done, with its agents' sections folded.

- Closing the pane stops nothing. It's made again when you look.
- A run started from the shell gets its pane when you look (`M-x agent-workflow-list`, `RET`). From then on, its pane
  opens by itself when the run needs you, even after you closed it.

#### The runs' list

`M-x agent-workflow-list` lists every run of the project, those not over first, including runs started from the shell
and runs that are over. Each shows its issue, workflow, state, time, what it spent and what it waits for.

| Key | Action |
|---|---|
| `RET` | Open the run's pane |
| `gr` | Read the runs again |
| `q` | Close the list |

#### When an agent asks you

An agent that asks you something in its session holds its turn: for a permission (a tool its agent doesn't allow without
asking), or with a question (its form). Its run waits for you and says what:
`build: its agent asks for your permission: npm install`.

- **Needs you** shows it. A permission's own buttons (Allow, Reject...) work from there.
- A question's form is shown as Agent UI's own and answered there. agent-shell's form gets the answer, as its Submit
  gives it: a question with options is a choice, with your free answer as its note; several questions make a form.
- **Go to it** shows its session at the question.
- Once you answer, there or in its session, the run goes on.

#### Notifications

A run that waits for you, or fails, sends a [notification](notifications.md) while Emacs isn't in front, however it was
started. Clicking it opens the run's pane. Its agents' sessions don't notify on their own (a turn over, a permission, a
question): their run says what needs you.

| Key | Action |
|---|---|
| `SPC t N` | Turn one kind of notification on or off: this one is `agent-workflow-needs-you` |

#### From the shell

`cmd/agent-workflow run` prints its runs' logs as they go, one line per event (time, issue, job, what happened), until
they all end. It exits 0 when they're all done, and 1 when one was cancelled or failed. A line about what needs you says
how to answer it from the shell. Ctrl-C stops following, never the runs.

```sh
cmd/agent-workflow run doom-a1b            # followed to its end
cmd/agent-workflow run doom-a1b --detach   # started, the reply only
cmd/agent-workflow logs doom-a1b -f        # its log, followed until it ends
cmd/agent-workflow status                  # every run not over, as JSON (where its work is too)
```

```text
10:42:07  doom-a1b  build  waits for you: build: its result waits for your OK → agent-workflow approve doom-a1b, or reject doom-a1b NOTE
```

Each run keeps its log in `log.txt`, beside its journal. If it's gone, it's made again from the journal.

### Limits

Two keys limit how much works at once, within the pool's size (`agent-workflow-pool`):

- **A workflow's `concurrency`** is how many of the pool's agents work on its runs at once. Every agent counts: a later
  step's, and an `on-fail` agent fixing a step, which waits for a free one the same way.
- **A job's `concurrency`** is how many of it run at once across its workflow's runs, its scripts too. `merge: 1` keeps
  merges from overlapping.
- A job held back waits, saying why: `build: waiting: feature at its limit, 3 of 3 agents`,
  `merge: waiting: merge at its limit, 1 of 1`.
- Runs of several workflows go side by side, each within its own limits.

### Budget

A workflow's `budget` caps each of its runs: its cost in dollars, its tokens, and its time. `agent-workflow-budget` is
the budget of a workflow without one. Time counts while the run runs or waits for an agent, not while it waits for you.

| Key | Action |
|---|---|
| **Go on** (in the pane's Needs you) | Give it more budget, in a form |
| `M-x agent-workflow-confirm` | Go on with more, or stop |

- **What it spent** is its agents'. Those gone are kept with the run, and those working are read from their sessions.
- **Its cost** is each agent session's, as Claude Code reports it: what its tokens would cost on the API, at list prices
  (a running total). On a subscription, it's an estimate: the run bills nothing.
- **An agent that reports no cost** counts nothing. The pane's cost then shows `+` (`$1.50+`), and the budget's message
  says an agent's cost isn't known. Its tokens and time count all the same.
- **Its tokens** are every turn's of each agent, added up as each turn ends. Cache reads are included, and they're most
  of them.
- **At 80%** of any of them, it's said once, in its journal and as a message.
- **At its budget**, its running steps stop. Their work is kept, and their agents' sessions are kept to resume them. The
  run asks you: go on with more, or stop.

From the shell, go on with `--more-cost`, `--more-tokens` or `--more-time`:

```sh
cmd/agent-workflow confirm doom-a1b go --more-cost 5 --more-time 1h
```

### Steps that aren't an agent's

A `run:` step's text is a script, run by its `shell`: bash by default, or `python3`, `node`, any interpreter. It runs in
the job's place: the issue's worktree, or a reading job's snapshot.

- A single line naming a file of `.agent-workflow/` runs your checkout's copy of it, never the branch's. So an agent
  can't change the check it's run against.
- Its environment has `ISSUE`, `BRANCH`, `MAIN` (your checkout), `MAIN_BRANCH`, `WORKTREE`, `JOB`, `ROUND` and `TRY`.
- Its output is kept in the run's `logs/`.

What it returns decides what comes next:

| It returns | Then |
|---|---|
| 0 | The next step |
| 1 | The work is wrong. Its output goes to the job's agent (or, in a job without one, the step's `on-fail` agent), which fixes it and says done. The step runs again, from its `retry-from` step with those between, up to its `retries` (0 by default). Its `on-fail` script runs first, if it has one ([A script on a failure](#a-script-on-a-failure)) |
| 3 | It can't go on: the run fails, its last line saying why. It ends as a cancelled run does: its agents stop, its issue is open again, and its branch is kept |
| Another code, or past its `timeout` | It broke: no agent is sent |

When its retries are used up, or a step broke, the run asks you:

| Key | Action |
|---|---|
| `M-x agent-workflow-confirm` | Go on (with a note for the agent fixing it; a step that broke runs again), skip the step, or stop |
| `cmd/agent-workflow confirm ISSUE go\|skip\|stop` | The same from the shell |

A step whose fix has to run what's before it again says where to start. For example, a check of what was pushed must
push again:

```yaml
steps:
  - name: push
    run: .agent-workflow/scripts/push.sh
  - name: watch
    run: .agent-workflow/scripts/watch.sh
    retries: 5
    retry-from: push        # fixed: pushed again, then watched
    on-fail: ci
```

An `elisp:` step runs in your Emacs, with the same functions as `if`. Returning normally is 0,
`(signal 'agent-workflow-fail '("why"))` is 1, and `(signal 'agent-workflow-abort '("why"))` is 3. Any other error means
it broke. It blocks Emacs while it runs, so keep it quick.

`uses: merge` merges the issue's branch into the main branch (origin's HEAD, else `main`, else `master`). It never
pushes:

1. If it's merged already, it's done.
2. It's tried first in a worktree of its own. On a conflict, the branch is rebased onto the main branch if that goes
   cleanly, and tried again. Otherwise the `on-fail` agent rebases it, resolving the conflicts. The run then goes back
   to its first job that edits, so its checks and its review run again on what was resolved.
3. Its suite (`with: {suite: make test}`) runs there, on the merge. A failure (1) goes to the `on-fail` agent, as a
   script's does.
4. Then it goes into the main branch. If your checkout has the main branch checked out, the merge happens there, as long
   as none of the files it changes has a change of yours. Otherwise it waits for you, naming them (**Go on** tries
   again). If the main branch isn't checked out, it's simply moved to the merge, and no files are touched.
5. The issue is closed. A run without a ticket has none.

### Going back

`M-x agent-workflow-back` sends a run back to a job that has run (or a step of it), with your note, to refine what it
did. Nothing is reset: the branch and its commits stay, and uncommitted changes stay in the worktree.

| Key | Action |
|---|---|
| `M-x agent-workflow-back` | Send a run back to a job, with a note |
| `C-u M-x agent-workflow-back` | The same, discarding the work since the job's round started |

- That job and the jobs that need it, directly or not, run again, one round more. A step of theirs that's running is
  stopped first. The other jobs keep their results.
- The job's agent has its session resumed, and is told your note and what the branch has now. If the agent can't resume,
  a fresh session is told the same.
- The journal keeps the earlier rounds.
- With `C-u`, the work since the job's round started is discarded: its commits and the uncommitted changes. You're told
  what's lost, and asked first. It's refused in a run in your checkout (`runs-in: checkout`).

```sh
cmd/agent-workflow back doom-a1b build "handle the empty list too"
cmd/agent-workflow back doom-a1b build.2 - < note.txt     # its second step; the note from stdin
cmd/agent-workflow back doom-a1b build --discard          # the work since, gone
```

### Approval

Every step's result is taken as it is, and the run goes on by itself. A step with `approve: true` waits for your OK once
it's done; on a job, its last step waits. The run says so, with what to look at: its outcome and notes, what the branch
got since the job started, a script's output.

| Key | Action |
|---|---|
| **Approve** / **Reject…** (in the pane's Needs you) | Approve it, or reject it with a note |
| `M-x agent-workflow-approve` | Approve it: the run goes on |
| `M-x agent-workflow-reject` | Reject it, with a note |

- A rejected agent step goes back to its agent, in its session or resumed. Its result waits for your OK again once it's
  done.
- A rejected script step stops the run for you: run it again, skip it, or stop.
- The journal keeps who decided.

```sh
cmd/agent-workflow approve doom-a1b
cmd/agent-workflow reject doom-a1b "name it lexer-escapes.el"
```

### Loops

An agent's outcome can send the work back. `changes: rerun build` sends it to build as going back does, with the
outcome's notes as its note, and build and every job after it run again. Going back makes loops, so they're counted, per
edge (review to build) and in all:

- **Past `max-rounds`** (the job's, else the workflow's, else `agent-workflow-max-rounds`: 10), or past 3 times that in
  all, the run asks you.
- **A round that changed nothing** on the branch (no commit, no uncommitted change) asks you at once.

The question shows what each round said. Answer it in the pane, with `M-x agent-workflow-confirm`, or from the shell:

| Answer | Does |
|---|---|
| go | Go on. The count starts again, with your note for the job that sends it back, the one it's sent to, or both |
| accept | Take it as it is: the run goes on as if the outcome had been `continue` |
| stop | The run waits |

```sh
cmd/agent-workflow confirm doom-a1b go --note-to review "only bugs from now on" --note-to build "use a table"
cmd/agent-workflow confirm doom-a1b accept
```

Your own going back isn't counted, and doesn't start the count again.

### Changed by hand

Each run not over is looked at again every 30 seconds (`agent-workflow-queue-check`). It notices what you change by hand
in its issue and its branch.

| Key | Action |
|---|---|
| `M-x agent-workflow-watch` | Look at the runs again now |

- **Its issue closed or deferred:** its running steps stop, their work and their agents' sessions kept. The run asks: go
  on (the issue in progress again), or cancel it.
- **Blocked by a new dependency:** no new job starts until it's unblocked, and the run says by what. Running jobs
  finish.
- **Its type or its `workflow:` label changed:** the run keeps its workflow, and its journal says so.
- **Its title, description, acceptance or notes edited:** the next steps read them anew.
- **Its branch:** your commits on it are work like any other. If a job's commits are no longer on it (a reset, a
  force-push), the run stops and asks: go on as it is now, or stop.

### Stopped, then on again

A run's `state.json` holds all it needs to come back. Once Emacs has started (and been idle a second), the runs not over
are read back, each with the workflow it started with. A command that uses a project's runs before then reads them back
first. A job that was running is interrupted, and waits for you.

| Key | Action |
|---|---|
| `M-x agent-workflow-continue` | Continue every interrupted run of the project |
| `C-u M-x agent-workflow-continue` | The same, each run taking its workflow as it is now (its jobs kept by name) |
| `M-x agent-workflow-pause` | Start nothing new; running steps finish |
| `C-u M-x agent-workflow-pause` | Stop the running steps at once, interrupted |
| `M-x agent-workflow-unpause` | On again |
| `M-x agent-workflow-cancel` | Cancel a run (or **Cancel** in its pane) |
| `M-x agent-workflow-remove-worktree` | Remove the worktree a finished run kept (or **Remove worktree** in its pane) |

```sh
cmd/agent-workflow continue                 # every interrupted run of the project
cmd/agent-workflow continue doom-a1b --current
cmd/agent-workflow cancel doom-a1b
cmd/agent-workflow pause --now
cmd/agent-workflow unpause
```

- **Continuing** resumes an agent step's session in the same worktree, telling it it was interrupted and what the branch
  has now. If it can't be resumed, a fresh session is told the same. A script runs again from its start. Steps already
  done never run again.
- `agent-workflow-continue-on-start` continues them by itself as Emacs starts.
- Instead of continuing, you can skip the step (`cmd/agent-workflow confirm ISSUE skip`), go back to a job, or cancel
  the run.
- **Cancelling** stops its agents and kills its scripts. Its running or waiting jobs end `cancelled` (in its pane, in
  `status`, and when read back). Its issue is open again, and its branch is kept.
- Its worktree is then removed by itself 10 seconds later (`agent-workflow-worktree-removal-delay`; nil: never), its
  pane counting down. **Keep worktree** stops it. It's removed only if nothing in it would be lost (no uncommitted
  changes); otherwise it stays. Its branch then goes too, if it has no commit of its own.
- A run that fails is handled the same way.
- **Removing a worktree** that a finished run kept (you kept it, or it had uncommitted changes) asks first, saying what
  goes: its uncommitted changes are lost. Its branch is deleted if it has no commit of its own; otherwise it's kept.

### What a run keeps

| Where | What |
|---|---|
| `.agent-shell/agent-workflow/runs/ISSUE/N/journal.jsonl` | Every event of the issue's run N, one JSON line each, as it happens |
| `state.json` beside it | The run as it stands |
| `workflow.yml` beside it | The workflow as the run started |
| The issue | In progress. Its metadata (`workflow`, `workflow_run`, `workflow_state`, `workflow_jobs`), the running job as a label (`job:review`), and what each job said, in its notes. Written as `agent-workflow`, in the background: a moment after the journal |

## A dry run

`M-x agent-workflow-dry-run` tries a workflow before it spends tokens. Nothing runs and nothing changes: no worktree,
branch, issue or session. It walks the workflow as a run would, wave by wave.

| Key | Action |
|---|---|
| `M-x agent-workflow-dry-run` | Walk a workflow, nothing run |
| `cmd/agent-workflow dry-run NAME` | The same from the shell |

- It shows what would run and which jobs at once, what would wait and why, and what each `if` skips.
- It shows what an outcome sends back (counted against `max-rounds`), a script fixed and run again, and where the run
  would stop to ask you. Or, once it ends, what happens to its branch.
- You choose the agents' outcomes, one per round (`review=changes,approved`), and the scripts' exit codes, one per try
  (`build.2=1,0`). Without a choice, an outcome is `done` and an exit code is 0.
- An `if` reads the issue you give (`--issue ID`), or else an issue of the first type the workflow is for.
- A project's workflow you don't trust yet (see [Trust](#trust)) has its `if` not evaluated and its Lisp not run: each
  is taken as true, and it says so.

```sh
cmd/agent-workflow dry-run feature --outcome review=changes,approved --exit build.2=1,0
```

## Trust

A workflow's scripts, `elisp` steps and `if` run as you, with everything you may do. So a project's own workflows (its
`.agent-workflow/`) run only once you trust the project. The first time, you're asked: run it this once, trust the
project (remembered), or not.

| Key | Action |
|---|---|
| `M-x agent-workflow-trust` | Trust a project's workflows. From the shell, they're refused until you do |
| `M-x agent-workflow-forget-trust` | Stop trusting a project |

- The starters and yours (out of git) are trusted.
- A file under `.agent-shell/agent-workflow/` that the repository tracks (someone committed it) is the project's, not
  yours.

Agents can't change what runs them:

- Every agent is denied editing what runs it: `.agent-workflow/`, and your own workflows and agents
  (`.agent-shell/agent-workflow/workflows/`, `agents/`, trusted without asking). This holds where it works, and in the
  main checkout by their absolute paths. Bash isn't covered: its agent's own rules have to watch it.
- A branch that changes `.agent-workflow/` is merged only once you say so (`confirm ISSUE go`), whatever the workflow's
  `approve` says.
- The check warns about a `run:` naming a file elsewhere (`tests/run.sh`): an agent could change it to make it pass. A
  file of `.agent-workflow/` runs your checkout's copy.

## For your agent

The [agent-workflow skill](../skills/agent-workflow/SKILL.md) teaches an agent to write, check and run workflows. Ask
yours to "write a bugfix workflow": it checks its draft with `cmd/agent-workflow check` before telling you where it
goes. Every agent-shell session is told where the skill is.

The agent doing a job of a run is told its job, where it works and how it ends its step. Then it's pointed to the
[agent-workflow-step skill](../skills/agent-workflow-step/SKILL.md): reading the issue and what came before, its canvas,
being sent back, and what its outcomes do.

## Checking them

`M-x agent-workflow-check` reads the project's workflows and agents again and lists every problem. Each line takes you
to its file and line.

| Key | Action |
|---|---|
| `M-x agent-workflow-check` | Check the project's workflows and agents |
| `cmd/agent-workflow check` | The same from the shell, as JSON ([more](cmd.md#cmdagent-workflow)) |
| `cmd/agent-workflow check FILE` | Check one file, anywhere |

- A file with an error is left out. Errors include a `needs` naming no job, `needs` that go round in a circle, an
  `agent` naming no agent, an `if` that isn't one Lisp form, and a variable that isn't one.
- A file with only warnings is kept.
- Neither `if` nor `elisp` is run to check them.

## Settings

| Setting | Default | What |
|---|---|---|
| `agent-workflow-pool` | `3` | How many agents run at once, across all projects |
| `agent-workflow-mode` | `"auto"` | The permission mode of an agent whose file has none (`mode:`) |
| `agent-workflow-kind` | `claude-code` | The kind of agent when neither its step nor its file says (`kind:`) |
| `agent-workflow-max-rounds` | `10` | How many times a job may send the work back before the run asks you |
| `agent-workflow-script-timeout` | `1800` | Seconds a script may run, unless its step's `timeout` says |
| `agent-workflow-budget` | `nil` | A run's budget when its workflow has none: `(:cost 15 :tokens 2000000 :time 10800)` |
| `agent-workflow-queue-check` | `30` | Seconds between looks at the runs not over |
| `agent-workflow-continue-on-start` | `nil` | Runs read back as Emacs starts continue by themselves |
| `agent-workflow-worktree-removal-delay` | `10` | Seconds before a cancelled or failed run's worktree is removed by itself; `nil`: never |
| `agent-workflow-pane-log-lines` | `200` | How many of a run's last log lines its pane keeps |
| `agent-workflow-pane-where-every` | `15` | Seconds between looks at a run's branch while its pane is open |
