# Repository layout

| Path | What |
|---|---|
| `init.el`, `packages.el` | Doom modules and extra packages |
| `config.el` | The main config; loads `config/` |
| `config/agent-shell.el`, `agent-shell/` | [Claude Code](claude-code.md), drawing for it |
| `config/banner.el`, `banner/` | [Notices](editor.md#notices) |
| `config/cheatsheet.el`, `cheatsheet.org` | A tips panel under the sidebar (off) |
| `config/childframe.el` | Frames laid over a window: notices, the error stripe |
| `config/compile.el` | Byte-compiles this config when Emacs is idle |
| `config/editor.el`, `editor/` | [The editor](editor.md): tabs, `Option+Enter`, `Cmd+B`, the sticky header, spelling |
| `config/emacs.el` | Garbage collection |
| `config/examples.el`, `examples/` | [Examples](examples.md) and their screenshots |
| `config/excalidraw.el`, `excalidraw/` | [Drawings](drawings.md) |
| `config/git.el` | [File diff](git.md#file-diff) |
| `config/lsp.el`, `lsp/` | Language servers (each language's settings: `lsp/LANGUAGE.el`), the usages list |
| `config/magit.el` | [Magit](git.md#magit) |
| `config/markdown.el`, `markdown/` | [Live preview](markdown.md) |
| `config/merge.el`, `merge/` | [Resolving conflicts](git.md#resolving-conflicts) |
| `config/pdf.el`, `pdf/` | [PDFs](pdf.md) |
| `config/profiling.el`, `profiling/` | [Profiling](claude-code.md#profiling-emacs) |
| `config/projectile.el` | [Projects](search.md#projects) |
| `config/search.el`, `search/` | [Search](search.md) |
| `config/stripe.el`, `stripe/` | [Error stripe](editor.md#error-stripe) |
| `config/terminal.el` | [Terminal](terminal.md) |
| `config/tiling.el`, `tiling/` | [Tiling](editor.md#tiling) |
| `config/treemacs.el`, `treemacs/` | [Sidebar](sidebar.md) |
| `config/webkit.el`, `webkit/` | Web pages in Emacs: PDFs, drawings, the Markdown preview |
| `config/window.el` | The frame, fringes, focus of new windows |
| `skills/` | [Agent skills](ai-agents.md): `emacs-profiling` reads a profile |
| `cmd/` | [Shell commands](cmd.md) |
| `dict/tech.txt` | Programming words for spelling, built by `scripts/dict.sh` |
| `scripts/` | Installers (`emacs.sh`, `tools.sh`, `lsp.sh`), `dict.sh`, `screenshots.sh` |
| `tests/` | [Tests](tests.md) |

A large feature is a file and a folder: `config/NAME.el` holds its settings and keys, and loads its code from
`config/NAME/`.
