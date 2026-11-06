# The editor

## Error stripe

`config/stripe.el` draws a one-column strip at the right edge of every file window that maps the whole file onto the
window height, like the marks on IntelliJ's scrollbar:

- errors (red) and warnings (yellow) from flycheck / the language server;
- git changes (diff-hl), in the gutter's colors: red deleted, orange changed, green added;
- where several overlap, the most important wins: error > warning > deleted > changed > added;
- a light band marks the part of the file on screen, like a scrollbar thumb.

It's on in code, text and config files, and in files with very long lines (`so-long-mode`). The strip is at the very
edge, the fringe (e.g. the arrows of lines cut off at the window edge) between it and the text: Doom's vc-gutter puts
fringes outside the margins for the git gutter's sake, which with no left margin only matters on the right.
File windows also get a character's width of space more on each side of the text (`+my/stripe-padding`): their
fringes are 16 px instead of 8, with the git gutter, flycheck's marks and the arrows in the middle (flycheck keeps
its small markers there; in fringes that wide it would switch to big 16 px ones). The sticky header
lines up with the text past the fringe.

In the GUI the strip is drawn to the pixel: each screen row shows its slice of the strip as a small image in the right
margin. Rows are measured (an emoji, or a glyph rising above the font like indent-bars' `│` on the top row, makes a
row taller), and smooth scrolling, which moves the rows by part of a line, shifts the slices back by as much, so the
marks stay still while the text glides. Wrapped lines (Markdown, `visual-line-mode`) get a slice on each of their
rows; a continuation row's slice hangs on its last character (the space it wraps at, or the newline). Laying out
the row before, Emacs looks ahead into the next row's first word, and draws a margin string it meets there on that
row too: hung at a row's start, slices showed on the wrong row (gaps) or on two rows (an extra mark). In a terminal
each row is a coloured cell.

Windows with the strip scroll past the end of the file only a bit: at most a quarter of the window
(`+my/stripe-overscroll`: a fraction, a number of rows, `0` for none, `t` for no limit). The strip maps the file plus
that space onto the whole window height, like IntelliJ's scrollbar, so it never shrinks: marks stay put as the end comes
into view, and the band reaches the bottom when the window can't scroll further. Margins need text to hang on, so below
the last line the strip is drawn on one extra row after the end of the buffer, which also repeats the empty-line `~` and
takes the place of the empty, unnumbered line after the final newline: as in Vim, the `~` start right after the last
line. The cursor stays off that line in normal state (`j` on the last line stays put, `G` goes to the last line), and a
click below the text puts it on the last line at the clicked column; insert state can go there, to add at the end.
In a terminal the strip covers only the rows with text. Files shorter than the window get one line height per line.

Click the strip to jump to that part of the file; the mouse wheel scrolls as usual. Info-level hints are left out
(`+my/stripe-diagnostic-levels`); marks are at least `+my/stripe-mark-height` pixels tall.

## Notices

`config/banner.el` shows notices at the top of a window, under the tabs, like IntelliJ's editor notifications: a row
each, with an icon and colour for its type (info blue, warning yellow, error red), the message, actions to click, and
`✕` to close it. They stay put while scrolling, and the header line (the path, or the sticky scopes) stays under them.
A header line is one row of text, so it grows a row per notice (an invisible tall image) and a small borderless child
frame lays the notices over those rows; each window showing the buffer gets its own. In a terminal the header line
shows the first notice instead (and how many more). Code adds one with
`(+my/banner-show ID TEXT :type 'warning :actions '(("Label" . function)))`; `M-x +my/banner-close` closes the first.
Notices so far: (warning) files with very long lines shown plain and unwrapped (**Wrap lines**, **Open normally**).

## Sticky header

The header line of code windows shows the classes/functions the top visible line is inside, once
their first lines have scrolled out of view, like IntelliJ's sticky lines (e.g. `class Api { › fun call(x: Int) {`);
otherwise the file's path. Nested scopes via tree-sitter (Kotlin, Python, Rust, ...), the enclosing defun elsewhere.
In Markdown (`markdown-ts-mode`) the headings: `# Guide › ## Setup › ### Install`. Only where scopes can be told:
files whose mode has no notion of them (HTML in `web-mode`, files with very long lines in `so-long-mode`) get no
header row. It lines up with the code past the line numbers by working out their width the way Emacs does, not with
`header-line-indent-mode`, which laid the window out (highlighting it first) on every scroll and before every redraw.

## Tabs per window

**Tabs per window**, like IntelliJ's split editors (Emacs's tab line instead of Doom's centaur-tabs, whose tab
groups were per project and shared by every window): each window's tabs are the buffers shown in it, in the order
they first were. A split starts with one tab, the buffer it shows. Files, Claude sessions, dired and magit keep tabs;
other buffers only while shown; popups, the dashboard and side panels have no tab line. Closing a tab (its ✕, a
middle click) takes it off that window, which goes back to the tab it showed before; a file is closed too once no
window has it as a tab any more (asking first if it has unsaved changes), a Claude session only leaves the tab line.
`gt` / `gT`: next / previous tab. Tabs show the file's icon, a bar on the current one (`+my/tabs-height`), `•` when
unsaved, and same-named files get the shortest distinguishing path as their label (`crate-a/src/lib.rs` vs
`crate-b/src/lib.rs`) instead of `lib.rs<2>`, since workspaces disable uniquify.

## Current line and selection across wrapped rows

A long line wraps onto rows indented like it (Doom's word wrap,
e.g. two spaces in a Markdown table), and the current line's highlight, and the selection's, left that indentation
out: Emacs draws a line's wrap prefix without the faces of the overlays on it. hl-line's overlay now carries a copy of
the prefix in its face; a selection gets one per line on screen, over its part of the selection. Only where the
highlight is the whole line: Doom's dashboard highlights just the menu item, its line centred by a prefix.

## Right margin

A thin vertical line at the maximum line length, like IntelliJ's, in files of code, text and
configuration: at `fill-column`, set in `config.el` (120; also where `gq` / `M-q` wrap text; commit messages 72). A
project's `.editorconfig` moves it with `max_line_length` (e.g. `100` for Kotlin with ktfmt) or removes it with
`max_line_length = off` (e.g. for `*.md`). As faint as the line numbers; a line that runs past it covers it.

## Right fringe

A character wider in every window (16 px instead of Doom's 8), so the arrows of lines cut off at
the window's edge (e.g. long names in treemacs) don't touch the text (`+my/right-fringe-padding`,
`config/window.el`). File windows get the same on the left too (see [Error stripe](#error-stripe)).

## Rainbow brackets

`()`, `[]` and `{}` colored by nesting depth in code (`rainbow-delimiters`).

## Font

JetBrains Mono with ligatures.

## Mode line

A space after its last item on the right (e.g. flycheck's checkmark), which touched the window's
edge; in every doom-modeline layout (`config/modeline.el`).

## New windows get focus

Splits (`SPC w s` / `SPC w v`) and any new window a command opens (diff pane, other-window
commands...) move the cursor there. Side windows (Doom popups, treemacs, which-key, transient menus) keep their own
behaviour, as do windows opened in the background; the live Markdown preview opts out with `+my/focus-new-windows`.

## Evil

Saving a buffer returns to normal state.

## `q` closes transient menus

**`q` closes transient menus** (agent-shell's help and drawing menus, magit's...), as Esc (Doom) and `C-g` do: it
only said "Unbound suffix: q". A menu that uses `q` for something of its own keeps it (magit's dispatch: bury the
buffer; blame, git-timemachine: quit them); `transient-bind-q-to-quit` would move such keys to `Q`, not done.

## `M-[` / `M-]`

**`M-[` / `M-]`** switch buffers in the GUI only; in a terminal they would swallow mouse/focus escape sequences.

## Hover help in the echo area, never in a tooltip

E.g. a warning's message when hovering its text, as Doom has
it. Doom also turned on `tty-tip-mode` (tips in a small child frame) when a terminal frame opened; that mode is
global, so after an `emacsclient -t` GUI frames drew their tips at the frame's top-left corner. Not anymore.
