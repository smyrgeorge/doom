# Project sidebar (treemacs)

`config/treemacs.el` makes treemacs behave like IntelliJ's project view:

- **Opens automatically** the first time a project file is shown in a workspace (`SPC p p`, `SPC SPC`, `SPC f r`, the
  dashboard...). Close it with `SPC o p` and it stays closed for that workspace.
- **Follows the current buffer**: highlights the open file and switches to the buffer's project, right after every
  buffer or window switch (treemacs' own project follow waits for 1.5 s without any input).
- **Git status** colours for files and folders, computed asynchronously. Saving a file refreshes its status (macOS's
  kqueue file notifications miss in-place edits, so this is done explicitly on save). Changes made outside Emacs
  (Claude Code, a terminal, git) show up within a few seconds: while Emacs has focus, the shown projects' `git status`
  is checked every 3 s in the background (`+my/treemacs-git-poll-interval`), and treemacs refreshes when it changed.
- **Reachable like any window**: `SPC w w` cycles into it and it gets a window number (`SPC w 1`, as the leftmost
  window).
- **No mode line**: it only said "Treemacs" and the workspace.
- **Arrows, like IntelliJ's trees**: `←` collapses a node, or goes to its parent; `→` expands a closed node, goes to
  the first child of an open one, and opens a file (in the error list, jumps to the error). `↑`/`↓` move a line, like
  `k`/`j`. The same in the LSP lists (`SPC c X`, `SPC c S`), where `←`/`→` didn't expand or collapse anything.
  `h`/`l` keep treemacs' own collapse / open. A **single click** opens a file or expands/collapses a folder
  (treemacs' default is a double click).
- `zR` / `zM` (`M-x treemacs-expand-all` / `treemacs-collapse-all`): expand every folder of the project, or collapse
  them all (the project stays open at its top level). Expanding asks first in projects with more than 300 folders.
- With `+lsp`: structure view (`SPC c S`), project errors (`SPC c X`) and call hierarchy (`SPC c y` / `SPC c Y`).
  The structure view and the error list open with the cursor in them, on their first line (it stayed in the code).
- **Tips panel** (disabled for now: uncomment `(load! "config/cheatsheet")` in `config.el`) below the sidebar,
  whenever it's open: a few tips from `cheatsheet.org` (this config's keys, Doom's, Vim's), two per section, changing
  every 5 minutes, so over time you see them all. In the panel `n` shows the next tips, `e` opens the whole
  cheatsheet, `q` hides it; `SPC t ?` hides / shows it. Edit `cheatsheet.org` to change the tips (one `- ` line each,
  under a `*` heading); the panel picks them up on save (`config/cheatsheet.el`).
