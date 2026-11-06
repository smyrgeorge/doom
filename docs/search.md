# Search

## Search Everywhere (`SPC s a`)

`config/search.el` emulates IntelliJ's double Shift: one list with **Classes**, **Files**, **Symbols** and
**Actions**. Typing searches all of them (words in any order, case-insensitive); to show one tab, type its key and
`SPC` — `c`, `f`, `s` or `a` — and `<<` (or `DEL` on an empty input) to go back to all.

- **Classes / Symbols:** the language server's workspace symbols, queried as you type (from 2 characters; only in
  buffers with an LSP server). Classes are classes, interfaces/traits, structs, enums and objects.
- **Files:** the project's files, recently opened ones first.
- **Actions:** every command (what `M-x` runs), recently used ones first, with key bindings and docs.

Emacs can't see a lone Shift key press on macOS, so it's on `SPC s a` instead of double Shift.

## Projectile

Projects are discovered under `~/dev`. The file cache is off, so `SPC SPC` also lists files created
outside Emacs (CLI, Claude Code, `git checkout`).
