# Search

## Search Everywhere (`SPC s a`)

One list of **Classes**, **Files**, **Symbols** and **Actions** (commands). Type `c`, `f`, `s` or `a` and a space to
keep one kind; `DEL` on an empty input goes back to all.

## Find in files (`Cmd+Shift+F`)

Searches the project with ripgrep; the selected text is the query. With `C-u`, ignored and hidden files too.

## Projects

- Projects under `~/dev` are found by themselves.
- Switching to a project (`SPC p p`) opens its README, if it has one.
- `SPC SPC` also lists files created outside Emacs.
- Each workspace keeps its own project.
