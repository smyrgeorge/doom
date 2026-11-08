# Search

## Search Everywhere

`SPC s a` searches classes, files, symbols and actions (commands) in one list. Type `c`, `f`, `s` or `a` and a space to
keep one kind; `DEL` on an empty input goes back to all.

## Find in files

`Cmd+Shift+F` (Linux: `Ctrl+Shift+F`) searches the project with ripgrep, starting from the selected text; with `C-u`, ignored and hidden files
too.

## Projects

- Projects under `~/dev` are found without adding them.
- `SPC p p` opens the project's README, if it has one.
- `SPC SPC` lists files created outside Emacs too.
- Each workspace keeps its own project.
