# The editor

## Error stripe

A strip at the right edge of file windows maps the whole file: errors (red) and
warnings (yellow) from flycheck, git changes (red removed, orange changed, green added), and a band for the part on
screen. Click it to jump (`C-o` comes back), drag the band to scroll. `M-x +my/stripe-mode` turns it off in a buffer.
Try it: `M-x +my/example-stripe`.

## Notices

Notices at the top of a window: an icon and colour per kind (info, warning,
error), a message, actions and `✕`. Markdown files offer the live preview; files with very long lines say they're shown
plain, with **Wrap lines** and **Open normally**. From code: `(+my/banner-show ID TEXT :type 'warning :actions
'(("Label" . function)))`. Try it: `M-x +my/example-banner`.

## Sticky header

The header line shows the classes and functions the top line is inside (`class Api { › fun call(x: Int) {`), or the
file's path in its project; in Markdown, the headings.

## Tabs per window

Each window has its own tabs: the files shown in it. Closing a tab (`✕`, middle click,
`Cmd+W`) removes it from that window; closing the last one closes the window, and a file closes once no window has it
as a tab. Right-click a tab to close others or split it vertically / horizontally. `gt` / `gT` move between tabs,
`Cmd+1`..`Cmd+8` pick one, `Cmd+9` the last (workspaces move to `]w` / `[w` and `M-1`..`M-9`). Same-named files show
the shortest distinct path.

## Tiling

`SPC w SPC` opens a pane where the tiling strategy puts it, like Amethyst; `SPC w a` arranges the panes again. The
strategy, `tall`: the main pane on the left, the others stacked on the right. Try it: `M-x +my/example-tiling`.

## Windows and scrolling

- New windows (splits, the diff pane...) take focus; `SPC w S` / `SPC w V` split and leave it.
- A thin line marks `fill-column` (120); a project's `.editorconfig` (`max_line_length`) moves or removes it.
- A mouse wheel's notches glide, on top of Doom's pixel scrolling.
- Windows scroll past the end by a quarter of their height at most.
- Files with lines over 5,000 characters open plain and unwrapped, with a notice to undo it.

## Code

- `Cmd+B` goes to the declaration; on the declaration, it lists the usages.
  `Cmd+[` / `Cmd+]` go back and forward.
- `Option+Enter` (`M-RET`) opens one menu with what applies at point: spelling fixes, the language server's code
  actions, Claude (fix or explain the error, explain the selection, add it to the prompt), and the PDF and drawing
  actions. Org keeps `M-RET` for a new heading.
- The usages peek (`gD`) says what it lists, groups usages by the function they're in, and numbers the preview's lines.
- Spelling knows ~40k programming words (`dict/tech.txt`, built by `scripts/dict.sh`) and checks camelCase words part
  by part.
- Language servers start without asking to import the project and don't watch git-ignored folders. Kotlin uses
  JetBrains' `kotlin-lsp`.
- The enabled languages' tree-sitter grammars are built in the background after startup, not asked for on first use.
- `SPC c ~` cycles a word through snake_case, UPPER_CASE, PascalCase, camelCase and kebab-case.

## PDFs

PDFs open in their tab, drawn by PDF.js inside Emacs (Doom's pdf-tools is off): sharp at any zoom, smooth scrolling,
selectable text. They reopen where you left them, and splits scroll on their own. Try it: `M-x +my/example-pdf`.

| Key | Action |
|---|---|
| `j` / `k`, `C-d` / `C-u`, `gg` / `G` | Scroll, half a screen, top / bottom (`5G`: page 5) |
| `J` / `K` | Next / previous page |
| `/` / `?`, `n` / `N` | Search, next / previous match |
| `y` or `Cmd+C` | Copy the selection |
| `Cmd+=` / `Cmd+-` / `Cmd+0`, `W` / `P` | Zoom, 100%; fit the width / the page |
| `C-o` / `C-i` | Back / forward through jumps (links, the outline, searches) |
| `o` / `O` | Go to a heading / the sidebar (outline, thumbnails) |
| `SPC m d` / `SPC m t` | Dark pages / the toolbar |
| `Option+Enter` | Actions on the selection (copy, search, Claude); Preview, Print |
| `SPC m p` / `Cmd+P` | Open in Preview / print |
| `q` | Close |

## Drawings (Excalidraw)

`*.excalidraw.svg` and `*.excalidraw` files open in their tab as a drawing in Excalidraw; the `.svg` is an image that
Markdown and GitHub show as is. Excalidraw's own keys work (`?` lists them); Emacs keeps `SPC`, `:` and its own
shortcuts. Save as any file (`Cmd+S`). Try it: `M-x +my/example-excalidraw`.

| Key | Action |
|---|---|
| `Cmd+C` / `Cmd+X` / `Cmd+V` | Copy / cut / paste, through the kill ring |
| `SPC m d` | Dark canvas |
| `SPC m l` | Libraries (libraries.excalidraw.com, inside Emacs) |
| `SPC m r` | Read the file again |

The library is shared by all drawings and kept between sessions. In Markdown or Org, `Option+Enter` → **Insert a new
drawing** links a new one at point and opens it beside.

## Small things

- The mode line has a space after its last item.
- Saving returns to normal state.
- `q` closes transient menus, as `Esc` and `C-g` do (unless the menu uses `q`).
- Brackets are coloured by depth in code.
