# Issues

A project's issues, tracked with [Beads](https://github.com/gastownhall/beads) (`bd`): a git-backed issue tracker
that keeps them in the project's `.beads/`, beside the code. Coding agents such as Claude Code use it as their memory
across sessions; [beads.el](https://codeberg.org/ctietze/beads.el) shows the same issues in Emacs. `scripts/tools.sh`
installs `bd` (Homebrew on macOS, npm on Linux).

A project starts tracking its issues with `bd init` at its root (it also adds instructions and hooks for agents).

| Key | Action |
|---|---|
| `SPC o i` | The project's issues |
| `SPC o I` | A new issue: title, type, priority |

## The list

| Key | Action |
|---|---|
| `RET` | Open the issue |
| `P` | Preview the issue under the cursor, beside the list, as you move |
| `c` / `C` | A new issue / a new one, previewed first |
| `e t`, `e s`, `e p`, `e T`, `e d` | Edit its title, status, priority, type, description |
| `E` | Edit all of it in a form (`TAB` next field, `C-c C-c` save, `C-c C-k` cancel) |
| `a` / `A` | Assign it / to yourself |
| `/` | Search the titles and descriptions |
| `f` | Filter: status, priority, type, assignee, label, ready (`f r`), blocked (`f b`) |
| `s`, `o`, `O` | Sections or columns; sort by the next column; reverse |
| `H` | Its dependencies, as a tree |
| `S` | The project's statistics |
| `D` / `R` | Delete it / reopen it |
| `gr` | Refresh (the list also refreshes every 30 seconds) |
| `?` | Every command, in a menu |
| `q` | Close |

## An issue

Its description, design, acceptance criteria and notes, rendered as Markdown, with its fields and dependencies.

| Key | Action |
|---|---|
| `e d`, `e D`, `e a`, `e n` | Edit the description, design, acceptance criteria, notes (`C-c C-c` save) |
| `e t`, `e s`, `e p`, `e A`, `e l a` | Edit the title, status, priority, assignee; add a label |
| `E` | Edit all of it in a form |
| `c` | Add a comment |
| `P` / `C` | Its parent / its children |
| `H` | Its dependencies, as a tree |
| `gr` / `q` | Refresh / close |

`M-x beads-stale`, `beads-orphans` (issues mentioned in commits but still open), `beads-duplicates` and `beads-lint`
(issues missing their type's sections) are reports of their own.

## With bd 1.x

beads.el was written for bd 0.49, which ran a daemon; bd 1.x has only its command line. `config/beads/bd.el` mends what
changed, and the tests run each command against the real `bd`. The activity feed and the merge conflicts view need
commands bd no longer has: they say so.

In normal state the buffers' own letters win over Vim's (Vim's `j`, `k`, `gg`, `gt` and `SPC` stay), and refreshing is
`gr`. Statuses and types take the theme's colours, and a P0 issue's row is tinted with its red.
