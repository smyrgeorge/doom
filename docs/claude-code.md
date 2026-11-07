# Claude Code

Claude Code runs in an Emacs buffer through [agent-shell](https://github.com/xenodium/agent-shell), with the `claude`
CLI's login.

| Key | Action |
|---|---|
| `SPC o c` | A new session, in a new [tiled](editor.md#tiling) pane |
| `SPC o C` | The project's session (`C-u`: a new one, `C-u C-u`: pick one) |
| `Option+Enter` | Send the error at point or the selection to Claude |

Sessions are told they run in Emacs: `path:line` references become links, images show inline in the theme's colours,
and Claude can ask Emacs what you're looking at.

## Drawing for Claude

In a Claude Code buffer, `C-c C-d` (`SPC m d`) opens a new [drawing](drawings.md) in the window on its left, which
shows its own file again when the drawing closes. The drawing is saved in the project's `.agent-shell/drawings/`.

| Key | Action |
|---|---|
| `C-c C-c` | Insert it into the prompt as an image (a PNG beside the drawing) and close it |
| `C-c C-k` | Discard it |
| `M-p` / `M-n` | An earlier drawing instead, to change and insert again |

## Profiling Emacs

`SPC h T` starts the profiler; do what's slow, then `SPC h T` again. The profile is written as text under
`~/.config/emacs/.local/cache/profiles/`, and a message (also copied) tells Claude where it is and to read the
[`emacs-profiling` skill](ai-agents.md) first.
