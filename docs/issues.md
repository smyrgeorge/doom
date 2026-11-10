# Issues

A project's issues, tracked with [Beads](https://github.com/gastownhall/beads) (`bd`): a git-backed issue tracker
that keeps them in the project's `.beads/`, beside the code. Coding agents such as Claude Code use it as their memory
across sessions; [beads.el](https://codeberg.org/ctietze/beads.el) shows the same issues in Emacs. `scripts/tools.sh`
installs `bd` (Homebrew on macOS, npm on Linux).

| Key | Action |
|---|---|
| `SPC o i` | The project's issues |
| `SPC o I` | A new issue: title, type, priority |

In a project that doesn't track its issues yet, `SPC o i` and `SPC o I` offer a terminal at its root with `bd init`
typed, not run: read it, run it with `RET`, then `SPC o i` again. `bd init` commits what it adds (and what's staged);
add `--skip-hooks` before running it to install no git hooks, `--skip-agents` to add no files for agents (`CLAUDE.md`,
`AGENTS.md`...). Claude Code in Emacs is told about the issues either way ([more](claude-code.md#issues-for-claude)).
The command typed is `+my/beads-init-command` in `config/beads.el`.

## The list

The list opens in a new pane where [tiling](editor.md#tiling) puts it, as Claude Code and Magit do; an issue opened
from it in a new pane too, and the next ones in that pane, as its tabs. The preview (`P`) stays beside the list.

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
| `gr` | Refresh (while it's shown, the list also refreshes itself every 30 seconds, in the background) |
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

## With Claude

Claude Code works with the same issues: a session in the project is told about them, your open lists follow its
changes, and `C-c C-a` on an issue hands it to the project's session ([more](claude-code.md#issues-for-claude)).

## With bd 1.x

beads.el was written for bd 0.49, which ran a daemon; bd 1.x has only its command line. `config/beads/bd.el` mends what
changed, and the tests run each command against the real `bd`. The activity feed and the merge conflicts view need
commands bd no longer has: they say so.

In normal state the buffers' own letters win over Vim's (Vim's `j`, `k`, `gg`, `gt` and `SPC` stay), and refreshing is
`gr`. Statuses and types take the theme's colours, and a P0 issue's row is tinted with its red.
