# Key bindings

The keys this config adds or changes, on macOS and on Linux. PDFs, images, drawings and the merge have their own: see
[PDFs](pdf.md), [Images](images.md), [Drawings](drawings.md) and [Resolving conflicts](git.md#resolving-conflicts).

On macOS the keys use `Cmd`, as macOS's apps do. Linux's desktops keep most `Super` keys for themselves (and a terminal
can't send `Super`), so on Linux each `Cmd` key is a `Ctrl` key, as Linux's apps have them:

- `Ctrl` where Vim and Emacs leave it free: `Ctrl+1`..`Ctrl+9`, `Ctrl+=` / `Ctrl+-` / `Ctrl+0`, `Ctrl+P`, `Ctrl+S`;
- `Ctrl+Shift` where `Ctrl` is Vim's (`Ctrl+B`, `Ctrl+W`, `Ctrl+C`, `Ctrl+V`...), as Linux's terminals copy with
  `Ctrl+Shift+C`;
- `Alt+←` / `Alt+→` for back and forward, as browsers.

The `Cmd` keys also work on Linux as `Super` keys, where the desktop lets them through. macOS gets none of the Linux keys:
Vim's and Doom's keys stay as they are there. `config/os.el` has the rules.

| macOS | Linux | Action |
|---|---|---|
| `Cmd+B` | `Ctrl+Shift+B` | Go to the declaration, or list the usages |
| `Cmd+[` / `Cmd+]` | `Alt+←` / `Alt+→` | Back / forward (`C-o` / `C-i` on both) |
| `Option+Enter` | `Alt+Enter` | Spelling fixes, code actions and Claude |
| `SPC c ~` | `SPC c ~` | Cycle the word's case style |
| `Cmd+W` | `Ctrl+Shift+W` | Close the tab |
| `Cmd+1`..`Cmd+9` | `Ctrl+1`..`Ctrl+9` | Pick a tab (`9`: the last) |
| `gt` / `gT` | `gt` / `gT` | Next / previous tab |
| `M-[` / `M-]` | `Alt+[` / `Alt+]` | Previous / next buffer |
| `SPC w SPC` / `SPC w a` | `SPC w SPC` / `SPC w a` | A new tiled pane / arrange the panes |
| `SPC w RET` | `SPC w RET` | Swap the pane with the main one (focus follows) |
| `SPC w ]` / `SPC w [` | `SPC w ]` / `SPC w [` | The main pane bigger / smaller (`]` / `[` repeat) |
| `SPC w }` / `SPC w {` | `SPC w }` / `SPC w {` | The current pane taller / shorter, the others of the stack even (`}` / `{` repeat) |
| `SPC w S` / `SPC w V` | `SPC w S` / `SPC w V` | Split, the cursor staying |
| `SPC o t` | `SPC o t` | The terminal, in a new tiled pane |
| `q` (transient menus) | `q` (transient menus) | Close |
| `SPC s a` | `SPC s a` | Search Everywhere |
| `Cmd+Shift+F` | `Ctrl+Shift+F` | Find in files (on Linux full screen is `F11`) |
| `←` / `→`, `zR` / `zM` (sidebar) | the same | Collapse / expand; everything |
| `Cmd+C` (sidebar) | `Ctrl+Shift+C` (sidebar) | Copy the file's path |
| `SPC g d` | `SPC g d` | The file's git diff in a pane |
| `e` (Magit, on a conflicted file) | the same | Resolve its conflicts |
| `SPC m p` / `SPC m P` (Markdown) | the same | Live preview / in the browser |
| `Cmd+C` (Markdown preview) | `Ctrl+Shift+C` | Copy the selection |
| `SPC o c` / `SPC o C` | `SPC o c` / `SPC o C` | A new Claude Code session / the project's |
| `RET` (Claude Code, normal state) | the same | Send the prompt |
| `n` / `p`, `y`, `RET` (Claude's diffs) | the same | The next / previous hunk, accept, open the file |
| `C-c C-d`, `SPC m d` (Claude Code) | the same | Draw for Claude |
| `SPC o i` / `SPC o I` | `SPC o i` / `SPC o I` | The project's [issues](issues.md) / a new one |
| `C-c C-i` (Claude Code), `C-c C-a` (an issue) | the same | An issue into Claude's prompt |
| `SPC h T` | `SPC h T` | Start / stop the profiler |
| `SPC t n` / `SPC t N` | the same | All [notifications](notifications.md) on / off; one kind |

On Linux, `Alt+1`..`Alt+9` stay Doom's workspace keys, and `Alt+←` / `Alt+→` still move by words in insert state. In a
terminal (`emacs -nw`), neither the `Cmd` keys nor most `Ctrl+Shift` and `Ctrl+digit` keys reach Emacs: use the `SPC`
and Vim keys there.
