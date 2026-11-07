# Project sidebar

The treemacs sidebar works as a project view:

- It opens by itself with a workspace's first project file; `SPC o p` closes it for that workspace.
- It follows the current file and its project at once. Scroll it away and it stays there until you switch files.
- Files and folders have their git status colours, updated on save and every few seconds for changes made outside
  Emacs.
- The arrows work in the tree (`←` collapses or goes to the parent, `→` expands or opens), in the LSP lists
  too. A single click opens a file or a folder. `zR` / `zM` expand or collapse everything.
- `SPC w w` and the window numbers reach it.
- With `+lsp`: the structure (`SPC c S`), the project's errors (`SPC c X`) and the call hierarchy (`SPC c y` /
  `SPC c Y`) open with the cursor in them.

A tips panel under it (from `cheatsheet.org`) is turned off; uncomment `config/cheatsheet` in `config.el` to turn it on.
