# Tests

Unit and end-to-end tests of this config, on macOS and Linux. Each test file runs in a throwaway Emacs, so your Emacs
and its files are never touched.

```sh
tests/run.sh               # unit tests
tests/run.sh e2e           # end-to-end tests, in a GUI Emacs
tests/run.sh all           # both
tests/run.sh unit tiling   # one file: tests/unit/test-tiling.el

tests/linux/run.sh all             # the same on Linux, in Docker (from macOS too)
XWIDGETS=no tests/linux/run.sh all # on an Emacs without xwidgets, as most distributions'
```

A failing or flaky test is a bug to fix in the config, not a test to relax.

## Running them

Test files run several at once, the longest first, and each result shows as soon as its file ends. In a terminal, a line
under the results says how many files are done and running. `Ctrl+C` stops them all. These variables change how they
run:

| Setting | Default | What |
|---|---|---|
| `JOBS` | The number of CPUs | How many unit test files run at once (`1`: one at a time) |
| `E2E_JOBS` | 8, at most `JOBS` | How many end-to-end test files run at once (`1`: one at a time) |
| `EMACS` | `emacs` | The Emacs for the unit tests |
| `EMACS_GUI` | macOS's `/Applications/Emacs.app`, else `emacs` | The GUI Emacs for the end-to-end tests |
| `E2E_TIMEOUT` | 180 | Seconds each end-to-end test file may take |
| `E2E_WINDOW` | Off screen | `front`: show the end-to-end tests' frames whole, each a step down and right of the one before |
| `NICE` | 10 | How nice the tests' Emacsen are: they keep every CPU busy, so your apps go first (`0`: as any other) |
| `RAM_DISK` | 4096 | On macOS, the size in MB of the RAM disk for the unit tests' folders (`0`: on the disk) |
| `TEST_LOGS` | None | A folder: each failed file's log is copied there, as `KIND-NAME.txt` (`unit-test-tabs.txt`) |

- On Linux without a display, run the end-to-end tests under Xvfb, one at a time:
  `E2E_JOBS=1 xvfb-run -a tests/run.sh e2e`.
- A failed file's log is in the run's folder: the path after `full log:`.
- `TEST_LOGS` works in `tests/linux/run.sh` too: the folder is mounted in its container.
- On macOS, the unit tests' folders (their Emacs's init folder, what their tests write) are on a RAM disk made for the
  run. It takes memory only as it's written, and is hidden from the Finder. It's gone once the unit tests end, however
  the run ends (`Ctrl+C`, killed, even with `kill -9`); a failed file's folder is copied beside its log first. A disk
  an earlier run left is detached as the next one starts.
- The end-to-end tests' folders stay on the disk, as WebKit reads no page from another volume.
- Each run writes how long each file took to `tests/.durations` (kept out of git), and the next run starts the longest
  first: the run ends once its longest file does, the short ones filling in beside it. With 4 or more at once, one of
  them takes the shortest first for the first 30 seconds, so results show from the start.

## The end-to-end tests' frames

Each end-to-end Emacs's frame sits off the screen, at the bottom right, with only its top left corner showing. The
corners form a staircase, each a step right of and above the one before, so no frame covers another. PDF.js draws no
page in a covered frame.

- Keep that corner clear while they run. A window over it (a video call's picture in picture) hides the frames too, and
  so does another Space shown (a video full screen, a desktop of its own).
- While WebKit says a frame's page is hidden, its tests' waits stop their clock, for 2 minutes at most.
- The PDF tests' log says how long each page took, and how long it was hidden.
- `E2E_WINDOW=front` shows the frames whole instead.

## What tests need

- The PDF and drawing tests copy PDF.js and Excalidraw from Doom's data folder, and skip without them. Opening a PDF or
  a drawing once downloads them, or run `emacs --batch -l tests/helper.el -l tests/assets.el`.
- The Mermaid end-to-end tests draw with the real `mmdc`, and skip without it. The unit tests use a stand-in.
- The tests don't see your shell's Beads settings: every `BEADS_` and `BD_` variable, and `AGENT_WORKSPACE_AGENT`. Run
  by an agent of a crew, their `bd` never reaches the project's issues. Their `bd` sends no usage metrics either
  (`DO_NOT_TRACK`).

## Writing tests

| Path | What |
|---|---|
| `tests/unit/test-NAME.el` | Tests `config/NAME.el` or a part of it (`test-tabs.el`: `config/editor/tabs.el`) |
| `tests/unit/test-lsp-LANGUAGE.el` | A language server's settings (`test-lsp-rust.el`: `config/lsp/rust.el`), sharing `tests/helper-lsp.el` |
| `tests/e2e/test-NAME.el` | What needs a GUI: WebKit pages, child frames, the merge on screen |
| `tests/linux/` | The same tests on Linux, in Docker |
| `tests/fixtures/` | What tests load: `diff-emacs.el` is the Emacs that `cmd/diff` starts in `test-cmd.el` |

- `test-keys.el` checks the keys of both systems. `+test-on-macos` and `+test-on-linux`, in `tests/helper.el`, run code
  as on either.
- No test opens another app: the apps of `config/emacs/os.el` are recorded instead.
- A test needing a `bd` project calls `+test-bd-init` (`tests/helper.el`). `bd init` runs once per test file, and its
  project is copied after.
- That project's repository commits as a test user (`+test-git-user`), and the tests read no `~/.gitconfig`. A `bd init`
  that leaves anything uncommitted stops the test there.
- The agent workspace's and agent workflow's tests run real sessions with `examples/agent-workspace/stand-in.el`, a
  stand-in coding agent run by a batch Emacs. It speaks ACP as Claude Code's adapter does: a system prompt from Emacs,
  its modes and effort. With `MOCK_ACP_NO_SYSTEM_PROMPT`, it acts as an agent taking no system prompt. The tests run it
  as Claude Code, or as another kind of agent.

A line in a test file changes how it runs:

| Line | What |
|---|---|
| `;; run.sh: alone` | It runs before the others, with none beside it: for a test timing itself by the clock (`test-large-files.el`) |
| `;; run.sh: slow` | It starts before the rest when no run has timed it yet (a new clone, CI), so its time runs beside theirs rather than after |
| `;; run.sh: split N` | It runs in N Emacsen at once, each running every Nth of its tests by name, started first as a slow one is. Its result is still one line (`21 tests · 44.4 s, in 3 parts`) |

## On Linux

`tests/linux/run.sh` runs the tests in a Debian image, set up by `scripts/emacs.sh` and `scripts/tools.sh`, with or
without xwidgets. The image is built the first time (about 15 minutes), then from its cached layers.

- The config and Doom's folder are mounted read-only.
- The end-to-end tests run under Xvfb, one at a time, as they share one X server.
- The container's temp folder, where the tests' folders are, is in memory, as macOS's RAM disk is (`RAM_DISK`).
- Tests needing what only the host built (ghostel's native module) skip there.

## On GitHub

Each push and pull request runs all the tests, unit and end-to-end (`.github/workflows/tests.yml`). Each machine is set
up the way the README sets up yours, so every push tests the installers too. There are three jobs:

| Job | What it runs |
|---|---|
| Linux, with xwidgets | `tests/linux/run.sh`, in its Docker image |
| Linux, without xwidgets | The same, on an Emacs without xwidgets (`XWIDGETS=no`) |
| macOS | `tests/run.sh`, after `scripts/emacs.sh` and `scripts/tools.sh` set the machine up |

- The Docker image's layers are cached between runs. Emacs is built again only when `emacs.sh` changes.
- Doom is cloned at the commit in the workflow's `DOOM_REF`, the one the config is used with. Bump it after updating
  Doom.
- `emacs.sh` syncs Doom. Its packages are cached until `init.el`, `packages.el` or `DOOM_REF` change. On macOS,
  Homebrew's downloads are cached too, a week at a time.
- PDF.js and Excalidraw are downloaded (`tests/assets.el`), so no test skips for want of them.
- A newer push to a branch cancels the run still going there.
- In each job, the end-to-end tests run even when a unit test failed, so one failure doesn't hide the other. The job
  fails if either does.
- When a job fails, its failed test files' logs (`TEST_LOGS`) are kept with the run for 14 days, an artifact per job:
  `test-logs-macos`, `test-logs-linux-with-xwidgets` and `test-logs-linux-without-xwidgets`. They show what a test saw
  where it fails only on GitHub. `gh run download RUN_ID` fetches them.
