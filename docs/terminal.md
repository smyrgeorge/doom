# Terminal

The config runs in a terminal too, with `emacs -nw` or `emacsclient -t`. `Cmd` keys (macOS) and most `Ctrl+Shift` keys
(Linux) don't reach Emacs there. Use these instead:

| GUI (macOS) | GUI (Linux) | Terminal |
|---|---|---|
| `Cmd+B` | `Ctrl+Shift+B` | `gd` / `gD` |
| `Cmd+[` / `Cmd+]` | `Alt+←` / `Alt+→` | `C-o` / `C-i` |
| `Cmd+Shift+F` | `Ctrl+Shift+F` | `SPC s p` |
| `M-[` / `M-]` | `Alt+[` / `Alt+]` | `[b` / `]b` |

## What differs

- The error stripe is a column of coloured cells.
- Notices take the header line.
- `SPC m p` falls back to markdown-mode's preview.
- The terminal's background follows the theme while Emacs runs. It goes back to its own while Emacs is suspended
  (`C-x C-z`) or gone.

## 24-bit colour

An `emacsclient -t` frame of a server started elsewhere, such as the GUI app, has 256 colours. For 24-bit colour:

```sh
tic -x -o ~/.terminfo ~/.config/doom/cmd/xterm-24bit.terminfo   # once
TERM=xterm-24bit emacsclient -t
```
