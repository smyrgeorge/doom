# Project sidebar

The treemacs sidebar shows the current project's files and their git status. It opens with a workspace's first project
file, and follows the current file and its project.

| macOS | Linux | Action |
|---|---|---|
| `←` / `→` | `←` / `→` | Collapse or go to the parent / expand; on a file, up / down (`RET` opens it) |
| `zR` / `zM` | `zR` / `zM` | Expand / collapse everything (`.git` stays closed) |
| Click | Click | Select (the sidebar gets the focus) |
| Double click | Double click | Open a file, expand / collapse a folder |
| `Cmd+C` | `Ctrl+Shift+C` | Copy the file (or folder) itself, as Finder does: paste it into Slack, a mail or a folder |
| `Option+Cmd+C`, `ya` | `ya` | Copy its absolute path |
| Right click → Reveal in Finder | Right click → Show in File Manager | The file or folder, selected in the file manager |
| `SPC w w`, window numbers | the same | Go to the sidebar |
| Drag its edge, `SPC w <` / `SPC w >`, `w` | the same | Resize it |

- The git status shows changes made outside Emacs too.
- Each git project's name is followed by its branch, and the commits it is ahead (`↑`) and behind (`↓`) its upstream:
  `doom  main ↑2`. A detached HEAD shows its short commit.
- The branch is updated after a refresh, a Magit operation, or a switch made in a terminal.
- The line of the project in view is the sidebar's top bar. It stays there while a long tree scrolls, and a click on it
  goes back to the project.
- The sidebar is 35 columns wide, and at most a quarter of the frame. It follows the frame as it's resized.
- A width set by hand is kept, also when the sidebar is closed and opened again.
- The arrows work in the language server's lists too (`SPC c S`, `SPC c X`, `SPC c y`), which open with the cursor in
  them.

Set these in `config.el`:

| Setting | Default | What |
|---|---|---|
| `+my/treemacs-sticky-title` | `t` | The project's line stays at the top. `nil` turns it off |
| `+my/treemacs-max-width` | `0.25` | The sidebar's widest, as a share of the frame |
