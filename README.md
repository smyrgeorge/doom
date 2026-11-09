# doom

[![Tests](https://github.com/smyrgeorge/doom/actions/workflows/tests.yml/badge.svg)](https://github.com/smyrgeorge/doom/actions/workflows/tests.yml)

My Emacs configuration, built on [Doom Emacs](https://github.com/doomemacs/core) with Vim keys.

It runs on **macOS** and **Linux** with **Emacs 31**, as a GUI app or in a terminal (`emacs -nw`). On top of Doom it
adds a tiling layout, tabs per window, a three-way merge for Git conflicts, PDFs, images and Excalidraw drawings that
open inside Emacs, a live Markdown preview, language servers set up for each language `init.el` enables, and Claude
Code in a pane of its own. The keys use `Cmd` on macOS and `Ctrl` on Linux, as each system's apps do.

## A tour

Each feature below opens on files of its own with `M-x +my/example-NAME`, so you can try it without a project of your
own ([Examples](docs/examples.md)).

### Tiling

Applications (Claude Code, the terminal, Magit, the Markdown preview, drawings, issues) open in a new pane where the
tiling layout puts it: the main pane on the left, the others stacked on the right. Files open as tabs in the current
pane, and a pane closes with its last tab. `SPC w SPC` opens a pane the same way ([more](docs/editor.md#tiling)).

![Tiling](examples/tiling.png)

### Three-way merge

`e` on a conflicted file in Magit shows Yours, the Result and Theirs side by side, lined up and scrolling together.
Take a change with `>>` / `<<`, ignore it with `x`, or let the ✨ wand merge the words of both sides. It works in a
terminal too, and from the shell with `cmd/diff.sh` ([more](docs/git.md#resolving-conflicts)).

![Three-way merge](examples/merge.png)

### Excalidraw drawings

`*.excalidraw.svg` files open as drawings in Excalidraw, inside Emacs, and are saved as images that Markdown and
GitHub show. In a Claude Code session, `C-c C-d` draws something for Claude to see ([more](docs/drawings.md)).

![Excalidraw](examples/excalidraw.png)

### PDFs

PDFs open in their tab, drawn by PDF.js: sharp at any zoom, with Vim keys, search and an outline. Pages are dark,
their colours' hues kept, and `SPC m d` turns them light ([more](docs/pdf.md)).

![PDF with dark pages](examples/pdf.png)

### Images

Images open with a toolbar: the folder's other images, zoom, rotate, flip, crop, sharp pixels, copy the image, and its
version in Git's HEAD beside it with `SPC m g` ([more](docs/images.md)).

![A picture beside its version in git's HEAD](examples/image.png)

### Markdown preview

`SPC m p` shows the rendered file beside it, in GitHub's style, updated as you type and following the cursor
([more](docs/markdown.md)).

![Markdown live preview](examples/markdown.png)

### Issues

`SPC o i` lists the project's issues, tracked with [Beads](https://github.com/gastownhall/beads) in its `.beads/`,
the same ones Claude Code and other agents read and write: filter them, preview them as you move, edit them, follow
their dependencies ([more](docs/issues.md)).

### Agent UI

Claude Code keeps things in view on a canvas beside its session while it works: a checklist of its steps, a table of
test results filling in, a build's progress bar, charts (SVG in the GUI, characters in a terminal), each updated in
place. It draws them with `cmd/agent-ui.sh`, which its system prompt tells it about ([more](docs/agent-ui.md)).

### Error stripe and notices

A strip at the right edge of each file maps the whole file: errors, warnings, TODOs and Git changes, with a band for
the part on screen. Click a mark to jump there. Notices at the top of a window offer actions, such as the Markdown
preview ([more](docs/editor.md#error-stripe)).

![The error stripe at the window's right edge](examples/stripe.png)

## Installation

| | macOS | Linux |
|---|---|---|
| System | Apple Silicon, macOS 15 or later | Debian, Ubuntu or Fedora; X11 or Wayland |
| Needs first | [Homebrew](https://brew.sh), `git` | `git`, `curl`, `sudo` |
| Emacs | emacs-plus's prebuilt Emacs.app | GNU's release, built from source |

```sh
# 1. This config, and Doom
git clone git@github.com:smyrgeorge/doom.git ~/.config/doom
git clone --depth 1 --recurse-submodules https://github.com/doomemacs/core ~/.config/emacs

# 2. Emacs, then Doom synced against it
~/.config/doom/scripts/emacs.sh

# 3. Everything init.el and this config need outside Emacs
~/.config/doom/scripts/tools.sh

# 4. Let the GUI app see your shell's PATH, then check the setup
~/.config/emacs/bin/doom env
~/.config/emacs/bin/doom doctor
```

**`emacs.sh`** installs Emacs 31, or updates it to the latest release, then runs `doom sync`. On macOS that's the
emacs-plus Emacs.app (it replaces Homebrew's terminal-only `emacs`). On Linux it builds GNU's latest release into
`/usr/local`, with WebKit for PDFs, drawings and the preview (`XWIDGETS=no` builds without it). When Emacs's version
changes, Doom's packages are rebuilt for it.

**`tools.sh`** installs Doom's own tools, the language servers, formatters and linters of the modules `init.el`
enables, and the config's fonts. A table at its top lists every tool and why it's there. If `init.el` enables a module
the table doesn't know, the script stops and names it, so a new language never goes without its tools.
`tools.sh --check` only reports what's installed and what's missing. It needs Emacs, so run `emacs.sh` first.

### Keeping it up to date

Run `scripts/emacs.sh` and `scripts/tools.sh` again: each brings what it installs to the latest version and leaves
alone what already is.

After changing `init.el` or `packages.el`, run `~/.config/emacs/bin/doom sync` and restart Emacs, and run
`scripts/tools.sh` if you enabled a module. Changes to `config.el` and `config/*.el` only need a restart.

### Once, by hand

- **Claude Code:** install the `claude` CLI, run it once in a terminal and log in; Emacs uses that login.
- **Kotlin:** accept kotlin-lsp's licence once: read it with `kotlin-lsp --show-eula`, then run `kotlin-lsp --stdio`.
- **Linux:** run `M-x nerd-icons-install-fonts` for the icons. `tools.sh` lists the few servers no distribution
  packages (marksman, kotlin-lsp, ktlint, lua-language-server), with where to get them.
- **iTerm** (terminal Emacs on macOS): in *Settings → Profiles → Text*, pick a Nerd Font (e.g. *JetBrainsMono Nerd
  Font*) and tick *Use ligatures*; in *Profiles → Keys*, set the left Option key to *Esc+* so `M-` keys work.

### On Linux

- **Without WebKit:** PDFs, drawings and the live preview need an Emacs with xwidgets, which `emacs.sh` builds but most
  distributions' packages lack. Without it they fall back: PDFs to DocView, drawings to their file, the preview to
  markdown-mode's.
- **Other apps:** macOS's Preview and Finder become the file's default app and your file manager. Printing goes through
  `lp`, copying images through `wl-copy` (Wayland) or `xclip` (X11), and rotating images through ImageMagick.
- **Keys:** Linux desktops keep many `Super` keys for themselves, so this config's keys there are `Ctrl` and
  `Ctrl+Shift` ones ([Key bindings](docs/keybindings.md)).

## Documentation

- [The editor](docs/editor.md): tabs per window, tiling, the error stripe, notices, the sticky header, code
- [Key bindings](docs/keybindings.md): this config's own keys, on macOS and Linux
- [Project sidebar](docs/sidebar.md): treemacs following the current file
- [Search](docs/search.md): Search Everywhere, find in files, projects
- [Git](docs/git.md): Magit additions, a file's diff, resolving conflicts in three panes
- [PDFs](docs/pdf.md), [Images](docs/images.md), [Drawings](docs/drawings.md), [Markdown](docs/markdown.md)
- [Claude Code](docs/claude-code.md): sessions, drawing for Claude, profiling Emacs
- [Agent UI](docs/agent-ui.md): what Claude shows on a canvas beside its session, and `cmd/agent-ui.sh`
- [Notifications](docs/notifications.md): on the desktop while you're in another app (Claude Code finished, needs you)
- [Issues](docs/issues.md): the project's Beads issues
- [AI agents](docs/ai-agents.md): the `emacs-profiling` skill
- [Terminal](docs/terminal.md): what differs in `emacs -nw`
- [Examples](docs/examples.md): each feature on files of its own, with screenshots
- [Shell commands](docs/cmd.md): `cmd/diff.sh`
- [Tests](docs/tests.md): unit and end-to-end tests, on macOS and Linux, on each push (GitHub Actions)
- [Repository layout](docs/layout.md): what each file is for
