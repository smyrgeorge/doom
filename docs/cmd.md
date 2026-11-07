# Shell commands

## cmd/diff.sh

Resolves Git conflicts in the [three-pane merge](git.md#resolving-conflicts) from the shell, one file after the other:

```sh
cmd/diff.sh                  # every conflicted file of the repository
cmd/diff.sh a.txt src/b.py   # those files
cmd/diff.sh example          # the merge example
cmd/diff.sh --list           # list the conflicted files
```

It opens in your running Emacs (a new frame in the terminal) when it's a server, else starts one. `-g` opens a GUI frame
instead, `-n` always starts a new Emacs, `-s NAME` picks a server. It exits with 0 when everything is resolved, 1 when
some files are still in conflict, 2 on a wrong use.

As Git's merge tool:

```sh
git config --global mergetool.doom.cmd '~/.config/doom/cmd/diff.sh "$MERGED"'
git config --global mergetool.doom.trustExitCode true
```
