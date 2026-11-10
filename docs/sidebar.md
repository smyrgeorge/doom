# Project sidebar

The treemacs sidebar opens with a workspace's first project file, follows the current file and its project, and shows
the git status, also of changes made outside Emacs. Each git project's branch follows its name, with the commits it is
ahead (`↑`) and behind (`↓`) its upstream: `doom  main ↑2` (a detached HEAD: its short commit), updated after a refresh,
a magit operation, or a switch made in a terminal. That line (the project in view, its
branch) is the sidebar's top bar, and stays there while a long tree scrolls; a click on it goes back to it
(`+my/treemacs-sticky-title`: nil turns it off).

| macOS | Linux | Action |
|---|---|---|
| `←` / `→` | `←` / `→` | Collapse or go to the parent / expand; on a file, up / down (`RET` opens it) |
| `zR` / `zM` | `zR` / `zM` | Expand / collapse everything (`.git` stays closed) |
| Click | Click | Select (the sidebar gets the focus) |
| Double click | Double click | Open a file, expand / collapse a folder |
| `Cmd+C` | `Ctrl+Shift+C` | Copy the file's (or folder's) absolute path (`ya` on both) |
| Right click → Reveal in Finder | Right click → Show in File Manager | The file or folder, selected in the file manager |
| `SPC w w`, window numbers | the same | Go to the sidebar |

The arrows work in the language server's lists too (`SPC c S`, `SPC c X`, `SPC c y`), which open with the cursor in
them.
