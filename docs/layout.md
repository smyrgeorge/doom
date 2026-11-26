# Repository layout

What each file and folder of this config is for.

| Path | What |
|---|---|
| `init.el`, `packages.el` | Doom modules and extra packages |
| `config.el` | The main config; loads `config/` |
| `config/agent-shell.el`, `agent-shell/` | [Your agent](agent-shell.md) (Claude Code, Codex...), drawing for it, its issues |
| `config/agent-ui.el` | [Agent UI](agent-ui.md): this config's layer over the agent-ui package (what the agent shows beyond its replies) |
| `config/agent-workspace.el`, `agent-workspace/` | [Agent workspace](agent-workspace.md): a crew of agents on one project, each in its own worktree (being built) |
| `config/agent-workflow.el`, `agent-workflow/` | [Agent workflow](agent-workflow.md): the work on an issue in jobs and steps, some an LLM (being built) |
| `config/notify.el`, `notify/` | [Notifications](notifications.md) on the desktop while Emacs isn't in front |
| `config/banner.el`, `banner/` | [Notices](editor.md#notices) |
| `config/beads.el`, `beads/` | [Issues](issues.md): Beads, mended for bd 1.x |
| `config/editor.el`, `editor/` | [The editor](editor.md): tabs, `Option+Enter`, `Cmd+B`, the sticky header, spelling |
| `config/emacs.el`, `emacs/` | Emacs itself: what differs between macOS and Linux ([the keys](keybindings.md), other apps, the clipboard's images, notifications), the frame, focus of new windows, frames laid over a window (notices, the error stripe), Emacs [in a terminal](terminal.md), garbage collection, [profiling](agent-shell.md#profiling-emacs), this config byte-compiled when Emacs is idle |
| `config/examples.el`, `examples/` | [Examples](examples.md) and their screenshots |
| `config/excalidraw.el`, `excalidraw/` | [Drawings](drawings.md) |
| `config/git.el`, `git/` | [Magit](git.md#magit), [a file's diff](git.md#file-diff) |
| `config/lsp.el`, `lsp/` | [Language servers](editor.md#language-servers) (each language's settings: `lsp/LANGUAGE.el`), the usages peek |
| `config/markdown.el`, `markdown/` | [Live preview](markdown.md) |
| `config/mermaid.el`, `mermaid/` | [Mermaid](mermaid.md): mermaid-mode, diagrams in the theme's colours |
| `config/html.el` | HTML files: a [notice](editor.md#notices) to open them in the browser; a page in WebKit (`+my/html-open-in-emacs`) |
| `config/image.el`, `image/` | [Images](images.md): the viewer, its toolbar, an image beside its version in Git's HEAD |
| `config/merge.el`, `merge/` | [Resolving conflicts](git.md#resolving-conflicts) |
| `config/pdf.el`, `pdf/` | [PDFs](pdf.md) |
| `config/projectile.el`, `projectile/` | [Projects](search.md#projects) |
| `config/search.el`, `search/` | [Search](search.md) |
| `config/stripe.el`, `stripe/` | [Error stripe](editor.md#error-stripe) |
| `config/tiling.el`, `tiling/` | [Tiling](editor.md#tiling) |
| `config/treemacs.el`, `treemacs/` | [Sidebar](sidebar.md) |
| `config/webkit.el`, `webkit/` | Web pages in Emacs: PDFs, drawings, the Markdown preview |
| `skills/` | [Agent skills](ai-agents.md): `emacs-profiling` reads a profile, `agent-ui` shows things on the canvas |
| `cmd/` | [Shell commands](cmd.md) |
| `dict/tech.txt` | Programming words for spelling, built by `scripts/dict.sh` |
| `scripts/` | Installers (`emacs.sh`; `tools.sh`: what `init.el` and this config need; `os.sh`: Homebrew, apt or dnf), `upgrade.sh` (Doom's packages, the pinned ones too, [tested](../README.md#keeping-it-up-to-date)), `dict.sh`, `screenshots.sh` |
| `tests/` | [Tests](tests.md); `tests/linux/`: the same on Linux, in Docker |
| `.github/workflows/tests.yml` | The tests on each push, on Linux and macOS ([Tests](tests.md#on-github)) |
| `.beads/` | This config's own [issues](issues.md); `hooks/post-commit` syncs them with their Dolt remote (`sync.remote` in `config.yaml`) on each commit |
| `.agent-workflow/` | This config's own [agent workflows](agent-workflow.md#this-configs-own) (`screenshots`, `github`), their profiles and scripts |

A large feature is a file and a folder. `config/NAME.el` holds its settings and keys, and loads its code from
`config/NAME/`.
