# Search

## Search Everywhere

`SPC s a` searches classes, files, symbols and actions (commands) in one list. Type `c`, `f`, `s` or `a` and a space to
keep one kind; `DEL` on an empty input goes back to all. `C-SPC` previews the file or symbol in the pane you searched from
(`C-g` puts it back).

## Find in files

`Cmd+Shift+F` (Linux: `Ctrl+Shift+F`) searches the project with ripgrep, starting from the selected text; with `C-u`, ignored and hidden files
too.

## Projects

- Projects under `~/dev` are found without adding them (`projectile-project-search-path`, set in `config.el`).
- `SPC p p` opens the project's README, if it has one.
- `SPC SPC` lists files created outside Emacs too.
- Each workspace keeps its own project, and what opens in it, even a moment later (a Claude session once picked,
  `SPC o C`): its tab stays and `SPC b b` lists it.
