# Claude Code

Claude Code runs in an Emacs buffer through [agent-shell](https://github.com/xenodium/agent-shell), with the `claude`
CLI's login.

| Key | Action |
|---|---|
| `SPC o c` | A new session, in a new [tiled](editor.md#tiling) pane |
| `SPC o C` | The project's session (`C-u`: a new one, `C-u C-u`: pick one) |
| `Option+Enter` (Linux: `Alt+Enter`) | Send the error at point or the selection to Claude |

Sessions are told they run in Emacs: `path:line` references become links, images show inline in the theme's colours,
and Claude can ask Emacs what you're looking at. While you're in another app, a [notification](notifications.md) says
when a session finished its turn or asks for your permission.

## Drawing for Claude

In a Claude Code buffer, `C-c C-d` (`SPC m d`) opens a new [drawing](drawings.md) in a new pane, saved in the project's
`.agent-shell/drawings/`.

| Key | Action |
|---|---|
| `C-c C-c` | Insert it into the prompt as an image (a PNG beside the drawing) and close it |
| `C-c C-k` | Discard it |
| `M-p` / `M-n` | An earlier drawing instead, to change and insert again |

## Issues for Claude

In a project that tracks its [issues](issues.md) with Beads, Claude works with them through `bd`. A session started
there is told so, with Beads' own guide for agents (`bd prime`), and each `bd` command Claude runs refreshes the
issue lists and issues you have open, so its changes show as it makes them.

| Key | Action |
|---|---|
| `C-c C-i` (`SPC m i`) | In a Claude Code buffer: pick one of the project's open issues (ready ones first) for the prompt |
| `C-c C-a` (`SPC m a`) | On an issue, in the list or its own buffer: put it in the prompt of the project's session |

An issue goes into the prompt as `Beads issue ID: title`, for you to say what to do with it.

## Profiling Emacs

`SPC h T` starts the profiler; do what's slow, then `SPC h T` again. The profile is written as text under
`~/.config/emacs/.local/cache/profiles/`, and a message (also copied) tells Claude where it is and to read the
[`emacs-profiling` skill](ai-agents.md) first.
