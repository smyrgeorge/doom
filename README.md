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
| `config/stripe.el`    | IntelliJ-like error stripe: git changes and errors across the file, at the right edge. |
| `config/window.el`    | Maximized frame; new windows (splits, panes) get focus.                           |
| `config/treemacs.el`  | Treemacs sidebar behaviour (auto-open, follow, git status, window keys).          |
| `config/markdown.el`  | Live Markdown preview inside Emacs.                                               |
| `config/tabs.el`      | Tab labels that show the path when two open files share a name.                  |
| `config/actions.el`   | Option+Enter context-actions menu (spelling, LSP code actions, Claude).           |
| `config/magit.el`     | Magit add-ons: git-delta diffs, TODOs in the status buffer.                       |
| `config/editor.el`    | Editing helpers: `SPC c ~` cycles the case style of the word at point.            |
| `config/evil.el`      | Evil tweaks: saving returns to normal state.                                      |
| `config/spell.el`     | Spell checking: tech-words dictionary, camelCase splitting, personal dictionary.  |
| `dict/tech.txt`       | ~40k programming words for the spell checker (built by `scripts/dict.sh`).        |
| `config/agent-shell.el` | Claude Code in Emacs (agent-shell): login, default agent, `SPC o c` / `SPC o C`. |
| `config/lsp.el`       | Language servers: projects imported without asking; JetBrains' `kotlin-lsp`.      |
| `config/projectile.el` | Projects under `~/dev`; project file list without a cache.                      |
| `config/search.el`    | `SPC s a`: Search Everywhere, like IntelliJ; `Cmd+Shift+F`: find in files (rg).   |
| `config/git.el`       | `SPC g d`: the current file's git diff in a side pane.                            |
| `config/terminal.el`  | Terminal Emacs: paint the terminal background with the theme colour.              |
| `scripts/emacs.sh`    | Installs Emacs (emacs-plus cask) and runs `doom sync`.                            |
| `scripts/tools.sh`    | CLI tools, fonts (JetBrains Mono, Nerd Font symbols), pdf-tools build deps, the `claude-agent-acp` bridge. |
| `scripts/lsp.sh`      | Language servers, formatters and linters.                                         |
| `scripts/dict.sh`     | Rebuilds `dict/tech.txt` from cspell's word lists (needs `npm`, `aspell`).        |

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
- `h`/`←` collapse, `l`/`→` expand or open. A **single click** opens a file or expands/collapses a folder (treemacs'
  default is a double click).
- `zR` / `zM` (`M-x treemacs-expand-all` / `treemacs-collapse-all`): expand every folder of the project, or collapse
  them all (the project stays open at its top level). Expanding asks first in projects with more than 300 folders.
- With `+lsp`: structure view (`SPC c S`), project errors (`SPC c X`) and call hierarchy (`SPC c y` / `SPC c Y`).

### Live Markdown preview

`config/markdown.el` renders Markdown in a WebKit side window (xwidgets) **inside Emacs**:

- **Updates as you type** (≈0.3 s after you stop), swapping the page content without reloading.
- **Scrolls to the cursor line**, using pandoc's `sourcepos` extension to map each element back to its source line.
- **GitHub look**: github-markdown-css plus highlight.js, following the macOS light/dark setting.
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
- where several fall on the same row, the most important wins: error > warning > deleted > changed > added;
- a light band marks the part of the file on screen, like a scrollbar thumb.

When the end of the file is on screen, the strip covers only the rows with text (the whole file mapped onto them);
the empty rows below keep Emacs' usual `~`.

Click the strip to jump to that part of the file; the mouse wheel scrolls as usual. Info-level hints are left out
(`+my/stripe-diagnostic-levels`). Doom's `smooth-scroll` module is off: scrolling by pixels moves the margin with the
text, which made the strip wobble; scrolling whole lines keeps it still.

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

### Other customizations

- **Font:** JetBrains Mono with ligatures.
- **Kotlin:** JetBrains' official [`kotlin-lsp`](https://github.com/Kotlin/kotlin-lsp) instead of the community
  `kotlin-language-server`; with `format +lsp`, Kotlin is formatted by IntelliJ's formatter.
- **Magit:** diffs rendered with [`git-delta`](https://github.com/dandavison/delta) through `magit-delta`.
- **File diff pane:** `SPC g d` shows the current file's changes vs `HEAD` (delta-rendered) in a pane on the right and
  moves the cursor there, onto the hunk of the line you were on. It refreshes on save and switches to another file
  when pressed there. In the pane: `s`/`u`/`x` stage/unstage/discard a hunk, `RET` jumps to the line, `SPC g d` or
  `q` closes it. Opening it saves the buffer.
- **Tabs:** same-named files get the shortest distinguishing path as their tab label (`crate-a/src/lib.rs` vs
  `crate-b/src/lib.rs`) instead of `lib.rs<2>`. Buffer names are untouched, since workspaces disable uniquify.
- **Terminal background:** in terminal Emacs, the strip below the echo area is painted with the theme background
  (OSC 11) and restored on exit (OSC 111).
- **`M-[` / `M-]`** switch buffers in the GUI only; in a terminal they would swallow mouse/focus escape sequences.
- **Spelling in code:** besides English and your personal dictionary, spell-fu knows ~40k programming words
  (`rect`, `rgba`, `async`, `kotlin`, `stdout`, ...) from `dict/tech.txt`, built by `scripts/dict.sh` from
  [cspell](https://github.com/streetsidesoftware/cspell-dicts)'s MIT-licensed dictionaries (only words English lacks).
  CamelCase identifiers are checked word by word (`AgreementController` = `Agreement` + `Controller`). Words you add
  with `zg` or Option+Enter still go to the personal dictionary.
- **LSP project import:** opening a file in a project starts its language server in the project root (the git
  repository) without the "import project root?" prompt, like Zed. Files outside any project still ask, so a stray
  file in `~` never makes a server scan your home folder (`config/lsp.el`).
- **LSP file watchers:** lsp-mode watches every directory under the project root but doesn't read `.gitignore`;
  `config/lsp.el` also skips what git ignores, so a root with big ignored folders (e.g. repositories cloned inside
  it) needs a few dozen watches instead of thousands, without the "watch N directories?" prompt.
- **Markdown links:** marksman calls a link "ambiguous" when the linked file has more than one top-level `#` heading;
  `config/markdown.el` hides that warning when the link is a path to an existing file (genuinely ambiguous links,
  like `[[README]]` matching several files, are still reported).
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
| `SPC g d`                   | Current file's git diff in a pane on the right (again in the pane: close) |
| `SPC o c`                   | Start Claude Code (agent-shell)                        |
| `SPC o C`                   | Pick / switch agent shell                              |
| `SPC m p` (Markdown)        | Toggle live preview inside Emacs                       |
| `SPC m P` (Markdown)        | Preview in the browser                                 |
| `SPC o p` / `SPC o P`       | Toggle treemacs / reveal current file in treemacs      |
| `h` `←` / `l` `→` (treemacs) | Collapse / expand or open                              |
| `zR` / `zM` (treemacs)      | Expand / collapse all folders                          |
| `M-[` / `M-]` (GUI)         | Previous / next buffer                                 |
| `s-[` / `s-]`               | Jump back / forward (better-jumper)                    |

## Enabled modules

See `init.el` for the full list. Notable choices:

| Group         | Modules                                                                                                   |
|---------------|-----------------------------------------------------------------------------------------------------------|
| `:completion` | `(corfu +orderless +icons)`, `(vertico +icons)`                                                            |
| `:ui`         | `dashboard`, `indent-guides`, `ligatures`, `tabs`, `(treemacs +lsp)`, `(vc-gutter +pretty)`, `(window-select +numbers)`, `workspaces` |
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

## Known `doom doctor` warnings

These are expected and safe to ignore:

| Warning                         | Why it's fine                                                                                   |
|---------------------------------|-------------------------------------------------------------------------------------------------|
| `Symbola` font not found        | Symbola is no longer freely available; Symbols Nerd Font Mono covers most symbols.              |
| `Couldn't find dockfmt`         | The check uses an outdated name; Docker formatting isn't used here.                             |
| `Couldn't find nosetests`       | nose is unmaintained; use pytest.                                                               |
| `Couldn't find stylelint`       | CSS is checked by the CSS language server; install stylelint per project if a project uses it. |
