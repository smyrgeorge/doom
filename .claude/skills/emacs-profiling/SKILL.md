---
name: emacs-profiling
description: How to read an Emacs profile recorded with this Doom config's profiler (SPC h T, `+my/profiling-toggle`), a folder holding summary.txt, cpu-calls.txt, cpu-callers.txt, mem-*.txt and *.profile under the Doom cache's profiles/ folder. Use when the user hands you such a folder or pastes "Emacs profile in …", or asks why their Emacs is slow.
---

# Reading an Emacs profile

## How it was recorded

The user pressed `SPC h T` (`+my/profiling-toggle`, in `~/.config/doom/config/profiling/session.el`; its settings are
in `config/profiling.el`), did what felt slow, and pressed it again. That runs Emacs's own profiler (`profiler.el`) in
`cpu+mem` mode:

- **CPU**: on a timer, while Emacs is using the CPU, the Lisp call stack is sampled. Only Emacs's own work counts:
  waiting for input, for a process (an LSP server, git) or for the network isn't sampled.
- **Memory**: the call stack is recorded as memory is allocated, weighted by bytes.
- Stacks keep up to 32 calls (Emacs keeps 16), so most reach the command or timer they started from.

The folder, named by the time it stopped: `~/.config/emacs/.local/cache/profiles/YYYY-MM-DD_HH-MM-SS/` (Doom's
`doom-cache-dir`, then `profiles/`). Every run makes a new folder; earlier ones stay, for comparing.

## The files, in the order to read them

| File | What |
|---|---|
| `summary.txt` | When and how long, garbage collections, then for CPU and memory: **Self** (top 30) and **Total** (top 30) |
| `cpu-callers.txt` | Bottom up: each function that was running, under it the calls that led to it |
| `cpu-calls.txt` | Top down: each call under the one that made it, from the command, timer or redisplay down |
| `mem-callers.txt`, `mem-calls.txt` | The same for memory (bytes allocated) |
| `cpu.profile`, `mem.profile` | Raw (a printed Lisp hash table). Don't read them; the user can open one in Emacs with `M-x profiler-find-profile` |

Each line is `COUNT SHARE NAME`, indented two spaces per call level, biggest first. Branches under 0.5% of the total are
left out (a `(N more, each under 0.5%)` line says how much, when it adds up). The trees can be long: read the top, or
grep a function's name and read around it.

## Reading the numbers

- CPU counts are **samples**, not milliseconds: compare shares (%). The summary's duration is wall time; few samples
  over a long run means Emacs was mostly idle or waiting, and the slowness is outside Emacs's Lisp (a process, I/O).
- **Self**: samples with the function itself running (where the time goes). **Total**: samples with the function
  anywhere on the stack (what it is responsible for). A function high in Total but low in Self delegates; look at what
  it calls.
- Memory counts are bytes allocated (sampled, so approximate). Allocation drives garbage collection: a big
  `Automatic GC` share in CPU plus many collections in the summary means find who allocates in `mem-*`.

## Special names

- `Automatic GC`: garbage collection; its samples have no caller. This config raises the GC thresholds with gcmh
  (`config/emacs.el`).
- `redisplay_internal (C function)`: redisplay. Under it: fontification (`jit-lock-function`, `font-lock-*`), the mode
  line (`doom-modeline`), `:eval` forms, window and redisplay hooks.
- `command-execute`, `call-interactively`: a command the user ran (a key press). `timer-event-handler`: a timer (idle
  timers too). `...` (top-down tree only): stacks deeper than 32 calls, whose start isn't known.
- `let`, `let*`, `if`, `progn`, `while`, `cond`, `save-excursion`...: special forms show up as calls only in
  interpreted code. This config's functions (`+my/...`) are byte-compiled once Emacs has been idle a moment
  (`config/compile.el`); a profile taken right after startup can catch them interpreted, slower than they really are.
- `#<lambda ...>`, `#<subr ...>`, closures: anonymous functions; their callers say whose they are.
- `profiler-start`, `profiler-stop`, `+my/profiling-...` at the start or end: the profiler itself; ignore.

## Finding the code

- `+my/...` and `+md-...` are this config's: `grep -rn "(defun +my/NAME" ~/.config/doom/config/`. A feature is
  `config/NAME.el` (its settings and keys) and `config/NAME/*.el` (its code).
- Doom: `~/.config/emacs/lisp/`, `~/.config/emacs/modules/`, `~/.config/emacs/sources/`.
- Packages: `~/.config/emacs/.local/straight/repos/PACKAGE/`.
- Emacs's own Lisp: `/Applications/Emacs.app/Contents/Resources/lisp/` (some files are `.el.gz`). Names ending in
  `(C function)` are in Emacs's C source.
- Or ask the running Emacs, read-only: `emacsclient --eval "(symbol-file 'FUNCTION 'defun)"`. Don't change its state
  without asking.

## Working through it

1. `summary.txt`: how long, how much GC; the top of Self (the hot functions) and of Total (which command, timer or
   redisplay the time went to).
2. `cpu-callers.txt`: grep the hot Self functions; follow the chains up to whoever is responsible.
3. `cpu-calls.txt`: check the path from the command or timer down.
4. Read the code. In this config, fix it there (settings in `config/NAME.el`, code in `config/NAME/`); for a package,
   prefer a setting or advice in the config to patching the package.
5. Measure: `tests/run.sh unit NAME` (see `docs/tests.md`), or `benchmark-run` in a throwaway `emacs --batch -Q`. Always
   pass `--init-directory=<a temp folder>`: a batch Emacs that creates `~/.emacs.d` makes the next Emacs start without
   Doom.
6. Ask the user to profile again (`SPC h T`, the same steps) and compare the new `summary.txt` with this one.

Tell the user the hot path in a few lines with its shares, the cause, and the fix.
