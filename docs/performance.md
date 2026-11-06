# Performance

## Compiled config

Doom loads `config/*.el` as source, so its functions ran interpreted, several times slower (the
stripe's redraw on each frame of a scroll: 1.5 ms instead of 0.2). Once Emacs has been idle for 2 s
(`+my/compile-idle-delay`) they're
byte-compiled in place, stopping at the first key press; again after anything loads (`after!` blocks define
functions when their package loads). No `.elc` files are written, so nothing gets stale (`config/compile.el`). Compiled
before a package loaded, a function would bind a local instead of the package's variable (`SPC g d` binding
`magit-display-buffer-function`: the diff opened in the same window) and call the package's macros as functions
(`invalid-function treemacs-run-in-every-buffer`); so such functions go back to their source and are compiled again
once the package loads. That's for their next call: a function that loads the package itself and then uses it runs
compiled to its end the first time. So such a function binds the package's variables with `dlet` (dynamic whatever
the compiler knew) and calls its functions, not its macros: the merge example's first run after a start failed with
"You have killed a vital Ediff buffer" (its `let` of Ediff's buffers bound locals). `tests/unit/test-merge.el` runs
the merge's functions compiled before Magit, Ediff and smerge load.

## Opening files faster

Opening a Markdown file went from ~1 s of pauses to ~0.35 s:

- **Tree-sitter grammar checks are remembered** (each one loaded the grammar's library again, ~10 ms on macOS with this
  many native-compiled libraries loaded; a Markdown file made ~9; `config/editor.el`). A grammar installed with
  `M-x treesit-install-language-grammar` (or by Doom) is picked up at once; one copied in by hand, after a restart.
- **Garbage collection while idle** waits for 32 MB instead of gcmh's 800 KB (`gcmh-low-cons-threshold`,
  `config/emacs.el`): the language server's replies and redraws after opening a file collected every few redraws,
  ~70 ms each.
- **Code lenses** go straight to the end of their line, without measuring the line on screen first, which highlighted
  the file around each lens: ~0.5 s when a Markdown file's lenses arrived (`config/lsp.el`, see
  [Code lenses](code.md#code-lenses)).
- **The sticky header** works out the line numbers' width itself instead of `header-line-indent-mode`, which laid the
  window out (highlighting it first) on every scroll and before every redraw (~100 ms more per Markdown file), and
  remembers the file's path in its project (finding the root took ~6% of the time spent scrolling;
  `config/sticky.el`).
- **The stripe** is drawn once when a file opens, at its final position (`config/stripe.el`).
- **good-scroll's timer** runs only while a scroll animates: always on, it made Emacs redraw ~50 times a second, which
  took time from everything else, opening files too (see [Keyboard scrolling](scrolling.md#keyboard-scrolling)).

And a file just opened shows first, plain, and gets its colours right after (~0.1 s to see it instead of ~0.4 s):
highlighting waits for its first display, like jit-lock's own deferral but only then, so scrolling never shows plain
text (`config/editor.el`).
