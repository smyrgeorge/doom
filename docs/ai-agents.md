# AI agents

This config ships [Agent Skills](https://agentskills.io/) that teach a coding agent about this Emacs. They're in
`skills/`, in the open `SKILL.md` format. An agent reads a skill's `SKILL.md` first, and its reference files only when
it needs them.

| Skill | What it teaches |
|---|---|
| [`emacs-profiling`](../skills/emacs-profiling/SKILL.md) | Reading a profile recorded with `SPC h T`, to find what makes Emacs slow |
| [`agent-ui`](../skills/agent-ui/SKILL.md) | Showing things on its session's canvas |
| [`agent-workflow`](../skills/agent-workflow/SKILL.md) | Writing, checking and running agent workflows |
| [`agent-workflow-step`](../skills/agent-workflow-step/SKILL.md) | Doing a job of a workflow's run |

## emacs-profiling

`emacs-profiling` teaches an agent to read a profile recorded with `SPC h T`, and find what makes Emacs slow. Once it's
installed, the agent uses it on its own when you ask why Emacs is slow or hand it a profile.

### Installing

Install it with the [skills](https://github.com/vercel-labs/skills) command-line tool. It detects your agents and asks
which ones to install it for. `-g` installs it for all your projects, as Emacs is the same in each.

```sh
npx skills add smyrgeorge/doom -g
```

Or link the folder into your agent's skills directory, so it changes with this config:

```sh
ln -s ~/.config/doom/skills/emacs-profiling ~/.claude/skills/emacs-profiling
```

- Claude Code's skills directory is `~/.claude/skills/`.
- Another agent's is where it reads them, such as Codex's `~/.codex/skills/`.
- For an agent with none, name the folder in its `AGENTS.md`.

### Without installing

When `SPC h T` stops the profiler, its message says where the profile and the skill are. The message is also copied.
Paste it to any agent, and it reads the skill first ([Profiling Emacs](agent-shell.md#profiling-emacs)).

## agent-ui

`agent-ui` teaches an agent running in Emacs (agent-shell) to show things on its session's canvas: progress bars,
checklists, tables, text, Markdown, updated as it works ([Agent UI](agent-ui.md)).

- Any agent in agent-shell is told where the skill is, and reads it from there. You don't need to install it.
- Install it as above, with `agent-ui` instead of `emacs-profiling`, for an agent outside Emacs. Install it also to
  have it in Claude Code's list of skills.

## agent-workflow

`agent-workflow` teaches an agent to write, check and run [agent workflows](agent-workflow.md): the project's
`.agent-workflow/` workflows and agents, and `cmd/agent-workflow`.

- Any agent in agent-shell is told where the skill is. You don't need to install it.
- Install it as above, with `agent-workflow` instead of `emacs-profiling`, for an agent outside Emacs.
- `agent-workflow-step` is for the agent doing a job of a run, which is told of it.

## A crew of agents

Several agents can work on one project at once, each with a role and its own worktree. That's the
[agent workspace](agent-workspace.md#roles). A role is a Markdown file, as Claude Code's own agents are. It gives the
agent, its instructions, its tools and its permission mode.
