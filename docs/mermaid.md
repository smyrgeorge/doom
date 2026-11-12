# Mermaid

[Mermaid](https://mermaid.js.org) diagrams. `.mmd` and `.mermaid` files open in mermaid-mode: flowcharts' and sequence
diagrams' keywords coloured, `TAB` indenting. Its commands draw the diagram as an SVG with `mmdc` (mermaid-cli;
`scripts/tools.sh` installs it), in the theme's colours, in the background: the SVG opens once drawn (a second or so),
and an error shows Mermaid's message. ```` ```mermaid ```` blocks are coloured too, in Markdown files
and in Claude Code's replies.

| Key | Action |
|---|---|
| `SPC m c` | Draw the file as an SVG next to it, and open it |
| `SPC m b` / `SPC m r` | Draw the buffer / the region |
| `SPC m f` | Draw a file you pick |
| `SPC m o` | Open the buffer (or the region) in Mermaid's Live Editor, in the browser |
| `SPC m d` | Mermaid's docs |

In Org, a `#+begin_src mermaid :file flow.svg` block draws with `C-c C-c`, in the theme's colours too.

## The theme's colours

Diagrams take their colours from the current theme's faces, and their font from the editor's. After a theme switch,
the next diagram drawn is in the new theme's colours.

| Face | Gives |
|---|---|
| `default` | Text, lines (dimmed), groups' boxes (a tint), the background behind edges' labels |
| `font-lock-keyword-face` | Nodes: their border, and a tint of it as their fill |
| `font-lock-function-name-face` | Secondary shapes: their border and fill |
| `shadow` | Groups' borders (subgraphs), lifelines, done tasks, a chart's grid |
| `warning` | Notes |
| `error` | Errors, critical tasks, today's line in a Gantt chart |
| The syntax colours | A series: a pie's slices, a git graph's branches, a mindmap's levels, a chart's lines |
