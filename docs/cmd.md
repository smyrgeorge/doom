# Shell commands

`cmd/` has scripts that open this config's features from the shell, in Emacs.

## cmd/diff.sh: resolving conflicts

Opens [the three-pane merge](git.md#resolving-conflicts) for Git's conflicted files from the shell, in this terminal
(or a GUI frame), one file after the other:

```sh
cmd/diff.sh                  # each conflicted file of the repository you're in
cmd/diff.sh a.txt src/b.py   # those files (relative to where you are)
cmd/diff.sh example          # the merge example (examples/merge.el), on a temp repository
cmd/diff.sh --list           # list the conflicted files, and exit
```

A file named `example` is `./example`. Done or Abort in the panes moves on to the next file. After the last one, the
frame closes, or the Emacs it started quits. Closing the frame stops: the files left are left as they are. Files the
panes can't show (not in conflict, binary, added on both sides...) are skipped, and the echo area says why at the end.

The Emacs: if one runs as a server (`emacsclient` reaches it), the merge opens in a new frame of it, which is quick and
uses your session. Otherwise it starts Emacs (Doom, `emacs -nw`) and quits it afterwards.

| Option | |
|---|---|
| `-g`, `--gui` | A GUI frame instead of this terminal |
| `-n`, `--new` | A new Emacs, even if one runs as a server |
| `-s NAME`, `--socket NAME` | The Emacs server to use (`emacsclient -s NAME`); an error if it isn't running |
| `-l`, `--list` | List the conflicted files (of those given, or the repository's), and exit |
| `-h`, `--help` | The help |

Exit status: 0 when every file was resolved (and staged by Done), 1 when some are still in conflict (it lists them),
2 for a wrong use (an unknown option, a missing file, not in a Git repository). `EMACS` (default `emacs`),
`EMACSCLIENT` (default `emacsclient`) and `EMACS_ARGS` (more arguments for a new Emacs, split on spaces) choose the
Emacs.

As Git's merge tool (`git mergetool` runs it once for each conflicted file):

```sh
git config --global mergetool.doom.cmd '~/.config/doom/cmd/diff.sh "$MERGED"'
git config --global mergetool.doom.trustExitCode true
git mergetool -t doom          # or set merge.tool doom, then: git mergetool
```

In Emacs, `M-x +my/merge-all` does the same for the current repository. `+my/merge-files` opens a list of files one
after the other, and `+my/merge-then` calls a function once a merge is closed (both in `config/merge.el`). A merge
whose frame is deleted is aborted.

In a terminal the panes' buttons are plain (`>>`, `<<`, `x`), and the mouse doesn't reach them: Emacs gets mouse
clicks in a terminal only with `xterm-mouse-mode`, which this config doesn't turn on. Use the keys (`SPC m l` /
`SPC m r` / `SPC m x`, `C-c C-c` Done, `C-c C-k` Abort; see [Git](git.md#resolving-conflicts)).

Tested by `tests/unit/test-cmd.el`, which runs the script in a pseudo-terminal (`script`) on a temp repository, with a
test Emacs (`tests/diff-sh-emacs.el` stands in for Doom and makes the choice in the panes). Both kinds run: a new Emacs
and a server of its own (a daemon); your Emacs and its server are never used.
