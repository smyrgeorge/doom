# The editor

## Tabs per window

Each window has its own tabs: the files shown in it. A file closes once no window has it as a tab.

| Key | Action |
|---|---|
| `gt` / `gT` | Next / previous tab |
| `Cmd+1`..`Cmd+8`, `Cmd+9` | Tab 1 to 8, the last tab |
| `Cmd+W`, middle click | Close the tab, and the window with its last tab |
| Right click | Close the others, split vertically / horizontally |

## Tiling

`SPC w SPC` opens a new pane where the tiling strategy puts it, and `SPC w a` arranges the panes again. The `tall`
strategy keeps the main pane on the left and stacks the others on the right. Try it: `M-x +my/example-tiling`.

## Error stripe

A strip at the right edge of a file's window maps the whole file: errors, warnings, git changes and the part on screen.
Click a mark to jump to it, drag the band to scroll. Try it: `M-x +my/example-stripe`.

## Notices

Notices at the top of a window, with action buttons. Markdown files offer the [live preview](markdown.md); files with
lines over 5,000 characters open plain, and offer to wrap them or open them normally. Try it: `M-x +my/example-banner`.

## Sticky header

The header line shows the classes and functions the top line is inside (`class Api { › fun call(x: Int) {`); in
Markdown, the headings.

## Code

| Key | Action |
|---|---|
| `Cmd+B` | Go to the declaration; on the declaration, list the usages |
| `Cmd+[` / `Cmd+]` | Back / forward |
| `Option+Enter` | Spelling fixes, code actions and [Claude](claude-code.md), in one menu |
| `SPC c ~` | Cycle the word through snake_case, UPPER_CASE, PascalCase, camelCase and kebab-case |

Spelling knows ~40k programming words and checks camelCase words part by part.

## Behaviour

- New windows take focus; `SPC w S` / `SPC w V` split and leave it.
- Saving returns to normal state.
- `q` closes transient menus.
- A thin line marks column 120, or a project's `.editorconfig` `max_line_length`.
