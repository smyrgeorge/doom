# Examples

`M-x +my/example-NAME` shows a feature on files of its own, deleted when you close them.

| Example | What it shows | Screenshot |
|---|---|---|
| `merge` | [Resolving conflicts](git.md#resolving-conflicts) | [merge.png](../examples/merge.png) |
| `pdf` | [A PDF](pdf.md) with dark pages | [pdf.png](../examples/pdf.png) |
| `markdown` | [The live preview](markdown.md) | [markdown.png](../examples/markdown.png) |
| `excalidraw` | [A drawing](drawings.md) | [excalidraw.png](../examples/excalidraw.png) |
| `stripe` | [The error stripe](editor.md#error-stripe) | [stripe.png](../examples/stripe.png) |
| `tiling` | [Tiled panes](editor.md#tiling) | [tiling.png](../examples/tiling.png) |
| `banner` | [Notices](editor.md#notices) | [banner.png](../examples/banner.png) |

`scripts/screenshots.sh [NAME...]` takes the screenshots. The terminal it runs from needs macOS's Screen Recording
permission.

To add an example, write `examples/NAME.el` with a `+my/example-NAME` command, list it here and in
`config/examples.el`, test it in `tests/unit/test-examples.el`, and take its screenshot.
