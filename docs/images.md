# Images

Images open in Emacs's own viewer, in their tab, with a toolbar in the header line: the folder's images, zoom, rotate,
flip, crop, sharp pixels, the image's size, copy, git's HEAD beside it, Preview. A file changed on disk (a regenerated
screenshot) is shown anew, its zoom kept.

```
 ‹ 3/12 › │ − 100% + Fit 1:1 │ ⟲ ⟳ ⇋ ⇵ Crop │ Sharp          1600×900 · PNG · 412 kB  Copy  Diff  Preview  Finder
```

| Key | Action |
|---|---|
| `J` / `K` | Next / previous image in the folder |
| `+` / `-`, `Cmd+=` / `Cmd+-`, `Cmd+scroll` | Zoom in / out |
| `W` / `0` (`Cmd+0`) | Fit the window / actual size |
| `r` / `R` | Rotate clockwise / anticlockwise |
| `f` / `F` | Flip horizontally / vertically |
| `c` | Crop: drag, `RET` crops, `q` cancels |
| `RET` | Play / pause an animation |
| `y`, `Cmd+C` | Copy the image (to paste in other apps) |
| `SPC m y` | Copy its path |
| `SPC m g` | The image as in git's HEAD, on its left; again, closed |
| `SPC m s` | Sharp pixels (no smoothing) |
| `SPC m t` | The toolbar |
| `SPC m p` / `SPC m f` | Open in Preview / show in Finder |
| `q` | Close |

Rotating, flipping and cropping change the image, as Preview does: save it as any file (`SPC f s`, or the toolbar's
Save), or revert it (`SPC b r`) to undo. Not SVGs, nor animations. They use macOS's `sips`; cropping needs ImageMagick
(`scripts/tools.sh` installs it).
