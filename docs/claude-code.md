# Claude Code

Claude Code runs in an Emacs buffer through [agent-shell](https://github.com/xenodium/agent-shell), with the `claude`
CLI's login.

| Key | Action |
|---|---|
| `SPC o c` | A new session, in a new [tiled](editor.md#tiling) pane |
| `SPC o C` | The same, in the window you're in (the file there kept as a tab) |
| `Option+Enter` (Linux: `Alt+Enter`) | Send the error at point or the selection to Claude |
| `RET` (normal state too) | Send the prompt (`S-RET`: a newline) |

`(setq +my/agent-shell-insert-ret-newline t)` in `config.el` makes `RET` in insert state a newline instead, the prompt
sent with `RET` from normal state.

A new session starts in insert state, its prompt empty but for what you chose: the selection, dired's marked files, the
image you're on. `(setq agent-shell-context-sources '(files region error line))` in `config.el` brings the error at
point too, or else the line you're on.

Sessions are told they run in Emacs: `path:line` references become links, images show inline in the theme's colours,
and Claude can ask Emacs what you're looking at. Claude can also keep things in view on a canvas beside its session:
progress bars, checklists, tables, updated as work goes on ([Agent UI](agent-ui.md)). Claude's small questions (2 to
4 options) come as a form in the conversation, Claude waiting for your answer (agent-shell's experimental forms:
`(setq agent-shell-elicitation--experimental-feature-enabled nil)` in `config.el` turns them off); a list to pick from
comes on the canvas, your answer its next prompt. While you're in another app, a [notification](notifications.md) says
when a session finished its turn or asks for your permission.

## Diagrams in replies

Claude's ```` ```mermaid ```` blocks are drawn as diagrams in its replies, in the theme's colours
([Mermaid](mermaid.md)), once a block is complete: its source shows until then, and with an error, Mermaid's message
under it. Copying a reply as Markdown, and its transcript, keep the source. Claude is told to use them for diagrams.

## Claude's diffs

A change Claude asks permission for opens as a diff with `v`. The keys its header line names work in normal state:

| Key | Action |
|---|---|
| `n` / `p` | The next / previous hunk |
| `y` | Accept the change |
| `RET` | Open the file at the change |

While Claude waits for a permission, `n` in normal state rejects it and interrupts Claude.

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
