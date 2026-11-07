# Tests

```sh
tests/run.sh               # unit tests
tests/run.sh e2e           # end-to-end tests, in a GUI Emacs
tests/run.sh all           # both
tests/run.sh unit tiling   # one file: tests/unit/test-tiling.el
```

Each test file runs in a throwaway Emacs set up like Doom (`tests/helper.el`): your Doom profile and running Emacs are
never touched, and nothing is downloaded or opened outside Emacs. The end-to-end tests' frame stays mostly off screen;
`E2E_WINDOW=front` shows it.

- `tests/unit/test-FILE.el` tests `config/FILE.el`, or a part in a folder (`test-tabs.el`: `config/editor/tabs.el`);
  `test-config.el` loads the whole config, `test-cmd.el` tests `cmd/`, `test-screenshots.el` the screenshots script.
- `tests/e2e/test-NAME.el` tests what needs a GUI: WebKit pages, child frames, the merge on screen.

Tests are ERT tests named `FILE/behaviour`. A failing or flaky test is a bug to fix in the config, not a test to relax.
