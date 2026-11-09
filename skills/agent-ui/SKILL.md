---
name: agent-ui
description: >-
  Show things to the user in Emacs beside your agent-shell session, on its Agent UI canvas: progress bars, checklists
  of steps, tables, text, Markdown, each updated in place as work goes on. Use when running inside Emacs (agent-shell)
  with this Doom config, for anything that changes over time or that the user should keep in view while the
  conversation scrolls: a long build or test run, a multi-step task's progress, results arriving one by one.
---

# Agent UI

Beside your agent-shell session, Emacs has a **canvas**: a pane of its own that opens, without taking the user's focus,
the first time you show something. It holds **elements**, in the order you showed them. Each has an id you choose, and
you change it in place: a progress bar moves, a table fills in, a step goes from running to done. The canvas belongs to
your session and closes with it.

You drive it with one command, from your shell: **`~/.config/doom/cmd/agent-ui`** (`agent-ui` below). Each call is one
quick round trip to Emacs; its reply is JSON on stdout.

## When to use it

- **Yes:** what changes while you work or that the user will want to glance at: a build or test run you're watching,
  the steps of a longer task and where you are in them, results that come in one by one, a summary that should stay in
  view while the conversation goes on.
- **No:** what you'd say once. Answers, explanations, code and reports go in your reply (Markdown), as usual. Don't
  duplicate your reply on the canvas.
- Keep it tidy: a handful of elements, each worth looking at. Update rather than add; remove what stopped helping.

## The command

```sh
agent-ui show JSON            # show an element; its id there already: replaced in place
agent-ui update ID JSON       # change some of its properties; null puts one back to its default
agent-ui append ID JSON       # add to its lists: a table's rows, a checklist's steps
agent-ui remove ID            # remove it
agent-ui clear                # remove every element
agent-ui list                 # the canvas's elements: ids and types
agent-ui types [TYPE]         # the types, their properties, an example each
agent-ui batch JSON           # several operations at once: [{"op":"show",...}, {"op":"update","id":...,...}]
```

JSON is the last argument (quote it with single quotes), or comes on stdin (a heredoc for anything long). An element
is an object with a `type`, an `id` (letters, digits, `-`, `_`, `.`), an optional `title` (a line above it) and its
type's properties.

Replies: `{"ok":true,"id":"build"}`, or `{"ok":false,"error":"..."}` saying exactly what's wrong (an unknown property
lists the right ones). Exit status: 0 done, 1 not done, 2 a wrong use, 3 no Emacs (the canvas can't be used: carry on
without it). A wrong element is refused whole; nothing half-shown.

## The types

### `progress`

A bar: `value` of `max`, with a `label` saying what's being done now, and an optional `unit` (files, MB). Without
`max`, no end is known: a block goes to and fro. `status`: `running` (default), `done` or `failed` colours it and stops
it.

```sh
agent-ui show '{"id":"build","type":"progress","title":"Build","max":12,"label":"configuring"}'
agent-ui update build '{"value":7,"label":"linking"}'
agent-ui update build '{"value":12,"status":"done","label":"done in 41s"}'
agent-ui show '{"id":"fetch","type":"progress","label":"downloading dependencies"}'
```

### `steps`

A checklist. A step is a name (pending), or `{"name", "status", "detail"}`; status is `pending`, `running` (a spinner),
`done`, `failed` or `skipped`; detail is a short note after it. **Append a step whose name is there to change it in
place**, so you only send what changed:

```sh
agent-ui show '{"id":"plan","type":"steps","title":"Release","steps":["Run the tests","Build","Publish"]}'
agent-ui append plan '{"steps":[{"name":"Run the tests","status":"running"}]}'
agent-ui append plan '{"steps":[{"name":"Run the tests","status":"done","detail":"412 passed"},{"name":"Build","status":"running"}]}'
```

### `table`

`columns` (names) and `rows` (arrays of cells: text, numbers, true, false, null), fitted to the pane's width; numbers
align right; cells reading passed, failed, running, pending, skipped... are coloured. Give a `key` (a column's index
from 0, or its name) and **an appended row whose key is there replaces that row**:

```sh
agent-ui show '{"id":"tests","type":"table","title":"Tests","columns":["Test","Result","Time"],"key":"Test"}'
agent-ui append tests '{"rows":[["lexer","running",null],["parser","running",null]]}'
agent-ui append tests '{"rows":[["lexer","passed","0.4s"]]}'
```

`align` sets each column's: `["left","right","center"]`.

### `text`

Plain text, wrapped to the width, newlines kept. `face`: `plain` (default), `muted`, `success`, `warning`, `error`.

```sh
agent-ui show '{"id":"status","type":"text","text":"All 412 tests pass.","face":"success"}'
```

### `markdown`

Markdown drawn as your replies are: headings, emphasis, lists, task lists, tables, highlighted code, links. For a plan
or notes that should stay in view. Images show as their text.

```sh
agent-ui show '{"id":"notes","type":"markdown","title":"Plan","markdown":"1. **Parse** the config\n2. Check it against `schema.json`\n3. Write the report"}'
```

## Following a long command

Your tool calls run one after another: while you wait on a command, nothing you'd update moves. To show a long
command's progress, update the canvas from a script running it, in the background or as it goes:

```sh
total=$(ls tests/*.sh | wc -l); n=0
agent-ui show "{\"id\":\"suite\",\"type\":\"progress\",\"title\":\"Test suite\",\"max\":$total}"
for t in tests/*.sh; do
  n=$((n+1)); agent-ui update suite "{\"value\":$n,\"label\":\"$(basename "$t")\"}" >/dev/null
  "$t" >/dev/null 2>&1 || failed="$failed $(basename "$t")"
done
agent-ui update suite "{\"status\":\"$([ -z "$failed" ] && echo done || echo failed)\",\"label\":\"failed:${failed:- none}\"}"
```

Updates are cheap (Emacs draws those coming close together at once), but each is a process: for many at a time, use
`batch`. Build JSON with care in loops: a value holding `"` or `\` needs escaping (`jq -n --arg` does it, if there).

## Cleaning up

Leave the final state of what the user will want to see (the finished bar, the test table) and remove the rest. When
the work it followed is over and talked through, `agent-ui clear`. Never leave an element saying "running" for
something that stopped: mark it `done` or `failed`.
