# Tests

```sh
tests/run.sh               # unit tests
tests/run.sh e2e           # end-to-end tests, in a GUI Emacs
tests/run.sh all           # both
tests/run.sh unit tiling   # one file: tests/unit/test-tiling.el

tests/linux/run.sh all             # the same on Linux, in Docker (from macOS too)
XWIDGETS=no tests/linux/run.sh all # on an Emacs without xwidgets, as most distributions'
```

Each test file runs in a throwaway Emacs, so your Emacs and its files are never touched. `E2E_WINDOW=front` shows the
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
