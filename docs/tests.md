# Tests

```sh
tests/run.sh               # unit tests
tests/run.sh e2e           # end-to-end tests, in a GUI Emacs
tests/run.sh all           # both
tests/run.sh unit tiling   # one file: tests/unit/test-tiling.el

tests/linux/run.sh all             # the same on Linux, in Docker (from macOS too)
XWIDGETS=no tests/linux/run.sh all # on an Emacs without xwidgets, as most distributions'
```

Each test file runs in a throwaway Emacs, so your Emacs and its files are never touched. Nor do the tests see your
shell's Beads settings (every `BEADS_` and `BD_` variable, and `AGENT_WORKSPACE_AGENT`): run by an agent of a crew,
their `bd` never reaches the project's issues, and it sends no usage metrics (`DO_NOT_TRACK`). A test needing a `bd`
project calls `+test-bd-init` (`tests/helper.el`): `bd init` runs once per test file, its project copied after (5 s
each before). Its repository commits as a test user (`+test-git-user`): the tests read no `~/.gitconfig`, and `bd init`
commits what it adds (where git can't make a user up, in a Linux container, it left its files staged and a merge was
refused); one that leaves anything uncommitted stops there. Test files run several at once, their results shown in file order: `JOBS` unit test Emacsen (default: the
number of CPUs), `E2E_JOBS` end-to-end ones (default: 8, at most `JOBS`; one at a time in `tests/linux/run.sh`, where
they share one X server); `JOBS=1` or `E2E_JOBS=1` runs them one at a time. Each end-to-end Emacs's frame is off the
screen but for its top left corner, at the bottom right, each its own: a staircase, each corner a step right of and
above the one before, so no frame covers another's (PDF.js draws no page in a covered frame). A window over that
corner (a video call's picture in picture), or another Space shown (a video full screen, a desktop of its own), hides
them too: a test's waits stop their clock while WebKit says the frame's page is hidden (WebKit draws nothing there),
for 2 minutes at most, and the PDF tests' log says how long a page took and how much of it hidden. A test file with a
line `;; run.sh: alone` runs with no other beside it, before the others: a test timing itself by the clock is slowed by
the others (`test-large-files.el`). One with a line `;; run.sh: slow` starts before the rest, so its seconds run beside
them rather than after (with 8 at once, the end-to-end tests take about 80 s on an M1 Max, 160 s with 4 at once before).
One with a line `;; run.sh: split N` starts before the rest too, in N Emacsen at once, each running every Nth of its
tests by name; its result is still one line (`21 tests · 44.4 s, in 3 parts`), so a file of several minutes no longer
ends the run on its own. On macOS the unit test files' folders (their Emacs's init folder, what their tests write) are
on a RAM disk made for the run: `bd` waits for each of its writes to reach the disk, and that was about 40% of a run's
time. `RAM_DISK` is its size in MB (default 4096, taken only as it's written); `RAM_DISK=0` keeps them on the disk. It's
hidden from the Finder and gone once the unit tests end; a failed file's folder is copied beside its log first. The
end-to-end tests' folders stay on the disk: WebKit reads no page from another volume (PDF.js and Excalidraw never load).
`Ctrl+C` stops them all. The PDF and drawing tests copy PDF.js and Excalidraw from Doom's data folder, and skip without
them: opening a PDF or a drawing once downloads them, or `emacs --batch -l tests/helper.el -l tests/assets.el` does. The
Mermaid end-to-end tests draw with the real `mmdc` and skip without it (the unit tests use a stand-in).
`E2E_WINDOW=front` shows the end-to-end tests' frames whole, each a step down and right of the one before, which
otherwise stay off screen. They run on macOS and on Linux; `EMACS_GUI` names the GUI Emacs for the end-to-end tests
(default: macOS's `/Applications/Emacs.app`, else `emacs`). On Linux without a display, run those under Xvfb, one at a
time: `E2E_JOBS=1 xvfb-run -a tests/run.sh e2e`. A failed file's log is in the run's folder (the path after `full
log:`); with `TEST_LOGS=DIR`, it's copied to `DIR` too, as `KIND-NAME.txt` (`unit-test-tabs.txt`), in
`tests/linux/run.sh` as well (the folder mounted in its container).

- `tests/unit/test-NAME.el` tests `config/NAME.el` or a part of it (`test-tabs.el`: `config/editor/tabs.el`); the
  language servers' settings, a file per language (`test-lsp-rust.el`: `config/lsp/rust.el`), sharing
  `tests/helper-lsp.el`. `test-keys.el` checks the keys of both systems (`+test-on-macos`, `+test-on-linux` in
  `tests/helper.el` run code as on either); no test opens another app (`config/emacs/os.el`'s are recorded).
- `tests/e2e/test-NAME.el` tests what needs a GUI: WebKit pages, child frames, the merge on screen.
- `tests/linux/` runs them on Linux: a Debian image set up by `scripts/emacs.sh` and `scripts/tools.sh` (with or
  without xwidgets), the config and Doom's folder mounted read-only, the end-to-end tests under Xvfb, the container's
  temp folder (the tests' folders) in memory, as macOS's RAM disk (`RAM_DISK` MB; `RAM_DISK=0`: on the disk). Built
  the first time (~15 minutes), then from its cached layers. Tests needing what only the host built (ghostel's native module) skip there.
- `tests/fixtures/` holds what tests load: `diff-emacs.el` is the Emacs that `cmd/diff` starts in `test-cmd.el`.
  The agent workspace's tests run real sessions with `examples/agent-workspace/stand-in.el`, a stand-in coding agent
  speaking ACP as Claude Code's adapter does, run by a batch Emacs.

A failing or flaky test is a bug to fix in the config, not a test to relax.

## On GitHub

Each push and pull request runs them all (`.github/workflows/tests.yml`), unit and end-to-end, in three jobs:

- **Linux, with xwidgets** and **Linux, without xwidgets**: `tests/linux/run.sh`, in its Docker image, which
  `scripts/emacs.sh` and `scripts/tools.sh` set up (its layers cached between runs: Emacs is built again only when
  `emacs.sh` changes);
- **macOS**: `tests/run.sh`, after `scripts/emacs.sh` and `scripts/tools.sh` set the machine up.

Each machine is set up the way the README sets up yours, so every push tests the installers too. Doom is cloned at the
commit in the workflow's `DOOM_REF` (the one the config is used with: bump it after updating Doom), and `emacs.sh`
syncs it (its packages cached until `init.el`, `packages.el` or that commit change; on macOS, Homebrew's downloads too,
a week at a time). PDF.js and Excalidraw are
downloaded (`tests/assets.el`), so no test skips for want of them. A newer push to a
branch cancels the run still going there.

In each job the end-to-end tests run even when a unit test failed, so one failure doesn't hide the other; the job fails
if either does. When a job fails, its failed test files' logs (`TEST_LOGS`) are kept with the run for 14 days, an
artifact per job (`test-logs-macos`, `test-logs-linux-with-xwidgets`, `test-logs-linux-without-xwidgets`): what a test
saw where it fails only on GitHub. `gh run download RUN_ID` fetches them.
