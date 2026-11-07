# Git

## Magit

- Diffs rendered by `git-delta`.
- The status buffer lists the repository's TODO comments.
- The log and the status buffer's recent commits draw the branch graph with lines, a colour per lane, the author and
  date in the margin (like tig).

## File diff pane (`SPC g d`)

The current file's changes against `HEAD`, in a pane on the right, refreshed on save. In it, `s` / `u` / `x` stage,
unstage or discard a hunk, `RET` jumps to the line, `q` closes it.

## Resolving conflicts

`e` on a conflicted file in Magit opens it in three panes: **Yours**, the **Result** (editable, starting from the
common base) and **Theirs**, under a bar. Try it: `M-x +my/example-merge`.

Each change is coloured (changed blue, added green, removed grey, conflicts red) and has buttons in its margin, next to
the Result: `>>` / `<<` put it in the Result (in a conflict whose other side is in already: after it, keeping both), and
`x` ignores it. When both sides changed different words of the same lines, the **✨ wand** in the Result's margin
merges them word by word.

The bar has **Accept Left** / **Accept Right** (the rest from one side), **✨ Apply non-conflicting**, what's left,
**Done** (saves, and stages once nothing is left) and **Abort**.

The panes line up, scroll together and number their own lines.

| Key | Action |
|---|---|
| `]c` / `[c` | Next / previous change |
| `SPC m l` / `SPC m r` / `SPC m x` | The change at point from Yours / Theirs / ignored |
| `SPC m w` | The wand |
| `SPC m L` / `SPC m R` / `SPC m a` | Accept left / right / non-conflicting |
| `C-c C-c` / `C-c C-k` | Done / Abort |
| `u` | Undo, buttons too |

It works for merges, rebases, cherry-picks and stash pops, and in a terminal too. Binary files, files added or deleted
on one side, and submodules open in Magit's usual Ediff. `M-x +my/merge-all` resolves every conflicted file in turn;
from the shell, see [`cmd/diff.sh`](cmd.md).
