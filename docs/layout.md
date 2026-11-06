# Repository layout

| Path | Purpose |
|---|---|
| `init.el` | Enabled Doom modules and their flags (`doom sync` after editing). |
| `packages.el` | Extra packages: `magit-delta`, `magit-todos`, `agent-shell` (+ `acp`, `shell-maker`), `string-inflection`, `rainbow-delimiters`. |
| `config.el` | Main configuration; small sections inline, big ones loaded from `config/`. |
| `docs/` | Documentation of the features, one file per topic (index in `README.md`). |
| `config/emacs.el` | Emacs itself: garbage collection (32 MB while idle instead of gcmh's 800 KB). |
| `config/stripe.el` | IntelliJ-like error stripe: git changes and errors across the file, and the scrollbar's thumb, at the right edge (one image in a child frame over the margin; click, drag, wheel). |
| `config/sticky.el` | Sticky header: the classes/functions (Markdown: headings) around the top line. |
| `config/window.el` | Maximized frame; new windows (splits, panes) get focus; a wider right fringe. |
| `config/tiling.el` | Tiling like a tiling window manager: `SPC w SPC` opens a pane where the strategy (tall) puts it, `SPC w a` arranges. |
| `config/banner.el` | Notices at the top of a window (IntelliJ's editor notifications), with actions and ✕. |
| `config/smooth.el` | Mouse-wheel notches glide (on top of Doom's pixel scrolling); scroll limit past the end; files with very long lines shown plain. |
| `config/webkit.el` | Web pages inside Emacs (xwidget WebKit), for the PDF viewer, the Markdown preview and drawings: a view per window (splits), no white flash, links out, JavaScript (answers awaited safely), the page's title read, mouse pointer, clicks, scroll / copy keys, a file's text from its page, downloads checked by SHA-256. |
| `config/pdf.el` | PDFs in WebKit inside the file's tab, drawn by PDF.js (downloaded once); Evil keys, search, copy, zoom, outline, dark pages, back / forward, places kept, Option+Enter actions, Preview, print; splits (on `config/webkit.el`). |
| `config/pdf.js` | The PDF's page: PDF.js's viewer, toolbar and sidebar (outline, thumbnails), driven from Emacs through `window.pdfx`. |
| `config/excalidraw.el` | Drawings (`*.excalidraw.svg`, `*.excalidraw`) in Excalidraw inside the file's tab (downloaded once): saved as any file, Excalidraw's keys before Evil's, copy / paste, dark canvas, splits, reverts, a library shared and kept (libraries.excalidraw.com in Emacs); inserted from Markdown / Org (on `config/webkit.el`). |
| `config/excalidraw.js` | A drawing's page: Excalidraw, driven from Emacs through `window.exd`; exports the drawing after each change. |
| `config/peek.el` | LSP peek (usages, definitions): calmer, with functions, line numbers, key hints. |
| `config/treemacs.el` | Treemacs sidebar behaviour (auto-open, follow, git status, window keys). |
| `config/cheatsheet.el` | Tips panel under treemacs, from `cheatsheet.org` (disabled for now, see `config.el`). |
| `cheatsheet.org` | The tips the (disabled) tips panel shows. |
| `config/markdown.el` | Live Markdown preview inside Emacs (on `config/webkit.el`: splits, links, keys); marksman's false link warnings dropped. |
| `config/tabs.el` | Tabs per window (Emacs's tab line), like IntelliJ's split editors. |
| `config/modeline.el` | Mode line: a space after its last item on the right. |
| `config/actions.el` | Option+Enter context-actions menu (spelling, LSP code actions, Claude; PDFs and drawings add theirs). |
| `config/magit.el` | Magit add-ons: commit graph (like tig), git-delta diffs, TODOs in the status buffer. |
| `config/editor.el` | Editing and navigation: Cmd+B, Cmd+[ / Cmd+], `M-[` / `M-]`, `SPC c ~`; rainbow brackets; right margin; current line and selection across wrapped rows; tree-sitter cache; highlighting after the first display. |
| `config/evil.el` | Evil tweaks: saving returns to normal state; `q` closes transient menus. |
| `config/spell.el` | Spell checking: tech-words dictionary, camelCase splitting, personal dictionary. |
| `dict/tech.txt` | ~40k programming words for the spell checker (built by `scripts/dict.sh`). |
| `config/agent-shell.el` | Claude Code in Emacs (agent-shell): login, default agent, `SPC o c` / `SPC o C`, what Claude is told about Emacs, image width. |
| `config/tree-sitter.el` | The enabled languages' tree-sitter grammars, built in the background after startup instead of asked for on first use. |
| `config/lsp.el` | Language servers: code lenses; projects imported without asking; file watchers skip git-ignored folders; `kotlin-lsp`. |
| `config/projectile.el` | Projects under `~/dev`; project file list without a cache; a project opens on its README; each workspace remembers its project. |
| `config/search.el` | `SPC s a`: Search Everywhere, like IntelliJ; `Cmd+Shift+F`: find in files (rg). |
| `config/git.el` | `SPC g d`: the current file's git diff in a side pane. |
| `config/merge.el` | Conflicts resolved in three panes like IntelliJ's (Yours, Result, Theirs, under a bar): `e` on a conflicted file in Magit; the versions from Git's index, the changes from Ediff's diff3 parser; the panes lined up (filler lines) and scrolling together; a ✨ wand merging a conflict's words (`git merge-file` on one word a line). |
| `config/terminal.el` | Terminal Emacs: paint the terminal background with the theme colour; no menu bar in terminal frames; hover help stays in the echo area. |
| `config/compile.el` | Byte-compiles this config's functions when Emacs is idle (they load as source). |
| `tests/` | Tests of this config's features (`tests/run.sh`; see [Tests](tests.md)): never loaded by Doom. |
| `config/examples.el` | `M-x +my/example` and a `+my/example-NAME` command for each example (see [Examples](examples.md)). |
| `examples/` | Examples of the features, each on files of its own in the temp folder (`merge.el`: a repository in conflict); loaded only when run. `NAME.png`: its screenshot (`scripts/screenshots.sh`). |
| `cmd/xterm-24bit.terminfo` | `xterm-256color` with 24-bit colour, for an Emacs server's terminal frames (`cmd/diff.sh` compiles it into `~/.terminfo`). |
| `cmd/diff.sh` | Git's conflicts resolved in the three panes from the shell, in the terminal or a GUI frame, one file after the other; `diff.sh example` runs the merge example (see [Shell commands](cmd.md)). |
| `scripts/emacs.sh` | Installs Emacs (emacs-plus cask) and runs `doom sync`. |
| `scripts/tools.sh` | CLI tools, fonts (JetBrains Mono, Nerd Font symbols), BasicTeX, the `claude-agent-acp` bridge. |
| `scripts/lsp.sh` | Language servers, formatters and linters. |
| `scripts/screenshots.sh` | Screenshots of the examples (`examples/NAME.png`): each opened in a GUI Emacs of its own with this config's look, its frame captured with `screencapture` (see [Examples](examples.md#screenshots)). |
| `scripts/screenshots.el` | What `scripts/screenshots.sh` runs in that Emacs: the look, the frame on top, each example opened, captured, closed. |
| `scripts/dict.sh` | Rebuilds `dict/tech.txt` from cspell's word lists (needs `npm`, `aspell`). |
