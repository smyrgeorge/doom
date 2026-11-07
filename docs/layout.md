# Repository layout

| Path | What |
|---|---|
| `init.el`, `packages.el` | Doom's modules and the extra packages (`doom sync` after editing) |
| `config.el` | The main config; loads `config/` |
| `config/actions.el` | `Option+Enter` actions menu |
| `config/agent-shell.el` | Claude Code |
| `config/banner.el` | Notices |
| `config/cheatsheet.el`, `cheatsheet.org` | Tips panel under the sidebar (turned off) |
| `config/compile.el` | Byte-compiles this config when Emacs is idle |
| `config/editor.el` | `Cmd+B`, jumps, case cycling, the `fill-column` line, the current line |
| `config/emacs.el` | Garbage collection |
| `config/evil.el` | Normal state on save; `q` closes transient menus |
| `config/examples.el`, `examples/` | The examples and their screenshots |
| `config/excalidraw.el`, `.js` | Drawings |
| `config/git.el` | `SPC g d` diff pane |
| `config/lsp.el` | Language server tweaks, `kotlin-lsp` |
| `config/magit.el` | Commit graph, delta diffs, TODOs |
| `config/markdown.el` | Live preview |
| `config/merge.el` | Three-pane conflict resolution |
| `config/modeline.el` | Mode line |
| `config/pdf.el`, `.js` | PDFs |
| `config/peek.el` | Usages peek |
| `config/projectile.el` | Projects |
| `config/search.el` | Search Everywhere, find in files |
| `config/smooth.el` | Wheel glide, scroll limit, long lines |
| `config/spell.el`, `dict/tech.txt` | Spelling with programming words |
| `config/stripe.el` | Error stripe |
| `config/sticky.el` | Sticky header |
| `config/tabs.el` | Tabs per window |
| `config/terminal.el` | Terminal Emacs |
| `config/tiling.el` | Tiling |
| `config/tree-sitter.el` | Tree-sitter grammars built ahead of time |
| `config/treemacs.el` | Sidebar |
| `config/webkit.el` | Web pages in Emacs, for PDFs, drawings and the preview |
| `config/window.el` | Frame, fringes, focus of new windows |
| `cmd/` | Shell commands (`diff.sh`) |
| `scripts/` | Installers (`emacs.sh`, `tools.sh`, `lsp.sh`), `dict.sh`, `screenshots.sh` |
| `tests/` | Tests (`tests/run.sh`) |
| `docs/` | These docs |
