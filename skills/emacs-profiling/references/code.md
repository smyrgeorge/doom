# Finding the code

| Name | Where |
|---|---|
| `+my/...`, `+md-...` | This config: `grep -rn "(defun +my/NAME" ~/.config/doom/config/` |
| Doom's | `~/.config/emacs/lisp/`, `~/.config/emacs/modules/`, `~/.config/emacs/sources/` |
| A package's | `~/.config/emacs/.local/straight/repos/PACKAGE/` |
| Emacs's own Lisp | `/Applications/Emacs.app/Contents/Resources/lisp/` (some files are `.el.gz`) |
| `NAME (C function)` | Emacs's C source |

In this config, a feature is `config/NAME.el` (its settings and keys) and `config/NAME/*.el` (its code). The profiler
itself is `+my/profiling-toggle`, in `config/emacs/profiling/session.el`; its settings are in `config/emacs.el`.

Or ask the running Emacs, read-only: `emacsclient --eval "(symbol-file 'FUNCTION 'defun)"`. Don't change its state
without asking.
