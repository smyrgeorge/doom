# Performance

## Compiled config

Doom loads `config/*.el` as source, so its functions ran interpreted, several times slower (the
stripe's redraw on each frame of a scroll: 1.5 ms instead of 0.2). Once Emacs has been idle for 2 s they're
byte-compiled in place, stopping at the first key press; again after anything loads (`after!` blocks define
functions when their package loads). No `.elc` files are written, so nothing gets stale (`config/compile.el`). Compiled
before a package loaded, a function would bind a local instead of the package's variable (`SPC g d` binding
`magit-display-buffer-function`: the diff opened in the same window) and call the package's macros as functions
(`invalid-function treemacs-run-in-every-buffer`); so such functions go back to their source and are compiled again
once the package loads.

## Opening files faster

Tree-sitter grammar checks are remembered (each one loaded the grammar's library again,
~10 ms on macOS with this many native-compiled libraries loaded; a Markdown file made ~9); garbage collection while
idle waits for 32 MB instead of gcmh's 800 KB (the language server's replies and redraws after opening a file
collected every few redraws, ~70 ms each). With the lens, sticky header and stripe changes, opening a Markdown file
went from ~1 s of pauses to ~0.35 s. And a file just opened shows first, plain, and gets its colours right after
(~0.1 s to see it instead of ~0.4 s): highlighting waits for its first display, like jit-lock's own deferral but only
then, so scrolling never shows plain text (`config/editor.el`).
