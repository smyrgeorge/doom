# Tests

```sh
tests/run.sh               # unit tests
tests/run.sh e2e           # end-to-end tests, in a GUI Emacs
tests/run.sh all           # both
tests/run.sh unit tiling   # one file: tests/unit/test-tiling.el

tests/linux/run.sh all             # the same on Linux, in Docker (from macOS too)
XWIDGETS=no tests/linux/run.sh all # on an Emacs without xwidgets, as most distributions'
```

Each test file runs in a throwaway Emacs, so your Emacs and its files are never touched. The PDF and drawing tests copy
PDF.js and Excalidraw from Doom's data folder, and skip without them: opening a PDF or a drawing once downloads them,
or `emacs --batch -l tests/helper.el -l tests/assets.el` does. `E2E_WINDOW=front` shows the
end-to-end tests' frame, which otherwise stays off screen. They run on macOS and on Linux; `EMACS_GUI` names the GUI
Emacs for the end-to-end tests (default: macOS's `/Applications/Emacs.app`, else `emacs`). On Linux without a display,
run those under Xvfb: `xvfb-run -a tests/run.sh e2e`.

- `tests/unit/test-NAME.el` tests `config/NAME.el` or a part of it (`test-tabs.el`: `config/editor/tabs.el`); the
  language servers' settings, a file per language (`test-lsp-rust.el`: `config/lsp/rust.el`), sharing
  `tests/helper-lsp.el`. `test-keys.el` checks the keys of both systems (`+test-on-macos`, `+test-on-linux` in
  `tests/helper.el` run code as on either); no test opens another app (`config/os.el`'s are recorded).
- `tests/e2e/test-NAME.el` tests what needs a GUI: WebKit pages, child frames, the merge on screen.
- `tests/linux/` runs them on Linux: a Debian image with Emacs 31.1 built as `scripts/emacs.sh` builds it (with or
  without xwidgets), the config and Doom's folder mounted read-only, the end-to-end tests under Xvfb. Built the first
  time (~10 minutes). Tests needing what only the host built (ghostel's native module) skip there.
- `tests/fixtures/` holds what tests load: `diff-sh-emacs.el` is the Emacs that `cmd/diff.sh` starts in `test-cmd.el`.

A failing or flaky test is a bug to fix in the config, not a test to relax.

## On GitHub

Each push and pull request runs them all (`.github/workflows/tests.yml`), unit and end-to-end, in three jobs:

- **Linux, with xwidgets** and **Linux, without xwidgets**: `tests/linux/run.sh`, in its Docker image (Emacs 31 built
  from source, the image's layers cached between runs);
- **macOS**: `tests/run.sh`, with emacs-plus's Emacs.app.

Each installs Doom at the commit in the workflow's `DOOM_REF` (the one the config is used with: bump it after updating
Doom), runs `doom sync` (its packages cached until `init.el`, `packages.el` or that commit change) and downloads PDF.js
and Excalidraw (`tests/assets.el`), so no test skips for want of them. A newer push to a
branch cancels the run still going there.
