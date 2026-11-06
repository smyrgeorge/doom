# Repository layout

| Path | Purpose |
|---|---|
| `init.el` | Enabled Doom modules and their flags (`doom sync` after editing). |
| `packages.el` | Extra packages: `magit-delta`, `magit-todos`, `agent-shell` (+ `acp`, `shell-maker`), `string-inflection`, `rainbow-delimiters`. |
| `config.el` | Main configuration; small sections inline, big ones loaded from `config/`. |
| `docs/` | Documentation of the features, one file per topic (index in `README.md`). |
| `config/emacs.el` | Emacs itself: garbage collection (32 MB while idle instead of gcmh's 800 KB). |
| `config/stripe.el` | IntelliJ-like error stripe: git changes and errors across the file, at the right edge. |
| `config/sticky.el` | Sticky header: the classes/functions (Markdown: headings) around the top line. |
| `config/window.el` | Maximized frame; new windows (splits, panes) get focus; a wider right fringe. |
| `config/tiling.el` | Tiling like a tiling window manager: `SPC w SPC` opens a pane where the strategy (tall) puts it, `SPC w a` arranges. |
| `config/banner.el` | Notices at the top of a window (IntelliJ's editor notifications), with actions and ✕. |
| `config/smooth.el` | Mouse-wheel notches glide (on top of Doom's pixel scrolling); scroll limit past the end; files with very long lines shown plain. |
| `config/pdf-xwidget.el` | PDFs in WebKit inside the file's tab, drawn by PDF.js (downloaded once); Evil keys, search, copy, zoom, outline, dark pages, back / forward, places kept, Option+Enter actions, Preview, print. |
| `config/pdf-xwidget.js` | The PDF's page: PDF.js's viewer, toolbar and sidebar (outline, thumbnails), driven from Emacs through `window.pdfx`. |
| `config/pdf.el` | pdf-tools' zoom like macOS apps: Cmd+= / Cmd+- / Cmd+0 and Cmd+scroll (not loaded: Doom's pdf module is off, see `config.el`). |
| `config/peek.el` | LSP peek (usages, definitions): calmer, with functions, line numbers, key hints. |
| `config/treemacs.el` | Treemacs sidebar behaviour (auto-open, follow, git status, window keys). |
| `config/cheatsheet.el` | Tips panel under treemacs, from `cheatsheet.org` (disabled for now, see `config.el`). |
| `cheatsheet.org` | The tips the (disabled) tips panel shows. |
| `config/markdown.el` | Live Markdown preview inside Emacs; marksman's false link warnings dropped. |
| `config/tabs.el` | Tabs per window (Emacs's tab line), like IntelliJ's split editors. |
| `config/modeline.el` | Mode line: a space after its last item on the right. |
| `config/actions.el` | Option+Enter context-actions menu (spelling, LSP code actions, Claude; PDFs add theirs). |
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
| `config/terminal.el` | Terminal Emacs: paint the terminal background with the theme colour; no menu bar in terminal frames; hover help stays in the echo area. |
| `config/compile.el` | Byte-compiles this config's functions when Emacs is idle (they load as source). |
| `scripts/emacs.sh` | Installs Emacs (emacs-plus cask) and runs `doom sync`. |
| `scripts/tools.sh` | CLI tools, fonts (JetBrains Mono, Nerd Font symbols), BasicTeX, pdf-tools build deps, the `claude-agent-acp` bridge. |
| `scripts/lsp.sh` | Language servers, formatters and linters. |
| `scripts/dict.sh` | Rebuilds `dict/tech.txt` from cspell's word lists (needs `npm`, `aspell`). |
