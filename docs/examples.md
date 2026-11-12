# Examples

`M-x +my/example-NAME` shows a feature on files of its own, deleted when you close them.

| Example | What it shows |
|---|---|
| `merge` | [Resolving conflicts](git.md#resolving-conflicts) |
| `pdf` | [A PDF](pdf.md) with dark pages |
| `image` | [The image viewer](images.md), a picture beside its version in git's HEAD |
| `markdown` | [The live preview](markdown.md) |
| `mermaid` | [A Mermaid diagram](mermaid.md) and its preview |
| `excalidraw` | [A drawing](drawings.md) |
| `stripe` | [The error stripe](editor.md#error-stripe) |
| `tiling` | [Tiled panes](editor.md#tiling) |
| `banner` | [Notices](editor.md#notices) |
| `agent-ui` | [An agent's canvas](agent-ui.md) beside its conversation, filled in as it works |
| `issues` | [A project's issues](issues.md) in their list (needs `bd`) |
| `panel` | [A project panel](agent-ui.md#project-panels), this config's CPU panel, filled every second |

`scripts/screenshots.sh [NAME...]` takes the screenshots, on macOS only (macOS's `screencapture`; the terminal it runs
from needs the Screen Recording permission). The examples themselves work on Linux too.

To add an example, write `examples/NAME.el` with a `+my/example-NAME` command, list it here and in
`config/examples.el`, test it in `tests/unit/test-examples.el`, and show its screenshot in the feature's doc.
