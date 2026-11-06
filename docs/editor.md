# The editor

## Error stripe

`config/stripe.el` draws a strip at the right edge of every file window that maps the whole file onto the window
height, like the marks on IntelliJ's scrollbar:

- errors (red) and warnings (yellow) from flycheck / the language server;
- git changes (diff-hl), in the gutter's colors: red deleted, orange changed, green added;
- where several overlap, the most important wins: error > warning > deleted > changed > added > info;
- a light band marks the part of the file on screen: the scrollbar's thumb.

It's on in code, text and config files, and in files with very long lines (`so-long-mode`). The strip is at the very
edge, the fringe (e.g. the arrows of lines cut off at the window edge) between it and the text: Doom's vc-gutter puts
fringes outside the margins for the git gutter's sake, which with no left margin only matters on the right.
File windows also get a character's width of space more on each side of the text (`+my/stripe-padding`: columns per
side, `nil` for none; GUI only): their fringes are 16 px instead of 8, with the git gutter, flycheck's marks and the
arrows in the middle (flycheck keeps its small markers there; in fringes that wide it would switch to big 16 px ones).

In the GUI the strip is one image, drawn to the pixel, in a small frame of its own (a child frame, like the notices')
laid over the window's right margin. It follows the window: splits, resizes, a notice above the text; it's hidden
while the window shows a buffer without a strip, and goes with the window. It used to be a column of images in the
margin, a slice per screen row: every scroll changed every row's slice, so Emacs redrew every row instead of moving
the text (5.8 ms a scroll step instead of 3.3), and rows had to be measured (emoji, wrapped lines, smooth scrolling's
part rows, the space below the last line). Now the window's rows are left alone, and a new image is made only when
the strip changes: most scroll steps move the band by less than a pixel (a 3,000-line file: about one step in five
redraws it, 0.2 ms; the old images are flushed from Emacs's image cache). The band covers the lines on screen: counted
when lines are cut off at the edge (Doom's default, a line a row), laid out when they wrap (Markdown). In a terminal
each row is a coloured cell in the margin.

Every window scrolls past the end of its buffer only a bit (see [Smooth
scrolling](scrolling.md#scrolling-past-the-end)): at most a quarter of it (`+my/stripe-overscroll`: a fraction, a number
of rows, `0` for none, `t` for no limit). The strip maps the file plus that space onto the whole window height, like
IntelliJ's scrollbar, so it never shrinks: marks stay put as the end comes into view, and the band reaches the bottom
when the window can't scroll further. In a terminal the strip covers only the rows with text. Files shorter than the
window get one line height per line.

Click the strip to jump to that part of the file: the line lands in the middle of the window, and `C-o` (`Cmd+[`)
jumps back. Drag the band to scroll, as a scrollbar's thumb. The mouse wheel over the strip scrolls the file. Info-level
hints are left out: add `info` to `+my/stripe-diagnostic-levels` (default `'(error warning)`) to show them, below every
other mark. Marks are at least 4 px tall (`+my/stripe-mark-height`), the band 12 px (`+my/stripe-thumb-min-height`, to
grab it). `M-x +my/stripe-mode` turns the strip off in a buffer (margin and fringes back to normal),
`M-x +my/stripe-global-mode` everywhere.

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
smooth trackpad scrolling, text selectable with the mouse (`config/pdf.el`, the page's script
`config/pdf.js`). Emacs drives the page with JavaScript, so the keys are Evil's:

| Key | Action |
|---|---|
| `j` / `k`, `h` / `l` | Scroll (`+my/pdf-scroll-step`, 60 px) |
| `C-d` / `C-u`, `C-f` / `C-b` | Half a screen / a screen |
| `gg` / `G` | Top / bottom; with a count, that page (`5G`) |
| `J` / `K` | Next / previous page |
| `/` / `?` | Search forward / backward (case-sensitive with a capital); `n` / `N` next / previous match; `Esc` ends it |
| `y` or `Cmd+C` | Copy the selected text (kill ring and clipboard) |
| `Cmd+=` / `Cmd+-` (or `+` / `-`) | Zoom in / out (`+my/pdf-zoom-step`, ×1.25); also `Cmd+scroll` |
| `Cmd+0` / `W` / `P` | 100% / fit the width (as it opens) / fit the page |
| `C-o` / `C-i` (or `Cmd+[` / `Cmd+]`) | Back / forward: where jumps (links, the outline, thumbnails, `gg` / `G`, a new search) left from |
| `o` (`SPC m o`) | Go to a heading of the outline, picked in the minibuffer (`Chapter 1 › Section 1.1`, with its page) |
| `O` (`SPC m O`) | The sidebar: outline or pages |
| `Option+Enter` | The actions menu: for the selected text, copy, search the PDF or the web, explain it with Claude or add it to Claude's prompt (quoted, with the file and page); Open in Preview, Print |
| `SPC m p` | Open it in macOS's Preview (to sign, annotate...) |
| `Cmd+P` (`SPC m P`) | Print it, in Preview's print dialog (macOS asks once to let Emacs control Preview) |
| `SPC m d` | Dark pages |
| `SPC m t` | The toolbar |
| `q` | Close the PDF |

**Toolbar** (at the top, in the theme's colours): the sidebar, back / forward, previous / next page with `3 / 12`, zoom
out / in with its percentage, fit the width, fit the page, dark pages, Open in Preview, Print. **Sidebar** (left), two
tabs: **Outline**, the PDF's headings with their pages (click one to go there, `▸` / `▾` to open / close its
sub-headings; an outline of over 100 headings opens with its first level only), the current one, the last before the
page shown, marked; **Pages**, the pages' thumbnails, drawn as they scroll into view, the current one marked. **Dark
pages**: the pages (and thumbnails) inverted to dark greys with their hues kept, like pdf-tools' midnight mode.

A PDF opens where it was when last closed (page, place on it, zoom), even after Emacs restarted: kept in
`+my/pdf-places-file` (Doom's `.local/state/pdf-places`) for the last 300 closed. It opens with the toolbar,
sidebar and dark pages as the last one you looked at; `+my/pdf-toolbar` (on), `+my/pdf-outline-sidebar`
and `+my/pdf-dark-pages` (off) are for the first one. The mode line shows the page (`P3/12`, doom-modeline's
PDF line).

Split (`SPC w v`, `SPC w SPC`, the tab's right-click menu...), each pane shows the PDF on its own: scrolled, zoomed and
searched apart, each mode line with its pane's page. A WebKit view is drawn in one window only (Emacs on macOS said
"You can't share an xwidget (webkit2) among windows" and left the new pane empty), so each window gets a view of its
own, starting where the PDF shows in the pane you came from. `SPC m d` / `SPC m t` / `O`, `Esc` and a reload from disk
apply to all of the PDF's panes; the other keys to the selected one. A pane that shows another tab keeps its view
for when it comes back (unless another pane needs one first); a closed pane's view goes a second later, but for the
PDF's last one. What a web page inside Emacs needs (a view per window, no white flash, links out, the title read every
0.1 s, the mouse pointer, clicks) is in `config/webkit.el`, shared with the
[Markdown preview](markdown.md#live-markdown-preview) and [drawings](#drawings-excalidraw).

The page can't call Emacs: it says its settings, page and place, the mouse pointer it wants, and the toolbar's requests
(Preview, Print) in its title, which Emacs reads every 0.1 s, without JavaScript, while a PDF is on screen. The mouse
pointer is the hand over the buttons, headings, thumbnails and links, the I-beam over the PDF's text, the arrow
elsewhere: Emacs draws its own pointer over the page (the I-beam everywhere), so a page's CSS cursor never shows.

The page shows the search's matches, and, without the toolbar, the page number while it changes. Links out of the PDF
open in the browser.
A PDF changed on disk (e.g. rebuilt by LaTeX) is shown anew, where it was. It opens without a white flash: covered in
the theme's background colour until WebKit has loaded it (2 s at most), the space around the pages in that colour too.

PDF.js (`pdfjs-dist` 3.11.174: newer versions only ship ES modules, which a `file://` page may not load) is downloaded
once, from jsdelivr, into Doom's `.local/etc/`, each file checked against its SHA-256 in `+my/pdf-js-files`;
`M-x +my/pdf-js-install` downloads it again. Without it (e.g. offline the first time), PDFs show in WebKit's own
viewer, trackpad only. Not that viewer by default: on macOS Emacs takes every key, so none reached it, and its buttons
and text selection didn't work inside Emacs. In a terminal, or an Emacs without xwidgets, PDFs open in doc-view,
Emacs's own viewer.

Doom's pdf module (pdf-tools) is off in `init.el`: PDFs are this config's own viewer (`config/pdf.el`, its page
`config/pdf.js`).

## Drawings (Excalidraw)

Files named `*.excalidraw.svg` or `*.excalidraw` open in the file's tab as a drawing in
[Excalidraw](https://excalidraw.com) (excalidraw.com's editor: shapes, arrows, lines, text, freehand, images), a web
page in WebKit like [PDFs](#pdfs-in-webkit) (`config/excalidraw.el`, the page's script `config/excalidraw.js`):

- **`*.excalidraw.svg`**: an SVG image with the drawing in it. Markdown and Org show it as any image (the
  [preview](markdown.md#live-markdown-preview), GitHub...), and it opens here again to edit, as at excalidraw.com. Its
  fonts are named at the CDN (jsdelivr), so it looks the same elsewhere; it's always saved light.
- **`*.excalidraw`**: Excalidraw's own JSON (what excalidraw.com saves).

A new file is a blank drawing. Draw with the mouse or the trackpad (two fingers pan, pinching zooms). Emacs takes the
keys and gives them to the page, so Excalidraw's work as at excalidraw.com (its `?` lists them): the tools (`v` `r`
`d` `o` `a` `l` `p` `t` `e` `h` `k`, `1`-`0`), `Delete`, `Esc`, `Enter`, the arrows (`Shift`: further), `Shift+1`
(fit), `Cmd+Z` / `Cmd+Shift+Z` (undo / redo), `Cmd+A`, `Cmd+D`, `Cmd+G` / `Cmd+Shift+G`, `Cmd+=` / `Cmd+-` / `Cmd+0`
(zoom), `Cmd+'` (grid), `Cmd+Option+[` / `]` (backward / forward)... They come before Evil's (and evil-snipe's `f`,
`t`, `s`). Text is typed straight into the page: double-click, or `t` then click. Emacs keeps `SPC` (the leader),
`:` (Evil's command line) and its keys that Excalidraw has none for (`Cmd+S`, `Cmd+W`, `Cmd+1`..`9`, `M-x`, `C-x`,
`C-g`, `Option+Enter`...). Also:

| Key | Action |
|---|---|
| `Cmd+C` / `Cmd+X` | Copy / cut the selection: Emacs's kill ring and the clipboard, in Excalidraw's format (it pastes back here or at excalidraw.com) |
| `Cmd+V` | Paste: shapes copied so, or text (a text element) |
| `SPC m d` | Dark canvas, for all drawings (`+my/excalidraw-theme`: `auto` follows Emacs's theme) |
| `SPC m l` | Excalidraw's libraries (libraries.excalidraw.com), in Emacs (see below) |
| `SPC m r` | Read the file again |

The buffer has the file's text, under the page: a moment after each change (`+my/excalidraw-export-delay`, 300 ms),
the page exports the drawing and Emacs puts it there, marked modified, so a drawing is saved as any file (`Cmd+S`,
`:w`, Emacs asking when it's closed), and its tab shows it's changed. Saving first asks the page for the drawing as it
is and waits for it (5 s at most), so a change made just before is saved too. Undo is Excalidraw's.

Split, each pane shows the drawing (a WebKit view per window, as for PDFs), and a change in one shows in the others.
A drawing changed on disk (git, say) is shown anew (`revert-buffer`, so also Doom's auto-revert); one changed here is
only read again after asking. A file that isn't a drawing (a plain SVG named so) opens blank, under a notice saying
that saving replaces it with what you draw.

**Libraries.** Excalidraw's library (its panel: shapes kept to reuse, drawn or added from
[libraries.excalidraw.com](https://libraries.excalidraw.com)) is the same in every drawing, kept in
`+my/excalidraw-library-file` (Doom's `.local/etc/excalidraw-library.excalidrawlib`) across Emacs sessions: a change in
one drawing shows in the others open, and the next ones start with it. The panel's **Browse libraries** (or `SPC m l`)
opens the libraries' site in Emacs, in the drawing's pane, under a notice whose **Back to the drawing** (or `Cmd+W`)
closes it; a library's **Add to Excalidraw** downloads it, adds it (the panel opens on it), closes the site and shows
the drawing again. (In the browser, the site sent the library to the drawing page's `file://` address, where Emacs
never saw it; inside Emacs, its links open a new window, which a click didn't do there, so the site is told to put the
link clicked in its title, which Emacs reads while it's open.) `M-x +my/excalidraw-add-library` adds one from its URL or file, or from a
link with `addLibrary=` in it, such as that `file://` one (the kill ring's latest is offered).

From Markdown or Org, `Option+Enter` (the [actions menu](code.md#context-actions-optionenter)) has **Insert a new
drawing** (`M-x +my/excalidraw-insert`): it asks for a name (`drawing.excalidraw.svg` by default, `.excalidraw.svg`
added if left out), links it at point as an image (`![](fig.excalidraw.svg)`, `[[file:fig.excalidraw.svg]]`),
opens it beside, taking focus, and saves it blank at once so the link shows. On a link to a drawing, **Edit the
drawing** opens it beside.

The page can't call Emacs: it says in its title whether it's ready, the drawing's version (one more at each change),
the version its latest export is of, the mouse pointer it wants (the hand over buttons and what can be moved, the
I-beam over text, the arrow elsewhere) and an error; Emacs reads it every 0.1 s while a drawing is on screen, and asks
the page for an export when there's a new one (an answer awaited: a view closed meanwhile is kept until the answer
has come, 5 s at most, as one closed with an answer pending crashed Emacs; see `config/webkit.el`).

Excalidraw 0.17.6 (its plain-script build, on React 18; newer versions only ship ES modules, which a `file://` page
may not load) is downloaded once, from jsdelivr, into Doom's `.local/etc/excalidraw-0.17.6/`, each file checked
against its SHA-256 in `+my/excalidraw-files`; `M-x +my/excalidraw-install` downloads it again. Without it (e.g.
offline the first time), in a terminal, or in an Emacs without xwidgets, a drawing opens in its file's own mode: the
SVG as an image (as XML in a terminal), the JSON as JSON.

## Mode line

A space after its last item on the right (e.g. flycheck's checkmark), which touched the window's
edge; in every doom-modeline layout (`config/modeline.el`).

## Tiling (`SPC w SPC`)

Like a tiling window manager ([Amethyst](https://github.com/ianyh/Amethyst)'s layouts): `SPC w SPC` opens a new pane
where the tiling strategy puts it, showing the current buffer (its only tab, as `SPC w v`), and moves the cursor there;
`SPC w a` arranges the panes as the strategy lays them out (e.g. after splits of your own). The usual splits (`SPC w v`,
`SPC w s`...) and the other window keys don't change. The strategy is chosen in `config.el`
(`(setq +my/tiling-strategy 'tall)`, also the default; `config/tiling.el`). Panes are the frame's windows besides its
side panels (treemacs, popups), which stay as they are.

- **tall** (Amethyst's Tall): the first pane is the main one, on the left (half the width, `+my/tiling-tall-ratio`), the
  others stacked on the right at equal heights. The second pane opens on the right; the next ones at the bottom of the
  stack, from whichever pane. Panes laid out otherwise are arranged tall first.

More strategies can be added to `+my/tiling-strategies`: a name, a function that opens a pane, one that arranges them.

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
