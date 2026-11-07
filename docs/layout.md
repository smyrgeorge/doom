# Repository layout

| Path | What |
|---|---|
| `init.el`, `packages.el` | Doom's modules and the extra packages (`doom sync` after editing) |
| `config.el` | The main config; loads `config/` |
| `config/agent-shell.el` | Claude Code |
| `config/banner.el`, `banner/` | Notices |
| `config/cheatsheet.el`, `cheatsheet.org` | Tips panel under the sidebar (turned off) |
| `config/childframe.el` | Frames laid over a window: notices, the error stripe, WebKit's cover |
| `config/compile.el` | Byte-compiles this config when Emacs is idle |
| `config/editor.el`, `editor/` | Case cycling, the `fill-column` line, the current line, wheel glide, scroll limit, Evil's normal state on save, `q` closing menus, the mode line, tabs per window, the `Option+Enter` menu |
| `config/emacs.el` | Garbage collection |
| `config/examples.el`, `examples/` | The examples and their screenshots |
| `config/excalidraw.el`, `excalidraw/` | Drawings |
| `config/git.el` | `SPC g d` diff pane |
| `config/lsp.el`, `lsp/` | Language server tweaks, `kotlin-lsp`, the usages peek |
| `config/long-lines.el` | Files with very long lines: plain, unwrapped, a notice |
| `config/magit.el` | Commit graph, delta diffs, TODOs |
| `config/markdown.el`, `markdown/` | Live preview; GitHub's alerts in it |
| `config/merge.el`, `merge/` | Three-pane conflict resolution |
| `config/pdf.el`, `pdf/` | PDFs |
| `config/navigation.el` | `Cmd+B`, jumps back and forward, previous / next buffer |
| `config/profiling.el`, `profiling/` | `SPC h T` profiles, written for an agent to read |
| `config/projectile.el` | Projects |
| `config/search.el`, `search/` | Search Everywhere, find in files |
| `config/spell.el`, `dict/tech.txt` | Spelling with programming words |
| `config/stripe.el`, `stripe/` | Error stripe |
| `config/sticky.el` | Sticky header |
| `config/terminal.el` | Terminal Emacs |
| `config/tiling.el`, `tiling/` | Tiling |
| `config/tree-sitter.el` | Tree-sitter grammars built ahead of time |
| `config/treemacs.el`, `treemacs/` | Sidebar |
| `config/webkit.el`, `webkit/` | Web pages in Emacs, for PDFs, drawings and the preview |
| `config/window.el` | Frame, fringes, focus of new windows |
| `.claude/skills/` | Skills for Claude: `emacs-profiling` reads a profile |
| `cmd/` | Shell commands (`diff.sh`) |
| `scripts/` | Installers (`emacs.sh`, `tools.sh`, `lsp.sh`), `dict.sh`, `screenshots.sh` |
| `tests/` | Tests (`tests/run.sh`) |
| `docs/` | These docs |

A large feature is a file and a folder: `config/NAME.el` has its settings and keys only, and loads its code from
`config/NAME/`.
