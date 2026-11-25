# Figures and state

Part of the agent-ui skill: read [SKILL.md](../SKILL.md) first. A type's every property: `agent-ui types TYPE`.

Numbers, how things stand, what happened when. To lay several out together (a dashboard), put them in a `panel`
([content.md](content.md)); to have them follow a command or a file as you go, give them a `source`
([sources.md](sources.md)).

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

### `stats`

A row of figures, each with its change: the summary at the top of a canvas. A figure is `{"label", "value", "unit",
"change", "good", "face"}`: `change` a number (▲ or ▼ with it) or text; `good` `"up"` (default: a rise is good, green),
`"down"` (a rise is bad, red: time, errors) or `"none"`; `face` the value's colour (`accent`, `success`, `warning`,
`error`, `muted`: a state, a figure past its limit). Tiles in the GUI; side by side, wrapping, as text.

```sh
agent-ui show '{"id":"summary","type":"stats","figures":[{"label":"Coverage","value":87.1,"unit":"%","change":2.3},{"label":"Tests","value":412,"change":"all pass"},{"label":"Build","value":29,"unit":"s","change":-12,"good":"down"}]}'
```

### `gauge`

One value that matters against its range and limits: coverage against a target, a budget used, a latency against an
SLO. `value` of `min` (0) to `max` (100), `unit`, `label`; `thresholds` are zones, each `{"at", "face"}` colouring
from `at` up to the next (coverage: error at 0, warning at 70, success at 80; a latency: success at 0, warning at 200,
error at 500); `target` a mark. A bar in text, an arc in the GUI. Several: side by side in a panel's row.

```sh
agent-ui show '{"id":"cov","type":"gauge","title":"Coverage","value":78,"unit":"%","target":80,"thresholds":[{"at":0,"face":"error"},{"at":70,"face":"warning"},{"at":80,"face":"success"}]}'
agent-ui update cov '{"value":81}'
```

### `heatmap`

A grid of cells coloured by their values: `rows` and `columns` (labels), `values` a row of cells for each row: a
number, coloured on a `scale` from the lowest to the highest (`"blue"`: low faint, high strong; `"green-red"`: low
good, high bad; `"red-green"`), a word coloured by its state (passed, failed, flaky, skipped...), or null. A legend
under it; SVG cells with their values in the GUI; columns whose labels don't fit numbered, a key under it. A test's
results by OS and version, flaky tests by day.

```sh
agent-ui show '{"id":"matrix","type":"heatmap","title":"Test runs by OS","rows":["lexer","parser","checker"],"columns":["linux","macos","windows"],"values":[["passed","passed","passed"],["passed","flaky","passed"],["failed","passed","skipped"]]}'
```

### `timeline`

Tasks as bars on a time axis: `{"name", "start", "end" or "duration", "status"}`, times in seconds or timestamps; a
task without `end` nor `duration` runs until now (with timestamps it grows). `status` running, done, failed or queued
colours it. Times under 1.5 s show in milliseconds (`"duration": 0.34` is 340ms). For CI jobs, parallel test shards, a
trace's spans; update the element as tasks start and end.

```sh
agent-ui show '{"id":"ci","type":"timeline","title":"CI","tasks":[{"name":"build","start":0,"duration":8},{"name":"test-1","start":8,"duration":14},{"name":"test-2","start":8,"duration":11,"status":"failed"},{"name":"deploy","start":22,"duration":4,"status":"queued"}]}'
```

### `countdown`

Time that matters while waiting, ticking on its own: `since` a start (the time elapsed: a long job) or `until` an end
(the time left: a deploy window, a rate limit's reset), each a timestamp (`"2026-11-10T18:30:00Z"`), epoch seconds,
or seconds from now; `label`; `warn` seconds before the end in the warning colour. Past the end: "ended 2m ago". No
updates needed: it ticks by itself. Work items you count (bugs fixed one by one): a `progress` bar, which says its
time elapsed and left itself (SKILL.md).

```sh
agent-ui show '{"id":"rl","type":"countdown","label":"Rate limit resets in","until":252,"warn":60}'
```

### `graph`

Nodes and edges: `nodes` are names, or `{"id", "label", "status"}` (status ok, error, warning, active colours one);
`edges` are `[from, to]`, or `{"from", "to", "label"}`; a node only an edge names is one too. Laid out in layers by
itself: boxes and arrows in the GUI (left to right, or `"direction": "down"`; in a pane too narrow for it, downwards,
or as text), each node's arrows as text. For module dependencies, a state machine, a call graph (a few dozen nodes at
most).

```sh
agent-ui show '{"id":"deps","type":"graph","title":"Modules","nodes":["lexer","parser",{"id":"checker","status":"error"},"codegen"],"edges":[["lexer","parser"],["parser","checker"],["parser","codegen"],["checker","codegen"]]}'
```

### `tags`

A row of chips: a project's labels, a run's statuses, the filters in use, the versions involved. `tags` are labels,
or `{"label", "face", "color", "count", "prompt"}`: `face` one of `muted`, `success`, `warning`, `error`, `accent`
(the default), `plain`; or a `color`. A chip with a `prompt` is a button putting it into your prompt. Append a tag
whose label is there to change it (its count). With `select`, the user picks chips (labels to apply, platforms to
build for): see [asking.md](asking.md).

```sh
agent-ui show '{"id":"labels","type":"tags","title":"Labels","tags":[{"label":"bug","face":"error","count":12},{"label":"feature","face":"success","count":4},{"label":"docs","face":"muted"}]}'
agent-ui append labels '{"tags":[{"label":"bug","count":11}]}'
```

### `log`

Lines of output, each coloured by its level (found by its words: error, fatal, panic, failed; warn; info; debug,
trace; or given as `{"level", "text"}`: `error`, `warning`, `info`, `debug`, or their words, case aside, and syslog's,
Datadog's, a logger's names: `warn`, `WARNING`, `crit`, `alert`, `trace`, `ok`...), errors and warnings counted above,
the last `show` shown (`keep` kept).
`lines` is text (a line each) or a list; append adds lines. To follow a log as it grows:

```sh
agent-ui show '{"id":"server","type":"log","title":"server.log","lines":"12:01:03 INFO listening on :8080\n12:01:09 ERROR db: connection refused"}'
agent-ui show <<'EOF'
{"id": "app", "type": "log", "title": "app.log", "show": 20,
 "source": {"file": "app.log", "from": "end", "into": "lines"}}
EOF
```

**A line in columns**, for events you make yourself (a run's steps, a deploy's stages): its `time` (muted, shown when
it changes), a `mark` coloured by `mark-face` (`plain`, `muted`, `accent`, `success`, `warning`, `error`, `bold`), its
`source` (a job, a service: each its colour, by its place in the log's `sources`, else by its name, their column as
wide as the widest), its `text` (text, or pieces: text or `{"text", "face"}`), `indent` (0 to 4: a step under its
job), `right` (muted at its end: how long it took) and `level`. `{"gap": "17m"}` is a pause between two lines, not
counted. The log's `unit` says what it counts (`12 events`), its `right` goes at the counts line's end (its span), and
`append` replaces it with the lines.

```sh
agent-ui show '{"id":"deploy","type":"log","unit":"event","sources":["build","ship"],"right":"16:22 – 16:41 · 19m","lines":[{"time":"16:22","mark":"▸","mark-face":"accent","source":"build","text":"started"},{"time":"16:22","mark":"✓","mark-face":"success","source":"build","indent":1,"text":["tests",{"text":" passed","face":"muted"}],"right":"48s"},{"gap":"17m"},{"time":"16:41","mark":"✗","mark-face":"error","source":"ship","level":"error","text":"upload refused: 403","right":"2s"}]}'
agent-ui append deploy '{"lines": [{"time": "16:42", "mark": "↻", "mark-face": "warning", "source": "ship", "text": "retrying"}], "right": "16:22 – 16:42 · 20m"}'
```

### `activity`

What one thing is doing now (a script running, an agent at work), a small box: a header line (a `mark` for its state,
`●` by default, coloured by `mark-face`; its `owner` in its colour, as a log's `sources`; its `label`; its `detail`
muted; `right` at its end, how long it's run, in `right-face`), its last `show` `lines` under it on a rail, each cut
to the width (a log's lines: text, its level found by its words, or `{"text", "level", "mark", "mark-face"}`), `empty`
said while it has none, and a `footer` closing them (text, muted, or pieces). Update it as it goes; remove it once
it's over.

```sh
agent-ui show '{"id":"tests","type":"activity","owner":"ci","label":"make test","detail":"step 2 of 3","right":"1m 23s","lines":[{"mark":"❯","mark-face":"muted","level":"debug","text":"make test"},"ok parser (12 tests)","FAILED lexer::escapes"],"footer":"the last 2 of 214 lines"}'
agent-ui update tests '{"mark":"◆","mark-face":"warning","right":"asks you","right-face":"warning"}'
```
