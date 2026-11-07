# Terminal

The config runs in a terminal too (`emacs -nw`, or `emacsclient -t` with a server). What's different:

- The error stripe is a column of coloured cells; notices take the header line.
- The wheel scrolls by lines. The mouse works where Emacs turns it on (iTerm2, kitty, WezTerm...; elsewhere
  `M-x xterm-mouse-mode`).
- `Cmd` keys don't reach Emacs: use `gd` / `gD`, `C-o` / `C-i` and `SPC s p`. `M-[` / `M-]` don't switch buffers; `[b` /
  `]b` do.
- `SPC m p` uses markdown-mode's preview.
- The terminal's background takes the theme's colour, and gets its own back when Emacs or the frame closes.
- An `emacsclient -t` frame of a server started elsewhere (the GUI app) has 256 colours. For 24-bit colour, install the
  terminfo entry once (`tic -x -o ~/.terminfo ~/.config/doom/cmd/xterm-24bit.terminfo`) and run
  `TERM=xterm-24bit emacsclient -t`; `cmd/diff.sh` does both itself.
- Terminal frames have no menu bar row, and hover help stays in the echo area.
