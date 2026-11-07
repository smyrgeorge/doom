# Examples

`M-x +my/example-NAME` shows a feature on files of its own, deleted when you close them.

| Example | What it shows |
|---|---|
| `merge` | [Resolving conflicts](git.md#resolving-conflicts) |
| `pdf` | [A PDF](pdf.md) with dark pages |
| `markdown` | [The live preview](markdown.md) |
| `excalidraw` | [A drawing](drawings.md) |
| `stripe` | [The error stripe](editor.md#error-stripe) |
| `tiling` | [Tiled panes](editor.md#tiling) |
| `banner` | [Notices](editor.md#notices) |

`scripts/screenshots.sh [NAME...]` takes the screenshots. The terminal it runs from needs macOS's Screen Recording
permission.

To add an example, write `examples/NAME.el` with a `+my/example-NAME` command, list it here and in
`config/examples.el`, test it in `tests/unit/test-examples.el`, and show its screenshot in the feature's doc.
