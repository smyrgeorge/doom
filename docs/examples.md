# Examples

`M-x +my/example` picks one from a list, `M-x +my/example-NAME` runs one by name. Each shows a feature on files of
its own, deleted when you close them; the echo area says what to try first.

| Example | What it shows | Try |
|---|---|---|
| `merge` | [Resolving conflicts](git.md#resolving-conflicts) | The margins' `>>` `<<` `x`, the ✨ wands on `discount()` and `tax()`, the bar's buttons; Done or Abort |
| `pdf` | [A PDF](pdf.md) with dark pages | `j` / `k`, `J` / `K` pages, `/` searches, `O` the outline, `SPC m d` light pages |
| `image` | [The image viewer](images.md), a picture beside its version in git's HEAD | `J` / `K` the folder's images, `+` / `-` zoom, `r` rotates, `y` copies; `SPC m g` closes the diff |
| `markdown` | [The live preview](markdown.md) | Type, move down the file, click a link in the preview; `SPC m p` closes it |
| `mermaid` | [A Mermaid diagram](mermaid.md) and its preview | Change a label, add a node, break a line; `SPC m p` closes the preview |
| `excalidraw` | [A drawing](drawings.md) | Draw with the mouse: `r` a rectangle, `a` an arrow, `t` text, `?` the keys; `SPC m d` the dark canvas |
| `stripe` | [The error stripe](editor.md#error-stripe) | Errors red, warnings yellow, TODOs blue, git's changes as in the gutter: click the strip to jump, drag to scroll |
| `tiling` | [Tiled panes](editor.md#tiling) | `SPC w SPC` another pane, `SPC w a` arranges them |
| `banner` | [Notices](editor.md#notices) | A notice's actions, its ✕ |
| `agent-ui` | [An agent's Agent UI](agent-ui.md) under its conversation, a stand-in agent (offline) releasing a project: its canvas, its tests and a question filled in as it works | `q` closes a view, `SPC m u` hides Agent UI |
| `issues` | [A project's issues](issues.md) in their list (needs `bd`) | `RET` opens one, Show closed shows the closed ones |
| `panel` | [A project panel](agent-ui.md#project-panels), this config's CPU panel, filled every second | `gR` reads it again, `q` closes it |
| `agent-workspace` | [An agent crew](agent-workspace.md) in its app: three stand-in agents, offline, each in its worktree | `a` then `A` answers sam's hand, `#ken` in the room, `j` / `k` on the bars, `Q` closes it |
| `agent-workflow` | [A run's pane](agent-workflow.md#following-a-run) as it runs: its tiles, branch, flow, jobs, live boxes and Log, from its journal (no agent runs: its e2e script does) | `TAB` on a divider folds its section, `RET` on a commit or a file opens it, Show output, `q` closes it |

`scripts/screenshots.sh [NAME...]` takes the screenshots, on macOS only (macOS's `screencapture`; the terminal it runs
from needs the Screen Recording permission). The examples themselves work on Linux too.

To add an example, write `examples/NAME.el` with a `+my/example-NAME` command, list it here and in
`config/examples.el`, test it in `tests/unit/test-examples.el`, and show its screenshot in the feature's doc. What it
says in the echo area fits 80 columns; the full keys go in its commentary and in the table above.
