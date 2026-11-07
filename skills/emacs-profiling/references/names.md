# Special names

Names in the call trees that aren't functions of the code being profiled.

- `Automatic GC`: garbage collection; its samples have no caller. This config raises the GC thresholds with gcmh
  (`config/emacs.el`).
- `redisplay_internal (C function)`: redisplay. Under it: fontification (`jit-lock-function`, `font-lock-*`), the mode
  line (`doom-modeline`), `:eval` forms, window and redisplay hooks.
- `command-execute`, `call-interactively`: a command the user ran (a key press).
- `timer-event-handler`: a timer (idle timers too).
- `...` (top-down tree only): stacks deeper than 32 calls, whose start isn't known.
- `let`, `let*`, `if`, `progn`, `while`, `cond`, `save-excursion`...: special forms show up as calls only in
  interpreted code. This config's functions (`+my/...`) are byte-compiled once Emacs has been idle a moment
  (`config/compile.el`); a profile taken right after startup can catch them interpreted, slower than they really are.
- `#<lambda ...>`, `#<subr ...>`, closures: anonymous functions; their callers say whose they are.
- `profiler-start`, `profiler-stop`, `+my/profiling-...` at the start or end: the profiler itself; ignore them.
