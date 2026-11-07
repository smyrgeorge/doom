# Markdown

`SPC m p` opens a live preview in a new pane: GitHub's look, updated as you type and following the cursor. Links to
files open them in Emacs. `SPC m P` previews in the browser instead. It needs `pandoc`. Try it:
`M-x +my/example-markdown`.

The notice at the top of a Markdown file has an **Open preview** button: it opens the preview, or shows it again if
its pane was closed. `SPC m p` closes the preview when it's on screen.

![A README beside its live preview](../examples/markdown.png)

In the preview, `j` / `k`, `C-d` / `C-u` and `gg` / `G` scroll, `y` copies and `q` closes it.
