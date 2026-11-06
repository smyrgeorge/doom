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
  Cmd+[ / Cmd+], `SPC s p` for Cmd+Shift+F. `C-i` jumps forward only in terminals with the kitty keyboard protocol
  (kitty, WezTerm, foot); elsewhere it's Tab.
- `M-[` / `M-]` (previous / next buffer) are GUI only: in a terminal they start escape sequences (mouse, focus, OSC),
  so binding them flipped buffers. Use `[b` / `]b`.
- Tabs show no icons and no bar on the current tab (its colour marks it). Icons in the mode line and notices need a
  Nerd Font in the terminal (see [Installation](../README.md#installation)).
- `SPC m p` (Markdown) shows markdown-mode's `eww` preview, which updates on save.
- No Emacs server in `emacs -nw` (Doom starts it only in GUI sessions), so Claude can't reach the editor with
  `emacsclient`: use `emacs --daemon` and `emacsclient -t`, or `M-x server-start`.
- Colours: `emacs -nw` has 24-bit colour where the terminal says so (`COLORTERM=truecolor`, as iTerm2 does), so the
  theme looks as in the GUI. An `emacsclient -t` frame of a server started elsewhere (the GUI app) gets 256 unless
  its `TERM` has them: `TERM=xterm-24bit emacsclient -t`, with `cmd/xterm-24bit.terminfo` compiled into
  `~/.terminfo` (see [Shell commands](cmd.md); `cmd/diff.sh` does this itself).

## Terminal background

In terminal Emacs, the strip below the echo area is painted with the theme background (`OSC 11`). The terminal gets
its own background back on exit, or when an `emacsclient -t` frame closes (the terminal's last one: another frame
there still shows the theme). That includes `cmd/diff.sh`, in both its kinds: a new Emacs, or a frame of the running
one.

- **The color given back:** before the first paint, Emacs asks the terminal for its background (`OSC 11 ?`, answered
  in order, so before the paint), and sets exactly that color back with `OSC 11`. Only a terminal that doesn't answer
  gets the generic reset (`OSC 111`), which iTerm2 ignores: the theme's color used to stay there.
- **When it paints:** only once the terminal is set up, since the query needs `term/xterm.el`. `emacs -nw` loads Doom's
  theme before that, and `tty-setup-hook` paints it then.
- **Closing a server's frame:** the restore runs first in `delete-frame-functions`. The server's own handler closes the
  client's terminal, and nothing sent after it arrives.

A terminal tab still showing the theme's color from before this fix reports that color as its own. Open a new tab
once.

## No menu bar in the terminal

MacOS GUI frames keep theirs (it lives in the system's menu bar); terminal frames
don't get a "File Edit Options ..." row.

## Hover help stays in the echo area

Hover help (e.g. a warning's message when hovering its text) shows in the echo area, never in a tooltip, as Doom has
it. Doom also turned on `tty-tip-mode` (tips in a small child frame) when a terminal frame opened; that mode is
global, so after an `emacsclient -t` GUI frames drew their tips at the frame's top-left corner. Not anymore
(`config/terminal.el`).
