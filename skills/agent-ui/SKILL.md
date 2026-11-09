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
your session and closes with it.

You drive it with one command, from your shell: **`~/.config/doom/cmd/agent-ui.sh`** (`agent-ui` below). Each call is one
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
agent-ui render JSON          # an element drawn as text, as the canvas would (nothing shown): {"ok":true,"text":...}
agent-ui define FILE          # a type of your own (see below), from FILE or stdin
agent-ui snapshot ID          # the element as an image, for your reply: {"file":..., "markdown":"![...](...)"}
```

The same operations are MCP tools too, where your session has the `agent-ui` server: same arguments (an `element`, an
`id` and a `patch`...), same replies. JSON is the last argument (quote it with single quotes), or comes on stdin (a
heredoc for anything long). An element is an object with a `type`, an `id` (letters, digits, `-`, `_`, `.`), an
optional `title` (a line above it) and its type's properties.

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

### `chart`

Numbers over time or side by side. `kind`: `line` (default; `values`, or several `series` each its colour),
`bar` (one series, a bar per value, `labels` naming them) or `sparkline` (one line of the latest values). `labels` name
the values in order, `unit` follows the numbers, `min`/`max` fix the axis, `height` is a line chart's in lines. Drawn
as SVG in a graphic Emacs, as characters in a terminal. **For a live chart, append values**, `window` keeping the
latest so many:

```sh
agent-ui show '{"id":"latency","type":"chart","title":"p95 latency","kind":"bar","unit":"ms","labels":["mon","tue","wed"],"values":[120,95,180]}'
agent-ui show '{"id":"mem","type":"chart","title":"Memory","unit":"MB","window":60,"values":[]}'
agent-ui append mem '{"values":[412]}'
agent-ui show '{"id":"times","type":"chart","series":[{"name":"p95","values":[12,15,11]},{"name":"p50","values":[4,5,4]}]}'
agent-ui append times '{"series":[{"name":"p95","values":[13]},{"name":"p50","values":[5]}]}'
```

### `image`

An image file (PNG, JPEG, GIF, WebP, SVG; an Excalidraw drawing's `.excalidraw.svg` too) shown in a graphic Emacs, at
most `width` percent of the pane wide and `height` lines high (never above its own size), `alt` under it; in a
terminal, a line naming it. `RET` on it opens it. `file` is relative to your directory. For a screenshot, a plot you
rendered, a drawing.

```sh
agent-ui show '{"id":"shot","type":"image","title":"The login page","file":"screenshots/login.png","alt":"After the fix","width":60}'
```

### `html`

A web page as a card: its title and the start of its text, from an HTML `file` (or a `url`: its address only).
`RET` on it opens it, in WebKit inside Emacs where it can, else in the browser. For a report or a page you made.

```sh
agent-ui show '{"id":"coverage","type":"html","title":"Coverage","file":"coverage/index.html","lines":3}'
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

## Seeing what you draw

You can't see the user's screen; `render` shows you an element as the canvas draws it, as text, at the canvas's width,
without showing it: check a layout before you show it.

```sh
agent-ui render '{"type":"table","columns":["Test","Result"],"rows":[["lexer","passed"]]}'
```

## In the conversation

The canvas changes; the conversation stays. To keep an element's state in it (the final test table, a chart you're
talking about), `agent-ui snapshot ID` saves it as it's drawn, an SVG in `.agent-shell/images/`, and replies with
`markdown`: put that line in your reply, and agent-shell shows the image there (its transcript keeps it). The user can
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
  (pixels, for an SVG). Keep it quick: it runs in the user's Emacs, on each change.
- Optional: `:gui` (the same, for a graphic frame: a string with an SVG image, see `svg.el`), `:check` (more than
  each property's kind: signal with `agent-ui--fail`), `:append` (how lists grow), `:animated` (t, or a function of
  PROPS).
- Helpers: `agent-ui-pad`, `agent-ui-truncate`, `agent-ui-wrap`, `agent-ui-format-number`, `agent-ui-spinner`.

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
lines.

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

## Cleaning up

Leave the final state of what the user will want to see (the finished bar, the test table) and remove the rest. When
the work it followed is over and talked through, `agent-ui clear`. Never leave an element saying "running" for
something that stopped: mark it `done` or `failed`.
