# Shell commands

The commands in `cmd/` work with Emacs from a shell, for you, your scripts and your agents.

`cmd/agent-ui`, `cmd/agent-workspace` and `cmd/agent-workflow` talk to your running Emacs, which must be a server. They
reply with JSON on stdout, and exit with these codes:

| Exit code | Meaning |
|---|---|
| 0 | Done |
| 1 | Not done. The reply says why |
| 2 | A wrong use |
| 3 | No Emacs server to talk to |

## cmd/diff

`cmd/diff` resolves Git conflicts in the [three-pane merge](git.md#resolving-conflicts), one file after the other. It
uses your running Emacs if it's a server, or else starts a new one.

```sh
cmd/diff                 # every conflicted file of the repository
cmd/diff a.txt src/b.py  # those files
cmd/diff example         # the merge example
cmd/diff --list          # list the conflicted files
```

| Option | What |
|---|---|
| `-g`, `--gui` | Open a GUI frame |
| `-n`, `--new` | Always start a new Emacs |
| `-s NAME`, `--socket NAME` | Use the Emacs server NAME |
| `-l`, `--list` | List the conflicted files |

It exits with 0 when every file is resolved, 1 when files are still in conflict, and 2 for a wrong use.

To use it as Git's merge tool, run this once:

```sh
git config --global mergetool.doom.cmd '~/.config/doom/cmd/diff "$MERGED"'
git config --global mergetool.doom.trustExitCode true
```

Then `git mergetool -t doom` runs it.

## cmd/agent-ui

`cmd/agent-ui` shows things in a coding agent's session, on its canvas: progress bars, checklists, tables. It's made for
agents, to run from their shell. It runs the [agent-ui](https://github.com/smyrgeorge/agent-ui) package's own command
(its `bin/agent-ui`, as Doom built it); [Agent UI](agent-ui.md) has the details.

```sh
cmd/agent-ui show '{"id":"build","type":"progress","title":"Build","max":12}'
cmd/agent-ui update build '{"value":5,"label":"linking"}'
cmd/agent-ui types           # what it can show
cmd/agent-ui show --canvas tests '{"id":"t","type":"table","columns":["Test","Result"]}'
                             # another canvas of the session, its own pane
```

The agent-ui package's `agent-ui-mcp.el` serves the same operations as MCP tools. Each agent-shell session starts it this way:
`emacs --batch -Q -l agent-ui-mcp.el -f agent-ui-mcp-main`.

## cmd/agent-workspace

`cmd/agent-workspace` works with the crew of this folder's project, for your scripts
([Agent workspace](agent-workspace.md)). It makes agents, sends them events, shows the crew and runs it.

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

| Command | Reply |
|---|---|
| `new` | `{"ok":true,"name":"ada","role":"builder","worktree":...,"branch":"agent/ada",...}` |
| `crew` | `{"ok":true,"made":[{"name":"ken","role":"reviewer",...}]}`, or `"made":[]` when the crew lacks nothing |
| `send` | `{"ok":true,"events":[{"id":1,"to":"ada","state":"queued"}]}` |
| `status` | `{"ok":true,"agents":[...],"conflicts":[...],"offers":[...],"talk":"ask"}` |
| `give`, `wake`, `sleep`, `loop` | The agent, as `new` has it. `give` adds `"prompt":"sent"` or `"queued"`, and `loop` adds `"loop":true` |

- `crew` lists the agents it couldn't make in `"failed":[{"role":"reviewer","error":...}]`. For an unknown crew, it
  names the crews there are.
- `give`, `wake`, `sleep` and `loop` are said in the room, with who did them (`shell gave doom-a1b to grace`).
- From an agent's session, `give`, `wake`, `sleep`, `loop`, `new` and `crew` are refused unless the agent's role leads
  ([The lead](agent-workspace.md#the-lead)). This holds whatever its `AGENT_WORKSPACE_AGENT` says. `status` works from
  any session.
- An event is queued, and delivered when its agent is free, as data from its source
  ([The inbox](agent-workspace.md#the-inbox)).
- `send` is refused for now, because `config.el` turns events from outside off:
  `(setq agent-workspace-outside-events nil)`. `t` turns them on.

## cmd/agent-workflow

`cmd/agent-workflow` starts the runs of [agent workflows](agent-workflow.md), and checks the workflows and agents of
this folder's project. It's for you and your scripts. An agent of a run ends its step with it. It runs the
[agent-workflow](https://github.com/smyrgeorge/agent-workflow) package's own command (its `bin/agent-workflow`, as Doom
built it); its [docs](https://github.com/smyrgeorge/agent-workflow/blob/main/docs/command-line.md) have the details.

```sh
cmd/agent-workflow run doom-a1b doom-c3d          # runs on these issues, each with its own workflow, followed
cmd/agent-workflow run doom-epic --workflow quick --detach  # an epic's open issues, with quick: started only
cmd/agent-workflow logs doom-a1b -f               # its run's log, followed until it ends (--json: its journal)
cmd/agent-workflow status                         # every run not over (status ISSUE: its latest)
cmd/agent-workflow done changes "notes"           # from an agent of a run: its step is done
cmd/agent-workflow back doom-a1b build "note"     # a run sent back to a job, the work kept
cmd/agent-workflow confirm doom-a1b go           # a run's question answered: go, accept, skip or stop
cmd/agent-workflow approve doom-a1b              # the result waiting for your OK: on (reject ISSUE "note": back)
cmd/agent-workflow continue                       # interrupted runs on again (cancel ISSUE, pause, unpause)
cmd/agent-workflow dry-run feature --outcome review=changes,approved   # nothing run: what would happen
cmd/agent-workflow check                          # every workflow and profile of the project
cmd/agent-workflow check draft.yml                # one file: a workflow (.yml) or a profile (.md), anywhere
```

| Command | Reply |
|---|---|
| `run --detach` | The runs started, and the issues refused |
| `done` | The step done |
| `status` | The runs' state, and their jobs |
| `check` | The project's workflows and agents, and each problem's level, file, line and message. It exits with 0 when there's no error |

- `run` and `logs -f` print a run's log instead, a line per event, until the runs end. A line says the time, the issue,
  the job and what happened. What needs you comes with the command that answers it.
- `run` exits with 0 when all its runs are done, and 1 when one was cancelled.
- Ctrl-C stops following the log, never the runs.
- With `--json`, they print the reply, then the journals' lines, each with its `issue`.
