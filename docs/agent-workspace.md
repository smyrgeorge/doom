# Agent workspace

> **Status:** being built (epic `doom-51z`). There are agents, their roles, sessions, worktrees and states, the
> app (its workspace, the issues, the stage, the room), the saved crew, notifications, raised hands answered from
> one place, and loops.

Several coding agents work on a project at once, a **crew**. Each agent has a name, a role and a colour. Each works in
its own git worktree, so they don't get in each other's way or touch your checkout. Each works only with you.

For now, only with you: agents don't talk to each other, and no event from outside reaches them. `config.el` sets
`agent-workspace-agents-talk` and `agent-workspace-outside-events` to `nil`. [The inbox](#the-inbox),
[work handed on](#work-handed-on-through-issues) and [agents asking each other](#agents-asking-each-other) work
again once they're `t`.

![The crew's app: the issues and the minimap, the stage, the room](../examples/agent-workspace.png)

Try it: `M-x +my/example-agent-workspace`, a crew of three stand-in agents, offline.

## The app

`SPC o w`, from inside a project, opens its crew in a workspace of its own, `crew · doom`. Outside a project, it asks
which one. `SPC o W` opens it in the window you're in. The first time, it asks for the crew's first agent.

- **The issues** are on the left. In progress, each with the agent on it. Ready, grouped by the role they're for:
  a role nobody in the crew has is flagged. Blocked, by what. Done today. Moving onto an issue in progress selects its
  agent. The [minimap](#the-minimap) is under them.
- **The stage** is in the middle. Every agent has a pane, in role order. The selected agent's is open: its session,
  and below it (beside it from 140 columns) its Agent UI canvas, its other canvases (`ask`, where it asks you
  things) and its [panels](#an-agents-panels) as tabs, `canvas │ ask │ logs`, one shown at a time. `v` shows the
  next one, `V` the one there full size, in the whole pane (`V` again: back), and a click on a tab shows it.
  Something new on a canvas brings its tab back; a question there doesn't take your cursor. `q` in a canvas closes
  it, as it does when the agent clears it, or once you've answered the question on `ask`: the tab shown before is
  shown, or the session takes the whole pane again. The others are folded to a bar: its avatar, name, role, state
  and how long it's been working, and `◫2` when it has two panels open. The stage arranges itself: drag a border
  and it's tiled again.

  A bar and an open pane's header line show, first on their right, how full the agent's context is: `20%`, green,
  yellow from 60%, red from 85%, as agent-shell colours it. Hover it for its tokens and cost. It's updated as the agent
  reports its usage, and shows nothing until it has.

- **The room** is on the right, 78 columns, or at the bottom in a frame under 200 columns (or with
  `agent-workspace-room-side` set to `bottom`). `2` shows the room alone, `1` the stage again.

`q` leaves the app and the crew goes on. Its tally shows in the other workspaces' mode line (`crew · doom ▶2 !1`), and
a click there brings you back. `Q`, or `SPC TAB d` in its workspace, closes it at once, without asking: every agent
exits, and the crew's windows, buffers and workspace go. Its worktrees stay.

A project that isn't a git repository, or has no commit yet, can't have a crew: `SPC o w` says so and offers a
terminal with `git init` typed.

| Key | In | Action |
|---|---|---|
| `j` / `k` | the issues | The next / previous issue |
| `RET` | the issues | Its agent's pane, or the issue |
| `t` | the issues | Give the issue to an agent: now if it's free, after its turn if it's working |
| `j` / `k` | a bar | The next / previous agent, the cursor in its pane |
| `RET` / `o` / `d` | the minimap | Its agent's pane / the file it's in / its branch's changes |
| `RET` / `TAB` | a bar | Its pane / open or fold it |
| `c` | anywhere | A new agent (on a ready issue: for it) |
| `i` / `K` / `r` | anywhere | Interrupt it / kill it (gone home) / restart it fresh |
| `s` | anywhere | Put it to sleep, or wake it |
| `e` | anywhere | Change its name, colour, role, permission mode or model |
| `d` / `M` | anywhere | Its branch's changes / merge its branch |
| `v` | anywhere | Its canvas and panels, the cursor in the one shown; there, the next one |
| `V` | anywhere | The one shown, full size; again: back beside its session |
| `I` | anywhere | Its issue |
| `L` | anywhere | Its [loop](#loops) on or off: once free, it takes the next ready issue by itself |
| `a` / `A` | anywhere | The next raised hand / answer it |
| `f` + initial | anywhere | That agent |
| `#` | anywhere | Talk to it in the room |
| `1` / `2` | anywhere | The stage / the room alone |
| `m` | anywhere | Show or hide the minimap |
| `P` | anywhere | Pause the crew's events, or let them go again (with the inbox on) |
| `T` | anywhere | May its agents message each other: off, ask me, on (while they may talk) |
| `E` | anywhere | The events waiting: reorder, drop, send now, a source off (with the inbox on) |
| `gr` / `gR` | anywhere | Lay it out again / read `crew.json` again |
| `q` / `Q` / `?` | anywhere | Leave / close / the keys |

In an agent's own session, the same keys follow `SPC m w` (`C-c w` in insert state), plus `]` / `[` for the next or
previous agent. In its canvas and panels, `v` and `V` work too. A click on a bar or a pane's header line
selects its agent, and `mouse-3` there lists its actions.

## The minimap

Under the issues, what each agent did over the last 15 minutes, a lane each:

```text
 CREW  15 minutes                         where now
 ▌A ⚙ ⌕⌕⌕✎✎▶✎✎✎✎▶✎✎✎▶ │ ⚙  src/lexer.el:214
 ▌S ⌕ ··⌕⌕⌕✎✎✎▶!!!!!! │ !  wants to use npm ins…
 quiet ▌K ⚙ ken ○
 ⚠ ada + sam: src/lexer.el
      -15m    -5m now
      ⌕ read  ✎ edit  ▶ run  ! asks you
```

Each agent shows as its avatar and its role's icon (`▶` for a role without one), the icon dimmed with the avatar
(waking, asleep, gone home); hover either for its name and role, `ada · builder`.

A cell is a minute: what the agent did most then (asked you, edited, ran a command, read or searched), `·` for
nothing. After the bar: its state, and the file and line it's in, or what it asks you. Agents that did nothing in those
minutes share the `quiet` line. A file two agents changed (on their branches or uncommitted) is marked `⚠`: they'll
conflict when you merge.

Every cell is one column, so the bars line up from lane to lane: a glyph your font lacks, drawn wider from another
font, gives way to one it has (JetBrains Mono has no `✎`: an edit is `±`, and the legend says so). A line too long for
the window ends in `…`.

On a lane, `RET` selects its agent, `o` opens the file it's in, in its worktree at its line, and `d` shows its branch's
changes. On a `⚠`, `RET` or `d` shows both agents' changes to that file. `m` shows or hides it, and the crew keeps
that. `agent-workspace-minimap-height` sets its height (12 lines); `agent-workspace-minimap` set to `nil` hides it in
new crews.

## The room

One chat for the whole crew: a feed of what matters, and below it a compose line that stays in view.

- **The feed** shows each agent's turns (their answers' first lines), the issues it files, claims and closes, the
  crew's changes (an agent joining, going home, started again, stuck), raised hands, and your messages. With the cursor
  on its last line it follows new lines; anywhere else (scrolled up, a line clicked) it stays put, the cursor on the
  same line. `RET` on a line opens its agent's pane. `F` shows raised hands only, then the selected agent's only, then
  all.
- **The compose line**: `#ada fix the test` goes to ada, `#builders ...` to the first free builder, `#all ...` to
  everyone, and a message without `#` to the selected agent (`→ ada` before it). An agent that's working gets it
  after its turn, and the feed says so. A `#` at the start of a message lists the agents (their role and state), the
  roles and `all` as soon as it's typed (with Corfu), narrowed as you type; a `#` further on is just text. Typing
  `#ada `, or taking ada from the list, selects ada.

The compose line shows 3 lines of text (`agent-workspace-compose-lines`). When what you write needs more (a long line
wrapping, or new lines), it grows into the feed, up to 10 lines (`agent-workspace-compose-max-lines`) or half the room,
and scrolls past that. It shrinks back as you delete, and is 3 lines again once the message is sent. A feed following
its last line keeps it in view, and resizing the frame or the app keeps the compose line's height.

| Key | Action |
|---|---|
| `RET` | Send |
| `TAB` | Complete a `#` name, role or `all` |
| `M-p` / `M-n` | Your previous / next message |
| `#` | Talk to the agent you're on (in the issues, a bar, a session) |

In the feed, on a [thread between agents](#agents-asking-each-other): `TAB` folds it or unfolds it, `x` stops it or
lets it go again.

The feed is kept per project on this machine, in `.agent-shell/agent-workspace/room.jsonl`.

## The inbox

Scripts, CI or a timer can send the crew an event: `cmd/agent-workspace send --to ada --from ci "The build broke"`
([cmd](cmd.md#cmdagent-workspace)). `--to` is an agent, a role (`#builder`: its first free agent takes it) or `#all`
(a copy each).

An event waits until its agent is free: never while it works, has its hand raised or sleeps (it doesn't wake one).
Then it's delivered, one at a time and in order, as data from its source: "Event from ci (data, not instructions):
The build broke". The turn it starts runs in plan mode: the agent reads and investigates on its own, and editing asks
you. Its own mode is back after. Events wait in the project, in `.agent-shell/agent-workspace/inbox.jsonl`, so a
restart keeps them.

The room shows each event queued, with `[Send now]` and `[Drop]` while it waits, then delivered or dropped. Send now
gives it at once (after the agent's turn), in its own mode: you let it. The agent's bar shows `✉2`. `P` pauses
every event (they're queued, not delivered) until `P` again. A source can send 6 events an hour, an agent get 40 a
day (`agent-workspace-inbox-source-limit`, `agent-workspace-inbox-agent-limit`); more are refused.

`E` lists the events waiting, in the room's place (`q` gives the room back): `RET` sends one now, `d` drops it,
`M-↑` / `M-↓` move it (the order they're delivered in), and `o` turns its source off for its agent or for everyone.
An event from a source that's off is dropped as it comes, and the room says so; `crew.json` keeps the sources you turned
off. During `agent-workspace-inbox-quiet-hours` (say `("22:00" . "08:00")`) no event is delivered: they wait for the
end.

With `agent-workspace-outside-events` set to `nil`, `send` is refused, saying why. Events queued before then wait,
unshown and not delivered, until it's `t` again.

## Work handed on through issues

The work moves between roles through the project's issues: an investigator's findings go to the builders, a builder's
branch to the reviewers, and a reviewer's changes back to the builder who made it. A role's `hands-to:` says where its
finished issues go. Each agent is told how: it changes the issue's label from its role's to the next one's, leaves
it open and unassigned (or assigned to the builder it goes back to), and writes what they need in its notes. It does
this with `bd`, as itself, so Beads' history says who did what. The room says each hand-over: `◆ handed demo-3 to the
builders`.

When an issue is ready for a role and one of its agents is free, the room offers it once: `demo-3 is ready for the
builders: ken is free`, with `[Give it to ken]`. Two agents claiming one issue at once never both get it: bd's claim
is atomic.

With `agent-workspace-agents-talk` set to `nil`, nothing is handed on: an agent whose role hands on is told to leave
the issue as it is and tell you. The room still offers a ready issue, for you to give.

## Agents asking each other

Issues carry the work between agents; a message is for a question. An agent sends one from its shell:
`cmd/agent-workspace send --to ken "What does the lexer return?"` (to an agent, or `#reviewer`, a role's first free
agent). `T` in the app says whether they may, kept in `crew.json`:

- **Ask me**, at first: each message waits in the room, `ada → ken`, for `[Send]`, `[Edit]` or `[Drop]`.
- **On**: sent at once. **Off**: refused, and the agent is told so.

A role's `talks-to: reviewer` lets its agents message reviewers without your OK. Once sent, a message goes through the
[inbox](#the-inbox): it waits until its agent is free, and never wakes one asleep. It's told as from the sender, data
and not your instructions, in plan mode. Its reply goes back to the sender the same way, as an answer, and an answer
gets none.

In the room, each exchange between two agents is a thread, with the issue the sender is on (`ada → ken … · demo-1`).
`TAB` folds a thread to its first line, and `x` stops it: its waiting messages are dropped and the agents can't send
more (the sender is told), until `x` again. `[Answer]` on a message answers its sender yourself, instead of the agent
it was for. Guards: a thread waits for your OK after 5 messages without you (`agent-workspace-thread-pause`), and an
agent sends at most 10 messages an hour (`agent-workspace-message-limit`). Each agent is told its crew, how to message,
which roles it may message without your OK, and never to wait for an answer.

With `agent-workspace-agents-talk` set to `nil`, a message is refused, whatever `T` says (`crew.json` keeps it), and
`T` says so. Agents aren't told of messages, and those queued before wait, not delivered.

## Raised hands

When several agents wait for you, you can answer them from one place. A raised hand's options are buttons under it in
the room, on its agent's bar and on its pane's header line:

- a permission's are agent-shell's own: Allow, Always allow, Reject;
- a question on the agent's canvas (a choice) has its options;
- anything else has "Go to it", which opens the agent's pane at the question: its canvas's tab, the cursor on
  it.

`a` goes to the next raised hand, across the crew, and `A` answers it. Once you answer from the room, it says what you
picked ("→ Allow (you)"). A hand answered in its session leaves the room.

## Loops

An agent can work through the project's issues by itself. `L` turns its loop on, and off again. Every agent starts
with its loop off, and its bar shows `↻` while it loops.

Once free, a looping agent takes the next issue: one you gave it first (`t`), else the next ready one its role's
`labels` say, the highest priority first. It claims it as itself (`bd ready --claim`), so two looping agents never get
the same one. Its session starts again for each issue, a fresh context, and it gets the issue as `t` gives it ("Work
on doom-a1b: ...").

It's free once its turn has ended and the issue it had is closed, or handed over. A turn that ends with its issue still
in progress is done, for you to look: it waits. Close the issue (or tell it to) and it takes the next. A raised hand
waits for you too.

When no issue is left, it naps: `☾ napping: nothing to build`. The room says so once, with a notification. It wakes
when an issue for it comes: when the project's issues change, and every 5 minutes (`agent-workspace-loop-check`). A
look that finds nothing says nothing.

If its turn stops on an error, its session doesn't start, or `bd` fails, it tries again 30 seconds later
(`agent-workspace-loop-retry`): the same issue, in its session. After 3 failures in a row
(`agent-workspace-loop-failures`) it stops: stuck, saying why. A turn that ends without an error breaks the row, and
`r`, `s` or `L` start it again.

Its loop is kept in the [saved crew](#the-saved-crew). A crew started again brings a looping agent back asleep, so
reopening never starts work by itself: wake it (`s`) and it loops. A role without `labels` has no issues to take, and
a project without Beads has none either: their agents can't loop.

## An agent's panels

An agent can open [project panels](agent-ui.md#project-panels) and keep them open while it works (a test watcher, a
service's logs). A panel it opens runs in its worktree, on its branch's code, and is its own: `tests · ada`. Two agents
opening `tests` get one each, and yours from the main checkout stays yours. They're tabs in its pane, beside its
canvas (`v` shows them), and its bar and header line count them: `◫2`. It reads them as data
(`agent-ui get --panel tests`), and a panel whose tab isn't shown fetches only when its agent reads it. They share the
project's trust: trust the project and its agents' worktrees are trusted too, but a panel file changed on an agent's
branch is asked about again. They close when the agent is killed, put to sleep or forgotten, and when the crew closes.
Renamed, it keeps them: they open again in its moved worktree, under its new name. They're saved with the crew, by name, and open again when it starts again ([The saved crew](#the-saved-crew)).

## Notifications

While you're in another app, a notification names the agent: a hand raised ("ada (builder) wants to run npm
install"), a turn finished, stuck, napping (its [loop](#loops) found nothing left), or a message of its own. A click
opens its crew with it selected. `SPC t N` turns each kind off ([Notifications](notifications.md)).

## The saved crew

The crew is kept per project on this machine, in `.agent-shell/agent-workspace/crew.json`, beside the room and the
inbox, not committed: each agent's name, role and colour, its model and permission mode when they aren't its role's,
whether it's asleep, whether it [loops](#loops), the [panels](#an-agents-panels) it has open (by name, never their
data), which agent is selected, whether the minimap is shown, whether its agents may message each other, and the event
sources you turned off. Not its session, state or issue.

```json
{"version": 2,
 "agents": [
  {"name": "ada", "role": "builder", "colour": "blue", "loop": true, "panels": ["logs", "tests"]},
  {"name": "ken", "role": "builder", "colour": "green", "asleep": true},
  {"name": "sam", "role": "investigator", "colour": "magenta", "model": "opus"}
 ],
 "layout": {"view": "stage", "room": "right", "selected": "ada", "open": true, "minimap": true,
            "talk": "ask", "sources_off": []}}
```

It's written when the crew changes (a panel opened or closed too), one agent a line, and read as JSON, never run, so
scripts can read it too (`jq`). Closing the crew leaves it as it was, its agents' panels in it. `SPC o w` in a project
whose crew isn't running starts every agent in it again: fresh, each in its worktree, with its role as it is now, its
panels open again there (fetched afresh), waiting for you. Asleep agents stay asleep, and their panels open when they
wake. Looping agents come back asleep: reopening never starts work by itself. An agent that can't start (its role is
gone, its worktree can't be made) is stuck, saying why, and the others start. A panel whose file is gone is skipped,
saying so, and the others open. A wrong agent is left out, and a warning names it (`crew.json: agent 2 (ken): its
colour "pink" isn't one of ...`). A file that isn't JSON, or isn't a crew, is said, nothing starts, and it's kept as it
is until you make an agent.

After you edit it, `gR` reads it again. It asks before it starts an agent, forgets one or turns a loop on; a colour, the
panels or a loop turned off it applies.

## Making an agent

`c` in the app (or `M-x agent-workspace-new` in the project) asks for:

1. **Its role.** Each one says what it does and how many of it run against its maximum: `builder · builds what you
   give it · 2 of 4`. A role at its maximum is refused.
2. **Its name.** Leave it empty and one is made for it, `ada`, `grace`, `linus`..., each with an initial no other
   agent has. A name is lowercase letters, digits and `-`.

With `C-u`, it also asks for its model, permission mode and colour. Its role's are the defaults (its mode: auto,
unless its role says).

The agent gets its worktree and its session starts. Then it waits for you. If its worktree can't be made, nothing is
made, and you're told why. If its session doesn't start, it's stuck, saying why.

From Lisp, `:issue` makes it for an issue, which is its first message ("Work on doom-a1b: ..."):

```elisp
(agent-workspace-create :role "builder" :name "ada" :issue "doom-a1b" :issue-title "Fix the thing")
```

From the shell: `cmd/agent-workspace new --role builder [--name ada] [--prompt TEXT]` ([more](cmd.md#cmdagent-workspace)).

## An agent

- **Its session** is a Claude Code session in agent-shell, in the buffer `ada · builder`. It's told who it is, that
  it works with you only, and to commit in its worktree, then its role's instructions. Its role's model and tools
  apply.
- **Its permission mode** is Claude Code's auto mode: Claude decides what needs your OK. A role's `mode` changes it
  for its agents, and `e` for one agent. `agent-workspace-mode` sets it for all (`nil`: Claude Code's own default).
  The agent's bar shows it.
- **Its worktree** is `.agent-shell/worktrees/builder-ada` (its role, then its name), on the branch `agent/ada`,
  branched from your checkout's HEAD. It's made with the agent and kept when the agent stops, so the next start finds
  its work. Renaming the agent or changing its role moves it; one named `worktrees/ada`, from before, moves when its
  agent starts. It's locked with the agent's name as the reason (`git worktree list -v`). `.agent-shell/` stays out
  of git. A project that isn't a git repository, or has no commit yet, can't have a crew.
- **Its colour** is one of the theme's ANSI colours, a free one by default.
- **Its name** goes into the issues' history: its `bd` commands run as `ada`.

## Roles

A role is what a kind of agent does and may do. These four ship with this config:

| Role | Does | May |
|---|---|---|
| scribe | writes issues with you | read, `bd`; no edits |
| investigator | investigates what you give it, writes its findings into the issue, hands it to the builders | read, search the web, `bd`; no edits |
| builder | builds what you give it, runs the tests, commits on its branch, hands it to the reviewers | edit, commit; never push |
| reviewer | reviews a branch, approves it to you or hands it back to its builder | read, `bd`; no edits |

Each role is a Markdown file, as Claude Code's own agents are: a front matter, then its instructions.

```markdown
---
description: writes and runs tests
tools: Read, Edit, Bash(npm test:*)
deny: WebFetch
model: haiku
mode: acceptEdits
labels: test
max: 2
icon: md-flask ⚗
verb: testing
colour: yellow
---
Write the tests first, then run them.
```

- `tools` are allowed without asking. `deny` are never offered. `mode` is Claude Code's permission mode (the four
  have none: their agents run in auto mode). Claude Code enforces all three.
- `max` is how many of the role may run at once. `labels` are the issues it's for. `talks-to` names the roles it may
  [message](#agents-asking-each-other) without your OK. `hands-to` names the role its finished issues
  [go to](#work-handed-on-through-issues).
- `icon` is a nerd icon for the GUI, then a glyph for the terminal. `verb` is what its agents show while they work:
  "testing doom-a1b". `colour` is its agents' colour while it's free.

A project's own roles go in its `.agent-workspace/roles/`, committed. They add to the four, or replace the one with the
same name. `M-x agent-workspace-copy-role` copies one of the four there for you to change. A file with a mistake is
left out, and a warning names its file and line.

## Its states

| State | Means |
|---|---|
| waking up | its session is starting |
| at the desk | it waits for you |
| working | its turn runs, timed from its start |
| hand raised | it waits for a permission or an answer: "wants to run npm install" |
| done, have a look | its turn ended; once you show its session, it's at the desk |
| napping | it [loops](#loops) and no issue is ready for it: "napping: nothing to build" |
| stuck | an error stopped it |
| asleep | you stopped it; it stays in the crew |
| gone home | killed, or its process ended |

## Its name on its worktree

- Its worktree is a project of its own, named `doom · ada`.
- A file of its worktree shows the agent in its mode line, in its colour: `▌A ada · builder`. A click there selects the
  agent.
- That file's tab starts with the agent's avatar, `▌A`.
- A worktree left by an agent you've forgotten shows its name dimmed.

## Its branch

| Command | Does |
|---|---|
| `M-x agent-workspace-review` | An agent's changes in magit: what its branch did since it left yours (`main...agent/ada`) |
| `M-x agent-workspace-merge` | Merges its branch into your checkout, tells the agent, and offers to reset its branch to the result |

A merge always makes a merge commit naming the agent's branch, even when it could fast-forward: its commits stay told
apart from yours. A merge that conflicts stops in your checkout, for you to resolve.

## What you do to one

You can interrupt an agent, kill it, restart it fresh, put it to sleep, wake it, rename it (its worktree and branch
follow), change its role (its worktree follows; not while it works) or recolour it. Killing it gives back the issue you gave it, if it's still in progress and assigned to the
agent.

Forgetting an agent takes it out of the crew. Its worktree and branch go too when they hold nothing your checkout
hasn't. Otherwise you're shown what they hold (changes not committed, commits not on your branch) and asked whether
to keep them.

Closing the crew, or quitting Emacs, stops every agent at once, without asking. No process of theirs is left
running. Their worktrees stay.
