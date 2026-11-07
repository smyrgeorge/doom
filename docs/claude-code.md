# Claude Code

[agent-shell](https://github.com/xenodium/agent-shell) runs Claude Code in an Emacs buffer, with the Claude CLI's
login.

- `SPC o c` starts a new session; `SPC o C` goes to the project's (`C-u`: a new one, `C-u C-u`: pick one).
- In code, `Option+Enter` sends the error at point or the selection to Claude, or adds them to the prompt.

Claude is told how Emacs shows it: the Markdown it renders, `path:line` references (they become links), images shown
inline (saved under `.agent-shell/images/`), the theme's colours for its diagrams, and that it can ask Emacs what you're
looking at (`emacsclient --eval`). Images are as wide as the window.

## Profiling

`SPC h T` starts Emacs's profiler (CPU and memory); do what's slow, then `SPC h T` again. The profile is written as text
into a new folder under `~/.config/emacs/.local/cache/profiles/`: a summary, the call trees, and the raw profiles
(`M-x profiler-find-profile`). The message says where, and to read the skill
`.claude/skills/emacs-profiling/SKILL.md` first, which explains the files to an agent. It's also copied, so you can paste
it to Claude.
