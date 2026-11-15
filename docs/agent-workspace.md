# Agent workspace

> **Status:** being built (epic `doom-51z`). There are agents, their roles, sessions, worktrees and states. The app
> comes next: its workspace, the issues, the stage, the room.

Several coding agents work on a project at once, a **crew**. Each agent has a name, a role and a colour. Each works in
its own git worktree, so they don't get in each other's way or touch your checkout. Each works only with you.

For now you make an agent from Lisp, in the project:

```elisp
(agent-workspace-create :role "builder" :name "ada")
```

## An agent

- **Its session** is a Claude Code session in agent-shell, in the buffer `ada · builder`. It's told who it is, that
  it works with you only, and to commit in its worktree, then its role's instructions. Its role's model, permission
  mode and tools apply.
- **Its worktree** is `.agent-shell/worktrees/ada`, on the branch `agent/ada`, branched from your checkout's HEAD.
  It's made with the agent and kept when the agent stops, so the next start finds its work. It's locked with the
  agent's name as the reason (`git worktree list -v`). `.agent-shell/` stays out of git. A project that isn't a git
  repository, or has no commit yet, can't have a crew.
- **Its colour** is one of the theme's ANSI colours, a free one by default.
- **Its name** goes into the issues' history: its `bd` commands run as `ada`.

## Roles

A role is what a kind of agent does and may do. These four ship with this config:

| Role | Does | May |
|---|---|---|
| scribe | writes issues with you | read, `bd`; no edits |
| investigator | investigates what you give it, writes its findings into the issue | read, search the web, `bd`; no edits |
| builder | builds what you give it, runs the tests, commits on its branch | edit, commit; never push |
| reviewer | reviews a branch you point it to, gives you its verdict | read, `bd`; no edits |

Each role is a Markdown file, as Claude Code's own agents are: a front matter, then its instructions.

```markdown
---
description: writes and runs tests
tools: Read, Edit, Bash(npm test:*)
deny: WebFetch
model: haiku
mode: acceptEdits
labels: test
max: 2
icon: md-flask ⚗
verb: testing
colour: yellow
---
Write the tests first, then run them.
```

- `tools` are allowed without asking. `deny` are never offered. `mode` is Claude Code's permission mode. Claude Code
  enforces all three.
- `max` is how many of the role may run at once. `labels` are the issues it's for.
- `icon` is a nerd icon for the GUI, then a glyph for the terminal. `verb` is what its agents show while they work:
  "testing doom-a1b". `colour` is its agents' colour while it's free.

A project's own roles go in its `.agent-workspace/roles/`, committed. They add to the four, or replace the one with the
same name. `M-x agent-workspace-copy-role` copies one of the four there for you to change. A file with a mistake is
left out, and a warning names its file and line.

## Its states

| State | Means |
|---|---|
| waking up | its session is starting |
| at the desk | it waits for you |
| working | its turn runs, timed from its start |
| hand raised | it waits for a permission or an answer: "wants to run npm install" |
| done, have a look | its turn ended; once you show its session, it's at the desk |
| stuck | an error stopped it |
| asleep | you stopped it; it stays in the crew |
| gone home | killed, or its process ended |

## Its name on its worktree

- Its worktree is a project of its own, named `doom · ada`.
- A file of its worktree shows the agent in its mode line, in its colour: `▌A ada · builder`. A click there selects the
  agent.
- That file's tab starts with the agent's avatar, `▌A`.
- A worktree left by an agent you've forgotten shows its name dimmed.

## Its branch

| Command | Does |
|---|---|
| `M-x agent-workspace-review` | An agent's changes in magit: what its branch did since it left yours (`main...agent/ada`) |
| `M-x agent-workspace-merge` | Merges its branch into your checkout, tells the agent, and offers to reset its branch to the result |

A merge that conflicts stops in your checkout, for you to resolve.

## What you do to one

You can interrupt an agent, kill it, restart it fresh, put it to sleep, wake it, rename it (its worktree and branch
follow) or recolour it. Killing it gives back the issue you gave it, if it's still in progress and assigned to the
agent.

Forgetting an agent takes it out of the crew. Its worktree and branch go too when they hold nothing your checkout
hasn't. Otherwise you're shown what they hold (changes not committed, commits not on your branch) and asked whether
to keep them.

Closing the crew, or quitting Emacs, stops every agent at once, without asking. No process of theirs is left
running. Their worktrees stay.
