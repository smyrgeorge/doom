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

## When to use it

- **Yes:** what changes while you work or that the user will want to glance at: a build or test run you're watching,
  the steps of a longer task and where you are in them, results that come in one by one, a summary that should stay in
  view while the conversation goes on.
- **Issues and plans, always, without being asked:** they stay worth seeing while the user decides and while the work
  on them goes on. A project's or an epic's issues (`bd ready`, an epic's children, a label's): the `issues` board
  (`parent`, `label`), which follows your bd commands by itself. A search's results or a few chosen tickets: a `table`
  (`key` the id). A plan, or the ticket you're working on: `steps`, its acceptance criteria as the steps, ticked as you
  go. Say so in a line of your reply rather than repeating the list there.
- **Questions with a list to pick from** (which bugs to fix, which files, which approach): a `choice` (`"multiple":
  true` for several, `"note": true`, `"submit": true`); say in a line that it's there and end your turn: the answer
  comes as your next prompt ("Answer to choice ID (QUESTION): A, B. Note: ..."). A small question (2 to 4 options,
  nothing to show): AskUserQuestion, in the conversation, if you have it.
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
agent-ui render JSON          # an element drawn as text, as the canvas would (nothing shown): {"ok":true,"text":...}
                              # --ansi first: in its colours, to print in a terminal
agent-ui define FILE          # a type of your own (see below), from FILE or stdin
agent-ui snapshot ID          # the element as an image, for your reply: {"file":..., "markdown":"![...](...)"}
agent-ui bug JSON             # a bug in Agent UI itself, filed in its own issues (see below)
```

The same operations are MCP tools too, where your session has the `agent-ui` server: same arguments (an `element`, an
`id` and a `patch`...), same replies. JSON is the last argument (quote it with single quotes), or comes on stdin (a
heredoc for anything long). An element is an object with a `type`, an `id` (letters, digits, `-`, `_`, `.`), an
optional `title` (a line above it) and its type's properties.

**Several canvases.** `--canvas NAME` on any operation (or `"canvas": "NAME"` in the JSON: an element's, a change's, a
batch's operation's; the `canvas` argument of the MCP tools) uses another canvas of your session, in a pane of its
own, instead of its canvas: `agent-ui show --canvas tests '{...}'`. Use it for a second subject worth its own pane
(the tests' results beside the build's dashboard), not for each element. Its name: letters, digits, spaces, `_ . -`.
Ids are its own; `list` and `clear` are a canvas's. It closes, is kept and comes back with your session.

Replies: `{"ok":true,"id":"build"}`, or `{"ok":false,"error":"..."}` saying exactly what's wrong (an unknown property
lists the right ones). Exit status: 0 done, 1 not done, 2 a wrong use, 3 no Emacs (the canvas can't be used: carry on
without it). A wrong element is refused whole; nothing half-shown.

## The types

### `progress`

A bar: `value` of `max`, with a `label` saying what's being done now, and an optional `unit` (files, MB). Without
`max`, no end is known: a block goes to and fro. `status`: `running` (default), `done` or `failed` colours it and stops
it. Its rate and the time left (`3.4 MB/s  19s left`) are worked out from your updates and shown once steady:
update its `value` as it goes (every second or so) rather than once at the end.

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

**Times and sub-steps.** A step is timed from `running` to `done` or `failed` (its time counting while it runs), or
give its `seconds`. A step's own `steps` are drawn under it; append one with `"parent"` (its step's name, at any
depth), or a step with `steps` (merged by name), up to 4 deep:

```sh
agent-ui append plan '{"steps":[{"name":"compile","parent":"Build","status":"running"}]}'
agent-ui append plan '{"steps":[{"name":"compile","parent":"Build","status":"done"},{"name":"link","parent":"Build","status":"running"}]}'
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

`align` sets each column's: `["left","right","center"]`. Columns all named `""`: no header, the rows alone (a
summary of figures). `sort` (a column's name or index) orders the rows, `descending` the other way; the user sorts
with `s` on a column, and you see it in `list`. `row-actions` are buttons on each row putting a prompt into your
session's prompt, `{Column}` in it that row's cell, `{row}` all of them:

```sh
agent-ui update tests '{"sort":"Time","descending":true,"row-actions":[{"label":"Fix","prompt":"Fix the failing test {Test}"}]}'
```

**To have the user pick rows** (which bugs to fix, which files to change): `select`, with a `question`, `multiple`
for several, `note` for a note, `submit` to send at once. Marks come before the rows, the user picks them (RET, a
click, All, None) and presses Send: "Answer to ID (QUESTION): their keys. Note: ..." comes as your next prompt (the
`key` column's cells, else the first column's). Say so in a line and end your turn:

```sh
agent-ui show '{"id":"bugs","type":"table","columns":["ID","P","Bug"],"key":"ID","rows":[["doom-1ms","P2","Tabs: a new buffer loses its tab"],["doom-3z6","P2","Large Markdown freezes Emacs"]],"select":{"question":"Which should I fix?","multiple":true,"note":true,"submit":true}}'
```

### `chart`

Numbers over time or side by side. `kind`: `line` (default; `values`, or several `series` each its colour),
`bar` (a bar per value, `labels` naming them; several `series` grouped under each label, or end to end with
`"stacked": true`), `histogram` (its `values` counted in `bins`, labelled with their ranges) or `sparkline` (one line
of the latest values). A line chart's `times` (ISO 8601, or seconds since 1970, one per value) place its values by
time, with an axis of ticks (hours, days) under it. `labels` name
the values in order, `unit` follows the numbers, `min`/`max` fix the axis, `height` is a line chart's in lines. Drawn
as SVG in a graphic Emacs, as characters in a terminal. **For a live chart, append values**, `window` keeping the
latest so many:

```sh
agent-ui show '{"id":"latency","type":"chart","title":"p95 latency","kind":"bar","unit":"ms","labels":["mon","tue","wed"],"values":[120,95,180]}'
agent-ui show '{"id":"mem","type":"chart","title":"Memory","unit":"MB","window":60,"values":[]}'
agent-ui append mem '{"values":[412]}'
agent-ui show '{"id":"times","type":"chart","series":[{"name":"p95","values":[12,15,11]},{"name":"p50","values":[4,5,4]}]}'
agent-ui append times '{"series":[{"name":"p95","values":[13]},{"name":"p50","values":[5]}]}'
agent-ui show '{"type":"chart","kind":"bar","stacked":true,"unit":"s","labels":["v2.3","v2.4"],"series":[{"name":"compile","values":[25,20]},{"name":"test","values":[9,6]}]}'
agent-ui show '{"type":"chart","kind":"histogram","unit":"ms","bins":8,"values":[12,15,18,22,25,31,33,41,58,90]}'
agent-ui show '{"id":"req","type":"chart","times":["2026-11-10T09:00:00","2026-11-10T12:00:00"],"values":[120,340]}'
agent-ui append req '{"times":["2026-11-10T13:00:00"],"values":[410]}'
```

### `image`

An image file (PNG, JPEG, GIF, WebP, SVG; an Excalidraw drawing's `.excalidraw.svg` too) shown in a graphic Emacs, at
most `width` percent of the pane wide and `height` lines high (never above its own size), `alt` under it; in a
terminal, a line naming it. `RET` on it opens it. `file` is relative to your directory. For a screenshot, a plot you
rendered, a drawing. Or give a `url` (http or https) instead: in a graphic Emacs it's downloaded once, in the
background, and kept; its place says so meanwhile, or why it failed (showing it again tries again). As text (a
terminal, `agent-ui render`) its URL is named, nothing downloaded.

```sh
agent-ui show '{"id":"shot","type":"image","title":"The login page","file":"screenshots/login.png","alt":"After the fix","width":60}'
agent-ui show '{"id":"badge","type":"image","url":"https://img.shields.io/badge/build-passing-green.svg"}'
```

### `html`

A web page as a card: its title and the start of its text, from an HTML `file` (or a `url`: its address only).
`RET` on it opens it, in WebKit inside Emacs where it can, else in the browser. For a report or a page you made.

```sh
agent-ui show '{"id":"coverage","type":"html","title":"Coverage","file":"coverage/index.html","lines":3}'
```

### `choice`

A question for the user, when you need a decision: which approach, approve a plan. `options` are labels, or
`{"label", "detail"}`; one to pick, or several with `"multiple": true`; `"note": true` lets them add a note. They pick
(`RET`, a click) and press Answer: "Answer to choice ID (QUESTION): A, B. Note: ..." comes into your prompt (sent at
once with `"submit": true`). Then it shows the answer. Ask one question at a time, and wait for the answer.

```sh
agent-ui show '{"id":"fix","type":"choice","question":"The checker test expects the old message. Which fix?","options":[{"label":"Change the test","detail":"keeps the new message"},{"label":"Revert the message","detail":"as before"}],"note":true}'
```

### `files`

Files, each with its state: a path, or `{"path", "status", "added", "removed", "errors", "line", "note"}`; status
`changed`, `added`, `deleted`, `renamed`, `failing`, `passing` or `none`. `"tree": true` groups them by folder (the
user folds a folder with `RET`). `RET` on a file opens it, at its `line`. For what you touched, or where the errors are.

```sh
agent-ui show '{"id":"touched","type":"files","title":"What I changed","tree":true,"files":[{"path":"src/parser.c","status":"changed","added":12,"removed":3},{"path":"src/lexer.h","status":"added","added":40},{"path":"tests/parser_test.c","status":"failing","errors":2,"line":88}]}'
```

`select` (as a table's: `question`, `multiple`, `note`, `submit`) asks the user to pick files: a mark before each (a
folder's picks its files), the answer their paths: `"select":{"question":"Which should I change?","multiple":true}`.

### `stats`

A row of figures, each with its change: the summary at the top of a canvas. A figure is `{"label", "value", "unit",
"change", "good"}`: `change` a number (▲ or ▼ with it) or text; `good` `"up"` (default: a rise is good, green),
`"down"` (a rise is bad, red: time, errors) or `"none"`. Tiles in the GUI; side by side, wrapping, as text.

```sh
agent-ui show '{"id":"summary","type":"stats","figures":[{"label":"Coverage","value":87.1,"unit":"%","change":2.3},{"label":"Tests","value":412,"change":"all pass"},{"label":"Build","value":29,"unit":"s","change":-12,"good":"down"}]}'
```

### `log`

Lines of output, each coloured by its level (found by its words: error, fatal, panic, failed; warn; info; debug,
trace; or given as `{"level", "text"}`), errors and warnings counted above, the last `show` shown (`keep` kept).
`lines` is text (a line each) or a list; append adds lines. To follow a log as it grows:

```sh
agent-ui show '{"id":"server","type":"log","title":"server.log","lines":"12:01:03 INFO listening on :8080\n12:01:09 ERROR db: connection refused"}'
agent-ui show <<'EOF'
{"id": "app", "type": "log", "title": "app.log", "show": 20,
 "source": {"file": "app.log", "from": "end", "into": "lines"}}
EOF
```

### `timeline`

Tasks as bars on a time axis: `{"name", "start", "end" or "duration", "status"}`, times in seconds or timestamps; a
task without `end` nor `duration` runs until now (with timestamps it grows). `status` running, done, failed or queued
colours it. For CI jobs, parallel test shards, a trace's spans; update the element as tasks start and end.

```sh
agent-ui show '{"id":"ci","type":"timeline","title":"CI","tasks":[{"name":"build","start":0,"duration":8},{"name":"test-1","start":8,"duration":14},{"name":"test-2","start":8,"duration":11,"status":"failed"},{"name":"deploy","start":22,"duration":4,"status":"queued"}]}'
```

### `graph`

Nodes and edges: `nodes` are names, or `{"id", "label", "status"}` (status ok, error, warning, active colours one);
`edges` are `[from, to]`, or `{"from", "to", "label"}`; a node only an edge names is one too. Laid out in layers by
itself: boxes and arrows in the GUI (left to right, or `"direction": "down"`), each node's arrows as text. For module
dependencies, a state machine, a call graph (a few dozen nodes at most).

```sh
agent-ui show '{"id":"deps","type":"graph","title":"Modules","nodes":["lexer","parser",{"id":"checker","status":"error"},"codegen"],"edges":[["lexer","parser"],["parser","checker"],["parser","codegen"],["checker","codegen"]]}'
```

### `code`

A snippet, highlighted by its `language`'s mode (python, c, rust, emacs-lisp...; else its `file`'s), each line
numbered from `from` and linked to `file` (`RET` opens it there). Give `code`, or a `file` with `from` and `to` (read
as it is now). `marks`: `{"line", "kind", "note"}`, kind error, warning, change or info: a sign in the gutter, the note
after the line. For the line an error is on, the code a change is about.

```sh
agent-ui show '{"id":"where","type":"code","title":"Where it fails","language":"c","from":40,"code":"int parse_expr(Parser *p) {\n  return NULL;\n}","marks":[{"line":41,"kind":"error","note":"never NULL here"}]}'
```

The user can review it: `c` on a line (or a region's lines) writes a comment under it, and Send the review puts
them into your prompt as "Review of ID: file:line: comment; ...". The same on a `diff`.


### `issues`

The project's Beads issues as a board: Ready (open, nothing blocking), In progress, Blocked, Done (the latest first),
each issue's id and title, P0/P1 marked. `parent` shows an epic's issues only, `label` those with it, `limit` per
column; `dir` is the project (default: your directory). Fetched by bd in the background, refreshed after your bd
commands; `RET` opens an issue. To keep the work's state in view while you go through an epic.

```sh
agent-ui show '{"id":"board","type":"issues","title":"The epic","parent":"doom-erp","limit":6}'
```

`select` (as a table's) asks the user to pick issues on the board, a mark before each card, the answer their ids:
"which should I work on?" in one click.

### `heatmap`

A grid of cells coloured by their values: `rows` and `columns` (labels), `values` a row of cells for each row: a
number, coloured on a `scale` from the lowest to the highest (`"blue"`: low faint, high strong; `"green-red"`: low
good, high bad; `"red-green"`), a word coloured by its state (passed, failed, flaky, skipped...), or null. A legend
under it; SVG cells with their values in the GUI. A test's results by OS and version, flaky tests by day.

```sh
agent-ui show '{"id":"matrix","type":"heatmap","title":"Test runs by OS","rows":["lexer","parser","checker"],"columns":["linux","macos","windows"],"values":[["passed","passed","passed"],["passed","flaky","passed"],["failed","passed","skipped"]]}'
```

### `panel`

Elements laid out together: `children` are ordinary elements (each its `type`, `title`, `id`), as a `"row"` (side by
side, each its share of the width: `weights`, equal by default) or a `"column"` (the default), in a border (`"border":
false` for none). Panels nest: rows of columns make a dashboard. A row too narrow (under `min-width` a child) stacks
its children. In the GUI, a row holding a chart, graph or image is drawn as one image, side by side (its children's
buttons not clickable there: put a `choice` in a row of its own); in a terminal, as text. Keep a dashboard's related
elements in one panel.

**Each child is an element of its own**: give it an `id`, and `update`, `append`, `remove`, `show` (replacing it),
`snapshot` and links work on it as on any element, its panel redrawn in place. Its `source` runs with it: a live
dashboard is a panel whose children follow commands and files. Ids are unique in the canvas, children's too.

```sh
agent-ui show '{"id":"release","type":"panel","title":"Release","layout":"row","children":[{"id":"release-build","type":"progress","title":"Build","value":8,"max":12},{"id":"release-tests","type":"table","title":"Tests","columns":["Test","Result"],"rows":[["lexer","passed"],["parser","failed"]]}]}'
```

### `diff`

Changes, from a unified diff (`git diff`'s): by file, its lines added and removed counted, and hunk; added lines
green, removed red, each line's number in the new file. `RET` on a line opens its file there. `dir` is where its files
are (default: your directory). To show what you changed, or follow the work tree as you go:

```sh
agent-ui show '{"id":"fix","type":"diff","title":"The fix","diff":"--- a/src/parser.c\n+++ b/src/parser.c\n@@ -40,2 +40,2 @@\n   int depth = 0;\n-  return NULL;\n+  return parse_term(p);\n"}'
agent-ui show <<'EOF'
{"id": "changes", "type": "diff", "title": "Uncommitted changes",
 "source": {"poll": "git diff", "every": 5, "into": "diff"}}
EOF
```

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

## Actions: buttons for the user

Any element can have `actions`: buttons under it that put a `prompt` into your session's prompt when the user
presses one, for them to read and send (or sent at once with `"submit": true`, for what needs no second look). Offer
the next steps that follow from what it shows; at most 6.

```sh
agent-ui show '{"id":"result","type":"text","text":"2 tests failed: checker, codegen.","face":"error","actions":[{"label":"Fix them","prompt":"Fix the 2 failing tests (checker, codegen)."},{"label":"Show the log","prompt":"Show me the test log.","submit":true}]}'
```

## Seeing what you draw

You can't see the user's screen; `render` shows you an element as the canvas draws it, as text, at the canvas's width,
without showing it: check a layout before you show it.

```sh
agent-ui render '{"type":"table","columns":["Test","Result"],"rows":[["lexer","passed"]]}'
```

## In the conversation

`show`'s reply has the element's `link` (`agent-ui://canvas/...#ID`): put it in your reply as a Markdown link
(`[the build](agent-ui://...)`), and clicking it brings up the canvas's pane, the cursor on the element.

The canvas changes; the conversation stays. To keep an element's state in it (the final test table, a chart you're
talking about), `agent-ui snapshot ID` saves it as it's drawn (its buttons left out: they'd do nothing in an image;
pressed on the canvas), an SVG in `.agent-shell/images/`, and replies with `markdown`: put that line in your reply,
and agent-shell shows the image there (its transcript keeps it). The user can
also send you an element: `a` on it in the canvas puts it into your prompt as text, "Agent UI element ID (TYPE), as
it's shown:" and its drawing.

## A type of your own

When none of the types fits (a gauge, a diff summary, a timeline...), write one: an Emacs Lisp file with **one**
`agent-ui-define`, and the definitions it uses, **each named after it** (`agent-ui-NAME-...`), nothing else (no
`setq`, no code run at load; `require` only cl-lib, subr-x, seq, map, pcase, rx, svg). Then `agent-ui define FILE`.
It's checked, compiled, loaded, and its `:example` drawn: the reply has that drawing (`preview`) and the compiler's
`warnings`. Fix and define it again until it's right; it's usable at once. The user then keeps it (loaded at each
start) or discards it (its elements go with it): say what you made and why.

```elisp
;;; gauge.el --- Agent UI type gauge -*- lexical-binding: t; -*-

(defun agent-ui-gauge--text (props ctx)
  "PROPS drawn in CTX's width: [#####.....] 50% LABEL."
  (let* ((value (plist-get props :value))
         (cells (min 20 (max 5 (- (plist-get ctx :width) 30))))
         (full (round (* cells (/ value 100.0)))))
    (concat "[" (propertize (make-string full ?#) 'face 'agent-ui-accent)
            (make-string (- cells full) ?.) "] "
            (format "%d%%" value)
            (if-let* ((label (plist-get props :label))) (concat "  " label) ""))))

(agent-ui-define gauge
  "A gauge: VALUE percent, with a LABEL."
  :props ((value integer "Percent, 0 to 100" :default 0)
          (label string "What it measures"))
  :example (:value 42 :label "disk")
  :check (lambda (props)
           (unless (<= 0 (plist-get props :value) 100)
             (agent-ui--fail "gauge: value must be from 0 to 100"))
           props)
  :text #'agent-ui-gauge--text)
```

- `:props`: `(NAME KIND DOC [:default V] [:required t])`, KIND one of `string`, `number`, `integer`, `boolean`,
  `list`, `any`, `(choice a b c)`. Each element is checked against them before it's drawn.
- `:text (lambda (PROPS CTX) ...)` returns a string, maybe with faces (`agent-ui-accent`, `agent-ui-muted`,
  `agent-ui-success`, `agent-ui-warning`, `agent-ui-error`, `bold`). PROPS: the properties, defaults filled; CTX:
  `:width` (columns: fit it), `:graphic`, `:tick` (counts up, for animations), `:char-width` and `:line-height`
  (pixels, for an SVG), `:still` (a snapshot: draw no buttons, they'd do nothing there). Keep it quick: it runs in
  the user's Emacs, on each change.
- Optional: `:gui` (the same, for a graphic frame: a string with an SVG image, see `svg.el`), `:check` (more than
  each property's kind: signal with `agent-ui--fail`), `:append` (how lists grow), `:animated` (t, or a function of
  PROPS), `:prepare` (the element as it's kept: what it notes as time passes), `:extend` (for a long one appended to:
  edits to its drawing instead of drawing it again; see docs/agent-ui.md).
- Helpers: `agent-ui-pad`, `agent-ui-truncate`, `agent-ui-wrap`, `agent-ui-format-number`, `agent-ui-spinner`. For a type
  that asks the user (picks, a note, an answer into your prompt): `agent-ui-ask-pick-button`, `agent-ui-ask-mark`,
  `agent-ui-ask-all-none`, `agent-ui-ask-note-button`, `agent-ui-ask-answer-button`, `agent-ui-ask-answered-line`,
  its state in the element's `selected`, `note-text`, `answered` (see docs/agent-ui.md).

## Following a long command: sources

Your tool calls run one after another: while you wait on a command, nothing you'd update moves. Give the element a
**`source`** instead, and Emacs updates it from what happens, while you go on:

- `{"command": "make -j8"}`: Emacs runs it (in your directory, or `dir`); the reply names a `log` with all its output,
  for you to read later. When it ends: `done` (exit 0) or `failed` (else), patches where `$code` is the exit code; a
  progress bar is marked done or failed by itself.
- `{"file": "build.log", "from": "end"}`: a file followed as it grows (yours: `make > build.log 2>&1 &`).
- `{"poll": "df -h /", "every": 10}`: a command run every so many seconds.

Each line of its output that matches a rule's `match` changes the element: `set` as an update, `append` as an
append. In them, a string that's only `"$1"` is that group (a number if it reads as one), `"$0"` the match, and `$N`
in other text is replaced. `match` is a regular expression as in `grep -E` (groups, `\d`, `\s`, `\w`, `|`, `?`, `+`,
`*`, `{n,m}`), written in JSON: each `\` doubled (`\\d`, `\\[`). `tail: N` instead sets a `text` element to the last N
lines; `into: PROP` sets that property to all of it (a `diff`'s `diff`).

```sh
agent-ui show <<'EOF'
{"id": "build", "type": "progress", "title": "Build", "max": 1,
 "source": {"command": "ninja -C build",
            "match": "^\\[(\\d+)/(\\d+)\\] (.*)$",
            "set": {"value": "$1", "max": "$2", "label": "$3"}}}
EOF
agent-ui show <<'EOF'
{"id": "tests", "type": "table", "title": "Tests", "columns": ["Test", "Result"], "key": "Test",
 "source": {"command": "cargo test 2>&1",
            "rules": [{"match": "^test (\\S+) \\.\\.\\. (ok|FAILED|ignored)$",
                       "append": {"rows": [["$1", "$2"]]}}],
            "failed": {"title": "Tests: failed (exit $code)"}}}
EOF
agent-ui show <<'EOF'
{"id": "log", "type": "text", "title": "Server log", "text": "",
 "source": {"file": "server.log", "from": "end", "tail": 8}}
EOF
agent-ui show <<'EOF'
{"id": "mem", "type": "chart", "title": "Memory", "unit": "MB", "window": 60, "values": [],
 "source": {"poll": "ps -o rss= -p 4242", "every": 5,
            "match": "(\\d+)", "append": {"values": ["$1"]}}}
EOF
```

`agent-ui list` says how each source goes: `running`, `exit`, `lines` read, its `log`, and the `error` of a change its
rules made that the element refused (a value that isn't a number...). A source stops when its element is removed or
shown again, or the session's canvas closes. To show progress from a script of your own, update the element from it
(`agent-ui update ...` in its loop; `batch` for many at once).

## A bug in Agent UI itself

When Agent UI misbehaves (an element drawn wrong, an error where there should be a drawing, a property it lacks), don't
only work around it: tell the user, ask whether to file it, then file it and carry on with the workaround. It goes
into Agent UI's own issues (found from its code), never the project you're working in:

```sh
agent-ui bug <<'EOF'
{"title": "a stats tile's text overlaps the next tile",
 "description": "A long label runs past its tile into the next one at narrow widths.",
 "expected": "The label cut, or wrapped, inside its tile",
 "workaround": "Shorter labels",
 "element": "kpis",
 "repro": {"type": "stats", "figures": [{"label": "A long label for a figure", "value": 87}]}}
EOF
```

`title` and `description` are required; `element` is the id of the element on the canvas showing it (its JSON and
its drawing go with the report); `repro` an element showing the bug with neutral data (no secrets: it's drawn into
the report). The environment is added for you. The reply: `{"ok":true,"issue":"doom-abc","new":true}`; a similar
bug already open gets your report as a note (`"new":false`; `"new": true` in the JSON files it anyway). Not filed (no
issues set up there, no `bd`): `{"ok":false,"error":...,"report":...}`: show the user the report, to file by hand.

## Cleaning up

Leave the final state of what the user will want to see (the finished bar, the test table) and remove the rest. When
the work it followed is over and talked through, `agent-ui clear` (its pane closes once it's empty). Never leave an
element saying "running" for
something that stopped: mark it `done` or `failed`.
