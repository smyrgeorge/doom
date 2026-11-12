---
name: agent-ui
description: >-
  Show things to the user in Emacs beside your agent-shell session, on its Agent UI canvas: progress bars, checklists
  of steps, tables, charts, text, Markdown, each updated in place as work goes on. Use when running inside Emacs (agent-shell)
  with this Doom config, for anything that changes over time or that the user should keep in view while the
  conversation scrolls: a long build or test run, a multi-step task's progress, results arriving one by one.
---

# Agent UI

Beside your agent-shell session, Emacs has a **canvas**: a pane of its own that opens, without taking the user's focus,
the first time you show something. It holds **elements**, in the order you showed them. Each has an id you choose, and
you change it in place: a progress bar moves, a table fills in, a step goes from running to done. The canvas belongs to
your session and closes with it; it's kept with it too, and comes back when the session is resumed (its sources not
started again).

You drive it with one command, from your shell: **`~/.config/doom/cmd/agent-ui`** (`agent-ui` below). Each call is one
quick round trip to Emacs; its reply is JSON on stdout.

This file is the core. The rest is in `references/`, each read only when your task needs it: see
[What to read when](#what-to-read-when). A type's every property: `agent-ui types TYPE`.

## When to use it

- **Yes:** what changes while you work or that the user will want to glance at: a build or test run you're watching,
  the steps of a longer task and where you are in them, results that come in one by one, a summary that should stay in
  view while the conversation goes on.
- **Issues and plans, always, without being asked:** a project's or an epic's issues (`bd ready`, an epic's
  children, a label's): the `issues` board, which follows your bd commands by itself. A search's results or a few
  chosen tickets: a `table` (`key` the id). A plan, or the ticket you're working on: `steps`, its acceptance criteria
  as the steps, ticked as you go. Say so in a line of your reply rather than repeating the list there.
- **Questions:** a list to pick from (which bugs to fix, which files, which approach): a `choice`; before something
  risky (a force-push, a deploy, deleting data): a `confirm`; on a canvas of its own (`--canvas ask`), then end your
  turn: the answer comes as your next prompt. See [asking.md](references/asking.md). A small question (2 to 4
  options, nothing to show): AskUserQuestion, in the conversation, if you have it.
- **No:** what you'd say once. Answers, explanations, code and reports go in your reply (Markdown), as usual. Don't
  duplicate your reply on the canvas.
- Keep it tidy: a handful of elements, each worth looking at. Update rather than add; remove what stopped helping.

## The command

```sh
agent-ui show JSON            # show an element; its id there already: replaced in place
agent-ui update ID JSON       # change some of its properties; null puts one back to its default
agent-ui append ID JSON       # add to its lists: a table's rows, a checklist's steps, a todo's items
agent-ui remove ID            # remove it
agent-ui clear                # remove every element
agent-ui list                 # the canvas's elements: ids and types
agent-ui types [TYPE]         # the types, their properties, an example each
agent-ui batch JSON           # several operations at once: [{"op":"show",...}, {"op":"update","id":...,...}]
agent-ui render JSON          # an element drawn as text, as the canvas would (nothing shown): {"ok":true,"text":...}
                              # --ansi first: in its colours, to print in a terminal
agent-ui define FILE          # a type of your own (references/custom-types.md), from FILE or stdin
agent-ui snapshot ID          # the element as an image, for your reply: {"file":..., "markdown":"![...](...)"}
agent-ui bug JSON             # a bug in Agent UI itself, filed in its own issues (references/bugs.md)
agent-ui panels               # the project's panels, kept in its repo (references/panels.md)
agent-ui open NAME            # one opened for the user; --panel NAME: any operation on it
agent-ui check NAME           # a panel's file checked, nothing run
```

The same operations are MCP tools too, where your session has the `agent-ui` server: same arguments (an `element`, an
`id` and a `patch`...), same replies. JSON is the last argument (quote it with single quotes), or comes on stdin (a
heredoc for anything long). An element is an object with a `type`, an `id` (letters, digits, `-`, `_`, `.`), an
optional `title` (a line above it) and its type's properties.

Replies: `{"ok":true,"id":"build"}`, or `{"ok":false,"error":"..."}` saying exactly what's wrong (an unknown property
lists the right ones). Exit status: 0 done, 1 not done, 2 a wrong use, 3 no Emacs (the canvas can't be used: carry on
without it). A wrong element is refused whole; nothing half-shown.

**Several canvases.** `--canvas NAME` on any operation (or `"canvas": "NAME"` in the JSON; the MCP tools' `canvas`)
uses another canvas of your session, in a pane of its own: for a second subject worth its own pane, or a question
(`ask`). Ids, `list` and `clear` are a canvas's own. It closes, is kept and comes back with your session.

## The types

- **Here, below:** `progress` a bar; `steps` a checklist; `table` rows, filled in by key; `issues` the project's
  Beads issues as a board.
- **Asking the user** ([asking.md](references/asking.md)): `choice` pick from a list; `compare` options shown side
  by side; `confirm` yes or no before something risky; `form` several answers at once; `rank` put in order; `slider`
  a number in a range; `todo` a checklist you both tick. Also there: picking rows, files, issues or chips
  (`select`), a plan to approve (`steps`), changes to accept (`diff`).
- **Figures and state** ([data.md](references/data.md)): `chart` line, bar, histogram, sparkline; `stats` figures
  and their changes; `gauge` a value against its limits; `heatmap` a grid of cells; `timeline` tasks on a time axis;
  `countdown` time elapsed or left; `graph` nodes and edges; `tags` chips; `log` lines by level.
- **Content and layout** ([content.md](references/content.md)): `text`; `markdown`; `code` a snippet, marked,
  reviewed; `diff` changes; `math` formulas; `mermaid` a diagram; `image`; `html` a page as a card; `files` files and their state;
  `panel` elements side by side or stacked: a dashboard.

### `progress`

A bar: `value` of `max`, with a `label` saying what's being done now, and an optional `unit` (files, MB). Without
`max`, no end is known: a block goes to and fro. `status`: `running` (default), `done` or `failed` colours it and stops
it. Its rate and the time left (`3.4 MB/s  19s left`) are worked out from your updates and shown once steady:
update its `value` as it goes (every second or so) rather than once at the end. `"pie": true` draws it small, on one
line (`◑ 7/12  58%  linking`): for a panel's corner, or several side by side.

```sh
agent-ui show '{"id":"build","type":"progress","title":"Build","max":12,"label":"configuring"}'
agent-ui update build '{"value":7,"label":"linking"}'
agent-ui update build '{"value":12,"status":"done","label":"done in 41s"}'
```

### `steps`

A checklist. A step is a name (pending), or `{"name", "status", "detail"}`; status is `pending`, `running` (a spinner),
`done`, `failed` or `skipped`; detail is a short note after it. **Append a step whose name is there to change it in
place**, so you only send what changed. A step is timed from `running` to `done` or `failed` (or give its
`seconds`). Its own `steps` are drawn under it: append one with `"parent"` (its step's name), up to 4 deep. A line
each, cut with … where too long: keep names short. A plan to approve first (`approve`): see
[asking.md](references/asking.md).

```sh
agent-ui show '{"id":"plan","type":"steps","title":"Release","steps":["Run the tests","Build","Publish"]}'
agent-ui append plan '{"steps":[{"name":"Run the tests","status":"done","detail":"412 passed"},{"name":"Build","status":"running"}]}'
agent-ui append plan '{"steps":[{"name":"compile","parent":"Build","status":"running"}]}'
```

### `table`

`columns` (names) and `rows` (arrays of cells: text, numbers, true, false, null), fitted to the pane's width; numbers
align right; cells reading passed, failed, running, pending, skipped... are coloured. Give a `key` (a column's index
from 0, or its name) and **an appended row whose key is there replaces that row**. `align` sets each column's
(`["left","right","center"]`); columns all named `""`: no header. `sort` (a column) orders the rows, `descending` the
other way (the user sorts with `s`). `row-actions` are buttons on each row, `{Column}` in their prompt that row's cell.
To have the user pick rows: `select` ([asking.md](references/asking.md)).

```sh
agent-ui show '{"id":"tests","type":"table","title":"Tests","columns":["Test","Result","Time"],"key":"Test"}'
agent-ui append tests '{"rows":[["lexer","running",null],["parser","running",null]]}'
agent-ui append tests '{"rows":[["lexer","passed","0.4s"]]}'
agent-ui update tests '{"sort":"Time","descending":true,"row-actions":[{"label":"Fix","prompt":"Fix the failing test {Test}"}]}'
```

### `issues`

The project's Beads issues as a board: Ready, In progress, Blocked, Done (the latest first), each issue's id and
title, P0/P1 marked. `parent` shows an epic's issues only, `label` those with it, `limit` per column; `dir` is the
project (default: your directory). Fetched by bd in the background, refreshed after your bd commands; `RET` opens an
issue. To keep the work's state in view while you go through an epic.

```sh
agent-ui show '{"id":"board","type":"issues","title":"The epic","parent":"doom-erp","limit":6}'
```

## Actions: buttons for the user

Any element can have `actions`: buttons under it that put a `prompt` into your session's prompt when the user
presses one, for them to read and send (or sent at once with `"submit": true`). Offer the next steps that follow from
what it shows; at most 6.

```sh
agent-ui show '{"id":"result","type":"text","text":"2 tests failed: checker, codegen.","face":"error","actions":[{"label":"Fix them","prompt":"Fix the 2 failing tests (checker, codegen)."},{"label":"Show the log","prompt":"Show me the test log.","submit":true}]}'
```

## Seeing it, and in the conversation

You can't see the user's screen: `agent-ui render JSON` shows you an element as the canvas draws it, as text, without
showing it: check a layout before you show it. `show`'s reply has the element's `link` (`agent-ui://canvas/...#ID`):
put it in your reply as a Markdown link, and clicking it brings up the canvas, the cursor on the element. To keep an
element's state in the conversation (the final test table), `agent-ui snapshot ID` saves it as an SVG and replies
with `markdown`: put that line in your reply. The user can send you an element too: "Agent UI element ID (TYPE),
as it's shown:" and its drawing come into your prompt.

## Cleaning up

A `steps`, `todo` or `progress` that finished well closes itself 10 s later, counting down: `"close": false` keeps it
(a result to talk through), `"close": N` waits N seconds. One that failed stays. Remove the rest once it stops helping;
`agent-ui clear` when the work is over (its pane closes once empty). Never leave an element saying "running" for
something that stopped: mark it `done` or `failed`.

## What to read when

- Asking the user anything (a list to pick from, a yes or no, a form, an order, a plan to approve, changes to
  accept): [references/asking.md](references/asking.md).
- Figures, charts, how things stand: [references/data.md](references/data.md).
- Notes, code, a diff, an image, a page, files, a dashboard's layout: [references/content.md](references/content.md).
- Following a long command, a file or a poll while you go on (`source`): [references/sources.md](references/sources.md).
- A panel kept in the project, opened again later, its data fetched anew: [references/panels.md](references/panels.md).
- None of the types fits: [references/custom-types.md](references/custom-types.md).
- Agent UI itself misbehaves: [references/bugs.md](references/bugs.md).
