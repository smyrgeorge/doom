# AI agents

This config ships an [Agent Skill](https://agentskills.io/), `emacs-profiling`: it teaches a coding agent to read a
profile recorded with `SPC h T` and find what makes Emacs slow. It's in
[skills/emacs-profiling](../skills/emacs-profiling/SKILL.md), in the open `SKILL.md` format, with reference files the
agent reads only when it needs them.

## Installing

Install it with the [skills](https://github.com/vercel-labs/skills) command-line tool, which detects your agents and
asks which ones to install it for. `-g` installs it for all your projects, as Emacs is the same in each:

```sh
npx skills add smyrgeorge/doom -g
```

Or link the folder into your agent's skills directory, so it changes with this config, e.g. for Claude Code:

```sh
ln -s ~/.config/doom/skills/emacs-profiling ~/.claude/skills/emacs-profiling
```

The agent then uses the skill on its own when you ask why Emacs is slow or hand it a profile.

## agent-ui

The [agent-ui skill](../skills/agent-ui/SKILL.md) teaches an agent running in Emacs (agent-shell) to show things on its
session's canvas: progress bars, checklists, tables, text, Markdown, updated as it works ([Agent UI](agent-ui.md)).
Claude Code in agent-shell is told where it is, and reads it from there: no need to install it. Install it as above
(`agent-ui` for `emacs-profiling`) for other agents, or to have it in Claude Code's list of skills.

## Without installing

The message `SPC h T` shows when it stops, also copied, says where the profile and the skill are. Paste it to any
agent, and it reads the skill first (see [Profiling Emacs](claude-code.md#profiling-emacs)).
