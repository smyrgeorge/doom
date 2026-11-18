# Shell commands

## cmd/diff

Resolves Git conflicts in the [three-pane merge](git.md#resolving-conflicts), one file after the other, in your running
Emacs if it's a server, else in a new one.

```sh
cmd/diff                 # every conflicted file of the repository
cmd/diff a.txt src/b.py  # those files
cmd/diff example         # the merge example
cmd/diff --list          # list the conflicted files
```

`-g` opens a GUI frame, `-n` always starts a new Emacs, and `-s NAME` picks a server. It exits with 0 when everything is
resolved, 1 when files are still in conflict.

As Git's merge tool:

```sh
git config --global mergetool.doom.cmd '~/.config/doom/cmd/diff "$MERGED"'
git config --global mergetool.doom.trustExitCode true
```

It was `cmd/diff.sh` before: a merge tool set up with that name needs the first line run again.

## cmd/agent-ui

Shows things in Emacs beside a coding agent's session, on its canvas: progress bars, checklists, tables. Made for
agents, from their shell; see [Agent UI](agent-ui.md).

```sh
cmd/agent-ui show '{"id":"build","type":"progress","title":"Build","max":12}'
cmd/agent-ui update build '{"value":5,"label":"linking"}'
cmd/agent-ui types           # what it can show
cmd/agent-ui show --canvas tests '{"id":"t","type":"table","columns":["Test","Result"]}'
                             # another canvas of the session, its own pane
```

The reply is JSON on stdout; it exits with 0 when done, 1 when not (the reply says why), 2 for a wrong use, 3 without
an Emacs server. `cmd/agent-ui-mcp.el` serves the same operations as MCP tools (`emacs --batch -Q -l
cmd/agent-ui-mcp.el -f agent-ui-mcp-main`), as each agent-shell session starts it.

## cmd/agent-workspace

Makes an agent in this folder's project, or the agents a crew lacks, or sends its crew an event; shows the crew and
runs it, for your scripts; see [Agent workspace](agent-workspace.md).

```sh
cmd/agent-workspace new --role builder                  # a name made for it
cmd/agent-workspace new --role investigator --name sam --prompt "Look into doom-a1b"
cmd/agent-workspace crew full                           # the crew file full's agents the crew lacks
cmd/agent-workspace send --to ada --from ci "The build broke on main"
cmd/agent-workspace send --to '#builder' --from cron - < triage.txt   # a role's first free agent; - reads stdin
cmd/agent-workspace status                              # the crew as it is
cmd/agent-workspace give doom-a1b --to grace            # as t: claimed as grace, sent now or after her turn
cmd/agent-workspace sleep linus                         # as Z
cmd/agent-workspace wake linus
cmd/agent-workspace loop linus on                       # as L; off turns it off
```

`give`, `wake`, `sleep` and `loop` are said in the room with who did them (`shell gave doom-a1b to grace`). From an
agent's shell they're refused unless its role leads (the [lead](agent-workspace.md#the-lead)); `status` works from
any.

An event is queued and delivered when its agent is free, as data from its source
([The inbox](agent-workspace.md#the-inbox)). For now `send` is refused: this config turns events from outside off. The reply is JSON on stdout
(`{"ok":true,"name":"ada","role":"builder","worktree":...,"branch":"agent/ada",...}` for new,
`{"ok":true,"made":[{"name":"ken","role":"reviewer",...}]}` for crew, `"made":[]` when it lacks nothing, those not
made in `"failed":[{"role":"merger","error":...}]`, an unknown crew naming the crews there are,
`{"ok":true,"events":[{"id":1,"to":"ada","state":"queued"}]}` for send, `{"ok":true,"agents":[...],"conflicts":[...],
"offers":[...],"talk":"ask"}` for status, the agent as new has it for give, wake, sleep and loop, with `"prompt":"sent"`
or `"queued"` for give and `"loop":true` for loop); it exits with 0 when done, 1 when not (the reply says why), 2 for a
wrong use, 3 without an Emacs server.
