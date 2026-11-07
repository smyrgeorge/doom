---
name: emacs-profiling
description: >-
  Read an Emacs profile recorded with this Doom config's profiler (SPC h T, `+my/profiling-toggle`): a folder holding
  summary.txt, cpu-calls.txt, cpu-callers.txt, mem-*.txt and *.profile under the Doom cache's profiles/ folder. Use
  when the user hands you such a folder or pastes "Emacs profile in …", or asks why their Emacs is slow.
---

# Emacs profiling

The user pressed `SPC h T`, did what felt slow, and pressed it again. That ran Emacs's own profiler (`profiler.el`) in
`cpu+mem` mode and wrote what it recorded, as text, into a new folder named by the time it stopped:
`~/.config/emacs/.local/cache/profiles/YYYY-MM-DD_HH-MM-SS/`. Earlier folders stay, for comparing.

- **CPU**: on a timer, while Emacs is using the CPU, the Lisp call stack is sampled. Only Emacs's own work counts:
  waiting for input, for a process (an LSP server, git) or for the network isn't sampled.
- **Memory**: the call stack is recorded as memory is allocated, weighted by bytes.
- Stacks keep up to 32 calls (Emacs keeps 16), so most reach the command or timer they started from.

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

## Reference

Read these only when the task needs them:

- [references/names.md](references/names.md): names in the trees that aren't the code's own functions: garbage
  collection, redisplay, commands and timers, special forms, anonymous functions, the profiler itself.
- [references/code.md](references/code.md): where the code behind a name is: this config, Doom, packages, Emacs.
