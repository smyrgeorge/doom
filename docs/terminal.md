# Terminal

The config runs in a terminal too: `emacs -nw`, or `emacsclient -t`. `Cmd` keys (macOS) and most `Ctrl+Shift` keys
(Linux) don't reach Emacs there:

| GUI (macOS) | GUI (Linux) | Terminal |
|---|---|---|
| `Cmd+B` | `Ctrl+Shift+B` | `gd` / `gD` |
| `Cmd+[` / `Cmd+]` | `Alt+←` / `Alt+→` | `C-o` / `C-i` |
| `Cmd+Shift+F` | `Ctrl+Shift+F` | `SPC s p` |
| `M-[` / `M-]` | `Alt+[` / `Alt+]` | `[b` / `]b` |

The error stripe is a column of coloured cells, notices take the header line, and `SPC m p` falls back to
markdown-mode's preview. The terminal's background follows the theme while Emacs runs.

## 24-bit colour

An `emacsclient -t` frame of a server started elsewhere (e.g. the GUI app) has 256 colours. For 24-bit colour:

```sh
tic -x -o ~/.terminfo ~/.config/doom/cmd/xterm-24bit.terminfo   # once
TERM=xterm-24bit emacsclient -t
```
