# Terminal usage

The same install runs in a terminal:

```sh
emacs -nw
```

`(tty +osc)` gives clipboard integration over OSC 52. Faster startup: run `emacs --daemon` once, then `emacsclient -t`
(terminal) or `emacsclient -c` (GUI window).

What changes in a terminal:

- The error stripe is a column of coloured cells (one per row); a click jumps there.
- Notices take the header line (the first one, with how many more), the message cut short so the actions and `✕` fit.
- Mouse-wheel scrolling moves by lines (no glide); the end-of-file scroll limit still applies.
- The mouse (wheel, clicks on tabs, the stripe, notices) needs `xterm-mouse-mode`. Emacs 31 turns it on by itself
  in iTerm2, kitty, WezTerm, Konsole, VTE, foot and Alacritty; elsewhere (e.g. inside tmux) `M-x xterm-mouse-mode`.
- Cmd shortcuts don't reach terminal Emacs: use Doom's keys instead, e.g. `gd` / `gD` for Cmd+B, `C-o` / `C-i` for
  Cmd+[ / Cmd+], `SPC s p` for Cmd+Shift+F.
- Icons (tabs, mode line, notices) need a Nerd Font in the terminal (see [Installation](../README.md#installation)).

## Terminal background

In terminal Emacs, the strip below the echo area is painted with the theme background
(OSC 11) and restored on exit (OSC 111).

## No menu bar in the terminal

MacOS GUI frames keep theirs (it lives in the system's menu bar); terminal frames
don't get a "File Edit Options ..." row.
