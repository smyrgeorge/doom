# Agent workspace

> **Status:** being built (epic `doom-51z`). There are agents, their sessions, worktrees and states. The app comes
> next: its workspace, the issues, the stage, the room.

Several coding agents work on a project at once, a **crew**. Each agent has a name, a role and a colour. Each works in
its own git worktree, so they don't get in each other's way or touch your checkout. Each works only with you.

For now you make an agent from Lisp, in the project:

```elisp
(agent-workspace-create :role "builder" :name "ada")
```

## An agent

- **Its session** is a Claude Code session in agent-shell, in the buffer `ada · builder`. It's told who it is, that
  it works with you only, and to commit in its worktree. Its role's model, permission mode and tools apply.
- **Its worktree** is `.agent-shell/worktrees/ada`, on the branch `agent/ada`. It's made with the agent and kept when
  the agent stops, so the next start finds its work. `.agent-shell/` stays out of git.
- **Its colour** is one of the theme's ANSI colours, a free one by default.
- **Its name** goes into the issues' history: its `bd` commands run as `ada`.

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

## What you do to one

You can interrupt an agent, kill it, restart it fresh, put it to sleep, wake it, rename it (its worktree and branch
follow) or recolour it. Forgetting an agent takes it out of the crew and leaves its worktree. Killing it gives back
the issue you gave it, if it's still in progress and assigned to the agent.

Closing the crew, or quitting Emacs, stops every agent at once, without asking. No process of theirs is left
running. Their worktrees stay.
