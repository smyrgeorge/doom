# Tests

`tests/` has tests for this config's features: unit tests, which run in `emacs --batch`, and end-to-end tests, which
run in a GUI Emacs for what needs one (WebKit pages, the notices' child frames). Doom never loads `tests/`: `config.el` only loads
`config/`, so the tests only ever run through `tests/run.sh`.

```sh
tests/run.sh               # unit tests
tests/run.sh e2e           # end-to-end tests (GUI windows open while they run)
tests/run.sh all           # both
tests/run.sh unit tiling   # one file: tests/unit/test-tiling.el (several names work, of any kind)
```

It prints one line per test file (`ok`, or `FAIL` with the failures and what led to them) and exits 1 if any test
failed. Each file's full log is kept in a temp folder, whose path is printed.

## How they run

Each test file runs in a throwaway Emacs of its own: `emacs -Q` with its own init folder (`--init-directory`) and
temp folder. Your Doom profile, its state (PDF places, history...) and a running Emacs are never touched.
`tests/helper.el` sets that Emacs up like Doom before a test file loads:

- Doom's packages are on `load-path`, from its build folder (`~/.config/emacs/.local/straight/build-*`, read only).
- Doom's macros come from its own source (`after!`, `defadvice!`, `map!`, `use-package!`...).
- `modulep!` answers from `init.el`'s `doom!` block.
- evil is on.
- Doom's folders (`doom-data-dir`, `doom-state-dir`...) point into the temp folder.
- `+test-load` loads config files the way Doom does. `map!` really binds keys there, though Doom's does nothing in
  batch mode.
- Nothing opens outside Emacs: `browse-url` only records the URL. The PDF tests also record `open -a Preview` and
  the print dialog's `osascript` instead of running them.
- No test downloads anything: the PDF and drawing tests use a copy of the PDF.js and Excalidraw that Doom already
  has (they skip without one: open a PDF or a drawing in Emacs once).
- No sound: Emacs's bell (macOS's alert sound in the GUI test Emacs) is silent, each ring said in the log instead
  (`BELL in <test>`, with how it came), as is each error the command loop reports (`COMMAND ERROR`): either is
  worth a look. Packages aren't compiled to native code as they load: their compiling Emacs's log buffer, killed by a
  test's reset, made its sentinel fail and the bell ring in each GUI test Emacs.
- Tests that need a tool skip when it's missing (pandoc, delta, git...).

The end-to-end tests run in the emacs-plus app (`EMACS_GUI`), its frame kept on top of other windows while they run:
macOS treats a window covered by others (or minimized) as hidden, and WebKit doesn't draw there (PDF.js renders no
page). Out of your way all the same: the frame is off the screen but for its top left corner (24 px), at the bottom
right of the screen's work area, above the Dock, and doesn't take the keyboard. `E2E_WINDOW=front` shows it whole and
focused, to watch the tests. While a test waits for WebKit, `tests/helper.el` redisplays and reads events the way Emacs's command loop
does. `sit-for` alone stalls once an input event stays pending, as one does after a child frame is made.

Variables: `EMACS` (default `emacs`) runs the unit tests, `EMACS_GUI` (default
`/Applications/Emacs.app/Contents/MacOS/Emacs`) the end-to-end ones, and `E2E_TIMEOUT` (default 180) gives the
seconds allowed per end-to-end file.

## Layout

| Path | What |
|---|---|
| `tests/run.sh` | The runner (above). |
| `tests/helper.el` | The test Emacs's setup and shared tools: `+test-load`, `+test-with-reset`, `+test-buffer`, `+test-file`, `+test-tmp-file`, `+test-messages`, `+test-make-pdf` (writes a real PDF: pages, outline, links), `+test-pdfjs-dir` / `+test-excalidraw-dir` (copies of Doom's), `+test-wait-for`, `+test-sleep`, `+test-js` (a page's JavaScript value, awaited), `+test-visible-frames`, `+test-browsed`. |
| `tests/unit/test-<file>.el` | Unit tests for `config/<file>.el`, one file each; `test-config.el` covers `config.el`, loading the whole config. |
| `tests/e2e/test-<name>.el` | End-to-end tests: `test-webkit.el` (WebKit pages: a view per window, splits, links out, JavaScript, copy, closing), `test-pdf.el` (PDFs with PDF.js: pages, splits, settings, outline, search, thumbnails, Option+Enter, Preview / print, places, links, revert), `test-excalidraw.el` (drawings in Excalidraw: new ones, saved as SVG and JSON and reopened, drawn with the mouse, Emacs's keys, copy and paste, split panes showing each other's changes, changes on disk, saving right after a change, closing with an answer on its way, the dark canvas, inserting from Markdown, files that aren't drawings, the pointer, the library kept and shared, a library added from a link and from the libraries' site, a local stand-in), `test-markdown.el` (the live preview: following the cursor and typing, splits, links, keys, closing), `test-banner.el` (notices laid over the header line by child frames: under the tabs, splits, other buffers, resizing, actions and ✕), `test-treemacs.el` (the sidebar scrolled away from the open file stays there, real wheel events; shows it again on a change of buffer; keys act on the selection), `test-stripe.el` (the error stripe's child frame over each window's margin: splits, other buffers, a notice above; the band and marks' pixels; a press, the wheel; images made only when the strip changes), `test-examples.el` (the merge example on screen, its wands; gone once done), `test-merge.el` (conflicts in three panes: Magit's `e`, a margin's button clicked where it shows, Done staging the file; the rows lined up on screen, the panes scrolling together with ultra-scroll, a glide of `config/smooth.el`'s, keys, the wheel, sideways; the wand clicked where it shows), `test-harness.el` (the end-to-end setup itself). |

## Writing tests

Tests are ERT tests named `<file>/<behaviour>` (end to end: `e2e-<name>/<behaviour>`), and `tests/unit/test-tiling.el`
is a short example. Each test file starts with `(+test-load "config/...")` for the files it covers, in `config.el`'s
order.

Mocking with `cl-letf` is fine: a test Emacs is thrown away. A test that waits for WebKit uses `+test-wait-for`, not
`sit-for` (see above). A test that asks a page for a value uses `+test-js`, which waits for the answer: closing a WebKit
view while an answer was pending crashed Emacs.

A failing test is a bug to fix, in the config if that's where it is, not a test to relax. A flaky test is often a race in
the code.
