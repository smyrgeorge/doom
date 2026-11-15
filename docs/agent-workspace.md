# Agent workspace

> **Status:** being built (epic `doom-51z`). There are agents, their roles, sessions, worktrees and states, the
> app (its workspace, the issues, the stage, the room), the saved crew, notifications, and raised hands answered from
> one place.

Several coding agents work on a project at once, a **crew**. Each agent has a name, a role and a colour. Each works in
its own git worktree, so they don't get in each other's way or touch your checkout. Each works only with you.

![The crew's app: the issues, the stage, the room](../examples/agent-workspace.png)

Try it: `M-x +my/example-agent-workspace`, a crew of three stand-in agents, offline.

## The app

`SPC o w`, from inside a project, opens its crew in a workspace of its own, `crew · doom`. Outside a project, it asks
which one. `SPC o W` opens it in the window you're in. The first time, it asks for the crew's first agent.

- **The issues** are on the left. In progress, each with the agent on it. Ready, grouped by the role they're for:
  a role nobody in the crew has is flagged. Blocked, by what. Done today. Moving onto an issue in progress selects its
  agent. The [minimap](#the-minimap) is under them.
- **The stage** is in the middle. Every agent has a pane, in role order. The selected agent's is open: its session,
  and below it (beside it from 140 columns) its Agent UI canvas and its [panels](#an-agents-panels) as tabs,
  `canvas │ logs │ tests`, one shown at a time. `v` shows the next one, `V` the one there full size, in the whole
  pane (`V` again: back), and a click on a tab shows it. Something new on its canvas brings the canvas back. The
  others are folded to a bar: its avatar, name, role, state and how long it's been working, and `◫2` when it has
  two panels open. The stage arranges itself: drag a border and it's tiled again.

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
| `a` / `A` | anywhere | The next raised hand / answer it |
| `f` + initial | anywhere | That agent |
| `#` | anywhere | Talk to it in the room |
| `1` / `2` | anywhere | The stage / the room alone |
| `m` | anywhere | Show or hide the minimap |
| `gr` / `gR` | anywhere | Lay it out again / read `crew.el` again |
| `q` / `Q` / `?` | anywhere | Leave / close / the keys |

In an agent's own session, the same keys follow `SPC m w` (`C-c w` in insert state), plus `]` / `[` for the next or
previous agent. In its canvas and panels, `v` and `V` work too. A click on a bar or a pane's header line
selects its agent, and `mouse-3` there lists its actions.

## The minimap

Under the issues, what each agent did over the last 15 minutes, a lane each:

```text
 CREW  15 minutes                       where now
 ▌A ⌕⌕⌕✎✎▶✎✎✎✎▶✎✎✎▶ │ ⚙  src/lexer.el:214
 ▌S ··⌕⌕⌕✎✎✎▶!!!!!! │ !  wants to use npm insta…
 quiet ▌K ken ○
 ⚠ ada + sam: src/lexer.el
    -15m    -5m now
    ⌕ read  ✎ edit  ▶ run  ! asks you
```

A cell is a minute: what the agent did most then (asked you, edited, ran a command, read or searched), `·` for
nothing. After the bar: its state, and the file and line it's in, or what it asks you. Agents that did nothing in those
minutes share the `quiet` line. A file two agents changed (on their branches or uncommitted) is marked `⚠`: they'll
conflict when you merge.

On a lane, `RET` selects its agent, `o` opens the file it's in, in its worktree at its line, and `d` shows its branch's
changes. On a `⚠`, `RET` or `d` shows both agents' changes to that file. `m` shows or hides it, and the crew keeps
that. `agent-workspace-minimap-height` sets its height (12 lines); `agent-workspace-minimap` set to `nil` hides it in
new crews.

## The room

One chat for the whole crew: a feed of what matters, and below it a compose line that stays in view.

- **The feed** shows each agent's turns (their answers' first lines), the issues it files, claims and closes, the
  crew's changes (an agent joining, going home, started again, stuck), raised hands, and your messages. At its end it
  follows new lines; scrolled up, it stays. `RET` on a line opens its agent's pane. `F` shows raised hands only, then
  the selected agent's only, then all.
- **The compose line**: `#ada fix the test` goes to ada, `#builders ...` to the first free builder, `#all ...` to
  everyone, and a message without `#` to the selected agent (`→ ada` before it). An agent that's working gets it
  after its turn, and the feed says so. Typing `#ada ` selects ada.

| Key | Action |
|---|---|
| `RET` | Send |
| `TAB` | Complete a `#` name, role or `all` |
| `M-p` / `M-n` | Your previous / next message |
| `#` | Talk to the agent you're on (in the issues, a bar, a session) |

The feed is kept per project on this machine, in `.agent-shell/agent-workspace/room.jsonl`.

## Raised hands

When several agents wait for you, you can answer them from one place. A raised hand's options are buttons under it in
the room, on its agent's bar and on its pane's header line:

- a permission's are agent-shell's own: Allow, Always allow, Reject;
- a question on the agent's canvas (a choice) has its options;
- anything else has "Go to it", which opens the agent's pane at the question.

`a` goes to the next raised hand, across the crew, and `A` answers it. Once you answer from the room, it says what you
picked ("→ Allow (you)"). A hand answered in its session leaves the room.

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
install"), a turn finished, stuck, or a message of its own. A click opens its crew with it selected. `SPC t N` turns
each kind off ([Notifications](notifications.md)).

## The saved crew

The crew is saved in the project, in `.agent-workspace/crew.el`, to commit: each agent's name, role and colour, its
model and permission mode when they aren't its role's, whether it's asleep, the [panels](#an-agents-panels) it has
open (by name, never their data), which agent is selected, and whether the minimap is shown. Not its session, state or issue.

```elisp
(agent-workspace-crew
 :version 1
 :agents ((:name "ada" :role "builder" :colour "blue" :panels ("logs" "tests"))
          (:name "ken" :role "builder" :colour "green" :asleep t)
          (:name "sam" :role "investigator" :colour "magenta" :model "opus"))
 :layout (:view stage :room right :selected "ada" :open t :minimap t))
```

It's written when the crew changes (a panel opened or closed too), and read as data, never run. Closing the crew
leaves it as it was, its agents' panels in it. `SPC o w` in a project whose crew isn't running starts every agent in
it again: fresh, each in its worktree, with its role as it is now, its panels open again there (fetched afresh),
waiting for you. Asleep agents stay asleep, and their panels open when they wake. An agent that can't start (its role is gone, its worktree can't be made)
is stuck, saying why, and the others start. A panel whose file is gone is skipped, saying so, and the others open. A
wrong entry is left out, and a warning names its line.

After you edit it or pull it, `gR` reads it again. It asks before it starts an agent or forgets one; a colour or the
panels you changed it applies.

## Making an agent

`c` in the app (or `M-x agent-workspace-new` in the project) asks for:

1. **Its role.** Each one says what it does and how many of it run against its maximum: `builder · builds what you
   give it · 2 of 4`. A role at its maximum is refused.
2. **Its name.** Leave it empty and one is made for it, `ada`, `grace`, `linus`..., each with an initial no other
   agent has. A name is lowercase letters, digits and `-`.

With `C-u`, it also asks for its model, permission mode and colour. Its role's are the defaults.

The agent gets its worktree and its session starts. Then it waits for you. If its worktree can't be made, nothing is
made, and you're told why. If its session doesn't start, it's stuck, saying why.

From Lisp, `:issue` makes it for an issue, which is its first message ("Work on doom-a1b: ..."):

```elisp
(agent-workspace-create :role "builder" :name "ada" :issue "doom-a1b" :issue-title "Fix the thing")
```

From the shell: `cmd/agent-workspace new --role builder [--name ada] [--prompt TEXT]` ([more](cmd.md#cmdagent-workspace)).

## An agent

- **Its session** is a Claude Code session in agent-shell, in the buffer `ada · builder`. It's told who it is, that
  it works with you only, and to commit in its worktree, then its role's instructions. Its role's model, permission
  mode and tools apply.
- **Its worktree** is `.agent-shell/worktrees/ada`, on the branch `agent/ada`, branched from your checkout's HEAD.
  It's made with the agent and kept when the agent stops, so the next start finds its work. It's locked with the
  agent's name as the reason (`git worktree list -v`). `.agent-shell/` stays out of git. A project that isn't a git
  repository, or has no commit yet, can't have a crew.
- **Its colour** is one of the theme's ANSI colours, a free one by default.
- **Its name** goes into the issues' history: its `bd` commands run as `ada`.

## Roles

A role is what a kind of agent does and may do. These four ship with this config:

| Role | Does | May |
|---|---|---|
| scribe | writes issues with you | read, `bd`; no edits |
| investigator | investigates what you give it, writes its findings into the issue | read, search the web, `bd`; no edits |
| builder | builds what you give it, runs the tests, commits on its branch | edit, commit; never push |
| reviewer | reviews a branch you point it to, gives you its verdict | read, `bd`; no edits |

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

- `tools` are allowed without asking. `deny` are never offered. `mode` is Claude Code's permission mode. Claude Code
  enforces all three.
- `max` is how many of the role may run at once. `labels` are the issues it's for.
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

A merge that conflicts stops in your checkout, for you to resolve.

## What you do to one

You can interrupt an agent, kill it, restart it fresh, put it to sleep, wake it, rename it (its worktree and branch
follow) or recolour it. Killing it gives back the issue you gave it, if it's still in progress and assigned to the
agent.

Forgetting an agent takes it out of the crew. Its worktree and branch go too when they hold nothing your checkout
hasn't. Otherwise you're shown what they hold (changes not committed, commits not on your branch) and asked whether
to keep them.

Closing the crew, or quitting Emacs, stops every agent at once, without asking. No process of theirs is left
running. Their worktrees stay.
