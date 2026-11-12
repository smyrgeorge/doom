# Markdown

`SPC m p` opens a live preview in a new pane: GitHub's look, updated as you type and following the cursor. Links to
files open them in Emacs. `SPC m P` previews in the browser instead. It needs `pandoc`. Try it:
`M-x +my/example-markdown`.

The notice at the top of a Markdown file has an **Open preview** button: it opens the preview, or shows it again if
its pane was closed. `SPC m p` closes the preview when it's on screen.

![A README beside its live preview](../examples/markdown.png)

In the preview, `j` / `k`, `C-d` / `C-u` and `gg` / `G` scroll, `y` (or `Cmd+C`; Linux: `Ctrl+Shift+C`) copies and `q`
closes it.

```` ```mermaid ```` blocks show as diagrams in the preview, in the theme's colours ([Mermaid](mermaid.md)), redrawn as
you edit them; one with an error shows Mermaid's message under its last drawing.

The preview needs an Emacs with xwidgets (WebKit; see [PDFs](pdf.md)) and works with any pandoc (Debian's and Ubuntu's
too). Without xwidgets, or in a terminal, `SPC m p` is markdown-mode's preview (eww), updated on save.

## Reflowed on screen

A file filled at a wider column than its pane (this config's docs are filled at 120) used to wrap raggedly: each source
line wrapped on its own, a short row after it. In a Markdown file, a paragraph's lines (a list item's, a quote's too)
are shown as one line, wrapped at the pane's edge, the following rows lined up under the item's text. The file itself
isn't changed. Hard line breaks (two trailing spaces, a backslash), code blocks, tables and headings are left as they
are, and so is everything while lines don't wrap. Line numbers then show on a paragraph's first line only.

In `config.el`, `(setq +my/markdown-reflow nil)` turns it off.
