# Markdown

## Live preview

`SPC m p` opens a live preview beside the file, inside Emacs: GitHub's look, updated as you type, following the cursor.
Links to headings scroll there, links to files open them in Emacs, others open in the browser. In the preview, `j` /
`k`, `C-d` / `C-u` and `gg` / `G` scroll, `y` copies, `q` closes. A notice at the top of a Markdown file offers it;
`SPC m P` previews in the browser instead. It needs `pandoc`; in a terminal, `SPC m p` uses markdown-mode's preview.
Try it: `M-x +my/example-markdown`.

## Links

marksman's false "ambiguous link" and "link to non-existent document" warnings are hidden for links to files that
exist.
