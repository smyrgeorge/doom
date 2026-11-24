# Agents

Part of the agent-workflow skill: read [SKILL.md](../SKILL.md) first.

An agent is what an agent step may do: `NAME.md`, a front matter, then the agent's instructions (added to its system
prompt, after what every agent of a run is told: its job, where it works, how it ends its step).

```markdown
---
description: builds an issue with its tests
tools: Read, Grep, Glob, Edit, Write, Bash(git add:*), Bash(git commit:*), Bash(git -C {worktree} status:*)
deny: Bash(git push:*)
model: opus
effort: high
mode: acceptEdits
icon: md-hammer ⚙
verb: building
colour: blue
---
Build what the issue asks for, with its tests. Commit as you go. Never push.
```

| Key | Is | Check |
|---|---|---|
| `name` | its file's, if given | another: an error |
| `description` | what it's for | none: an error |
| `kind` | its agent: `claude-code`, `codex`, `gemini-cli`, `opencode`, `qwen-code`, `copilot`, `goose`, `cursor`; none: the user's (`agent-workflow-kind`) | another: an error |
| `tools` | allowed without asking (Claude Code's `allowedTools`; another agent: its requests allowed), a list | `Tool` or `Tool(pattern)` |
| `deny` | never offered (`disallowedTools`; another agent: its requests refused, weaker) | the same |
| `model` | Claude Code's: `fable`, `opus`, `sonnet`, `haiku`, a model's id; another agent's own; none: the user's default | Claude Code's not one: a warning |
| `effort` | how hard it thinks: Claude Code's `low`, `medium`, `high`, `xhigh`, `max`; another agent's own; none: its model's default | Claude Code's not one: a warning |
| `mode` | its permission mode: Claude Code's `default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions` (none: auto); another agent's own (none: its default) | Claude Code's not one: an error |
| `icon`, `verb`, `colour` | how its steps are shown | |

An agent that denies both `Edit` and `Write` only reads: its jobs work on a snapshot of the branch, beside the others.
One that may edit takes the issue's worktree, one job at a time.

Every agent of a run may run `cmd/agent-workflow done` without asking, and may never edit `.agent-workflow/`, whatever
its agent says.
