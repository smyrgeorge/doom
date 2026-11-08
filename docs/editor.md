# The editor

## Tabs per window

Each window has its own tabs: the files shown in it. A file closes once no window has it as a tab.

| macOS | Linux | Action |
|---|---|---|
| `gt` / `gT` | `gt` / `gT` | Next / previous tab |
| `Cmd+1`..`Cmd+8`, `Cmd+9` | `Ctrl+1`..`Ctrl+8`, `Ctrl+9` | Tab 1 to 8, the last tab |
| `Cmd+W`, middle click | `Ctrl+Shift+W`, middle click | Close the tab, and the window with its last tab |
| Right click | Right click | Close the others, split vertically / horizontally |

## Tiling

Emacs is tiling first:

- Applications (Claude Code, the terminal, magit, the Markdown preview, drawings) open in a new pane where the tiling
  strategy puts it. Inside magit, a log or a diff stays in its pane; a commit opens in a new one.
- Files open as a tab in the current pane. From an application's pane, a popup or the sidebar, they open in the last
  pane of files.
- A pane closes with its last tab.

The `tall` strategy keeps the main pane on the left and stacks the others on the right. `SPC w SPC` opens a new pane
showing the current buffer, `SPC w a` arranges the panes again, and `SPC w RET` moves the current pane's buffer to the
main pane (the main's to its place). Try it: `M-x +my/example-tiling`.

Without `(load! "config/tiling")` in `config.el`, each opens where it would on its own.

![Tiled panes: the main one on the left, the others stacked on the right](../examples/tiling.png)

## Error stripe

A strip at the right edge of a file's window maps the whole file, as IntelliJ's does:
- diagnostics: errors (red), warnings (yellow), suggestions (dim yellow: LSP hints and information);
- TODO comments: `TODO`, `FIXME`, `HACK` (blue);
- git changes: added, changed and deleted lines, in the gutter's colours;
- the part on screen, a light band.

Where marks overlap the most important wins: error > warning > TODO > deleted > changed > added > suggestion.
Click a mark to jump to it, drag the band to scroll. Try it: `M-x +my/example-stripe`.

![The error stripe at the window's right edge](../examples/stripe.png)

## Notices

Notices at the top of a window, with action buttons. Markdown files offer the [live preview](markdown.md); files with
lines over 5,000 characters open plain, and offer to wrap them or open them normally. Try it: `M-x +my/example-banner`.

![Notices of each kind at the top of a window](../examples/banner.png)

## Sticky header

The header line shows the classes and functions the top line is inside (`class Api { › fun call(x: Int) {`); in
Markdown, the headings.

## Code

| macOS | Linux | Action |
|---|---|---|
| `Cmd+B` | `Ctrl+Shift+B` | Go to the declaration; on the declaration, list the usages |
| `Cmd+[` / `Cmd+]` | `Alt+←` / `Alt+→` | Back / forward (`C-o` / `C-i` on both) |
| `Option+Enter` | `Alt+Enter` | Spelling fixes, code actions and [Claude](claude-code.md), in one menu |
| `SPC c ~` | `SPC c ~` | Cycle the word through snake_case, UPPER_CASE, PascalCase, camelCase and kebab-case |

Spelling knows ~40k programming words and checks camelCase words part by part.

## Behaviour

- New windows take focus; `SPC w S` / `SPC w V` split and leave it.
- Saving returns to normal state.
- `q` closes transient menus.
- A thin line marks column 120, or a project's `.editorconfig` `max_line_length`.
