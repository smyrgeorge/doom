# Agent UI

> **Status:** working, in Claude Code sessions in agent-shell (epic `doom-nwj`): the canvas, the command line and MCP
> tools, the `text`, `markdown`, `progress`, `steps`, `table`, `chart`, `image`, `html`, `diff`, `choice`, `files`, `stats`, `log`, `timeline`, `graph` and `code` types, sources (an element
> following a command, a file, a poll), actions (buttons into the prompt), types the agent makes (kept or discarded by
> you), elements in the conversation, canvases kept with their sessions, and what the agent is told. `M-x
> +my/example-agent-ui` shows it ([Examples](examples.md)).

A coding agent (Claude Code in [agent-shell](claude-code.md)) shows you things in Emacs beyond its replies: a progress
bar that moves while a build runs, a table of test results filling in, a chart. It draws them on a **canvas**, a pane
beside its session, through a small command line. Everything works in a terminal (`emacs -nw`); the GUI draws some
elements better (charts as SVG) and has elements of its own (images, drawings, web pages).

![A canvas beside the conversation: steps, tests, a build, a chart](../examples/agent-ui.png)
## The model

- An **element** is data: a JSON object with a `type`, an `id` and the type's properties. The agent never writes Lisp
  for the common case, and an element can be saved and shown again.
- An **element type** (`progress`, `table`...) is defined once in Lisp: its properties, a function drawing it as text,
  and optionally one drawing it for the GUI. The types form a **registry**, from which the agent's catalog is made.
- A **canvas** is a buffer per agent-shell session, shown in a [tiled](editor.md#tiling) pane beside it, without taking
  the focus. It holds the session's elements in the order they were shown. Showing an element with an id already there
  replaces it in place; updating it redraws only that element.

## Elements as JSON

```json
{"id": "build", "type": "progress", "title": "Build", "value": 3, "max": 12, "label": "compiling parser.c"}
```

| Key | |
|---|---|
| `id` | A name of the agent's choice (`[a-z0-9_-]+`), unique in its canvas. Omitted: one is made and returned |
| `type` | An element type of the registry |
| `title` | Optional, any type: a heading line above the element |
| `source` | Optional, any type: a command, file or poll it follows ([Sources](#sources)) |
| `actions` | Optional, any type: buttons putting a prompt into the session's prompt ([Actions](#actions)) |
| anything else | The type's properties. An unknown one is an error naming the type's properties, so the agent learns them |

**Updates** are partial: an object with the `id` and the properties that change, merged into the element's
(shallowly: a list given replaces the list). A property set to `null` goes back to its default.

**Appends** add to an element's list properties (a table's `rows`, a chart's `values`) without sending them all again.
A table with a `key` column replaces a row with the same key instead of adding one, so a row can change state:
`parser` *running*, then `parser` *passed*.

## The command line

`cmd/agent-ui` (the system prompt gives its full path). JSON comes on stdin or as the last argument; the reply is JSON
on stdout.

```sh
agent-ui show '{"id":"build","type":"progress","title":"Build","max":12}'
agent-ui update build '{"value":5,"label":"linking"}'
agent-ui append tests '{"rows":[["lexer","passed","0.4s"]]}'
agent-ui remove build
agent-ui clear                 # every element of the canvas
agent-ui list                  # the canvas's elements: id, type
agent-ui types [TYPE]          # the catalog: each type, its properties, an example
agent-ui batch < ops.json      # several operations, one trip to Emacs
agent-ui render '{"type":...}' # an element drawn as text, nothing shown: for the agent to see it
agent-ui render --ansi '{...}' # the same in its colours (24-bit ANSI), to print in a terminal
agent-ui define gauge.el       # a type of the agent's own (below)
agent-ui snapshot build        # the element as an image for the agent's reply (below)
```

A batch is an array of operations, each an object with its `op` and what it takes, flat:

```json
[{"op": "show", "id": "build", "type": "progress", "max": 12},
 {"op": "update", "id": "build", "value": 3},
 {"op": "append", "id": "tests", "rows": [["lexer", "passed"]]},
 {"op": "remove", "id": "old"}]
```

Its reply has each one's: `{"ok": true, "results": [{"ok": true, "id": "build"}, ...]}`, `ok` false if one failed
(the others are done).

| Reply | |
|---|---|
| `{"ok": true, "id": "build"}` | Done |
| `{"ok": false, "error": "progress: unknown property \"total\"; its properties: value, max, label, unit, status"}` | Not done, and why |

Its exit status: 0 done, 1 not done (the reply says why), 2 a wrong use (an unknown operation, an argument missing),
3 no Emacs to talk to. Each error is a reply too, on stdout.

**How it reaches Emacs.** The script writes the request in a temporary folder (`request`: the operation, the id, the
session, the directory, a line each; `payload`: the JSON as given) and runs `emacsclient --eval '(agent-ui-request
"FOLDER")'`; Emacs writes its `reply` there. No JSON is ever quoted into Lisp, whatever it holds.
Without an Emacs server it fails with a clear error.

**Which canvas.** agent-shell starts the agent with `AGENT_UI_SESSION` in its environment (advice on the client
agent-shell makes), naming its session after its buffer; the agent's shell inherits it, so the script finds its
session's canvas, `Agent UI: SESSION`. Without it (a session started before Agent UI was loaded, an agent in a
terminal), the session working in the script's directory or above it (the deepest; of those, the most recently used),
else the canvas `default`. A session's canvas is killed with it.

**In Lisp,** the same operations: `(agent-ui-show SPEC)`, `(agent-ui-update ID PATCH)`, `(agent-ui-append ID PATCH)`,
`(agent-ui-remove ID)`, each taking an optional `:canvas`. SPEC and PATCH are plists (`(:type progress :value 3)`), as
`json-parse-string` makes them with `:object-type 'plist`.

## The canvas

- **Its buffer** is `*agent-ui: SESSION*`, read-only, in `agent-ui-canvas-mode`. It opens in a tiled pane the first
  time an element is shown (an application of `+my/tiling-apps`), without taking the focus, and again if it was closed.
  `q` hides it; it closes with its session. `a` on an element puts it into the session's prompt; `R` reviews the
  types the agent made.
- **Each element** is the text between two markers, its id in a text property. Drawing replaces that text only;
  point and each window's scroll stay where they were.
- **Redraws are throttled:** an update marks the element dirty, and a timer (`agent-ui-redraw-delay`, 0.1s) redraws the
  dirty ones. A hundred updates a second cost ten redraws.
- **Animated elements** (a spinner, an indeterminate bar) are redrawn by one timer of the canvas, running only while one
  is shown in a window.
- **The width** is the canvas window's; its elements are drawn again when it changes size.
- **Terminal or GUI** is decided by the frame showing the canvas (`display-graphic-p`). A type without a GUI drawing
  draws as text in both.

## Defining a type

```elisp
(agent-ui-define progress
  "A progress bar: VALUE of MAX. Without MAX, it runs without an end (indeterminate)."
  :props ((value  number "Done so far" 0)
          (max    number "The total; none: indeterminate")
          (label  string "What's being done now")
          (status (choice running done failed) "Its colour" running))
  :example (:title "Build" :value 5 :max 12 :label "linking")
  :animated (lambda (props) (null (plist-get props :max)))
  :check (lambda (props) ...)       ; optional: more than each property's kind
  :append (lambda (element patch) ...) ; optional: how its lists grow
  :text (lambda (props ctx) ...)    ; a propertized string
  :gui  (lambda (props ctx) ...))   ; optional: a string with an image
```

- **`:props`** list each property: its name, its kind (`string`, `number`, `boolean`, `list`, `(choice A B...)`), a line
  saying what it is (in the catalog the agent reads), and a default. A spec is checked against them before drawing.
- **`:check`** checks what each property's kind can't (a list's items, properties that go together), signalling
  `agent-ui-error` with what's wrong; it may return the properties normalized (a step's status as a symbol). Inside a
  list, JSON's `false` stays `:false`, for the type to show.
- **`:append`** says how `agent-ui append` adds to it (a table's rows by key); without it, each list is added to.
- **`:text` and `:gui`** take the element's properties (checked, defaults filled) and a context: `:width` in
  characters, `:graphic`, `:tick` for animations, the theme's colours. They return the text to insert; they don't touch
  the buffer. So a type is tested by calling them.
- **Errors are contained:** a drawing that signals shows the error in the element's place, in the error face; the
  canvas and its other elements go on.
- **Limits** keep a drawing quick, as it runs in Emacs's only thread: a table's rows, a chart's values, a text's length
  are capped (`agent-ui-max-rows`...), with a line saying what was left out.

## The first types

| Type | What | Properties |
|---|---|---|
| `text` | A paragraph | `text`, `face` (plain, muted, success, warning, error) |
| `markdown` | Markdown, drawn as agent-shell draws replies | `markdown` |
| `table` | Columns and rows, fitting the width; with a `key` column (index or name), appending a row by its key replaces it | `columns`, `rows`, `key`, `align` |
| `progress` | A bar, or a run without an end | `value`, `max`, `label`, `unit`, `status` |
| `steps` | A checklist whose steps change state; appending a step by its name changes it | `steps`: `["name", {"name":..., "status": "pending/running/done/failed/skipped", "detail":...}]` |
| `chart` | Lines (several series), bars or a sparkline; SVG in the GUI, characters in a terminal; appending values makes it live | `kind`, `values` or `series`, `labels`, `unit`, `min`, `max`, `height`, `window` |
| `image` | An image file (an `.excalidraw.svg` drawing too) in the GUI, sized to the pane; in a terminal, a line naming it; `RET` opens it | `file`, `alt`, `width` (percent), `height` (lines) |
| `choice` | A question for you: options to pick (one or several), a note; Answer puts "Answer to choice ID (question): …" into the session's prompt, then it shows the answer | `question`, `options`, `multiple`, `note`, `submit`, `selected` |
| `files` | Files with their state (changed, added, deleted, renamed, failing, passing) and counts, flat or a tree by folder (`RET` folds a folder); `RET` opens a file at its line | `files`, `tree`, `dir` |
| `stats` | A row of figures with their change (▲▼, green or red by whether a rise is good): tiles in the GUI, side by side as text | `figures` |
| `log` | Lines coloured by level (found by their words, or given), errors and warnings counted, the last ones shown; follows a file with `"into": "lines"` | `lines`, `show`, `keep` |
| `timeline` | Tasks as bars on a time axis (seconds or timestamps), running ones growing, coloured by status, a scale under them; SVG in the GUI | `tasks` |
| `graph` | Nodes and edges, laid out in layers by itself (no Graphviz): boxes and curved arrows in the GUI, shrunk to fit; each node's arrows as text; nodes coloured by status | `nodes`, `edges`, `direction` |
| `code` | A snippet highlighted by its language's mode, lines numbered and linked to its file (`RET` opens it there), marked lines with notes; or a file's lines, read when drawn | `code`, `file`, `from`, `to`, `language`, `marks` |
| `diff` | Changes from a unified diff: by file (lines added and removed) and hunk, coloured, line numbers; `RET` opens the file there; a source with `"into": "diff"` follows `git diff` | `diff`, `dir` |
| `html` | A web page as a card: its title and the start of its text; `RET` opens it in WebKit in a pane (`config/html.el`), else the browser | `file` or `url`, `lines` |

A `file` property is relative to the agent's directory, kept by its full name. A button (`agent-ui-button`) opens
what an element shows: `RET` or a click on it.

## Examples

**A build**, its bar moving as the agent learns more:

```sh
agent-ui show '{"id":"build","type":"progress","title":"Build","max":12}'
agent-ui update build '{"value":7,"label":"linking"}'
agent-ui update build '{"value":12,"status":"done","label":"done in 41s"}'
```

```text
Build
███████████████░░░░░░░░░░░  7/12  58%  linking
```

**Tests as they run**, one row per test, changing state by its key:

```sh
agent-ui show '{"id":"tests","type":"table","title":"Tests","columns":["Test","Result","Time"],"key":0,"rows":[]}'
agent-ui append tests '{"rows":[["lexer","passed","0.4s"],["parser","running",""]]}'
agent-ui append tests '{"rows":[["parser","failed","1.2s"]]}'
```

```text
Tests
 Test    │ Result │ Time
─────────┼────────┼──────
 lexer   │ passed │ 0.4s
 parser  │ failed │ 1.2s
```

**A chart**, as text in a terminal and as SVG in the GUI:

```sh
agent-ui show '{"id":"latency","type":"chart","title":"p95 latency (ms)","kind":"bar",
                "labels":["mon","tue","wed","thu"],"values":[120,95,180,60]}'
```

```text
p95 latency (ms)
mon  ████████████████          120
tue  ████████████▋              95
wed  ████████████████████████  180
thu  ████████                   60
```

## Sources

The agent's tool calls run one after another: a bar it updates itself stands still while it waits on a long command.
An element's `source` has Emacs follow what changes instead (`config/agent-ui/source.el`):

| Source | |
|---|---|
| `{"command": "make -j8"}` | Run by Emacs, in the agent's directory (or `dir`); its output kept in a log the reply names; when it ends, its `done` or `failed` patch (`$code`: its exit code), a progress bar's own if none |
| `{"file": "build.log", "from": "end"}` | A file followed as it grows (from its start by default; written again, from its start again) |
| `{"poll": "df -h /", "every": 10}` | A command run every so many seconds |

Rules turn its lines (`\r` ends one too, as a progress meter's) into changes: each line matching a rule's `match` (a
regular expression as in `grep -E`, turned into Emacs's) applies its `set` (an update) and `append`, their `"$1"`
a group's value (a number if it reads as one), `$N` in text replaced. `tail: N` sets a text element to the last N
lines. A chunk of output is one update, however many lines it has.

```json
{"id": "build", "type": "progress", "title": "Build", "max": 1,
 "source": {"command": "ninja -C build", "match": "^\\[(\\d+)/(\\d+)\\] (.*)$",
            "set": {"value": "$1", "max": "$2", "label": "$3"}}}
```

`agent-ui list` gives each source's state: running, its exit code, how many lines, its log, and the error of a
change the element refused. A source stops when its element is removed or shown again, or its canvas closed. An
update can't change a source: showing the element again does.

## MCP

Each agent-shell session also gets the operations as MCP tools, with their schemas: `show`, `update`, `append`,
`remove`, `clear`, `list`, `types`, `render`, `snapshot`, `batch`, `define` (`show`'s description lists the types,
asked of Emacs). The server is `cmd/agent-ui-mcp.el`, run by a batch Emacs (this Emacs's binary) the agent starts,
registered in `agent-shell-mcp-servers` with the session's name and directory; each call goes through
`cmd/agent-ui`, so replies and errors are the command line's. The system prompt says the tools are there.
`(setq +my/agent-ui-mcp nil)` in `config.el` turns them off.

## Actions

Any element can have `actions`: buttons under it, each a `label` and the `prompt` it puts into the session's prompt
when pressed (`RET` or a click), for you to read and send; with `"submit": true`, sent at once. At most 6; they're
checked when the element is shown.

```json
{"id": "result", "type": "text", "text": "2 tests failed.", "face": "error",
 "actions": [{"label": "Fix them", "prompt": "Fix the 2 failing tests."},
             {"label": "Show the log", "prompt": "Show me the test log.", "submit": true}]}
```

```text
2 tests failed.
⏵ Fix them   ⏵ Show the log
```

## Kept with the session

A session's canvas is saved as it changes (a moment later, the changes together), as its elements' JSON, in the
session's `.agent-shell/agent-ui/`, named by its ACP session id, beside agent-shell's transcripts
(`config/agent-ui/persist.el`). When a session starts with that id (resumed: `SPC o C` with `C-u C-u`, or
agent-shell's restart), its canvas comes back as it was. Its elements' sources aren't started again: a command isn't
run twice. Closing a canvas, or its session, leaves what's saved; clearing it saves it empty.

## In the conversation

agent-shell owns its buffer's text, so an element isn't put there: it goes the ways agent-shell already has
(`config/agent-ui/snapshot.el`).

- **From the agent:** `agent-ui snapshot ID` saves the element as it's drawn, an SVG (its text in its faces' colours,
  a word at its column; a bar's blocks as rectangles; a chart's own SVG nested), in the session's
  `.agent-shell/images/`, and replies with a Markdown image link. In its reply, agent-shell shows it inline, and the
  transcript keeps it.
- **From you:** `a` on an element in a canvas puts it into its session's prompt, as text: its id, its type, its
  drawing in a code block.
- **Links:** `show`'s reply has the element's link, `agent-ui://canvas/NAME#ID`. In the agent's reply as a Markdown
  link, agent-shell draws it, and a click on it (`browse-url`, whose handler this is) brings up the canvas's pane,
  selected, the cursor on the element.

## Types the agent makes

When none of the types fits, the agent writes one: an Emacs Lisp file with one `agent-ui-define` and the definitions it
uses, each named after it (`agent-ui-NAME-...`), nothing else (no `setq`, nothing run at load; `require` of a few
built-in libraries only). `agent-ui define FILE` stages it (`config/agent-ui/staging.el`):

1. **Checked:** its forms read, one type, its definitions named after it, not a type already there (built in or kept).
2. **Compiled** by the byte compiler, nothing written: errors refuse it, warnings go back to the agent (by its lines).
3. **Loaded,** and **its example drawn:** the reply has that drawing as text (`preview`), so the agent sees what it
   made. An example that doesn't draw refuses it. Refused, nothing of it stays (a staged type it was replacing is back).

A staged type is usable at once. A message says the agent made one, and each canvas's header lists the types waiting.
**`R`** in a canvas (`M-x agent-ui-review`) lists them (`config/agent-ui/review.el`):

| Key | Action |
|---|---|
| `RET` | Its preview: what it is, its properties, its example drawn (as SVG if it has a GUI drawing), its code |
| `a` | Keep it: its file moves to `config/agent-ui/kept/` (this config, in git), loaded at each start; an issue is filed in this config's Beads issues for its tests and documentation |
| `x` | Discard it: its file deleted, the elements of it removed from the canvases |
| `v` | Its code, read-only |

Staged types wait in Doom's cache (`agent-ui/staged/`): after a restart they aren't loaded again, but stay listed for
the review, which loads one to preview it. Kept types are the library's like the others: the tests expect each type
to have its tests and its section in the skill, which the filed issue is for.

## What the agent is told

A paragraph in Claude Code's system prompt (`agent-ui-agent-context`, one of
`+my/agent-shell-claude-context-functions`), while Emacs runs a server: the canvas, when to use it rather than Markdown
in a reply (for what changes over time or deserves watching), the command's full path with an example, and to read the
skill before using it the first time. The skill, [skills/agent-ui/SKILL.md](../skills/agent-ui/SKILL.md), has each
type with examples, how to follow a long command, and cleaning up; it's read from there, nothing to install (as other
skills, it can be installed too: [AI agents](ai-agents.md)). A test runs each of its examples, so they stay right as
the types change.

## Later


## Files

| Path | What |
|---|---|
| `config/agent-ui.el` | Settings and keys; loads `config/agent-ui/` |
| `config/agent-ui/core.el` | The registry, `agent-ui-define`, checking specs, containing errors |
| `config/agent-ui/canvas.el` | The canvas: its buffer, elements, redraws |
| `config/agent-ui/request.el` | `agent-ui-request`: the command line's way in, finding the canvas |
| `config/agent-ui/agent.el` | agent-shell's sessions: `AGENT_UI_SESSION`, finding a request's session, its canvas |
| `config/agent-ui/persist.el` | Kept with the session: saved as it changes, back when it's resumed |
| `config/agent-ui/snapshot.el` | In the conversation: an element as an SVG for the agent's reply, into the prompt |
| `config/agent-ui/source.el` | Sources: an element following a command, a file, a poll |
| `config/agent-ui/staging.el` | Types the agent makes: checked, compiled, loaded, kept or discarded |
| `config/agent-ui/review.el` | The review: the list of staged types, a preview, keep, discard |
| `config/agent-ui/kept/` | The types you kept (made when you keep one) |
| `config/agent-ui/elements.el`, `elements/` | The element types, a file each: `text`, `markdown`, `progress`, `steps`, `table`, `chart`, `image`, `html`, `diff`, `choice`, `files`, `stats`, `log`, `timeline`, `graph`, `code` |
| `examples/agent-ui.el` | The example: a canvas beside a conversation, filled in as the agent works |
| `cmd/agent-ui` | The command line |
| `cmd/agent-ui-mcp.el` | The MCP server: the same operations as tools |
| `skills/agent-ui/SKILL.md` | The skill: the types with examples, for the agent |

None of `config/agent-ui/` uses Doom (`config/agent-ui.el` does: its settings, keys, the Beads issue for a kept type),
so it can become a package of its own.
