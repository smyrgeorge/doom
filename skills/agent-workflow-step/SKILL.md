---
name: agent-workflow-step
description: >-
  Do a job of an agent workflow's run, as its agent: read the issue and what the jobs before it said, work in the
  issue's worktree (or a snapshot of its branch) and commit there, show your plan and ask the user on your canvas, and
  end your step with cmd/agent-workflow done OUTCOME "notes". Use when your system prompt says you do a job of a run.
---

# Doing a job of a run

The user's Emacs runs a workflow on an issue: its jobs, in order, some at once. You are the agent of one of them (your
system prompt names it, `doom-a1b · review`). You have no name and no role of your own: your profile says what you may
do. Emacs moves the work: you do your job, say it's done, and the workflow says what follows.

## Your job

1. **Read the issue**, as your first message gives it: its title, description, acceptance criteria. `bd show ISSUE
   --json` has the rest (its notes: what earlier jobs said). Your first message also has what the jobs before you
   said, when the workflow passes it on.
2. **Work where you're told**: the issue's worktree, on its branch; commit there, in small commits with clear messages.
   A job that only reads gets a snapshot of the branch: read it, run what you need, change nothing, commit nothing.
3. **End your step** (below), then end your turn.

## Ending your step

```sh
cmd/agent-workflow done "Built the lexer's escapes, with tests (tests/lexer-test.el)."
cmd/agent-workflow done changes "src/lexer.el:42: \\u isn't read. Add a test for it."
cmd/agent-workflow done approved "Reads well; the tests cover the acceptance criteria."
```

The outcome comes first when your job has outcomes (your system prompt lists them: `done`, or `approved`, `changes`...);
without one it's `done`. The notes are what the next jobs and the user need to know, in a few lines: what you did, where
(file:line), what's left. They go on the issue and into the next jobs' prompts. Its full path is in your system
prompt; it never asks the user's permission.

A turn ending without it leaves the run waiting for the user. Said too early (your work not committed), the next jobs
start without it.

## Never

- Switch, make or rename branches; push; rebase (unless told to, to resolve a merge's conflicts).
- Change the issue: its status, labels, assignee. Emacs does. `bd` reads are fine.
- Edit `.agent-workflow/`: you can't (what runs you never changes by you).
- Run `cmd/agent-workflow run`, `back`, `confirm`, `approve`, `continue`, `cancel`, `pause`: they're the user's, and
  refused from your session.

## Your canvas

Your Agent UI canvas is shown in your ticket's pane, in a section of its own, not a pane of yours: show your plan
there (`steps`, your acceptance criteria) and tick it as you go, as the agent-ui skill says. A question for the user
goes there too (`--canvas ask`); then end your turn: the run waits for your step's done, which comes after the answer.

## Coming back

Your session may be stopped and resumed, or started fresh, with a first message saying why:

- **Sent back**, by the user or a later job (a review's changes): its note says what to change. Change that, commit,
  and end your step again.
- **Rejected**: the user didn't approve your result; their note says why.
- **A script failed**: its output says what's wrong (a test, a check). Fix it, commit, end your step again: it runs
  again.
- **Interrupted** (Emacs stopped, the run paused): carry on from what the branch has now (the message says).

What each outcome does, approval, loops and budgets: [references/outcomes.md](references/outcomes.md).
