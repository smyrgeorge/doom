# doom

My Emacs configuration, built on [Doom Emacs](https://github.com/doomemacs/core).

> Doom is a configuration framework for GNU Emacs tailored for Emacs bankruptcy veterans who want less framework in their
> frameworks, a modicum of stability (and reproducibility) from their package manager, and the performance of a hand
> rolled config (or better).

It targets **macOS on Apple Silicon** with **Emacs 31** (emacs-plus), and aims for an IntelliJ-like workflow: a project
sidebar that follows the current file, LSP for every language I use, format-on-save, and Claude Code inside Emacs. It
works both as a GUI app and in the terminal (`emacs -nw`).

## Table of contents

- [Installation](#installation)
- [Repository layout](#repository-layout)
- [Highlights](#highlights)
- [Custom key bindings](#custom-key-bindings)
- [Enabled modules](#enabled-modules)
- [Languages and tooling](#languages-and-tooling)
- [Terminal usage](#terminal-usage)
- [Known `doom doctor` warnings](#known-doom-doctor-warnings)

## Installation

Requirements: macOS (Apple Silicon), [Homebrew](https://brew.sh), `git`, `node`/`npm` and
[`uv`](https://github.com/astral-sh/uv).

```sh
# 1. This config
git clone git@github.com:smyrgeorge/doom.git ~/.config/doom

# 2. Doom itself (its modules are a git submodule)
git clone --depth 1 --recurse-submodules https://github.com/doomemacs/core ~/.config/emacs

# 3. Emacs (prebuilt emacs-plus Emacs.app) + `doom sync` (also fetches Doom's modules)
~/.config/doom/scripts/emacs.sh

# 4. CLI tools, fonts, language servers
~/.config/doom/scripts/tools.sh
~/.config/doom/scripts/lsp.sh

# 5. Let the GUI app see your shell's PATH (re-run when PATH changes)
~/.config/emacs/bin/doom env

# 6. Check everything
~/.config/emacs/bin/doom doctor
```

After changing `init.el` or `packages.el`, run `~/.config/emacs/bin/doom sync` and restart Emacs. Changes to
`config.el` and `config/*.el` only need a restart.

**One-time manual steps**

- **Claude login:** run `claude` once in a terminal and log in; `agent-shell` reuses that login.
- **Kotlin LSP EULA:** read it with `kotlin-lsp --show-eula`, then run `kotlin-lsp --stdio` once and accept.
- **iTerm (terminal Emacs):** in *Settings → Profiles → Text*, use a Nerd Font (e.g. *JetBrainsMono Nerd Font*) for
  icons and tick *Use ligatures*.

## Repository layout

| Path                  | Purpose                                                                          |
|-----------------------|----------------------------------------------------------------------------------|
| `init.el`             | Enabled Doom modules and their flags (`doom sync` after editing).                |
| `packages.el`         | Extra packages: `magit-delta`, `agent-shell` (+ `acp`, `shell-maker`).            |
| `config.el`           | Main configuration; small sections inline, big ones loaded from `config/`.        |
| `config/emacs.el`     | Emacs itself: garbage collection (32 MB while idle instead of gcmh's 800 KB).      |
| `config/stripe.el`    | IntelliJ-like error stripe: git changes and errors across the file, at the right edge. |
| `config/sticky.el`    | Sticky header: the classes/functions (Markdown: headings) around the top line.    |
| `config/window.el`    | Maximized frame; new windows (splits, panes) get focus.                           |
| `config/banner.el`    | Notices at the top of a window (IntelliJ's editor notifications), with actions and ✕. |
| `config/smooth.el`    | Mouse-wheel notches glide (on top of Doom's pixel scrolling).                     |
| `config/pdf.el`       | PDF zoom like macOS apps: Cmd+= / Cmd+- / Cmd+0 and Cmd+scroll.                   |
| `config/peek.el`      | LSP peek (usages, definitions): calmer, with functions, line numbers, key hints.  |
| `config/treemacs.el`  | Treemacs sidebar behaviour (auto-open, follow, git status, window keys).          |
| `config/cheatsheet.el` | Tips panel under treemacs, from `cheatsheet.org` (disabled for now, see `config.el`). |
| `config/markdown.el`  | Live Markdown preview inside Emacs.                                               |
| `config/tabs.el`      | Tabs per window (Emacs's tab line), like IntelliJ's split editors.               |
| `config/modeline.el`  | Mode line: a space after its last item on the right.                             |
| `config/actions.el`   | Option+Enter context-actions menu (spelling, LSP code actions, Claude).           |
| `config/magit.el`     | Magit add-ons: commit graph (like tig), git-delta diffs, TODOs in the status buffer. |
| `config/editor.el`    | Editing and navigation: Cmd+B, Cmd+[ / Cmd+], `M-[` / `M-]`, `SPC c ~`; rainbow brackets; right margin. |
| `config/evil.el`      | Evil tweaks: saving returns to normal state; `q` closes transient menus.          |
| `config/spell.el`     | Spell checking: tech-words dictionary, camelCase splitting, personal dictionary.  |
| `dict/tech.txt`       | ~40k programming words for the spell checker (built by `scripts/dict.sh`).        |
| `config/agent-shell.el` | Claude Code in Emacs (agent-shell): login, default agent, `SPC o c` / `SPC o C`. |
| `config/lsp.el`       | Language servers: code lenses; projects imported without asking; `kotlin-lsp`.    |
| `config/projectile.el` | Projects under `~/dev`; project file list without a cache.                      |
| `config/search.el`    | `SPC s a`: Search Everywhere, like IntelliJ; `Cmd+Shift+F`: find in files (rg).   |
| `config/git.el`       | `SPC g d`: the current file's git diff in a side pane.                            |
| `config/terminal.el`  | Terminal Emacs: paint the terminal background with the theme colour.              |
| `config/compile.el`   | Byte-compiles this config's functions when Emacs is idle (they load as source).   |
| `scripts/emacs.sh`    | Installs Emacs (emacs-plus cask) and runs `doom sync`.                            |
| `scripts/tools.sh`    | CLI tools, fonts (JetBrains Mono, Nerd Font symbols), pdf-tools build deps, the `claude-agent-acp` bridge. |
| `scripts/lsp.sh`      | Language servers, formatters and linters.                                         |
| `scripts/dict.sh`     | Rebuilds `dict/tech.txt` from cspell's word lists (needs `npm`, `aspell`).        |

## Highlights

### Project sidebar (treemacs)

`config/treemacs.el` makes treemacs behave like IntelliJ's project view:

- **Opens automatically** the first time a project file is shown in a workspace (`SPC p p`, `SPC SPC`, `SPC f r`, the
  dashboard...). Close it with `SPC o p` and it stays closed for that workspace.
- **Follows the current buffer**: highlights the open file and switches to the buffer's project, right after every
  buffer or window switch (treemacs' own project follow waits for 1.5 s without any input).
- **Git status** colours for files and folders, computed asynchronously. Saving a file refreshes its status (macOS's
  kqueue file notifications miss in-place edits, so this is done explicitly on save). Changes made outside Emacs
  (Claude Code, a terminal, git) show up within a few seconds: while Emacs has focus, the shown projects' `git status`
  is checked every 3 s in the background (`+my/treemacs-git-poll-interval`), and treemacs refreshes when it changed.
- **Reachable like any window**: `SPC w w` cycles into it and it gets a window number (`SPC w 1`, as the leftmost
  window).
- **No mode line**: it only said "Treemacs" and the workspace.
- **Arrows, like IntelliJ's trees**: `←` collapses a node, or goes to its parent; `→` expands a closed node, goes to
  the first child of an open one, and opens a file (in the error list, jumps to the error). `↑`/`↓` move a line, like
  `k`/`j`. The same in the LSP lists (`SPC c X`, `SPC c S`), where `←`/`→` didn't expand or collapse anything.
  `h`/`l` keep treemacs' own collapse / open. A **single click** opens a file or expands/collapses a folder
  (treemacs' default is a double click).
- `zR` / `zM` (`M-x treemacs-expand-all` / `treemacs-collapse-all`): expand every folder of the project, or collapse
  them all (the project stays open at its top level). Expanding asks first in projects with more than 300 folders.
- With `+lsp`: structure view (`SPC c S`), project errors (`SPC c X`) and call hierarchy (`SPC c y` / `SPC c Y`).
  The structure view and the error list open with the cursor in them, on their first line (it stayed in the code).
- **Tips panel** (disabled for now: uncomment `(load! "config/cheatsheet")` in `config.el`) below the sidebar,
  whenever it's open: a few tips from `cheatsheet.org` (this config's keys, Doom's, Vim's), two per section, changing
  every 5 minutes, so over time you see them all. In the panel `n` shows the next tips, `e` opens the whole
  cheatsheet, `q` hides it; `SPC t ?` hides / shows it. Edit `cheatsheet.org` to change the tips (one `- ` line each,
  under a `*` heading); the panel picks them up on save (`config/cheatsheet.el`).

### Live Markdown preview

`config/markdown.el` renders Markdown in a WebKit side window (xwidgets) **inside Emacs**:

- **Updates as you type** (≈0.3 s after you stop), swapping the page content without reloading.
- **Scrolls to the cursor line**, using pandoc's `sourcepos` extension to map each element back to its source line.
- **GitHub look**: github-markdown-css plus highlight.js, following the macOS light/dark setting; as wide as the pane.
- Math is rendered as MathML; relative image links work.
- In terminal Emacs it falls back to markdown-mode's `eww` preview (updates on save).

Requires `pandoc`. Styles are loaded from a CDN, so the preview is unstyled offline.

### Context actions (Option+Enter)

`config/actions.el` gives `M-RET` (Option+Enter) one menu with everything that applies at point, like Alt+Enter in
JetBrains IDEs:

- **Spelling** (when the word at point is underlined): the top aspell suggestions and "Add to dictionary".
- **Code actions**: the LSP server's quick fixes and refactors for the point or the active region (same list as
  `SPC c a`).
- **Claude** (agent-shell): *Fix / Explain error with Claude* for the error at point and *Explain selection with
  Claude* are sent straight away (queued if Claude is busy, a Claude Code shell is started if the project has none);
  *Add selection / file to Claude prompt* puts the context in the prompt for you to finish.

Works in visual state too, on the selection. Each section comes from a provider function listed in
`+my/context-action-providers`; new kinds of actions are added by writing another provider. Org keeps `M-RET` for "new heading/item"; in Markdown a new list item is
`C-c C-j` or `M-*`.

### Error stripe

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

### Smooth scrolling

Doom's `smooth-scroll` module scrolls by pixels (ultra-scroll), which suits a trackpad's stream of small steps. A
mouse wheel reports a few lines per notch, so it still jumped; `config/smooth.el` spreads bigger steps over a glide
(about 0.15 s, fast at first then slowing down), and notches in quick succession add to what's left without
restarting it. A frame per refresh of the display (60 Hz), each covering a share of what's left that depends on the
time since the last frame, so a late frame catches up instead of slowing the glide down
(`+my/smooth-scroll-min-step`, `-frame`, `-time-constant`). good-scroll (the `+interpolate` flag: it animates keyboard
scrolling, `C-d`, `C-v`...) runs its 20 ms timer only while a scroll animates: always on, it made Emacs redraw ~50 times
a second, which on macOS took time from everything else. Heavy jobs that run when Emacs is idle (gcmh's garbage
collection, ~80 ms; treemacs' refresh after a git change, ~130 ms) wait until a glide ends: a glide runs from a timer,
so Emacs counted as idle and they froze it for a few frames. The module also pauses some modes while scrolling; hl-todo is
kept on, otherwise TODO/NOTE/FIXME lose their highlight during a scroll and flicker. Its mode-line freeze during scrolls
is off: in popups like `*Messages*` it broke the mode line, and with it Esc (which then couldn't close the popup). The wheel doesn't scroll the
minibuffer / echo area (it always fits what it shows, so it only jumped and came back); with a completion list open,
it moves through the candidates instead. Every window (`*Messages*`, help, magit... not just files) stops scrolling
with at most a quarter of it empty below the last line (`+my/stripe-overscroll`), instead of going on until the last
line reaches the top and bouncing back at each further notch; images, PDFs and terminals are left alone. The limit is
measured in pixels, not rows: a row showing an image (e.g. a screenshot in a Claude reply) is as tall as many lines,
and counted as one, scrolling down to an image near the end went on past it, then snapped back up by screens.
Files with lines over 5,000 characters (`+my/long-line-threshold`; Doom keeps Emacs's 10,000 in native-comp builds)
open in `so-long-mode`: plain, without highlighting, ligatures or LSP. Otherwise, e.g. an HTML report with
7,000-character SVG lines stayed in `web-mode`, where redisplay walks each such line character by character (~6 ms a
line a pass) and scrolling stalled for seconds. They don't wrap either: wrapped, such a line fills screens of rows and
every scroll step lays it out again (~60 ms, a visible stutter; ~15-20 ms unwrapped). A notice at the top says so, with
**Wrap lines** and **Open normally** (the file's own mode back) actions (see below).

### Notices

`config/banner.el` shows notices at the top of a window, under the tabs, like IntelliJ's editor notifications: a row
each, with an icon and colour for its type (info blue, warning yellow, error red), the message, actions to click, and
`✕` to close it. They stay put while scrolling, and the header line (the path, or the sticky scopes) stays under them.
A header line is one row of text, so it grows a row per notice (an invisible tall image) and a small borderless child
frame lays the notices over those rows; each window showing the buffer gets its own. In a terminal the header line
shows the first notice instead (and how many more). Code adds one with
`(+my/banner-show ID TEXT :type 'warning :actions '(("Label" . function)))`; `M-x +my/banner-close` closes the first.
Notices so far: (warning) files with very long lines shown plain and unwrapped (**Wrap lines**, **Open normally**).

### Usages peek

`config/peek.el` reworks lsp-ui's peek, the inline panel that lists usages (`gD`, or `Cmd+B` on a declaration) and
definitions:

- a header that says what's listed (`Usages of HOLD1 · 22 in 1 file`) and a footer with the keys (`j`/`k`, `C-j`/`C-k`
  file, `RET` open, `M-RET` other window, `Esc` close);
- each usage shows the function/class it's in, grouped: the name on the first usage of each, with a count (`×21`);
  outside functions, the top-level variable it's in (e.g. a constant holding a big literal);
- usages don't include the declaration itself;
- the preview has line numbers, with the usage's line highlighted, and shows non-ASCII text (`–`, Greek) as such:
  lsp-ui read files that aren't open without decoding them (`\342\200\223`);
- it stands out from the code: an empty row above and below in the colour of its top and bottom bars, and a panel
  clearly darker than the editor (the preview more than the list), all following the theme; softer colours for the
  selection and the matches, and only as tall as the list needs.

### Search Everywhere (`SPC s a`)

`config/search.el` emulates IntelliJ's double Shift: one list with **Classes**, **Files**, **Symbols** and
**Actions**. Typing searches all of them (words in any order, case-insensitive); to show one tab, type its key and
`SPC` — `c`, `f`, `s` or `a` — and `<<` (or `DEL` on an empty input) to go back to all.

- **Classes / Symbols:** the language server's workspace symbols, queried as you type (from 2 characters; only in
  buffers with an LSP server). Classes are classes, interfaces/traits, structs, enums and objects.
- **Files:** the project's files, recently opened ones first.
- **Actions:** every command (what `M-x` runs), recently used ones first, with key bindings and docs.

Emacs can't see a lone Shift key press on macOS, so it's on `SPC s a` instead of double Shift.

### Claude Code in Emacs

[`agent-shell`](https://github.com/xenodium/agent-shell) runs Claude Code (via the Agent Client Protocol) in a native
Emacs buffer — evil keys, search and copy work as usual. It uses the Claude CLI login. `C-u M-x agent-shell` starts a
second, parallel session.

Claude is told where it runs and what that allows (`+my/agent-shell-claude-context`, appended to Claude Code's own
system prompt in every session it starts or resumes):

- **Formatting:** the Markdown agent-shell renders (tables, code blocks highlighted by their language's mode), and what
  it doesn't (HTML, LaTeX, Mermaid).
- **File references** as `path:line`: agent-shell makes them links that open the file at that line.
- **Images** inline: a Markdown image link to a local file or an image's path alone on a line (PNG, JPEG, WebP, SVG),
  saved under the project's `.agent-shell/images/`, next to agent-shell's transcripts, so they keep showing there.
- **Reports** with diagrams or graphs come as Markdown in the reply, with only the diagrams rendered as images (not the
  whole report as one image or a web page), so they read inside the editor.
- **The editor:** Emacs runs a server, so Claude can ask it (`emacsclient --eval`) what you're looking at (buffers,
  file and line, region, diagnostics) or open a file for you: quickly, never waiting for input, changing nothing unless
  asked, and checking a file's buffer has no unsaved changes before editing it.
- **The theme's colours**, read when the session starts, so the images it draws suit them (dark here).

Images show as wide as the window (agent-shell shrinks them to 40% of it; `agent-shell-markdown-image-max-width` 1.0),
smaller ones at their own size; `{width=100%}` after an image link sizes one image,
`M-x agent-shell-markdown-image-scale-increase` / `-decrease` resize the ones on screen.

### Other customizations

- **Compiled config:** Doom loads `config/*.el` as source, so its functions ran interpreted, several times slower (the
  stripe's redraw on each frame of a scroll: 1.5 ms instead of 0.2). Once Emacs has been idle for 2 s they're
  byte-compiled in place, stopping at the first key press; again after anything loads (`after!` blocks define
  functions when their package loads). No `.elc` files are written, so nothing gets stale (`config/compile.el`). Compiled
  before a package loaded, a function would bind a local instead of the package's variable (`SPC g d` binding
  `magit-display-buffer-function`: the diff opened in the same window) and call the package's macros as functions
  (`invalid-function treemacs-run-in-every-buffer`); so such functions go back to their source and are compiled again
  once the package loads.
- **Opening files faster:** tree-sitter grammar checks are remembered (each one loaded the grammar's library again,
  ~10 ms on macOS with this many native-compiled libraries loaded; a Markdown file made ~9); garbage collection while
  idle waits for 32 MB instead of gcmh's 800 KB (the language server's replies and redraws after opening a file
  collected every few redraws, ~70 ms each). With the lens, sticky header and stripe changes, opening a Markdown file
  went from ~1 s of pauses to ~0.35 s. And a file just opened shows first, plain, and gets its colours right after
  (~0.1 s to see it instead of ~0.4 s): highlighting waits for its first display, like jit-lock's own deferral but only
  then, so scrolling never shows plain text (`config/editor.el`).
- **Font:** JetBrains Mono with ligatures.
- **Mode line:** a space after its last item on the right (e.g. flycheck's checkmark), which touched the window's
  edge; in every doom-modeline layout (`config/modeline.el`).
- **Right fringe:** a character wider in every window (16 px instead of Doom's 8), so the arrows of lines cut off at
  the window's edge (e.g. long names in treemacs) don't touch the text (`+my/right-fringe-padding`,
  `config/window.el`). File windows get the same on the left too (see Error stripe).
- **Kotlin:** JetBrains' official [`kotlin-lsp`](https://github.com/Kotlin/kotlin-lsp) instead of the community
  `kotlin-language-server`; with `format +lsp`, Kotlin is formatted by IntelliJ's formatter.
- **Magit:** diffs rendered with [`git-delta`](https://github.com/dandavison/delta) through `magit-delta`.
- **Commit graph, like tig:** the log (`l l`) and the status buffer's commits (`SPC g g`: "Recent commits" open,
  20 of them) show the branch tree, each lane in its own colour, drawn with box-drawing lines (`●` `│` `╱` `╲`) instead
  of ASCII, with the author and the date (`2026-11-04 09:58`) in the margin.
- **File diff pane:** `SPC g d` shows the current file's changes vs `HEAD` (delta-rendered) in a pane on the right and
  moves the cursor there, onto the hunk of the line you were on. It refreshes on save and switches to another file
  when pressed there. In the pane: `s`/`u`/`x` stage/unstage/discard a hunk, `RET` jumps to the line, `SPC g d`,
  `q` or `Esc` closes it. Opening it saves the buffer.
- **Tabs per window**, like IntelliJ's split editors (Emacs's tab line instead of Doom's centaur-tabs, whose tab
  groups were per project and shared by every window): each window's tabs are the buffers shown in it, in the order
  they first were. A split starts with one tab, the buffer it shows. Files, Claude sessions, dired and magit keep tabs;
  other buffers only while shown; popups, the dashboard and side panels have no tab line. Closing a tab (its ✕, a
  middle click) takes it off that window, which goes back to the tab it showed before; a file is closed too once no
  window has it as a tab any more (asking first if it has unsaved changes), a Claude session only leaves the tab line.
  `gt` / `gT`: next / previous tab. Tabs show the file's icon, a bar on the current one (`+my/tabs-height`), `•` when
  unsaved, and same-named files get the shortest distinguishing path as their label (`crate-a/src/lib.rs` vs
  `crate-b/src/lib.rs`) instead of `lib.rs<2>`, since workspaces disable uniquify.
- **Terminal background:** in terminal Emacs, the strip below the echo area is painted with the theme background
  (OSC 11) and restored on exit (OSC 111).
- **No menu bar in the terminal:** macOS GUI frames keep theirs (it lives in the system's menu bar); terminal frames
  don't get a "File Edit Options ..." row.
- **Hover help in the echo area, never in a tooltip:** e.g. a warning's message when hovering its text, as Doom has
  it. Doom also turned on `tty-tip-mode` (tips in a small child frame) when a terminal frame opened; that mode is
  global, so after an `emacsclient -t` GUI frames drew their tips at the frame's top-left corner. Not anymore.
- **`M-[` / `M-]`** switch buffers in the GUI only; in a terminal they would swallow mouse/focus escape sequences.
- **Spelling in code:** besides English and your personal dictionary, spell-fu knows ~40k programming words
  (`rect`, `rgba`, `async`, `kotlin`, `stdout`, ...) from `dict/tech.txt`, built by `scripts/dict.sh` from
  [cspell](https://github.com/streetsidesoftware/cspell-dicts)'s MIT-licensed dictionaries (only words English lacks).
  CamelCase identifiers are checked word by word (`AgreementController` = `Agreement` + `Controller`). Words you add
  with `zg` or Option+Enter still go to the personal dictionary.
- **Sticky header:** the header line of code windows shows the classes/functions the top visible line is inside, once
  their first lines have scrolled out of view, like IntelliJ's sticky lines (e.g. `class Api { › fun call(x: Int) {`);
  otherwise the file's path. Nested scopes via tree-sitter (Kotlin, Python, Rust, ...), the enclosing defun elsewhere.
  In Markdown (`markdown-ts-mode`) the headings: `# Guide › ## Setup › ### Install`. Only where scopes can be told:
  files whose mode has no notion of them (HTML in `web-mode`, files with very long lines in `so-long-mode`) get no
  header row. It lines up with the code past the line numbers by working out their width the way Emacs does, not with
  `header-line-indent-mode`, which laid the window out (highlighting it first) on every scroll and before every redraw.
- **Current line and selection across wrapped rows:** a long line wraps onto rows indented like it (Doom's word wrap,
  e.g. two spaces in a Markdown table), and the current line's highlight, and the selection's, left that indentation
  out: Emacs draws a line's wrap prefix without the faces of the overlays on it. hl-line's overlay now carries a copy of
  the prefix in its face; a selection gets one per line on screen, over its part of the selection. Only where the
  highlight is the whole line: Doom's dashboard highlights just the menu item, its line centred by a prefix.
- **`q` closes transient menus** (agent-shell's help and drawing menus, magit's...), as Esc (Doom) and `C-g` do: it
  only said "Unbound suffix: q". A menu that uses `q` for something of its own keeps it (magit's dispatch: bury the
  buffer; blame, git-timemachine: quit them); `transient-bind-q-to-quit` would move such keys to `Q`, not done.
- **Rainbow brackets:** `()`, `[]` and `{}` colored by nesting depth in code (`rainbow-delimiters`).
- **Right margin:** a thin vertical line at the maximum line length, like IntelliJ's, in files of code, text and
  configuration: at `fill-column`, set in `config.el` (120; also where `gq` / `M-q` wrap text; commit messages 72). A
  project's `.editorconfig` moves it with `max_line_length` (e.g. `100` for Kotlin with ktfmt) or removes it with
  `max_line_length = off` (e.g. for `*.md`). As faint as the line numbers; a line that runs past it covers it.
- **Code lenses:** what the language server offers at the end of the line: rust-analyzer's "▶ Run", implementations
  and reference counts; references/implementations for TypeScript/JavaScript. (Rust's "Debug" lens is off until a
  debugger is set up.) Placing them no longer measures the line on screen first (needed only for lenses above the
  line): that highlighted the file around each lens, ~0.5 s when a Markdown file's lenses arrived.
- **LSP project import:** opening a file in a project starts its language server in the project root (the git
  repository) without the "import project root?" prompt, like Zed. Files outside any project still ask, so a stray
  file in `~` never makes a server scan your home folder (`config/lsp.el`).
- **LSP file watchers:** lsp-mode watches every directory under the project root but doesn't read `.gitignore`;
  `config/lsp.el` also skips what git ignores, so a root with big ignored folders (e.g. repositories cloned inside
  it) needs a few dozen watches instead of thousands, without the "watch N directories?" prompt.
- **Markdown links:** two false warnings from marksman are hidden when the link is a path to an existing file
  (`config/markdown.el`): "Ambiguous link to document", when the linked file has more than one top-level `#` heading
  (genuinely ambiguous links, like `[[README]]` matching several files, are still reported); and "Link to non-existent
  document", for files git ignores, which marksman doesn't index (links to files that are really missing are still
  reported).
- **Evil:** saving a buffer returns to normal state.
- **New windows get focus:** splits (`SPC w s` / `SPC w v`) and any new window a command opens (diff pane, other-window
  commands...) move the cursor there. Side windows (Doom popups, treemacs, which-key, transient menus) keep their own
  behaviour, as do windows opened in the background; the live Markdown preview opts out with `+my/focus-new-windows`.
- **Projectile:** projects are discovered under `~/dev`. The file cache is off, so `SPC SPC` also lists files created
  outside Emacs (CLI, Claude Code, `git checkout`).

## Custom key bindings

Everything else is Doom's default (`SPC h b b` lists all bindings).

| Key                         | Action                                                 |
|-----------------------------|--------------------------------------------------------|
| `M-RET` (Option+Enter)      | Context actions at point (spelling, code actions, Claude) |
| `SPC s a`                   | Search Everywhere: classes, files, symbols, actions (IntelliJ's double Shift) |
| `Cmd+Shift+F` (GUI)         | Find in files: search the project with ripgrep (selected text is the query) |
| `Cmd+B`                     | Go to declaration, or on the declaration list its usages (IntelliJ's Go to Declaration or Usages); with a language server, also where it knows no declaration (e.g. a Markdown heading: the links to it) |
| `SPC g d`                   | Current file's git diff in a pane on the right (in the pane: `SPC g d`, `q` or `Esc` close) |
| `SPC o c`                   | Start Claude Code (agent-shell)                        |
| `SPC o C`                   | Pick / switch agent shell                              |
| `Cmd+=` / `Cmd+-` / `Cmd+0` (PDF) | Zoom in / out / actual size (elsewhere: font size) |
| `Cmd+scroll` (PDF)          | Zoom in (up) / out (down)                              |
| `SPC m p` (Markdown)        | Toggle live preview inside Emacs                       |
| `SPC m P` (Markdown)        | Preview in the browser                                 |
| `SPC o p` / `SPC o P`       | Toggle treemacs / reveal current file in treemacs      |
| `gt` / `gT`                 | Next / previous tab of the window                      |
| `SPC t ?`                   | Hide / show the tips panel (when enabled)              |
| `←` / `→` (treemacs, LSP lists) | Collapse or go to parent / expand, into, or open    |
| `zR` / `zM` (treemacs)      | Expand / collapse all folders                          |
| `M-[` / `M-]` (GUI)         | Previous / next buffer                                 |
| `s-[` / `s-]`               | Jump back / forward (better-jumper)                    |

## Enabled modules

See `init.el` for the full list. Notable choices:

| Group         | Modules                                                                                                   |
|---------------|-----------------------------------------------------------------------------------------------------------|
| `:completion` | `(corfu +orderless +icons)`, `(vertico +icons)`                                                            |
| `:ui`         | `dashboard`, `indent-guides`, `ligatures`, `(smooth-scroll +interpolate)`, `(treemacs +lsp)`, `(vc-gutter +pretty)`, `(window-select +numbers)`, `workspaces` |
| `:editor`     | `(evil +everywhere)`, `(format +onsave +lsp)`, `multiple-cursors`, `snippets`, `(whitespace +guess +trim)`  |
| `:emacs`      | `(dired +dirvish +icons)`, `(ibuffer +icons)`, `undo`, `vc`                                                |
| `:term`       | `(ghostel +everywhere)`                                                                                   |
| `:checkers`   | `(syntax +childframe +icons)`, `(spell +everywhere)`                                                      |
| `:tools`      | `(lsp +peek)`, `tree-sitter`, `magit`, `(debugger +lsp)`, `(docker +lsp +tree-sitter)`, `pdf`, `make`     |
| `:os`         | `macos`, `(tty +osc)`                                                                                     |

## Languages and tooling

All languages use LSP and tree-sitter where available. Most servers and formatters are installed by `scripts/lsp.sh`;
the rest are installed by lsp-mode itself, which offers to do so the first time you open such a file
(`M-x lsp-install-server`).

| Language              | Module flags                         | Language server / tools                                  |
|-----------------------|--------------------------------------|----------------------------------------------------------|
| Rust                  | `+lsp +tree-sitter`                  | `rust-analyzer`                                          |
| Python                | `+lsp +pyright +uv +tree-sitter`     | `pyright`, `black`, `isort`, virtualenvs via `uv`        |
| Kotlin                | `+lsp +tree-sitter`                  | `kotlin-lsp` (JetBrains), `ktlint`                       |
| JavaScript/TypeScript | `+lsp +tree-sitter`                  | `typescript-language-server`, `prettier`                 |
| C/C++                 | `+lsp +tree-sitter`                  | `clangd` (Xcode CLT), `clang-format`, `glslang`          |
| Shell                 | `+lsp`                               | `bash-language-server`, `shellcheck`, `shfmt`            |
| Web (HTML/CSS)        | `+lsp +tree-sitter`                  | `vscode-langservers-extracted`, `js-beautify`, `prettier` |
| Markdown              | `+lsp +tree-sitter`                  | `marksman` (pulls in .NET), `pandoc` for previews        |
| Docker                | `+lsp +tree-sitter`                  | `dockerfile-language-server-nodejs`                      |
| GDScript (Godot)      | `+lsp +tree-sitter`                  | Godot's LSP, `gdformat` (`gdtoolkit`)                    |
| JSON / YAML           | `+lsp +tree-sitter`                  | `vscode-langservers-extracted`, `yaml-language-server`   |
| Org                   | `+pretty`                            | —                                                        |
| REST                  | `+jq`                                | `jq`                                                     |
| CSV / XML             | `data`                               | —                                                        |

## Terminal usage

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
- Icons (tabs, mode line, notices) need a Nerd Font in the terminal (see Setup).

## Known `doom doctor` warnings

These are expected and safe to ignore:

| Warning                         | Why it's fine                                                                                   |
|---------------------------------|-------------------------------------------------------------------------------------------------|
| `Symbola` font not found        | Symbola is no longer freely available; Symbols Nerd Font Mono covers most symbols.              |
| `Couldn't find dockfmt`         | The check uses an outdated name; Docker formatting isn't used here.                             |
| `Couldn't find nosetests`       | nose is unmaintained; use pytest.                                                               |
| `Couldn't find stylelint`       | CSS is checked by the CSS language server; install stylelint per project if a project uses it. |
