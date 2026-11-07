# Shell commands

## cmd/diff.sh

Resolves Git conflicts in the [three-pane merge](git.md#resolving-conflicts), one file after the other, in your running
Emacs if it's a server, else in a new one.

```sh
cmd/diff.sh                  # every conflicted file of the repository
cmd/diff.sh a.txt src/b.py   # those files
cmd/diff.sh example          # the merge example
cmd/diff.sh --list           # list the conflicted files
```

`-g` opens a GUI frame, `-n` always starts a new Emacs, and `-s NAME` picks a server. It exits with 0 when everything is
resolved, 1 when files are still in conflict.

As Git's merge tool:

```sh
git config --global mergetool.doom.cmd '~/.config/doom/cmd/diff.sh "$MERGED"'
git config --global mergetool.doom.trustExitCode true
```
