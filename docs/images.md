# Images

Images open in Emacs's own viewer, in their tab, with a toolbar in the header line: the folder's images, zoom, rotate,
flip, crop, sharp pixels, the image's size, copy, git's HEAD beside it, Preview (Linux: Open). In a narrow pane it keeps
what fits, the rest in the menu of its `…` button. A file changed on disk (a regenerated screenshot) is shown anew, its
zoom kept. Try it: `M-x +my/example-image`.

![A picture beside its version in git's HEAD](../examples/image.png)

| macOS | Linux | Action |
|---|---|---|
| `J` / `K` | `J` / `K` | Next / previous image in the folder |
| `+` / `-`, `Cmd+=` / `Cmd+-`, `Cmd+scroll` | `+` / `-`, `Ctrl+=` / `Ctrl+-`, `Ctrl+scroll` | Zoom in / out |
| `W` / `0` (`Cmd+0`) | `W` / `0` (`Ctrl+0`) | Fit the window / actual size |
| `r` / `R` | `r` / `R` | Rotate clockwise / anticlockwise |
| `f` / `F` | `f` / `F` | Flip horizontally / vertically |
| `c` | `c` | Crop: drag, `RET` crops, `q` cancels |
| `RET` | `RET` | Play / pause an animation |
| `y`, `Cmd+C` | `y`, `Ctrl+Shift+C` | Copy the image (to paste in other apps) |
| `SPC m y` | `SPC m y` | Copy its path |
| `SPC m g` | `SPC m g` | The image beside its version in git's HEAD, in its own pane: HEAD on the left (above, in a narrow pane), a caption over each, both at the image's zoom; again (or `q`), closed |
| `TAB` (`SPC m h`) | `TAB` (`SPC m h`) | Flip: git's HEAD in the image's place, at its zoom and scrolled to the same spot; again, the image |
| `SPC m s` | `SPC m s` | Sharp pixels (no smoothing) |
| `SPC m t` | `SPC m t` | The toolbar |
| `SPC m p` / `SPC m f` | `SPC m p` / `SPC m f` | Open in Preview / show in Finder (Linux: the default app / the file manager) |
| `q` | `q` | Close |

The toolbar's Diff button is a menu of both. With git's HEAD beside it or flipping, zoom, `W`, `0` and Sharp change
both, `W` fitting the pair to the pane. Flipping, the toolbar says `HEAD abc1234` while HEAD is shown, edits wait for
the image, and `SPC m g` puts them side by side again; `q` closes either. It stays while the
file changes on disk (shown anew beside HEAD) and while you rotate or flip the image; cropping closes it first, and `J`
/ `K` show the other image without it.

Rotating, flipping and cropping change the image, as Preview does: save it as any file (`SPC f s`, or the toolbar's
Save), or revert it (`SPC b r`) to undo. Not SVGs, nor animations. On macOS they use `sips`; on Linux ImageMagick
(`magick`, or `convert` of ImageMagick 6), which cropping needs on both (`scripts/tools.sh` installs it). Copying the
image on Linux needs `wl-copy` (Wayland, the wl-clipboard package) or `xclip` (X11).
