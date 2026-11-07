# Drawings

`*.excalidraw.svg` and `*.excalidraw` files open in their tab in [Excalidraw](https://excalidraw.com). A
`.excalidraw.svg` is also an image that Markdown and GitHub show. Excalidraw's keys work (`?` lists them). Try it:
`M-x +my/example-excalidraw`.

![A drawing in Excalidraw, inside Emacs](../examples/excalidraw.png)

| Key | Action |
|---|---|
| `Cmd+S` | Save |
| `Cmd+C` / `Cmd+X` / `Cmd+V` | Copy / cut / paste, through the kill ring |
| `SPC m d` | Dark canvas |
| `SPC m l` | Browse libraries |
| `SPC m r` | Reload the file |

The library is shared by all drawings. In Markdown or Org, `Option+Enter` → **Insert a new drawing** links a new one at
point. In a Claude Code buffer, `C-c C-d` draws for Claude: see
[Drawing for Claude](claude-code.md#drawing-for-claude).
