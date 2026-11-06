# Git

## Magit

Diffs rendered with [`git-delta`](https://github.com/dandavison/delta) through `magit-delta`, ignoring the delta
settings in `~/.gitconfig` (`--no-gitconfig`): those are for the terminal, and delta applies `line-numbers` even in
magit-delta's colour-only mode, writing line numbers into the diff's text, so that staging or discarding a hunk (`s`,
`x`) failed with "corrupt patch". The status buffer lists the repository's TODO/FIXME/... comments (`magit-todos`,
using `rg`, told never to colour its output: in terminal Emacs it did, and none were listed).

## Commit graph, like tig

The log (`l l`) and the status buffer's commits (`SPC g g`: "Recent commits" open,
20 of them) show the branch tree, each lane in its own colour, drawn with box-drawing lines (`●` `│` `╱` `╲` `─`,
`+my/magit-graph-glyphs`) instead of ASCII, with the author and the date (`2026-11-04 09:58`) in the margin.

## File diff pane

`SPC g d` shows the current file's changes vs `HEAD` (delta-rendered) in a pane on the right and
moves the cursor there, onto the hunk of the line you were on. It refreshes on save and switches to another file
when pressed there. In the pane: `s`/`u`/`x` stage/unstage/discard a hunk, `RET` jumps to the line, `SPC g d`,
`q` or `Esc` closes it. Opening it saves the buffer.

## Resolving conflicts

`e` on a conflicted file in Magit (its status, under Unmerged) opens it in three panes, like IntelliJ's merge window
(`config/merge.el`): **Yours** on the left, the **Result** in the middle (focused), **Theirs** on the right, under a bar.
Yours is your side: the branch you're on in a merge or a cherry-pick, what you're rebasing onto in a rebase. Theirs is
the branch merged, the commit being rebased or cherry-picked, the stash. Each pane's title says which (`Yours: main`,
`Theirs: feature`, `Theirs: 1a2b3c Fix the parser (being rebased)`). The Result starts as the version both sides came
from.

Each change of a side is highlighted: changed lines blue, added green, removed grey, conflicts (both sides changed the
lines, differently) red; the words that changed too. Its buttons are in its pane's margin, by the Result (icons in the
GUI, `>>` / `<<` / `x` in a terminal):

| Button | Action |
|---|---|
| `>>` (Yours) / `<<` (Theirs) | Put the change in the Result. In a conflict whose other side is in already, add it after that one (keep both) |
| `x` | Ignore the change: the Result keeps what it has there |

A change is done when each side that changed is in or ignored; it then turns grey (a check by the side put in). The
bar, across the top:

| Bar | Action |
|---|---|
| **Accept Left** / **Accept Right** | Yours / Theirs for every change not done yet |
| **✨ Apply non-conflicting** | Every change only one side made (or both the same), not done yet |
| *N changes left, M conflicts* | What's left |
| **Done** | Save the file, and stage it (`git add`) if no change is left. With some left, it asks first, and saves those as Git's conflict markers, not staged |
| **Abort** | Close, the file left as it was |

The Result can be edited as any file, and `u` undoes the buttons too (`C-r` redoes them). Keys in the panes: `]c` / `[c`
next / previous change; `SPC m l` / `SPC m r` the change at point from Yours / Theirs, `SPC m x` ignore it, `SPC m L` /
`SPC m R` accept left / right, `SPC m a` apply non-conflicting; `C-c C-c` (or `Cmd+S`) Done, `C-c C-k` Abort.
Closing a pane aborts. Done writes the file as is (no save hooks, such as formatting) and shows it in its buffer if
one is open (asking first if that one has changes not saved).

The three versions are Git's, from its index (stages `:1:` the base, `:2:` yours, `:3:` theirs), so merges, rebases,
cherry-picks, reverts and stash pops alike. Ediff finds the changes (its diff3 parser, comparing the three: it says
which side changed each region, or both), without its windows: the Result starts from the base, so it needs the
changes both sides made the same too, which Ediff's merge leaves out. macOS's `diff3` can't print a last line without
its newline in a way Ediff reads, so it's given copies ending with one: a change of the final newline alone isn't
seen. Binary files, files added on both sides or deleted on one, submodules and links open in Magit's usual Ediff
instead.
