# The editor

## Error stripe

`config/stripe.el` draws a one-column strip at the right edge of every file window that maps the whole file onto the
window height, like the marks on IntelliJ's scrollbar:

- errors (red) and warnings (yellow) from flycheck / the language server;
- git changes (diff-hl), in the gutter's colors: red deleted, orange changed, green added;
- where several overlap, the most important wins: error > warning > deleted > changed > added > info;
- a light band marks the part of the file on screen, like a scrollbar thumb.

It's on in code, text and config files, and in files with very long lines (`so-long-mode`). The strip is at the very
edge, the fringe (e.g. the arrows of lines cut off at the window edge) between it and the text: Doom's vc-gutter puts
fringes outside the margins for the git gutter's sake, which with no left margin only matters on the right.
File windows also get a character's width of space more on each side of the text (`+my/stripe-padding`: columns per
side, `nil` for none; GUI only): their fringes are 16 px instead of 8, with the git gutter, flycheck's marks and the
arrows in the middle (flycheck keeps its small markers there; in fringes that wide it would switch to big 16 px ones).

In the GUI the strip is drawn to the pixel: each screen row shows its slice of the strip as a small image in the right
margin. Rows are measured (an emoji, or a glyph rising above the font like indent-bars' `│` on the top row, makes a
row taller), and smooth scrolling, which moves the rows by part of a line, shifts the slices back by as much, so the
marks stay still while the text glides. Wrapped lines (Markdown, `visual-line-mode`) get a slice on each of their
rows; a continuation row's slice hangs on its last character (the space it wraps at, or the newline). Laying out
the row before, Emacs looks ahead into the next row's first word, and draws a margin string it meets there on that
row too: hung at a row's start, slices showed on the wrong row (gaps) or on two rows (an extra mark). In a terminal
each row is a coloured cell.

Every window scrolls past the end of its buffer only a bit (see [Smooth
scrolling](scrolling.md#scrolling-past-the-end)): at most a quarter of it (`+my/stripe-overscroll`: a fraction, a number
of rows, `0` for none, `t` for no limit). The strip maps the file plus that space onto the whole window height, like
IntelliJ's scrollbar, so it never shrinks: marks stay put as the end comes into view, and the band reaches the bottom
when the window can't scroll further. Margins need text to hang on, so below the last line the strip is drawn on one
extra row after the end of the buffer, which also repeats the empty-line `~` and takes the place of the empty,
unnumbered line after the final newline: as in Vim, the `~` start right after the last line. The cursor stays off that
line in normal state (`j` on the last line stays put, `G` goes to the last line), and a click below the text puts it on
the last line at the clicked column; insert state can go there, to add at the end. In a terminal the strip covers only
the rows with text. Files shorter than the window get one line height per line.

Click the strip to jump to that part of the file: the line lands in the middle of the window, and `C-o` (`Cmd+[`)
jumps back; the mouse wheel scrolls as usual. Info-level hints are left out: add `info` to
`+my/stripe-diagnostic-levels` (default `'(error warning)`) to show them, below every other mark. Marks are at least
4 px tall (`+my/stripe-mark-height`). `M-x +my/stripe-mode` turns the strip off in a buffer (margin and fringes back to
normal), `M-x +my/stripe-global-mode` everywhere.

## Notices

`config/banner.el` shows notices at the top of a window, under the tabs, like IntelliJ's editor notifications: a row
each, with an icon and colour for its type (info blue, warning yellow, error red), the message, actions to click, and
`✕` to close it. They stay put while scrolling, and the header line (the path, or the sticky scopes) stays under them.
In narrow windows the message is cut short with `…` so the actions and `✕` still fit. A header line is one row of
text, so it grows a row per notice (an invisible tall image) and a small borderless child frame lays the notices over
those rows; each window showing the buffer gets its own. In a terminal the header line shows the first notice instead
(and how many more).

Notices so far: (info) Markdown files offer the live preview (see [Markdown](markdown.md#live-markdown-preview)),
until it opens; (warning) files with very long lines shown plain and unwrapped. **Wrap lines** wraps them (the notice
stays, without that action); **Open normally** goes back to the file's own mode, and the notice goes. Both can make
scrolling slow again (see [Very long lines](scrolling.md#very-long-lines)). A buffer's notices go when its major mode
changes.

From code: `(+my/banner-show ID TEXT :type 'warning :actions '(("Label" . function)))` (`:type` defaults to `info`; the
actions run in the window and buffer the notice is about). Showing an ID again replaces that notice in place;
`(+my/banner-close ID)` closes one, `M-x +my/banner-close` the first. Each type's icon and colour: `+my/banner-types` (a
codicon name and a theme colour, which also tints the row).

## Sticky header

The header line of code windows shows the classes/functions the top visible line is inside, once
their first lines have scrolled out of view, like IntelliJ's sticky lines (e.g. `class Api { › fun call(x: Int) {`);
otherwise the file's path in its project, dimmed (`~/…` outside a project). The header row is always there, so the
code doesn't shift as it changes. Nested scopes via tree-sitter (Kotlin, Python, Rust, ...), the enclosing defun
elsewhere. In Markdown (`markdown-ts-mode`) the headings: `# Guide › ## Setup › ### Install`. Only where scopes can be
told: files whose mode has no notion of them (HTML in `web-mode`, files with very long lines in `so-long-mode`) get no
header row. It lines up with the code, past the fringe and the line numbers.

For a tree-sitter mode that doesn't declare its classes/functions, add `(LANGUAGE . NODE-TYPE-REGEXP)` to
`+my/sticky-defun-types` (Kotlin's and Markdown's are there). `+my/sticky-separator` is the ` › ` between scopes.
`M-x +my/sticky-header-mode` turns it off (or on) in a buffer.

## Tabs per window

**Tabs per window**, like IntelliJ's split editors (Emacs's tab line instead of Doom's centaur-tabs, whose tab groups
were per project and shared by every window): each window's tabs are the buffers shown in it, in the order they first
were. A split starts with one tab, the buffer it shows. Files, Claude sessions, dired and magit keep tabs; other buffers
only while shown; popups, the dashboard and side panels have no tab line. Closing a tab (its ✕, a middle click, `Cmd+W`)
takes it off that window, which goes back to the tab it showed before; closing its last tab closes the window (the
frame's only one, beside the sidebar, shows Doom's dashboard instead). A file is closed too once no window has it as a
tab any more (asking first if it has unsaved changes); a Claude session only leaves the tab line. `SPC b k` still kills
the buffer, in every window.

Right-clicking a tab opens its menu: **Close**, **Close other tabs**, and, as in IntelliJ, **Split Vertically** (a new
pane on the right) and **Split Horizontally** (a new pane below). The new pane has only that tab and takes focus; the
tab stays in its own pane too.

`gt` / `gT`: next / previous tab, wrapping around. Doom used them for workspaces: those are `]w` / `[w` or
`SPC TAB ]` / `SPC TAB [`. `Cmd+1`..`Cmd+8` show the pane's tabs 1-8, `Cmd+9` its last, as in browsers (Doom's
workspaces 1-9 are on `M-1`..`M-9` and `SPC TAB 1`..`9`; in a pane without tabs, e.g. the sidebar, `Cmd+N` still
switches workspaces). Tabs show the file's icon, a bar on the current one (`+my/tabs-bar-width`, 2 px; the tab row
is `+my/tabs-height`, 22 px, tall; icon and bar in the GUI only), `•` when unsaved, and same-named files get the
shortest distinguishing path as their label (`crate-a/src/lib.rs` vs `crate-b/src/lib.rs`) instead of `lib.rs<2>`,
since workspaces disable uniquify.

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

## Case style

`SPC c ~` cycles the word at point through snake_case, UPPER_CASE, PascalCase, camelCase and kebab-case
(`string-inflection`).

## Font and theme

JetBrains Mono 13 (`doom-font` in `config.el`; `scripts/tools.sh` installs it) with ligatures (Doom's `ligatures`
module); the `doom-one` theme; absolute line numbers. The frame opens maximized.

## PDFs in WebKit

PDFs open inside the file's tab as a web page in WebKit, like the [Markdown preview](markdown.md#live-markdown-preview),
drawn by [PDF.js](https://mozilla.github.io/pdf.js/) (Mozilla's PDF renderer, Firefox's): pages sharp at any zoom,
smooth trackpad scrolling, text selectable with the mouse (`config/pdf-xwidget.el`, the page's script
`config/pdf-xwidget.js`). Emacs drives the page with JavaScript, so the keys are Evil's:

| Key | Action |
|---|---|
| `j` / `k`, `h` / `l` | Scroll (`+my/pdf-xwidget-scroll-step`, 60 px) |
| `C-d` / `C-u`, `C-f` / `C-b` | Half a screen / a screen |
| `gg` / `G` | Top / bottom; with a count, that page (`5G`) |
| `J` / `K` | Next / previous page |
| `/` / `?` | Search forward / backward (case-sensitive with a capital); `n` / `N` next / previous match; `Esc` ends it |
| `y` or `Cmd+C` | Copy the selected text (kill ring and clipboard) |
| `Cmd+=` / `Cmd+-` (or `+` / `-`) | Zoom in / out (`+my/pdf-xwidget-zoom-step`, ×1.25); also `Cmd+scroll` |
| `Cmd+0` / `W` / `P` | 100% / fit the width (as it opens) / fit the page |
| `q` | Close the PDF |

The page shows the page number while it changes, and the search's matches. Links out of the PDF open in the browser.
A PDF changed on disk (e.g. rebuilt by LaTeX) is shown anew, where it was. It opens without a white flash: covered in
the theme's background colour until WebKit has loaded it (2 s at most), the space around the pages in that colour too.

PDF.js (`pdfjs-dist` 3.11.174: newer versions only ship ES modules, which a `file://` page may not load) is downloaded
once, from jsdelivr, into Doom's `.local/etc/`, each file checked against its SHA-256 in `+my/pdf-js-files`;
`M-x +my/pdf-js-install` downloads it again. Without it (e.g. offline the first time), PDFs show in WebKit's own
viewer, trackpad only. Not that viewer by default: on macOS Emacs takes every key, so none reached it, and its buttons
and text selection didn't work inside Emacs. In a terminal, or an Emacs without xwidgets, PDFs open in doc-view,
Emacs's own viewer.

Doom's pdf module (pdf-tools) is off in `init.el`. Its setup is kept in `config/pdf.el`, not loaded: `Cmd+=` / `Cmd+-`
/ `Cmd+0` zoom as in Preview, and `Cmd+scroll` a step (×1.1) per wheel notch. To go back to it, turn `pdf` on in
`init.el`, load `config/pdf.el` instead of `config/pdf-xwidget.el` in `config.el`, and run `doom sync`.

## Mode line

A space after its last item on the right (e.g. flycheck's checkmark), which touched the window's
edge; in every doom-modeline layout (`config/modeline.el`).

## New windows get focus

Splits (`SPC w s` / `SPC w v`) and any new window a command opens (diff pane, other-window
commands...) move the cursor there; `SPC w S` / `SPC w V` split and leave it where it was. Side windows (Doom popups,
treemacs, which-key, transient menus) keep their own behaviour, as do windows opened in the background. Set
`+my/focus-new-windows` to `nil` to stop selecting the windows commands open (the live Markdown preview does, for its
own).

## Evil

Saving a buffer returns to normal state.

## `q` closes transient menus

**`q` closes transient menus** (agent-shell's help and drawing menus, magit's...), as Esc (Doom) and `C-g` do: it
only said "Unbound suffix: q". A menu that uses `q` for something of its own keeps it (magit's dispatch: bury the
buffer; blame, git-timemachine: quit them); `transient-bind-q-to-quit` would move such keys to `Q`, not done.
