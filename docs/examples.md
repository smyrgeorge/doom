# Examples

`M-x +my/example` (or `M-x +my/example-NAME`) opens a feature on files of its own in the temp folder; they're deleted
when you close it.

| Example | What it shows |
|---|---|
| `merge` | [Resolving conflicts](git.md#resolving-conflicts) in three panes, every kind of change they handle |
| `pdf` | [A PDF](editor.md#pdfs) with dark pages |
| `markdown` | [The live preview](markdown.md#live-preview) beside a README |
| `excalidraw` | [A drawing](editor.md#drawings-excalidraw) |
| `stripe` | [The error stripe](editor.md#error-stripe) of a file with errors, warnings and git changes |
| `tiling` | [Tiled panes](editor.md#tiling) of a project's files |
| `banner` | [Notices](editor.md#notices) of each kind |

To add one, write `examples/NAME.el` with a `+my/example-NAME` command, list it here and in `config/examples.el`, test
it in `tests/unit/test-examples.el`, and take its screenshot.

## Screenshots

`scripts/screenshots.sh` (or `scripts/screenshots.sh NAME...`) saves each example's screenshot as `examples/NAME.png`,
from a GUI Emacs of its own with this config's look. The terminal you run it from needs macOS's Screen Recording
permission; reopen the terminal after granting it.

| Example | Screenshot |
|---|---|
| `merge` | ![The merge example](../examples/merge.png) |
| `pdf` | ![The PDF example](../examples/pdf.png) |
| `markdown` | ![The Markdown example](../examples/markdown.png) |
| `excalidraw` | ![The drawing example](../examples/excalidraw.png) |
| `stripe` | ![The error stripe example](../examples/stripe.png) |
| `tiling` | ![The tiling example](../examples/tiling.png) |
| `banner` | ![The notices example](../examples/banner.png) |
