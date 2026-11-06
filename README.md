# doom

My Emacs configuration, built on [Doom Emacs](https://github.com/doomemacs/core).

> Doom is a configuration framework for GNU Emacs tailored for Emacs bankruptcy veterans who want less framework in their
> frameworks, a modicum of stability (and reproducibility) from their package manager, and the performance of a hand
> rolled config (or better).

It targets **macOS on Apple Silicon** with **Emacs 31** (emacs-plus), and aims for an IntelliJ-like workflow: a project
sidebar that follows the current file, LSP for every language I use, format-on-save, and Claude Code inside Emacs. It
works both as a GUI app and in the terminal (`emacs -nw`).

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

## Documentation

- [The editor](docs/editor.md): error stripe, notices, sticky header, tabs per window, current line, right margin,
  fringes, mode line, evil.
- [Project sidebar](docs/sidebar.md): treemacs that follows the current file, git status, IntelliJ-like arrows, LSP
  panels.
- [Smooth scrolling](docs/scrolling.md): mouse-wheel glide, scroll limit past the end, long lines.
- [Performance](docs/performance.md): compiled config, opening files faster.
- [Code](docs/code.md): Option+Enter actions, usages peek, code lenses, language servers, Kotlin, spelling in code.
- [Search](docs/search.md): Search Everywhere (`SPC s a`), find in files, projects.
- [Markdown](docs/markdown.md): live preview inside Emacs, Markdown links.
- [Git](docs/git.md): Magit, commit graph, file diff pane.
- [Claude Code in Emacs](docs/claude.md): agent-shell, what Claude is told about Emacs, images.
- [Terminal usage](docs/terminal.md): running in a terminal (`emacs -nw`).
- [Key bindings](docs/keybindings.md): this config's own keys.
- [Modules and languages](docs/modules.md): enabled Doom modules, languages and tooling, known `doom doctor` warnings.
- [Repository layout](docs/layout.md): what each file is for.
