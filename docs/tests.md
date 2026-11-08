# Tests

```sh
tests/run.sh               # unit tests
tests/run.sh e2e           # end-to-end tests, in a GUI Emacs
tests/run.sh all           # both
tests/run.sh unit tiling   # one file: tests/unit/test-tiling.el
```

Each test file runs in a throwaway Emacs, so your Emacs and its files are never touched. `E2E_WINDOW=front` shows the
end-to-end tests' frame, which otherwise stays off screen.

- `tests/unit/test-NAME.el` tests `config/NAME.el` or a part of it (`test-tabs.el`: `config/editor/tabs.el`); the
  language servers' settings, a file per language (`test-lsp-rust.el`: `config/lsp/rust.el`), sharing
  `tests/helper-lsp.el`.
- `tests/e2e/test-NAME.el` tests what needs a GUI: WebKit pages, child frames, the merge on screen.
- `tests/fixtures/` holds what tests load: `diff-sh-emacs.el` is the Emacs that `cmd/diff.sh` starts in `test-cmd.el`.

A failing or flaky test is a bug to fix in the config, not a test to relax.
