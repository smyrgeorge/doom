# Agent workspace

> **Status:** being built. For now, events from outside are off ([the inbox](#the-inbox)).

Several coding agents work on one project at once, as a **crew**. Each has a name, a role and a colour, and works in its
own git worktree, so agents don't get in each other's way or touch your checkout. They [ask each
other](#agents-asking-each-other) questions and [hand work on](#work-handed-on-through-issues) as their roles say.

![The crew's app: the issues and the minimap, the stage, the room](../examples/agent-workspace.png)

Try it: `M-x +my/example-agent-workspace`, a crew of three stand-in agents, offline.

## The app

`SPC o w`, from inside a project, opens its crew in a workspace of its own, named `crew · doom`. The app shows the
project's issues on the left, the stage where the agents work in the middle, and [the room](#the-room) on the right. The
first time, the stage is empty and says so: `c` makes an agent, or a whole [crew](#crews).

| Key | Action |
|---|---|
| `SPC o w` | Open the project's crew (outside a project, it asks which) |
| `SPC o W` | Open it in the window you're in |
| `c` | A new agent, or a whole [crew](#crews) |
| `q` | Leave the app; the crew goes on |
| `Q` or `SPC TAB d` | Close the crew at once |
| `M-x +my/example-agent-workspace` | Try it: three offline agents |

- When another open crew's project has the same folder name, the workspace's name adds the parent folder's:
  `crew · b/web`.
- A project that isn't a git repository, or has no commit yet, can't have a crew. `SPC o w` says so and offers a
  terminal with `git init` typed.
- In a small frame (a terminal's 80x24), the issue list narrows and the room at the bottom shrinks, or goes (`2` shows
  it). An agent's pane still opens.
- When you leave with `q`, the crew goes on. Its lanes show [under treemacs](#the-crew-under-treemacs) while treemacs
  shows the project, and the mode line shows what needs you. A click there brings you back.
- `Q`, or `SPC TAB d` in its workspace, closes the crew at once, without asking. Every agent exits, and the crew's
  windows, buffers and workspace go. Its worktrees stay.

### The issues

The issues are on the left, grouped by where they stand. Moving onto an issue in progress selects its agent. The
[minimap](#the-minimap) is under them.

- **In progress:** each with the agent on it.
- **Ready:** grouped by the role they're for, then by epic. A role nobody in the crew has is flagged. Each epic's
  heading says how many of its issues are there, and its issues are under it. A subtask goes under its nearest epic, and
  issues of no epic come last.
- **Blocked:** grouped by what blocks them. bd's `blocked` status counts too.
- **Done today.**
- Deferred issues aren't shown, nor bd's pinned and hooked ones.
- Each issue's type comes before its id: its icon in its colour, as in the [issue list](issues.md#the-list). In a
  terminal, it's the type's first letter.

### The stage

The stage is in the middle. Every agent has a pane there, in role order. The selected agent's pane is open, and the
others are folded to a bar.

- An open pane shows the agent's session. Below it is its [Agent UI](agent-ui.md#in-the-sessions-pane), as in any
  session's pane: its canvas, its other canvases (`ask`, where it asks you things) and its [panels](#an-agents-panels).
  They're laid out to use the room, each with a bar naming it.
- `v` goes into them, and again to the next one. `V` lets Agent UI take the whole pane, the session keeping its last
  lines; `V` again goes back.
- A question in Agent UI doesn't take your cursor.
- `q` in a view closes it. A view also goes when the agent clears it, or once you've answered the question on `ask`.
  With no view left, the session takes the whole pane again.
- A folded agent's bar shows its avatar, name, role, state and how long it's been working. It shows `◫2` when the agent
  has two panels open.
- A bar and an open pane's header line show, first on their right, how full the agent's context is: `20%`. It's green,
  yellow from 60% and red from 85%, as agent-shell colours it. Hover it for the tokens and cost. It's updated as the
  agent reports its usage, and shows nothing until it has.
- The stage arranges itself: drag a border and it's tiled again.

### Keys

| Key | Where | Action |
|---|---|---|
| `j` / `k` | the issues | The next / previous issue |
| `RET` | the issues | Its agent's pane, or the issue (on an epic's heading, the epic) |
| `t` | the issues | Give the issue to an agent, on a [branch of its own](#its-branches): now if it's free, after its turn if it's working |
| `gr` | the issues | Read the issues again |
| `j` / `k` | a bar | The next / previous agent, the cursor in its pane |
| `RET` / `TAB` | a bar | Its pane / open or fold it |
| `RET` / `o` / `d` | the minimap | Its agent's pane / the file it's in, or was last in / its branch's changes |
| `c` | anywhere | A new agent, or the agents a [crew](#crews) lacks (on a ready issue: an agent for it) |
| `i` / `K` / `r` | anywhere | Interrupt it / kill it (gone home) / restart it fresh |
| `X` | anywhere | [Forget it](#what-you-do-to-one): out of the crew (asked first) |
| `Z` | anywhere | Put it to sleep, or wake it |
| `e` | anywhere | Change its name, colour, role, permission mode or model |
| `d` / `M` | anywhere | Its [branch](#its-branches)'s changes / merge its branch |
| `b` | anywhere | The [branches waiting to be merged](#its-branches), in the stage's place (`q` back) |
| `v` | anywhere | Its Agent UI, the cursor in its first view; there, the next view |
| `V` | anywhere | Its Agent UI full size, the session keeping its last lines; again: back |
| `I` | anywhere | Its issue |
| `L` | anywhere | Its [loop](#loops) on or off: once free, it takes the next ready issue by itself |
| `a` / `A` | anywhere | The next raised hand / answer it |
| `f` + a letter | anywhere | The agent whose name starts with it |
| `#` | anywhere | Talk to it in the room |
| `1` / `2` | anywhere | The stage / the room alone |
| `m` | anywhere | Show or hide the minimap |
| `P` | anywhere | Pause the crew's events, or let them go again (with the inbox on) |
| `T` | anywhere | May its agents message each other: off, ask me, on (while they may talk) |
| `E` | anywhere | The events waiting: reorder, drop, send now, turn a source off (with the inbox on) |
| `gr` / `gR` | anywhere | Lay the app out again / read `crew.json` again |
| `q` / `Q` | anywhere | Leave / close |
| `?` | anywhere | The keys of where you are (a bar, the issues, the minimap, the room, the branches, the inbox), then the app's |

### In an agent's session

The app's keys work in an agent's own session too, after a prefix.

| Key | Action |
|---|---|
| `SPC m w` + a key (`C-c w` in insert state) | The app's key, for this agent |
| `SPC m w ]` / `SPC m w [` | The next / previous agent |
| `v` / `V` (in its canvas or panels) | As in the app |
| A click on a bar or a pane's header line | Select its agent |
| `mouse-3` on a bar or a header line | Its actions |

## The minimap

The minimap is under the issues. It shows what each agent did over the last 15 minutes, a line each, in the crew's
order.

```text
 CREW  15 minutes                         where now
 ▌A ⚙ ⌕⌕⌕✎✎▶✎✎✎✎▶✎✎✎▶ │ ⚙  src/lexer.el:214
 ▌K ⚙ ··············· │ ○  at the desk
 ▌S ⌕ ··⌕⌕⌕✎✎✎▶!!!!!! │ !  wants to use npm ins…
 ⚠ ada + sam: src/lexer.el
      -15m    -5m now
      ⌕ read  ✎ edit  ▶ run  ! asks you
```

| Key | Action |
|---|---|
| `RET` (on an agent's line) | Select its agent |
| `o` | Open the file it's in, in its worktree at its line (once its turn is over, the one it was last in) |
| `d` | Its branch's changes |
| `RET` or `d` (on a `⚠`) | Both agents' changes to that file |
| `j` / `k` | The next / previous lane |
| `m` (anywhere in the app) | Show or hide the minimap; the crew keeps your choice |

- Each lane starts with the agent's avatar and its role's icon (`▶` for a role without one). The icon is dimmed with the
  avatar: waking, asleep, gone home. Hover either for the agent's name and role, `ada · builder`.
- A cell is a minute. It shows what the agent did most then: asked you, edited, ran a command, or read and searched. `·`
  means nothing.
- After the bar comes the agent's state. While it works, the file and line it's in this turn follow. While its hand is
  raised, what it asks you follows. Otherwise (before its turn touches a file, done, at the desk), its state is in
  words, dimmed.
- An agent that did nothing in those minutes has a lane of `·`.
- `⚠` marks a file changed on two branches, committed there or uncommitted in two worktrees: they'll conflict when you
  merge. Agents on one branch (a reviewer on its builder's) count as one.
- An agent's changed files are checked again when its turn ends and when its branch changes. A branch it leaves no
  longer counts as its.
- Every cell is one column, so the bars line up from lane to lane. A glyph your font lacks gives way to one it has:
  JetBrains Mono has no `✎`, so an edit is `±`, and the legend says so.
- A line too long for the window ends in `…`.
- The minimap is as tall as its lines, with the axis and legend under them, and half a line of space above and below (a
  blank line below, in a terminal). With no agents, it's one line: `No agents yet.`
- Past 10 lanes, the lanes scroll (`j`, `k` or the wheel), and the axis and legend stay under them.

| Setting | Default | What |
|---|---|---|
| `agent-workspace-minimap` | `t` | `nil` hides the minimap in new crews |
| `agent-workspace-minimap-lines` | `10` | The most lanes shown before they scroll, here and under treemacs |

## The crew under treemacs

Once you've left the app, the minimap shows under treemacs, while treemacs shows the crew's project. It's as wide as
treemacs, its lines cut to fit.

```text
 CREW · doom          ▶1 !1
 ▌A ⚙ ⌕⌕⌕✎✎▶✎✎✎✎▶✎✎✎▶ │ ⚙  …el:214
 ▌S ⌕ ··⌕⌕⌕✎✎✎▶!!!!!! │ !  wants…
      -15m    -5m now
      ⌕ read  ✎ edit  ▶ run  ! as…
```

| Key | Action |
|---|---|
| `RET` or a click (on a lane) | Open the app with that agent selected |
| A click on its header | Open the app |
| A click on the mode line's tally | Open the app |

- It's as tall as the minimap, and padded alike. It shows at most 10 lanes, then they scroll with the wheel, the axis
  and legend under them.
- It goes when treemacs closes or shows another project. It isn't shown in the crew's own frame, where the minimap shows
  it all.
- Meanwhile, the mode line of the frames not showing the crew says what needs you: hands raised, done, stuck (`!1 ✓1`).
  It says nothing while agents only work.

| Setting | Default | What |
|---|---|---|
| `agent-workspace-mode-line-tally` | `needs-you` | `all` counts the working agents too; `nil` shows nothing |
| `agent-workspace-sidebar` | `t` | `nil` keeps the crew from treemacs |

## The room

The room is one chat for the whole crew: a feed of what matters, and below it a compose line that stays in view. It's on
the right, 78 columns wide, or at the bottom in a frame under 200 columns. `2` shows the room alone, and `1` the stage
again.

| Key | Action |
|---|---|
| `RET` | Send (in the compose line); open the line's agent's pane (in the feed) |
| `TAB` | Complete a `#` name, role or `all` |
| `M-p` / `M-n` | Your previous / next message |
| `i` or `#` (in the feed) | Go to the compose line |
| `F` (in the feed) | Raised hands only, then the selected agent's only, then all |
| `TAB` / `x` (on a [thread](#agents-asking-each-other)) | Fold or unfold it / stop it, or let it go again |
| `#` (in the issues, a bar, a session) | Talk to the agent you're on |
| `q` / `Q` | In Evil's normal state: leave / close the app, as anywhere in it |

The feed shows:

- each agent's turns: the first lines of its answers;
- the issues an agent files, claims, labels, hands on and closes, as the issues show them after its `bd` commands and
  turns. Your own changes, and what was there when the app opened, aren't shown;
- the crew's changes: an agent joining, going home, started again, stuck;
- raised hands;
- your messages: those from the compose line, and those you type in an agent's session or answer on its canvas
  (`you → ada`, before its answer). One queued while the agent works shows once it's sent.

With the cursor on its last line, the feed follows new lines. Anywhere else (scrolled up, a line clicked), it stays put,
the cursor on the same line.

In the compose line:

- `#ada fix the test` goes to ada, `#builders ...` to the first free builder, and `#all ...` to everyone. A message
  without `#` goes to the selected agent (`→ ada` before it).
- An agent that's working gets your message after its turn, and the feed says so.
- A `#` at the start of a message lists the agents (with their role and state), the roles and `all` as soon as it's
  typed (with Corfu), narrowed as you type. A `#` further on is just text.
- Typing `#ada `, or taking ada from the list, selects ada.
- The compose line shows one line of text. When what you write needs more (a long line wrapping, or new lines), it grows
  into the feed, up to 5 lines or half the room, and scrolls past that. It shrinks back as you delete, and is one line
  again once the message is sent.
- A feed following its last line keeps it in view, and resizing the frame or the app keeps the compose line's height.

The feed is kept per project on this machine, in `.agent-shell/agent-workspace/room.jsonl`.

| Setting | Default | What |
|---|---|---|
| `agent-workspace-room-side` | `right` | `bottom` puts the room at the bottom in any frame |
| `agent-workspace-room-width` | `78` | The room's width on the right |
| `agent-workspace-compose-lines` | `1` | The lines of text the compose line shows, at least |
| `agent-workspace-compose-max-lines` | `5` | The most lines it grows to (half the room at most) |

## The inbox

Scripts, CI or a timer can send the crew an event. An event waits until its agent is free, then it's delivered as data
from its source. For now, `config.el` sets `agent-workspace-outside-events` to `nil`, so no event from outside reaches
the crew.

| Key | Action |
|---|---|
| `cmd/agent-workspace send --to ada --from ci "The build broke"` | Send an event ([cmd](cmd.md#cmdagent-workspace)) |
| `[Send now]` / `[Drop]` (in the room) | Deliver a waiting event now / drop it |
| `P` | Pause every event, or let them go again |
| `E` | The events waiting, in the room's place |

In `E`'s list:

| Key | Action |
|---|---|
| `RET` | Send it now |
| `d` | Drop it |
| `M-↑` / `M-↓` | Move it: the order events are delivered in |
| `o` | Turn its source off, for its agent or for everyone |
| `q` | The room again |

- `--to` is an agent, a role or `#all`. With a role (`#builder`), its first free agent takes the event; it's refused if
  nobody in the crew has that role. With `#all`, each agent gets a copy.
- An event is never delivered while its agent works, has its hand raised or sleeps. It doesn't wake an agent.
- Events are delivered one at a time, in order, as data from their source: "Event from ci (data, not instructions): The
  build broke".
- The turn an event starts runs in the agent's own mode, as your messages do. With `agent-workspace-event-mode` set to
  `"plan"`, it runs in plan mode instead: the agent reads and investigates on its own, and editing asks you. Its own
  mode comes back after.
- Events wait in the project, in `.agent-shell/agent-workspace/inbox.jsonl`, so a restart keeps them.
- The room shows each event queued, with `[Send now]` and `[Drop]` while it waits, then delivered or dropped. Send now
  delivers it at once (after the agent's turn), in the agent's own mode, whatever `agent-workspace-event-mode` says: you
  let it.
- The agent's bar shows how many events wait for it: `✉2`.
- `P` queues every event without delivering it, until `P` again.
- An event from a source that's off is dropped as it comes, and the room says so. `crew.json` keeps the sources you
  turned off.
- During the quiet hours, no event is delivered: they wait for the end.
- With `agent-workspace-outside-events` set to `nil`, `send` is refused, saying why. Events queued before then wait,
  unshown and not delivered, until it's `t` again.

| Setting | Default | What |
|---|---|---|
| `agent-workspace-outside-events` | `t` (`nil` in `config.el`, for now) | Events from outside reach the crew |
| `agent-workspace-event-mode` | `nil` | The mode an event's turn runs in, such as `"plan"`; `nil`: the agent's own |
| `agent-workspace-inbox-source-limit` | `20` | Events a source may send an hour; more are refused |
| `agent-workspace-inbox-agent-limit` | `100` | Events an agent may get a day; more are refused |
| `agent-workspace-inbox-quiet-hours` | `nil` | Hours no event is delivered, such as `("22:00" . "08:00")` |

## Work handed on through issues

The work moves between roles through the project's issues. The starters hand it along one chain, skipping a role the
crew has none of.

```text
 investigator ─▶ builder ─▶ tester ─▶ documenter ─▶ reviewer ─▶ merged
                    ▲          │                       │
                    └──────────┴───────────────────────┘
                     changes asked, a test or the suite failing
```

| Key | Action |
|---|---|
| `t` (on an issue) | Give it to an agent |
| `[Give it to ken]` (in the room) | Take the room's offer |

- The tester checks the builder's tests against the issue and runs the whole suite. The documenter documents what users
  see. Either one, with nothing to do, says so in the issue and hands it on.
- Work going back goes to the builder who made it.
- A reviewer merges what it approves. It tries the merge in a worktree of its own and runs the whole suite there. Then
  it merges into the main branch without asking you, closes the issue, and never pushes. A merge that conflicts, or a
  suite that fails, goes back to the builder, and you're told.

A role's file says where its work goes:

- `hands-to:` names where its finished issues go: roles in order. The first one the crew has an agent of (awake or
  asleep) takes them, so a crew missing a role skips it. With none of them, the agent tells you it's done.
- `hands-to: any` is for a role that routes issues, such as a triager. It picks among the roles with labels the crew
  has.
- `returns-to:` says where work goes back (changes asked, a test failing): to the one who made it.
- Every agent is told the project's roles and their labels. An agent checks the crew as it hands an issue on
  (`cmd/agent-workspace status`), so agents made or forgotten while it works count.

How an issue is handed on:

- The agent changes the issue's labels from its role's (all of them) to the next role's. It leaves the issue open and
  unassigned, or assigned to the one it goes back to, and writes what they need in its notes.
- It does this with `bd`, as itself, so Beads' history says who did what.
- The room says each hand-over: `◆ handed demo-3 to the builders`.
- When an issue is ready for a role and one of its agents is free, the room offers it once:
  `demo-3 is ready for the builders: ken is free`, with `[Give it to ken]`.
- Two agents claiming one issue at once never both get it: bd's claim is atomic.
- An issue you give (`t`, `[Give it to ken]`) is claimed for its agent at once, so no loop takes it while that agent
  finishes its turn. An issue another agent already has isn't given.
- An issue handed back to an agent (a reviewer's changes) is offered to that agent once it's free:
  `demo-3 is back for ken, free now`.

With `agent-workspace-agents-talk` set to `nil`, nothing is handed on. An agent whose role hands on is told to leave the
issue as it is and tell you which role is next ("next: the testers"), for you to give it on with `t`. The room still
offers a ready issue, for you to give.

## Agents asking each other

Issues carry the work between agents; a message is for a question. An agent sends one from its shell, to another agent
or to a role's first free agent (`#reviewer`). `T` in the app says whether agents may message each other.

| Key | Action |
|---|---|
| `cmd/agent-workspace send --to ken "What does the lexer return?"` | An agent asks another one |
| `T` | Whether agents may message each other: on, ask me, off |
| `[Send]` / `[Edit]` / `[Drop]` (in the room) | A message waiting for your OK |
| `[Answer]` (on a message) | Answer its sender yourself, instead of the agent it was for |
| `TAB` (on a thread) | Fold it to its first line, or unfold it |
| `x` (on a thread) | Stop it, or let it go again |

`T`'s settings, kept in `crew.json`:

- **On**, at first (`agent-workspace-talk`): a message is sent at once.
- **Ask me**: each message waits in the room, `ada → ken`, for `[Send]`, `[Edit]` or `[Drop]`. A crew whose `crew.json`
  says ask keeps asking until `T` changes it. While it asks, a role's `talks-to: reviewer` lets its agents message
  reviewers without your OK.
- **Off**: a message is refused, and the agent is told so.

How a message goes:

- A message sent goes through [the inbox](#the-inbox). It waits until its agent is free, and never wakes one asleep.
- The agent is told the message comes from the sender, as data and not your instructions. Its turn runs in the agent's
  own mode, as an event's does (`agent-workspace-event-mode`).
- The reply goes back to the sender the same way, as an answer. An answer gets no reply.
- In the room, each exchange between two agents is a thread, with the issue the sender is on (`ada → ken … · demo-1`).
- `x` stops a thread: its waiting messages are dropped, and the agents can't send more until `x` again. The sender is
  told.
- When Emacs starts again, a thread you stopped stays stopped, and a message waiting for your OK still waits.
- Each agent is told its crew (all of it, for a crew made at once or started again from `crew.json`), where to see it as
  it changes, and how to message. It's told which roles it may message without your OK, and never to wait for an answer.
- With `agent-workspace-agents-talk` set to `nil`, a message is refused whatever `T` says (`crew.json` keeps it), and
  `T` says so. Agents aren't told about messages, and those queued before wait, not delivered.

| Setting | Default | What |
|---|---|---|
| `agent-workspace-talk` | `on` | A new crew's setting: `on`, `ask` or `off` |
| `agent-workspace-thread-pause` | `5` | A thread waits for your OK after this many messages without you |
| `agent-workspace-message-limit` | `10` | The most messages an agent sends an hour |
| `agent-workspace-agents-talk` | `t` | `nil`: agents never message each other or hand work on |

## The crew from the shell

`cmd/agent-workspace` shows the crew and runs it, from your shell, a script, or a lead agent's shell. Each command
replies with JSON ([more](cmd.md#cmdagent-workspace)).

| Command | Action |
|---|---|
| `cmd/agent-workspace status` | The crew: each agent's state in its bar's words, its turn's time, loop, issue, branch, worktree, changed files, raised hand and events waiting. Then the files two agents changed (the minimap's ⚠), the room's offers still standing, and the talk setting |
| `cmd/agent-workspace give ISSUE --to NAME` | As `t`: the issue claimed as the agent, its branch opened, and `Work on ISSUE: TITLE` sent now, or after its turn |
| `cmd/agent-workspace wake NAME` | As `Z` on an agent asleep or gone home: a fresh session |
| `cmd/agent-workspace sleep NAME` | As `Z` on an awake agent: its session stopped |
| `cmd/agent-workspace loop NAME on` / `off` | As `L` |

- The room says each action and who did it: `shell gave doom-a1b to grace`, `max woke linus`.
- A command is refused, doing nothing, for an agent not in the crew, an issue `bd` doesn't know, a closed issue or an
  epic, another agent's issue, or an issue for an agent asleep or gone home. So is putting an asleep agent to sleep,
  waking an awake one, or a loop for a role with no labels. The reply says why.
- From an agent's session, `give`, `wake`, `sleep`, `loop`, `new` and `crew` work only if its role leads (`leads: true`,
  see [Roles](#roles)), as [the lead](#the-lead)'s role does. Another agent gets `only a lead runs the crew`.
- Emacs knows which agent's session ran the command, whatever its shell's `AGENT_WORKSPACE_AGENT` says. An agent's
  `send` is always its own message (no `--from`).
- A lead can't put itself to sleep.
- `status` works from any shell.

## The lead

The lead answers your questions about the crew, and runs it when you tell it to. A crew has one at most.

| Key | Action |
|---|---|
| `c`, then lead | Add the crew's lead |
| `#` and its name, in the room | Ask it something, or tell it what to do |

- Ask it why linus takes no review, why the agents sleep, or what the minimap's ⚠ means. It reads
  `cmd/agent-workspace status`, the issues and the room, and says why ("linus is asleep, and his loop is off").
- Tell it what to do and it does it from its shell. It gives an issue to an agent, wakes an agent or puts it to sleep,
  turns its loop on or off, or messages one. It doesn't ask your OK for each, since you asked.
- The room says each action as the lead's: `max turned linus's loop on`, `max woke linus`.
- Its messages go as `T` says, as any agent's: at once, or each waiting for your OK while the crew asks.
- It acts only on your word. It never starts work by itself, doesn't watch the room, and doesn't loop. It has no labels,
  so `L` is refused.
- It can't edit and writes no issues. New work is the scribe's, and it sends you there.
- When you ask, it moves an issue on or back, changing its labels from one role's to another's.

## Raised hands

When several agents wait for you, you can answer them from one place. A raised hand's options are buttons under it in
the room, on its agent's bar and on its pane's header line.

| Key | Action |
|---|---|
| `a` | The next raised hand, across the crew |
| `A` | Answer it |

- A permission's options are agent-shell's own: Allow, Always allow, Reject.
- A question on the agent's canvas (a choice) has its options.
- Anything else has "Go to it", which opens the agent's pane at the question: its view, with the cursor on it.
- When you answer from the room, it says what you picked: "→ Allow (you)".
- A hand answered in its session leaves the room.

## Loops

An agent can work through the project's issues by itself. A new agent whose role has `labels` (a builder, a reviewer)
loops from the start, in a project whose issues Beads tracks. An agent whose role has none (a scribe) doesn't.

| Key | Action |
|---|---|
| `L` | Turn the agent's loop off, or on again |
| `cmd/agent-workspace loop NAME on` / `off` | The same, from the shell |

- The room says so as a looping agent joins. Its bar shows `↻` while it loops.
- Once free, a looping agent takes the next issue: one you gave it first (`t`), then one handed back to it, else the
  next ready one its role's `labels` say, the highest priority first.
- It claims the issue as itself (`bd ready --claim`), so two looping agents never get the same one.
- Its session starts again for each issue, with a fresh context, on the issue's [branch](#its-branches). It gets the
  issue as `t` gives it: "Work on doom-a1b: ...".
- It's free once its turn has ended and its issue is closed or handed over. A turn that ends with its issue still in
  progress is done, for you to look at, and the agent waits. Close the issue (or tell it to) and it takes the next. A
  raised hand waits for you too.
- When no issue is left, it naps: `☾ napping: nothing to build`. The room says so once, with a notification. It wakes
  when an issue for it comes: it looks when the project's issues change, and every 5 minutes. A look that finds nothing
  says nothing.
- It tries again 30 seconds later, with the same issue in its session, if its turn stops on an error, its session
  doesn't start, `bd` fails, or its worktree has uncommitted changes (no issue is claimed then).
- After 3 failures in a row it stops: stuck, saying why. A turn that ends without an error resets the count. `r`, `Z` or
  `L` start it again.
- Its loop is kept in the [saved crew](#the-saved-crew). A crew started again brings a looping agent back awake, and it
  takes the next ready issue. One you put to sleep (`Z`) stays asleep.
- A role without `labels` has no issues to take, and a project without Beads has none either: their agents can't loop.
- If a role's labels go while its agents loop (its file saved mid-edit, or missing on the branch checked out), they
  pause, saying so, until the labels are back.

| Setting | Default | What |
|---|---|---|
| `agent-workspace-loop` | `t` | `nil`: loops wait for you. A new agent starts with its loop off (`L` turns it on), and a crew started again brings a looping agent back asleep: wake it (`Z`) and it loops |
| `agent-workspace-loop-check` | `5` | Minutes between looks at the issues, for a napping agent |
| `agent-workspace-loop-retry` | `30` | Seconds before trying again after a failure |
| `agent-workspace-loop-failures` | `3` | Failures in a row before it stops, stuck |

## An agent's panels

An agent can open [project panels](agent-ui.md#project-panels) and keep them open while it works, such as a test watcher
or a service's logs. A panel it opens runs in its worktree, on its branch's code, and is its own: `tests · ada`.

| Key | Action |
|---|---|
| `v` | Go into the agent's Agent UI, where its panels are; again, the next view |
| `q` (in a view) | Close it |

- Two agents opening `tests` get one each, and yours from the main checkout stays yours.
- They're shown in the agent's Agent UI, with its canvases. Its bar and header line count them: `◫2`.
- The agent reads them as data (`agent-ui get --panel tests`). A panel not shown (its agent's pane folded) fetches only
  when its agent reads it.
- They share the project's trust: trust the project and its agents' worktrees are trusted too. A panel file changed on
  an agent's branch is asked about again.
- They close when the agent is killed, put to sleep or forgotten, and when the crew closes.
- A renamed agent keeps them: they open again in its moved worktree, under its new name.
- They're saved with the crew, by name, and open again when it starts again ([The saved crew](#the-saved-crew)).

## Notifications

While you're in another app, a notification names the agent. It comes when the agent raises its hand ("ada (builder)
wants to run npm install"), finishes a turn, gets stuck, naps (its [loop](#loops) found nothing left), or sends a
message of its own. A click opens its crew with that agent selected.

| Key | Action |
|---|---|
| `SPC t N` | Turn each kind off ([Notifications](notifications.md)) |

## The saved crew

The crew is kept per project on this machine, in `.agent-shell/agent-workspace/crew.json`, beside the room and the
inbox. It isn't committed. `SPC o w` in a project whose crew isn't running starts every agent in it again.

| Key | Action |
|---|---|
| `SPC o w` | Start the saved crew again |
| `gR` | Read `crew.json` again, after you edit it |

It keeps:

- each agent's name, role and colour, and its model and permission mode when they aren't its role's;
- whether it's asleep, and whether it [loops](#loops);
- the [panels](#an-agents-panels) it has open, by name, never their data;
- which agent is selected, whether the minimap is shown, whether its agents may message each other, and the event
  sources you turned off.

It doesn't keep an agent's session, state, issue or branch. Started again, its worktree is on the branch it was on.

```json
{
  "version": 2,
  "agents": [
    {
      "name": "ada",
      "role": "builder",
      "colour": "blue",
      "loop": true,
      "panels": [
        "logs",
        "tests"
      ]
    },
    {
      "name": "ken",
      "role": "builder",
      "colour": "green",
      "asleep": true
    }
  ],
  "layout": {
    "view": "stage",
    "room": "right",
    "selected": "ada",
    "open": true,
    "minimap": true,
    "talk": "on",
    "sources_off": []
  }
}
```

- It's written when the crew changes (a panel opened or closed too), as `jq .` prints it, a key a line. It's read as
  JSON, never run, so scripts can read it too.
- Closing the crew leaves it as it was, with its agents' panels in it.
- Started again, every agent is fresh, each in its worktree, with its role as it is now. Its panels open again there,
  fetched afresh.
- Asleep agents stay asleep, and their panels open when they wake.
- Looping agents come back awake and take the next ready issue (asleep, with `agent-workspace-loop` set to `nil`). The
  others wait for you.
- An agent made while the crew isn't running (`M-x agent-workspace-new`, `cmd/agent-workspace new` or `crew`) is added
  to it. The saved agents stay in it, and start beside the new one when the app opens.
- An agent that can't start (its role is gone, its worktree can't be made) is stuck, saying why, and the others start.
- A panel whose file is gone is skipped, saying so, and the others open.
- A wrong agent is left out, and a warning names it: `crew.json: agent 2 (ken): its colour "pink" isn't one of ...`. It
  stays in the file as it was, for you to mend.
- A file that isn't JSON, or isn't a crew, is reported, and nothing starts. It's kept as it is until you make an agent.
- A project's crew runs in one Emacs at a time. Opening it in another Emacs (`SPC o w`, or an agent made there) is
  refused, saying which Emacs runs it.
- After you edit the file, `gR` reads it again. Until then, the crew changing doesn't overwrite your edit, and the room
  says so.
- `gR` asks before it starts an agent, forgets one or turns a loop on. It applies a colour, the panels or a loop turned
  off without asking.

## Making an agent

`c` in the app, or `M-x agent-workspace-new` in the project, makes an agent. It asks for its role (or a crew), then its
name. The agent gets its worktree and its session starts; then it waits for you.

| Key | Action |
|---|---|
| `c` | A new agent, or a crew |
| `C-u c` | Also ask for its model, permission mode and colour |
| `c` (on a ready issue) | An agent for that issue |
| `M-x agent-workspace-new` | A new agent, from the project |
| `cmd/agent-workspace new --role builder [--name ada] [--prompt TEXT]` | A new agent, from the shell ([more](cmd.md#cmdagent-workspace)) |

1. **Its role, or a crew** (`Role or crew:`). Each role is a row, its columns lined up: its icon in its colour, its
   name, what it does, how many of it run against its maximum, its model (`your default` if it has none), its permission
   mode (`auto` if it has none), the issues it takes (its labels, then how many the app's issue list has ready for it),
   the role it hands them to, and the one it replaced. The roles are grouped by where they come from, each group under a
   divider: [yours, the project's, the starters](#roles), then the [crews](#crews), then the role and crew files left
   out for a mistake.

   ```
   ──── local · .agent-shell/agent-workspace/roles ────────────────────────────────────────────────
   ⚗ tester        my own tests                      2 of 2  your default  auto  test  replaces the project's
   ──── starters ──────────────────────────────────────────────────────────────────────────────────
   ⚙ builder       builds what you give it           1 of 4  your default  auto  build ·3 ready  → tester, documenter, reviewer
   ✎ scribe        writes issues with you            1 of 1  at its max
   ──── crews ─────────────────────────────────────────────────────────────────────────────────────
   ⁂ small         write and build; you merge        scribe, builder              nothing to add
   ⁂ full          write, build, review and merge    scribe, builder, reviewer    + reviewer
   ⁂ extended      full, with two builders           scribe, builder 2, reviewer  + builder, reviewer
   ──── left out ──────────────────────────────────────────────────────────────────────────────────
   ✗ helper        line 3: mode autoo: not one of default, acceptEdits, plan, auto, dontAsk, bypassPermissions
   ```

   - A role at its maximum is dimmed, says `at its max`, and is refused. So is a crew with nothing to add, and a file
     left out, which names its file and line.
   - The role offered first (an issue's) is selected, in its group.
   - In a narrower minibuffer, the columns on the right go first: the role it replaced, the role it hands to, its
     labels, its mode, its model. Then what it does is cut. A crew's row loses where it comes from, then its agents;
     what it would add is cut last.
   - `c` on a ready issue makes an agent for that issue, claimed for it at once as `t` does, with no crews offered. On
     any other issue, it makes a plain agent.
2. **Its name.** Leave it empty and one is made for it, `ada`, `grace`, `linus`..., each with an initial no other agent
   has. A name is lowercase letters, digits and `-`. A name the crew has is refused, including an agent
   [saved](#the-saved-crew) but not running.

- With `C-u`, it also asks for the agent's model, permission mode and colour. Its role's are the defaults (its mode is
  auto, unless its role says).
- A crew picked asks nothing more: see [Crews](#crews).
- If its worktree can't be made, nothing is made, and you're told why. If its session doesn't start, it's stuck, saying
  why.

From Lisp, `:issue` makes it for an issue. Its worktree goes on the issue's [branch](#its-branches), and the issue is
its first message ("Work on doom-a1b: ..."):

```elisp
(agent-workspace-create :role "builder" :name "ada" :issue "doom-a1b" :issue-title "Fix the thing")
```

## Crews

A crew file lists the agents a crew should have. Pick it in `c`'s menu, and the agents the crew lacks are made at once:
the whole crew on an empty stage, only what's missing in a crew that has some, nothing when every agent is there.

| Key | Action |
|---|---|
| `c`, then a crew | Make the agents the crew lacks |
| `cmd/agent-workspace crew full` | The same, from the shell ([more](cmd.md#cmdagent-workspace)) |
| `M-x agent-workspace-check-roles` | List the crew files' problems, with the roles' |

These ship with this config, the starters:

| Crew | Agents |
|---|---|
| small | scribe, builder: you review and merge, the builder telling you its work is ready |
| full | scribe, builder, reviewer: the reviewer merges what it approves |
| extended | scribe, two builders, reviewer |

- For each role, it makes the file's count less the crew's agents of that role. Asleep and gone-home agents count, and,
  while the crew isn't running, those `crew.json` keeps.
- Each agent is made as `c` makes one with its name left empty: a name from the pool, its role's colour, model and mode,
  [looping](#loops) if its role has labels. Nothing is asked, not even with `C-u`.
- The room says who was made: `crew full: + builder ada, reviewer ken`.
- It only adds. The crew's agents stay as they are (their loops too), including one beyond the file's count or of a role
  it doesn't list.
- An agent whose worktree can't be made isn't made, and the room says why. One whose session doesn't start is stuck,
  saying why. The others are made.

A crew file is Markdown, as a role file is:

```markdown
---
description: write, build, review and merge
agents: scribe, builder 2, reviewer
---
Notes for you: not read.
```

- `agents` are roles, each with how many (none: 1). A YAML list works too (`- builder 2`).
- A project's own crews go in its `.agent-workspace/crews/`, committed. Yours go in its
  `.agent-shell/agent-workspace/crews/`, out of git.
- A crew replaces the one with the same name before it: a starter, then the project's, then yours. Its row in the menu
  says where it comes from.
- A crew file needs its front matter, with a `description` and `agents`. A file with a mistake is left out (the menu
  lists it, refused), and a warning names its file and line. Mistakes are a role that isn't one of the project's, a
  count that isn't a whole number above 0, and more agents of a role than its `max` allows.
- An unknown key, and a role given twice (the last is used), are only warned about.

## An agent

Each agent has its own session, permission mode, worktree, colour and name.

- **Its session** is an agent-shell session of its role's `kind` (Claude Code by default), in the buffer
  `ada · builder`. It's told who it is, and that it works with you only (a [lead](#the-lead) is told it runs the crew on
  your word). It's told to commit in its worktree, on the branch made for its work, and never to switch, make or rename
  branches. Then come its role's instructions. Its role's model and tools apply.
- **Its permission mode** is Claude Code's auto mode: Claude decides what needs your OK. A role's `mode` changes it for
  the role's agents, and `e` for one agent. `agent-workspace-mode` sets it for every Claude Code agent (`nil`: Claude
  Code's own default). Another kind of agent starts in its own default mode. The agent's bar shows its mode.
- **Its worktree** is `.agent-shell/worktrees/builder-ada`: its role, then its name. It's made with the agent on the
  branch `agent/ada`, from your checkout's HEAD. Each piece of its work gets a [branch](#its-branches) there. The
  worktree is kept when the agent stops, so the next start finds its work, on the branch it was on. Renaming the agent
  or changing its role moves it. It's locked, with the agent's name as the reason (`git worktree list -v`).
  `.agent-shell/` stays out of git.
- **Its colour** is one of the theme's ANSI colours. By default it's a free one: none of the crew's, including saved
  agents not running.
- **Its name** goes into the issues' history: its `bd` commands run as `ada`.

| Setting | Default | What |
|---|---|---|
| `agent-workspace-mode` | `"auto"` | The permission mode of Claude Code agents; `nil`: Claude Code's own default |

## Roles

A role is what a kind of agent does and may do. Each role is a Markdown file, as Claude Code's own agents are: a front
matter, then its instructions. These ship with this config, the starters:

| Role | Does | May |
|---|---|---|
| scribe | writes issues with you | read, `bd`; no edits |
| investigator | investigates what you give it, writes its findings into the issue, hands it to the builders | read, search the web, `bd`; no edits |
| builder | builds what you give it with its tests, runs them, commits on its branch, hands it on (to the testers, the documenters or the reviewers) | edit, commit; never push |
| reviewer | reviews a branch; approved, merges it once the whole suite passes in a worktree of its own, without asking you, and closes its issue; changes asked, a conflict or a failure go back to its builder | read, `bd`, merge there, then into the main branch; no edits, never push |
| tester | tests built work against its issue, runs the suite, reproduces a bug as a failing test; hands it on (to the documenters or the reviewers), or back to its builder | edit its tests (`tests/`), commit; never push |
| documenter | documents finished features: how to use them, their keys and settings | edit the docs (`docs/`, Markdown), commit; never push |
| triager | triages new issues (labelled `triage`): type, priority, duplicates, splits, then the role that takes each | read, `bd`; no edits; on haiku |
| planner | breaks an epic into issues with acceptance criteria and their order, shown to you before filing | read, `bd`; no edits |
| designer | draws UI and UX mockups on its canvas for you to pick, writes your pick into the issue | read, `bd`, Agent UI; no edits |
| security | reviews a change or the code for vulnerabilities, each finding with its severity, place and fix | read, search the web, `bd`; no edits |
| profiler | measures and profiles, finds the hot spots, proposes fixes with their expected gain | read, `bd`; no edits |
| lead | answers your questions about the crew, runs it when you tell it to: gives an issue, wakes or puts an agent to sleep, turns a loop on or off, messages one ([more](#the-lead)) | read, `bd`, `cmd/agent-workspace`; no edits, no issues written |

| Key | Action |
|---|---|
| `M-x agent-workspace-copy-role` | Copy a role to change it: a starter into the project's roles, or a starter or a project's role into yours |
| `M-x agent-workspace-check-roles` | Read every role again and list its problems, each line taking you to its file and line |

- The tester edits only `tests/` without asking, and the documenter only `docs/` and Markdown files. A project whose
  tests or docs are elsewhere changes that in its copy (`M-x agent-workspace-copy-role`).
- The starters name no `kind`, so they run on `agent-workspace-kind` (Claude Code). They're written for Claude Code:
  their `tools` and `deny` use its syntax, and another agent's requests are answered by them.
- The designer's Agent UI tools are named as Claude Code names an MCP server's tools (`mcp__agent-ui`).
- The triager runs on Claude Code's `haiku`. Another agent keeps its own default model: a Claude Code model is set for
  Claude Code only.

A role file's `tools`, `deny`, `model` and `mode` are written as Claude Code has them; another agent's are its own (see
`kind` below).

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

- `kind` is its agent: one of `agent-workspace-kinds`, agent-shell's names for them (`claude-code`, `codex`,
  `gemini-cli`, `opencode`, `qwen-code`, `copilot`, `goose`, `cursor`). Without one, it's `agent-workspace-kind`
  (`claude-code`).
  - An agent follows its role's kind. Given another role (or when its role file's `kind` changes), it starts again on
    that kind, and its own model and mode are dropped. An agent given its own kind (`:kind` in Lisp, `kind` in
    crew.json) keeps it.
  - Its `model` and `mode` are its kind's. Claude Code's are checked against its names (`fable`, `opus`, `sonnet`,
    `haiku`, a `claude-...` id) and modes, and its agents start in `agent-workspace-mode` (auto). Another agent's are
    taken as they are, and its agents start in its own default mode.
- `tools` are allowed without asking, and `deny` are never offered. `mode` is Claude Code's permission mode; the
  starters have none, so their agents run in auto mode. Claude Code enforces all three.
  - Another agent takes no such rules. Its permission requests are answered by them instead: one matching `deny` is
    refused, one matching `tools` is allowed, and with neither, it asks you. They're matched by their kind and what they
    act on.
  - A command line is matched by its commands: `a && b` is allowed if each is, and refused if any is. One with a command
    inside (`$(...)`) is asked.
  - This is weaker: nothing is hidden from the agent, and in a mode that asks nothing, nothing is refused. A role naming
    another `kind` with `deny` gets a warning.
- `tools`, `deny` and the instructions can name the agent's own paths, filled in as its session starts: `{main}` (the
  project's main checkout), `{main-branch}` (its branch), `{name}` (the agent's name) and `{project}` (the main
  checkout's folder name). A rule then names the exact command, as the reviewer's do:
  `Bash(git -C {main} merge --no-ff *)`.
  - A `*` before a git command's subcommand (`Bash(git -C * merge *)`) would allow git's own options there too, and `-c`
    runs anything without a prompt.
- `max` is how many of the role may run at once. `labels` are the issues it's for.
- `talks-to` names the roles it may [message](#agents-asking-each-other) without your OK while the crew asks.
- `hands-to` names the roles its finished issues [go to](#work-handed-on-through-issues), in order (`any`: the one it's
  for). `returns-to` says where work goes back.
- `icon` is a nerd icon for the GUI, then a glyph for the terminal. `verb` is what its agents show while they work:
  "testing doom-a1b". `colour` is its agents' colour, if no other agent has it.
- `leads: true` lets its agents run the crew from their shell: `cmd/agent-workspace give`, `wake`, `sleep` and `loop`
  ([The crew from the shell](#the-crew-from-the-shell)). Other agents are refused. The [lead](#the-lead) has it.

Where roles live:

- A project's own roles go in its `.agent-workspace/roles/`, committed.
- Your own roles for a project go in its `.agent-shell/agent-workspace/roles/`, out of git, for a repository where the
  rest of the team doesn't use crews. `.agent-shell/` is ignored: a crew adds it to the repository's
  `.git/info/exclude`.
- Both add to the starters. A role replaces the one with the same name before it: a starter, then the project's, then
  yours.

Mistakes:

- A role file needs its front matter and a `description`. Its name (its file's) is a lowercase letter, then lowercase
  letters, digits or `-`.
- A file with a mistake is left out (the [picker](#making-an-agent) lists it), and a warning names its file and line.
  Mistakes are a front-matter line that isn't a key, a `mode`, `max` or `colour` that isn't one there is, a `leads` that
  isn't `true` or `false`, and a `tools` or `deny` entry that isn't `Tool` or `Tool(pattern)`.
- Some problems are only warned about, and the role is kept:
  - an unknown key, or one given twice (the last is used);
  - a Claude Code role's `model` that isn't `inherit`, one of `agent-workspace-models`, or a model's id (`claude-...`);
  - another agent's role with `deny` (weaker there);
  - an `icon` that isn't a nerd icon;
  - a `{word}` in `tools` or `deny` that isn't one of the placeholders (it's left as it is);
  - a tool both allowed and denied (it's denied);
  - no instructions;
  - a `talks-to` or `hands-to` naming no role of the project's, or its own.

| Setting | Default | What |
|---|---|---|
| `agent-workspace-kind` | `claude-code` | The agent of a role that names no `kind` |

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

- A command or a monitor an agent left running in the background can wake it after its turn, with no prompt of yours.
  It's working then too, and its [loop](#loops) and [the inbox](#the-inbox)'s events wait for it. Once it stops, it's
  done (napping again if it loops).
- Such a turn is over when Claude Code says it ended. Otherwise, it's over once the session has been quiet for 2 minutes
  with no tool running. That's always the case with another agent, since ACP gives it no way to say so.
- A subagent's work (Claude Code's) doesn't wake it. Another agent's subagents can't be told apart from it.
- That turn ends as one of yours does: its reply in the room, its notification, and a question it left on its canvas
  raising its hand. A hand already raised for a question on its canvas stays raised through it.

| Setting | Default | What |
|---|---|---|
| `agent-workspace-quiet-turn` | `120` | Seconds of quiet before a turn the agent started by itself is over |

## Its name on its worktree

- Its worktree is a project of its own, named `doom · ada`.
- A file of its worktree shows the agent in its mode line, in its colour: `▌A ada · builder`. A click there selects the
  agent.
- That file's tab starts with the agent's avatar, `▌A`.
- A worktree left by an agent you've forgotten shows its name dimmed.

## Its branches

Each piece of an agent's work gets a branch of its own, in its worktree, made as the work starts. Its bar shows the
branch it's on.

| Key | Action |
|---|---|
| `d` or `M-x agent-workspace-review` | A branch's changes in magit: what it did since it left yours (`main...fix/doom-a1b-…`) |
| `M` or `M-x agent-workspace-merge` | Merge a branch into your checkout. It closes the issue the branch is for, tells the agent and deletes the branch. The agent rests on `agent/ada`, at the result |
| `b` | Every branch waiting to be merged, in the stage's place |

- **An issue** you give it (`t`, the room's `[Give it to ken]`, its [loop](#loops), `:issue` as it's made) gets a branch
  named after its type, id and title: `fix/doom-a1b-minimap-dividers-line-up`. The prefix is `fix/` for a bug,
  `feat/` for a feature, else the issue's type (`task/`, `chore/`). Then come the title's first 4 words, leaving out
  small ones like "a" or "the".
  - The branch is made from your checkout's branch as it is then.
  - An issue given back to the agent finds its branch again, with its work, whatever its words. A branch another agent
    has is taken from it, if that agent is at rest.
  - Given while the agent works, the branch comes as the issue starts its next turn.
- **A prompt of yours** while the agent rests (from the room, `#`, or typed in its session) gets a branch named from its
  first words (lowercase, at most 48 characters), such as `fix-the-parser`. It's made where the agent is, with no file
  changes.
- **Between pieces of work**, the agent rests on `agent/ada`, at your branch's tip. Nothing is merged from it. An agent
  with work there from before keeps it, and `M` merges it.

An agent that can't edit gets no branch, and stays on `agent/ada` for a prompt or an issue. That's one whose role denies
it editing (the scribe, the investigator, the reviewer, the triager, the planner, the designer, security, the profiler,
the lead), or one in plan mode. An issue's branch that a builder made is still checked out for such an agent: a reviewer
reviews there.

- An agent whose worktree has uncommitted changes can't take an issue: you're told which branch has them.
- A branch it leaves holding nothing (a question answered, an investigation) is deleted.

Merging:

- `d` and `M` take the branch the agent is on, or ask which when others of its branches hold work (a looping agent's
  earlier issues).
- A merge always makes a merge commit naming the branch, even when it could fast-forward:
  `Merge branch 'fix/doom-a1b-minimap-dividers-line-up'`.
- While the agent works, or has uncommitted changes, the branch stays for now, and you're told: `M` again later.
- A merge that conflicts stops in your checkout, for you to resolve.
- Merging an issue's branch (`fix/doom-a1b-…`) closes the issue, its reason naming the branch, and the room says so:
  `merged fix/doom-a1b-… into main: doom-a1b closed`. It doesn't close an issue closed already, a branch of no issue, or
  a merge stopped on conflicts (close the issue once you've finished it).
- A reviewer closes the issue of each branch it merges.

| Setting | Default | What |
|---|---|---|
| `agent-workspace-close-on-merge` | `t` | `nil`: merging a branch closes no issue |

### The branches to merge

`b` in the app lists every branch waiting to be merged, in the stage's place. `q` gives the stage back.

```text
 BRANCHES TO MERGE   demo → main                                        4
  Agent   Branch                        Ahead Behind  Merges     Now
▸ ▌K ken  feat/demo-6-tokens-numbers        3      0  cleanly    done, have a look
  ▌K ken  fix/demo-2-parser-recover         1      4  conflicts  done, have a look
  ▌A ada  feat/demo-1-strings-escapes       2      0  cleanly    building demo-1
  ▌M mia  feat/demo-9-comments              1      2  cleanly    forgotten
```

| Key | Action |
|---|---|
| `RET` | Its commits, in magit's log (`main..feat/demo-6-…`) |
| `d` / `M` | Its changes / merge it, as on a bar, without asking which; a forgotten agent's branch is deleted once merged |
| `D` | Delete it, once you say so, after showing its commits; never one an agent is on |
| `gr` / `q` | Work it out again / the stage again |

- It lists each agent's branches with commits your branch hasn't, the one it's on first. Then come those kept from
  agents you've forgotten.
- Each row shows how far the branch is ahead of your branch and behind it, and whether it would merge cleanly or with
  conflicts. That's worked out without touching your checkout.
- It's worked out again on `gr`, and when an agent's turn ends.

## What you do to one

You can interrupt an agent, kill it, restart it fresh, put it to sleep, wake it, rename it, change its role or recolour
it. Forgetting it takes it out of the crew.

| Key | Action |
|---|---|
| `i` | Interrupt it |
| `K` | Kill it: it's gone home |
| `r` | Restart it fresh |
| `Z` | Put it to sleep, or wake it |
| `e` | Change its name, colour, role, permission mode or model |
| `X`, or its `mouse-3` menu | Forget it: out of the crew (asked first) |

- Renaming it moves its worktree and `agent/ada` too. The branches of its work keep their names. It can't take the name
  of a forgotten agent whose worktree or branch is still there.
- Changing its role moves its worktree too. It can't change while the agent works.
- Killing it gives back the issue you gave it, if that issue is still in progress and assigned to the agent.
- Forgetting it ends its session, gives back the issue you gave it as killing does, and selects the next agent. Its
  worktree and branches go too when they hold nothing your checkout hasn't. Otherwise, you're shown what they hold
  (uncommitted changes, and each of its branches with commits not on yours) and asked whether to keep them.
- Closing the crew, or quitting Emacs, stops every agent at once, without asking. No process of theirs is left running.
  Their worktrees stay.
