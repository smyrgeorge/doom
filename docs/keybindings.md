# Key bindings

Everything else is Doom's default (`SPC h b b` lists all bindings).

| Key | Action |
|---|---|
| `M-RET` (Option+Enter) | Context actions at point or on the selection (spelling, code actions, Claude); not in Org (new heading) |
| `SPC s a` | Search Everywhere: classes, files, symbols, actions (IntelliJ's double Shift) |
| `Cmd+Shift+F` (GUI) | Find in files: search the project with ripgrep (selected text is the query) |
| `Cmd+B` (GUI) | Go to declaration, or on the declaration list its usages (IntelliJ's Go to Declaration or Usages); with a language server, also where it knows no declaration (e.g. a Markdown heading: the links to it) |
| `SPC g d` | Current file's git diff in a pane on the right (in the pane: `SPC g d`, `q` or `Esc` close) |
| `SPC o c` | Start a new Claude Code session (agent-shell) |
| `SPC o C` | The project's Claude Code session, started if none (`C-u`: a new one, `C-u C-u`: pick an open one) |
| `Cmd+=` (or `Cmd++`) / `Cmd+-` / `Cmd+0` (PDF) | Zoom in / out / 100% (elsewhere: font size) |
| `j` `k` `gg` `G` `J` `K` `/` `n` `y` `o` `O` `q`... (PDF) | Scroll, pages, search, copy, outline, close: see [PDFs in WebKit](editor.md#pdfs-in-webkit) |
| `SPC m d` / `SPC m t` (PDF) | Dark pages / the toolbar |
| `C-o` / `C-i`, `Option+Enter`, `SPC m p`, `Cmd+P` (PDF) | Back / forward, actions on the selection, Open in Preview, Print |
| `r` `o` `a` `t` `Delete` `Cmd+Z` `Cmd+A`... (drawing) | Excalidraw's keys, before Evil's: see [Drawings](editor.md#drawings-excalidraw) |
| `Cmd+C` / `Cmd+X` / `Cmd+V` (drawing) | Copy / cut / paste the selection through the kill ring |
| `SPC m d` / `SPC m r` (drawing) | Dark canvas / read the file again |
| `Option+Enter` (Markdown, Org) | Also: insert a new drawing, linked as an image; on a drawing's link, edit it |
| `SPC m p` (Markdown) | Toggle live preview inside Emacs |
| `SPC m P` (Markdown) | Preview in the browser |
| `j` `k` `C-d` `C-u` `gg` `G` `y` `q` (Markdown preview) | Scroll, copy the selection, close the preview |
| `SPC o p` / `SPC o P` | Toggle treemacs / reveal current file in treemacs |
| `Cmd+W` (GUI) | Close the current tab, like its ✕ (without tabs, e.g. popups: the window) |
| `Cmd+1`..`Cmd+8` / `Cmd+9` (GUI) | Tab 1-8 / last tab of the pane (workspaces: `M-1`..`M-9`, `SPC TAB 1`..`9`) |
| `gt` / `gT` | Next / previous tab of the window, wrapping around (workspaces: `]w` / `[w`) |
| `SPC t ?` | Hide / show the tips panel (disabled: uncomment `config/cheatsheet` in `config.el`) |
| `←` / `→` (treemacs, LSP lists) | Collapse or go to parent / expand, into, or open |
| `zR` / `zM` (treemacs) | Expand / collapse all folders |
| `M-[` / `M-]` (GUI) | Previous / next buffer |
| `Cmd+[` / `Cmd+]` (GUI) | Back / forward through where the cursor jumped (IntelliJ's Back / Forward) |
| `SPC c ~` | Cycle the word at point: snake_case → UPPER_CASE → PascalCase → camelCase → kebab-case |
| `SPC w S` / `SPC w V` | Split below / right, the cursor stays (`SPC w s` / `SPC w v` move it) |
| `SPC w SPC` / `SPC w a` | New pane where the tiling strategy puts it (tall: main left, stack right) / arrange the panes so |
| `q` (transient menus) | Close the menu, like Esc / `C-g` (menus that use `q` keep it) |
