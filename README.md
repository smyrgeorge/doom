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
git clone git@github.com:smyrgeorge/.doom.d.git ~/.config/doom

# 2. Doom itself
git clone --depth 1 https://github.com/doomemacs/core ~/.config/emacs

# 3. Emacs (prebuilt emacs-plus Emacs.app) + `doom sync`
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
| `config/treemacs.el`  | Treemacs sidebar behaviour (auto-open, follow, git status, window keys).          |
| `config/markdown.el`  | Live Markdown preview inside Emacs.                                               |
| `config/tabs.el`      | Tab labels that show the path when two open files share a name.                  |
| `config/terminal.el`  | Terminal Emacs: paint the terminal background with the theme colour.              |
| `scripts/emacs.sh`    | Installs Emacs (emacs-plus cask) and runs `doom sync`.                            |
| `scripts/tools.sh`    | CLI tools, JetBrains Mono font, the `claude-agent-acp` bridge.                    |
| `scripts/lsp.sh`      | Language servers, formatters and linters.                                         |

## Highlights

### Project sidebar (treemacs)

`config/treemacs.el` makes treemacs behave like IntelliJ's project view:

- **Opens automatically** the first time a project file is shown in a workspace (`SPC p p`, `SPC SPC`, `SPC f r`, the
  dashboard...). Close it with `SPC o p` and it stays closed for that workspace.
- **Follows the current buffer**: highlights the open file and switches to the buffer's project.
- **Git status** colours for files and folders, computed asynchronously. Saving a file refreshes its status (macOS's
  kqueue file notifications miss in-place edits, so this is done explicitly on save).
- **Reachable like any window**: `SPC w w` cycles into it and it gets a window number (`SPC w 1`, as the leftmost
  window).
- `h`/`←` collapse, `l`/`→` expand or open.
- With `+lsp`: structure view (`SPC c S`), project errors (`SPC c X`) and call hierarchy (`SPC c y` / `SPC c Y`).

### Live Markdown preview

`config/markdown.el` renders Markdown in a WebKit side window (xwidgets) **inside Emacs**:

- **Updates as you type** (≈0.3 s after you stop), swapping the page content without reloading.
- **Scrolls to the cursor line**, using pandoc's `sourcepos` extension to map each element back to its source line.
- **GitHub look**: github-markdown-css plus highlight.js, following the macOS light/dark setting.
- Math is rendered as MathML; relative image links work.
- In terminal Emacs it falls back to markdown-mode's `eww` preview (updates on save).

Requires `pandoc`. Styles are loaded from a CDN, so the preview is unstyled offline.

### Claude Code in Emacs

[`agent-shell`](https://github.com/xenodium/agent-shell) runs Claude Code (via the Agent Client Protocol) in a native
Emacs buffer — evil keys, search and copy work as usual. It uses the Claude CLI login. `C-u M-x agent-shell` starts a
second, parallel session.

### Other customisations

- **Font:** JetBrains Mono with ligatures.
- **Kotlin:** JetBrains' official [`kotlin-lsp`](https://github.com/Kotlin/kotlin-lsp) instead of the community
  `kotlin-language-server`; with `format +lsp`, Kotlin is formatted by IntelliJ's formatter.
- **Magit:** diffs rendered with [`git-delta`](https://github.com/dandavison/delta) through `magit-delta`.
- **Tabs:** same-named files get the shortest distinguishing path as their tab label (`crate-a/src/lib.rs` vs
  `crate-b/src/lib.rs`) instead of `lib.rs<2>`. Buffer names are untouched, since workspaces disable uniquify.
- **Terminal background:** in terminal Emacs, the strip below the echo area is painted with the theme background
  (OSC 11) and restored on exit (OSC 111).
- **`M-[` / `M-]`** switch buffers in the GUI only; in a terminal they would swallow mouse/focus escape sequences.
- **Evil:** saving a buffer returns to normal state.
- **Projectile:** projects are discovered under `~/dev`.

## Custom key bindings

Everything else is Doom's default (`SPC h b b` lists all bindings).

| Key                         | Action                                                 |
|-----------------------------|--------------------------------------------------------|
| `SPC o c`                   | Start Claude Code (agent-shell)                        |
| `SPC o C`                   | Pick / switch agent shell                              |
| `SPC m p` (Markdown)        | Toggle live preview inside Emacs                       |
| `SPC m P` (Markdown)        | Preview in the browser                                 |
| `SPC o p` / `SPC o P`       | Toggle treemacs / reveal current file in treemacs      |
| `h` `←` / `l` `→` (treemacs) | Collapse / expand or open                              |
| `M-[` / `M-]` (GUI)         | Previous / next buffer                                 |
| `s-[` / `s-]`               | Jump back / forward (better-jumper)                    |

## Enabled modules

See `init.el` for the full list. Notable choices:

| Group         | Modules                                                                                                   |
|---------------|-----------------------------------------------------------------------------------------------------------|
| `:completion` | `(corfu +orderless +icons)`, `(vertico +icons)`                                                            |
| `:ui`         | `dashboard`, `indent-guides`, `ligatures`, `(smooth-scroll +interpolate)`, `tabs`, `(treemacs +lsp)`, `(vc-gutter +pretty)`, `(window-select +numbers)`, `workspaces` |
| `:editor`     | `(evil +everywhere)`, `(format +onsave +lsp)`, `multiple-cursors`, `snippets`, `(whitespace +guess +trim)`  |
| `:emacs`      | `(dired +dirvish +icons)`, `(ibuffer +icons)`, `undo`, `vc`                                                |
| `:term`       | `(ghostel +everywhere)`                                                                                   |
| `:checkers`   | `(syntax +childframe +icons)`, `(spell +flyspell +everywhere)`                                            |
| `:tools`      | `(lsp +peek)`, `tree-sitter`, `magit`, `(debugger +lsp)`, `(docker +lsp +tree-sitter)`, `pdf`, `make`     |
| `:os`         | `macos`, `(tty +osc)`                                                                                     |

## Languages and tooling

All languages use LSP and tree-sitter where available. Most servers and formatters are installed by `scripts/lsp.sh`;
the rest are installed by lsp-mode itself, which offers to do so the first time you open such a file
(`M-x lsp-install-server`).

| Language              | Module flags                         | Language server / tools                                  |
|-----------------------|--------------------------------------|----------------------------------------------------------|
| Rust                  | `+lsp +tree-sitter`                  | `rust-analyzer`                                          |
| Python                | `+lsp +pyright +uv +tree-sitter`     | `pyright`, `black`, virtualenvs via `uv`                 |
| Kotlin                | `+lsp +tree-sitter`                  | `kotlin-lsp` (JetBrains), `ktlint`                       |
| JavaScript/TypeScript | `+lsp +tree-sitter`                  | `typescript-language-server` (installed by lsp-mode)     |
| C/C++                 | `+lsp +tree-sitter`                  | `clangd` (Xcode CLT), `clang-format`, `glslang`          |
| Shell                 | `+lsp`                               | `bash-language-server`, `shfmt`                          |
| Web (HTML/CSS)        | `+lsp +tree-sitter`                  | `vscode-langservers-extracted`, `js-beautify`            |
| Markdown              | `+lsp +tree-sitter`                  | `marksman` (pulls in .NET), `pandoc` for previews        |
| Docker                | `+lsp +tree-sitter`                  | `dockerfile-language-server-nodejs`                      |
| GDScript (Godot)      | `+lsp +tree-sitter`                  | Godot's LSP, `gdformat` (`gdtoolkit`)                    |
| JSON / YAML           | `+lsp +tree-sitter`                  | JSON: `vscode-langservers-extracted`; YAML: lsp-mode     |
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

## Known `doom doctor` warnings

These are expected and safe to ignore:

| Warning                         | Why it's fine                                                                                   |
|---------------------------------|-------------------------------------------------------------------------------------------------|
| `Symbola` font not found        | Symbola is no longer freely available; Symbols Nerd Font Mono covers most symbols.              |
| `Couldn't find dockfmt`         | The check uses an outdated name; Docker formatting isn't used here.                             |
| `Couldn't find nosetests`       | nose is unmaintained; use pytest.                                                               |
| `Couldn't find stylelint`       | CSS is checked by the CSS language server; install stylelint per project if a project uses it. |
