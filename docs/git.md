# Git

## Magit

Diffs rendered with [`git-delta`](https://github.com/dandavison/delta) through `magit-delta`. The status buffer
lists the repository's TODO/FIXME/... comments (`magit-todos`, using `rg`).

## Commit graph, like tig

The log (`l l`) and the status buffer's commits (`SPC g g`: "Recent commits" open,
20 of them) show the branch tree, each lane in its own colour, drawn with box-drawing lines (`●` `│` `╱` `╲` `─`,
`+my/magit-graph-glyphs`) instead of ASCII, with the author and the date (`2026-11-04 09:58`) in the margin.

## File diff pane

`SPC g d` shows the current file's changes vs `HEAD` (delta-rendered) in a pane on the right and
moves the cursor there, onto the hunk of the line you were on. It refreshes on save and switches to another file
when pressed there. In the pane: `s`/`u`/`x` stage/unstage/discard a hunk, `RET` jumps to the line, `SPC g d`,
`q` or `Esc` closes it. Opening it saves the buffer.
