# Search

Search Everywhere finds classes, files, symbols and commands in one list. Find in files searches the project's files
with ripgrep.

## Search Everywhere

`SPC s a` searches classes, files, symbols and actions (commands) in one list. Typing searches all of them at once.

| Key | Action |
|---|---|
| `SPC s a` | Search Everywhere |
| `c`, `f`, `s` or `a`, then a space | Keep one kind: classes, files, symbols or actions |
| `DEL` on an empty input | Back to all kinds |
| `C-SPC` | Preview the file or symbol in the pane you searched from (`C-g` puts it back) |

## Find in files

Find in files searches the project with ripgrep, starting from the selected text.

| macOS | Linux | Action |
|---|---|---|
| `Cmd+Shift+F` | `Ctrl+Shift+F` | Search the project's files |
| `C-u Cmd+Shift+F` | `C-u Ctrl+Shift+F` | The same, with ignored and hidden files too |

## Projects

- Projects under `~/dev` are found without adding them.
- `SPC p p` opens the project's README, if it has one.
- `SPC SPC` lists files created outside Emacs too.
- Each workspace keeps its own project, and what opens in it, even a moment later. An agent's session once picked with
  `SPC o C` is one: its tab stays, and `SPC b b` lists it.

| Setting | Default | What |
|---|---|---|
| `projectile-project-search-path` | `'("~/dev")` | Where projects are found, set in `config.el` |
