---
name: agent-workflow
description: >-
  Write, check and run agent workflows: the work on an issue described as GitHub Actions does (jobs, their order,
  which run in parallel, their steps), some steps an LLM in agent-shell with an agent, others scripts, Lisp or a
  built-in merge, run by Emacs on a pool of agents. Use when asked to write or change a project's workflow or agent
  (.agent-workflow/), check one, or start, follow, answer, continue or send back a run (cmd/agent-workflow).
---

# Agent workflow

A **workflow** is the work on a project's issue, as GitHub Actions describes it: **jobs**, the order they run in
(`needs`), which run in parallel (those that don't need each other), and their **steps**, in order. A step is a script
(`run:`), Lisp in the user's Emacs (`elisp:`), a built-in (`uses: merge`), or an **agent**: an LLM in agent-shell,
its tools, rules and instructions a Markdown file of `agents/` (`agent: review`: `agents/review.md`). Emacs is the
engine: it starts each job, gives agent steps to sessions of a **pool** (no role, no name: a session is a job's,
`doom-a1b · review`), moves the issue, and writes a run's journal.
Agents never hand work on: they end their step, and the workflow says what follows.

## Where they are

| Place | Committed | What |
|---|---|---|
| `.agent-workflow/workflows/NAME.yml`, `.agent-workflow/agents/NAME.md` | yes | the project's; run once the user trusts the project |
| `.agent-shell/agent-workflow/workflows/`, `agents/` | no | the user's own |
| `~/.config/doom/config/agent-workflow/workflows/`, `agents/` | with this config | the starters: feature, bugfix, quick; build, test, docs, review, investigate, security |

One of the same name replaces the one before it: a starter, then the project's, then the user's. Agents of a run can't
edit `.agent-workflow/`, and a branch changing it merges only once the user says so.

## The command

`~/.config/doom/cmd/agent-workflow` (`agent-workflow` below), from a shell in the project. Its reply is JSON; exit 0
done, 1 not (the reply says why), 2 a wrong use, 3 no Emacs.

```sh
agent-workflow check                    # every workflow and agent of the project, their problems
agent-workflow check draft.yml          # one file, anywhere: check what you write before saving it in place
agent-workflow dry-run feature --outcome review=changes,approved   # walked, nothing run: what would happen
agent-workflow run doom-a1b doom-c3d --detach   # runs started, each with its own workflow (--workflow NAME)
agent-workflow status doom-a1b          # its run: state, jobs, what it asks (logs ISSUE: its log, as lines)
agent-workflow back doom-a1b build "handle the empty list too"   # sent back to a job, the work kept
agent-workflow confirm doom-a1b go      # a run's question answered: go, accept, skip, stop, cancel
agent-workflow approve doom-a1b         # the result waiting for the user's OK (reject ISSUE "note")
agent-workflow continue                 # interrupted runs on again (cancel ISSUE, pause, unpause)
```

`run`, `back`, `confirm`, `approve`, `reject`, `continue`, `cancel` and `pause` are the user's: refused from an agent of
a run. Do them when the user asks you to. Without `--detach`, `run` prints its runs' logs until they end (hours):
from your shell, detach, then read `status` or `logs`.

## A workflow

```yaml
name: feature
description: A feature, built with its tests, checked, reviewed, merged.
for: [feature, task]              # the issue types it's offered for
concurrency: 3                    # agents on its runs at once
budget: {cost: 15, time: 3h}      # then the run asks

jobs:
  build:
    steps:
      - agent: build              # the build agent, an LLM
        prompt: |
          Build {issue}: {issue.title}.
          {issue.acceptance}
      - run: .agent-workflow/scripts/check.sh   # 0: on; 1: back to build's agent, then again
        retries: 3

  docs:
    needs: build
    if: (not (eq (issue-type) 'task))
    agent: docs

  review:
    needs: [build, docs]          # it sees the docs too
    agent: review
    approve: true                 # its result waits for the user's OK
    outcomes:
      approved: continue
      changes: rerun build        # build and every job after it again (10 rounds, then it asks)

  merge:
    needs: review
    concurrency: 1                # one merge at a time, across runs
    uses: merge
    with: {suite: make test}
    on-fail: build                # a conflict: the build agent rebases
```

Its keys, in a line each: `name` (its file's), `description`, `ticket` (`false`: it runs on no ticket), `runs-in` (`checkout`: in the user's), `for`, `concurrency`, `budget` (`cost`, `tokens`,
`time`), `max-rounds`, `branch` (`delete` once merged, the default, or `keep`), `jobs`. A job: `needs`, `if`, `steps` (or one step's keys on the job itself), `approve`,
`outcomes`, `max-rounds`, `concurrency`. A step: one of `agent` (with `prompt`), `run` (with `shell`), `elisp`, `uses`
(with `with`); and `name`, `timeout`, `retries`, `retry-from`, `on-fail`, `approve`.

## Writing one

1. Read the project's: `agent-workflow check` lists them and their problems. Start from a starter or the project's own.
2. Write it in a file outside `.agent-workflow/` first, and `agent-workflow check draft.yml` until it has no error.
3. Tell the user where it goes; saved in `.agent-workflow/workflows/`, check the project again.

Mind: a job's agents that may edit (their file doesn't deny both `Edit` and `Write`) take the branch one at a time;
those that only read work on a snapshot, beside them. A `run:` naming a file elsewhere than `.agent-workflow/` is
warned about: an agent could change the check to make it pass. Lisp with `: ` in it goes under `elisp: |` (YAML).

## What to read when

- Every key, its values and checks: [references/format.md](references/format.md).
- `if:` and the variables of a prompt or agent (`{issue.acceptance}`, `{jobs.build.notes}`...):
  [references/conditions.md](references/conditions.md).
- An agent (what an agent step may do): [references/agents.md](references/agents.md).
- Scripts (their environment, exit codes, retries, on-fail) and the built-in merge:
  [references/scripts.md](references/scripts.md).
- Running them: starting, following (logs, status, the pane), what a run waits for, its questions, going back, loops,
  approval, budgets, continuing, its journal and files: [references/running.md](references/running.md).
- Patterns: a feature, a bug, something small, a parallel review, an approval gate, a suite on the merge:
  [references/patterns.md](references/patterns.md).
