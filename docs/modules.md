# Modules and languages

## Enabled modules

See `init.el` for the full list. Notable choices:

| Group | Modules |
|---|---|
| `:completion` | `(corfu +orderless +icons)`, `(vertico +icons)` |
| `:ui` | `dashboard`, `indent-guides`, `ligatures`, `(smooth-scroll +interpolate)`, `(treemacs +lsp)`, `(vc-gutter +pretty)`, `(window-select +numbers)`, `workspaces` |
| `:editor` | `(evil +everywhere)`, `(format +onsave +lsp)`, `multiple-cursors`, `snippets`, `(whitespace +guess +trim)` |
| `:emacs` | `(dired +dirvish +icons)`, `(ibuffer +icons)`, `undo`, `vc` |
| `:term` | `(ghostel +everywhere)` |
| `:checkers` | `(syntax +childframe +icons)`, `(spell +everywhere)` |
| `:tools` | `(lsp +peek)`, `tree-sitter`, `magit`, `(debugger +lsp)`, `(docker +lsp +tree-sitter)`, `make` |
| `:os` | `macos`, `(tty +osc)` |

Not enabled: `tabs` (centaur-tabs), replaced by [tabs per window](editor.md#tabs-per-window) (`config/tabs.el`);
`nav-flash`, which blinked the cursor line after every buffer or window switch; `pdf` (pdf-tools), replaced by
[PDFs in WebKit](editor.md#pdfs-in-webkit) (`config/pdf-xwidget.el`).

## Languages and tooling

All languages use LSP and tree-sitter where available. The servers and formatters come from `scripts/lsp.sh`, except
`clangd` (Xcode Command Line Tools) and GDScript's server, which is the Godot editor itself (keep it open on the
project). The scripts also install LaTeX tools (`basictex`, `texlab`), though `:lang latex` is off.

| Language | Module flags | Language server / tools |
|---|---|---|
| Rust | `+lsp +tree-sitter` | `rust-analyzer`, `rustfmt` |
| Python | `+lsp +pyright +uv +tree-sitter` | `pyright`, `black`, `isort`, virtualenvs via `uv` |
| Kotlin | `+lsp +tree-sitter` | `kotlin-lsp` (JetBrains), `ktlint` |
| JavaScript/TypeScript | `+lsp +tree-sitter` | `typescript-language-server`, `prettier` |
| C/C++ | `+lsp +tree-sitter` | `clangd` (Xcode CLT), `clang-format`, `glslang` |
| Shell | `+lsp` | `bash-language-server`, `shellcheck`, `shfmt` |
| Web (HTML/CSS) | `+lsp +tree-sitter` | `vscode-langservers-extracted`, `js-beautify`, `prettier` |
| Markdown | `+lsp +tree-sitter` | `marksman` (pulls in .NET), `pandoc` for previews |
| Docker | `+lsp +tree-sitter` | `dockerfile-language-server-nodejs` |
| GDScript (Godot) | `+lsp +tree-sitter` | Godot's LSP, `gdformat` (`gdtoolkit`) |
| JSON / YAML | `+lsp +tree-sitter` | `vscode-langservers-extracted`, `yaml-language-server` |
| Emacs Lisp | — | Emacs itself |
| Org | `+pretty` | — |
| REST | `+jq` | `jq` |
| CSV / XML | `data` | — |

## Known `doom doctor` warnings

These are expected and safe to ignore:

| Warning | Why it's fine |
|---|---|
| `Symbola` font not found | Symbola is no longer freely available; Symbols Nerd Font Mono covers most symbols. |
| `Couldn't find dockfmt` | The check uses an outdated name; Docker formatting isn't used here. |
| `Couldn't find nosetests` | nose is unmaintained; use pytest. |
| `Couldn't find stylelint` | CSS is checked by the CSS language server; install stylelint per project if a project uses it. |
