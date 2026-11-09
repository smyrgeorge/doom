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

## cmd/agent-ui

Shows things in Emacs beside a coding agent's session, on its canvas: progress bars, checklists, tables. Made for
agents, from their shell; see [Agent UI](agent-ui.md).

```sh
cmd/agent-ui show '{"id":"build","type":"progress","title":"Build","max":12}'
cmd/agent-ui update build '{"value":5,"label":"linking"}'
cmd/agent-ui types           # what it can show
```

The reply is JSON on stdout; it exits with 0 when done, 1 when not (the reply says why), 2 for a wrong use, 3 without
an Emacs server. `cmd/agent-ui-mcp.el` serves the same operations as MCP tools (`emacs --batch -Q -l
cmd/agent-ui-mcp.el -f agent-ui-mcp-main`), as each agent-shell session starts it.
