# Agent UI

> **Status:** working in agent-shell's sessions, whatever their agent.

Your coding agent (in [agent-shell](agent-shell.md)) shows you things in Emacs beyond its replies: a progress bar that
moves while a build runs, a table of test results filling in, a chart. It draws them on a **canvas** under its
conversation, through a small command line, in the GUI and in a terminal.

![A session with its Agent UI under it: the release's steps, build and chart, a question, the tests](../examples/agent-ui.png)

Try it: `M-x +my/example-agent-ui`, an offline agent releasing a project ([Examples](examples.md)).

## The model

- An **element** is data: a JSON object with a `type`, an `id` and the type's properties. The agent doesn't write Lisp
  for the common case, and an element can be saved and shown again.
- An **element type** (`progress`, `table`...) is defined once in Lisp. It has its properties, a function that draws it
  as text, and optionally one that draws it for the GUI. The types form a **registry**, and the agent's catalog is made
  from it.
- A **canvas** is a buffer for each agent-shell session, shown under the session's conversation
  ([below](#in-the-sessions-pane)). It holds the session's elements in the order they were shown. Showing an element
  whose id is already there replaces it in place. Updating an element redraws only that element.

## Elements as JSON

```json
{"id": "build", "type": "progress", "title": "Build", "value": 3, "max": 12, "label": "compiling parser.c"}
```

| Property | What |
|---|---|
| `id` | A name the agent picks (`[a-z0-9_-]+`), unique in its canvas. Without one, one is made and returned |
| `type` | An element type from the registry |
| `title` | Optional, any type: a heading above the element, wrapped if too long |
| `source` | Optional, any type: a command, file or poll it follows ([Sources](#sources)) |
| `actions` | Optional, any type: buttons that put a prompt into the session's prompt ([Actions](#actions)) |
| `close` | Optional, for `steps`, `todo` and `progress`: seconds it stays once finished well, or `false` to keep it ([Finished, it closes](#finished-it-closes)) |
| `with` | Optional, any type: the id of the question it's shown with. It goes when that question is answered ([A question waiting](#a-question-waiting)) |
| anything else | The type's properties. An unknown one is an error that lists the type's properties, so the agent learns them |

- **Updates** are partial: an object with the `id` and the properties that change. They're merged into the element's
  properties shallowly, so a list given replaces the list. A property set to `null` goes back to its default.
- **Appends** add to an element's lists (a table's `rows`, a chart's `values`) without sending them all again. In a
  table with a `key` column, a row with the same key replaces the old row instead of adding one. So a row can change
  state: `parser` *running*, then `parser` *passed*.

## The command line

The agent runs `cmd/agent-ui`; what the session is told gives its full path. JSON comes on stdin or as the last
argument, and the reply is JSON on stdout.

```sh
agent-ui show '{"id":"build","type":"progress","title":"Build","max":12}'
agent-ui update build '{"value":5,"label":"linking"}'
agent-ui append tests '{"rows":[["lexer","passed","0.4s"]]}'
agent-ui remove build
agent-ui clear                 # every element of the canvas
agent-ui list                  # the canvas's elements: id, type
agent-ui get [ID] [--changed]  # what it shows, as data: its elements and their values (--changed: since the last read)
agent-ui types [TYPE]          # the catalog: each type, its properties, an example
agent-ui batch < ops.json      # several operations, one trip to Emacs
agent-ui render '{"type":...}' # an element drawn as text, nothing shown: for the agent to see it
agent-ui render --ansi '{...}' # the same in its colours (24-bit ANSI), to print in a terminal
agent-ui define dial.el        # a type of the agent's own (below)
agent-ui snapshot build        # the element as an image for the agent's reply (below)
agent-ui list --canvas tests   # any of them, on another canvas of the session (below)
agent-ui bug < bug.json        # a bug in Agent UI itself, into its own issues (below)
agent-ui panels                # the project's panels, which are open (below)
agent-ui open service          # one of them opened for the user
agent-ui list --panel service  # any operation on an open one
agent-ui check service         # a project panel's file checked, nothing run (below)
```

A batch is an array of operations. Each one is a flat object with its `op` and what that operation takes:

```json
[{"op": "show", "id": "build", "type": "progress", "max": 12},
 {"op": "update", "id": "build", "value": 3},
 {"op": "append", "id": "tests", "rows": [["lexer", "passed"]]},
 {"op": "remove", "id": "old"}]
```

The batch's reply has each operation's result: `{"ok": true, "results": [{"ok": true, "id": "build"}, ...]}`. Its `ok`
is false if one failed; the others are still done.

| Reply | Meaning |
|---|---|
| `{"ok": true, "id": "build"}` | Done |
| `{"ok": false, "error": "progress: unknown property \"total\"; its properties: value, max, label, unit, status"}` | Not done, and why |

| Exit status | Meaning |
|---|---|
| `0` | Done |
| `1` | Not done; the reply says why |
| `2` | A wrong use: an unknown operation, a missing argument |
| `3` | No Emacs to talk to |

Every error is also a reply, on stdout.

- **Emacs's server:** the script reaches Emacs through `emacsclient`, so Emacs must run a server. Without one, it fails
  with a clear error. The JSON is never quoted into Lisp, whatever it holds.
- **Which canvas:** agent-shell starts the agent with `AGENT_UI_SESSION` in its environment, naming its session. The
  agent's shell inherits it, so the script finds its session's canvas, `Agent UI: SESSION`.
- **Without `AGENT_UI_SESSION`** (a session started before Agent UI was loaded, an agent in a terminal), the script uses
  the session working in its directory or above it. The deepest one wins, then the most recently used. With no such
  session, it uses the canvas `default`.
- **Another canvas:** `--canvas NAME`, or `"canvas": "NAME"` in the JSON (an element's, a change's, a batch
  operation's), picks the session's other canvas `Agent UI: SESSION / NAME`. A name has letters, digits, spaces and
  `_ . -`, up to 40 characters.
- **From Lisp,** the same operations are `(agent-ui-show SPEC)`, `(agent-ui-update ID PATCH)`,
  `(agent-ui-append ID PATCH)` and `(agent-ui-remove ID)`. Each takes an optional `:canvas`, and `:section`
  ([below](#sections)). SPEC and PATCH are plists (`(:type progress :value 3)`), as `json-parse-string` makes them with
  `:object-type 'plist`.

## The canvas

A canvas is a read-only buffer, `Agent UI: SESSION`, in `agent-ui-canvas-mode`. It opens in its session's pane
([below](#in-the-sessions-pane)) the first time an element is shown, without taking the focus. Its keys act on the
element at point.

| Key | Action |
|---|---|
| `q` | Close the canvas for good, with its elements |
| `gr` | Redraw it |
| `RET` or a click | Press the button at point, or open what the element shows |
| `a` | Put the element into the session's prompt ([In the conversation](#in-the-conversation)) |
| `b` | File a bug in Agent UI about the element ([below](#bugs-in-agent-ui)) |
| `c` | On a line of code or a diff, or a region's lines: write a review comment under it. On a comment: edit it |
| `d` | On a comment: remove it |
| `s` | On a table's column: sort the table by it. Again: the other way |
| `S` | Save the element as one of the project's panels ([Project panels](#project-panels)) |
| `R` | Review the types the agent made ([below](#types-the-agent-makes)) |
| `SPC m e` | Save what the canvas shows now as a PDF, in the session's `.agent-shell/pdf/` (a project panel's: beside its file) |

Questions have keys of their own ([Types that ask](#types-that-ask)).

- **Closing it:** `q` closes it for good, with its elements. A session's saved elements come back when the session is
  resumed; an element the agent updates after you closed it is gone.
- **Review comments:** **Send the review** sends all your comments, with their places, to the agent at once.
- **Emptied** (cleared, or its last element removed), a canvas hides. It closes with its session, its buffer killed.
- **Without a session** (an agent in a terminal), a canvas opens in a [tiled](editor.md#tiling) pane of its own, as
  tiling's `agent-ui` application.
- **Other canvases:** besides its own canvas, a session may have others, named (`--canvas tests`, `"canvas": "tests"` in
  the JSON, the MCP tools' `canvas`). `Agent UI: SESSION / tests` has its own elements and ids, and is a view of its own
  in the session's pane.
  - They close with the session, and are kept and come back with it.
  - An emptied one closes, until an element is shown there again.
  - A question that takes the focus is brought fully into view. Its view is made taller if it must be.
- **Terminal or GUI:** the frame showing the canvas decides. The GUI draws some elements better (charts as SVG) and has
  elements of its own (images, drawings, web pages). A type without a GUI drawing draws as text in both.
- **Its top line** is empty, and the cursor is there when the canvas opens. Its first element can start with an image
  (stat tiles, a chart, a panel), and the cursor on an image frames the whole of it.
- **Redrawing** an element leaves the cursor and each window's scroll where they were.
- **Width:** elements fit the canvas window's width. They're drawn again when the window changes size, or the font's
  size changes.
- **Animated elements** (a spinner, a bar without an end) are redrawn only while one is shown in a window. The spinner
  is a dot, `●`, whose colour glows brighter and dimmer.
- **Glyphs:** in the GUI, a character the default font lacks (`✎`, `⏵`) comes from another font, often wider or narrower
  than a column and taller than a line. The canvas draws it as large as a line holds, and makes the space beside it
  narrower or wider to match. Borders and the `│` between columns stay in place, and every line keeps the same height.
- **Limits** keep drawing quick, since it runs in Emacs's only thread. A table's rows, a chart's values and a text's
  length are capped, with a line saying what was left out.
- **A drawing that fails** shows its error in the element's place, in the error face. The canvas and its other elements
  go on.

| Setting | Default | What |
|---|---|---|
| `agent-ui-close-finished` | `10` | Seconds a finished element stays ([below](#finished-it-closes)). `nil`: only those whose `close` asks close |
| `agent-ui-redraw-delay` | `0.1` | Seconds from an update to its redraw. The updates within it are drawn together |
| `agent-ui-spinner-frames` | `'("●")` | The spinner's frames, such as `'("▟" "▙" "▛" "▜")` |
| `agent-ui-spinner-pulse` | `8` | The spinner's glow, over this many animation ticks. `nil`: no glow |
| `agent-ui-max-rows` | `500` | The most rows (a table's) or values (a chart's) an element draws |
| `agent-ui-max-chars` | `20000` | The most characters an element's drawing has |
| `agent-ui-pdf-directory` | `".agent-shell/pdf/"` | Where `SPC m e` saves a canvas's PDF, in its session's directory |
| `agent-ui-svg-font-weight` | `600` on macOS, `400` elsewhere | The weight of the text in charts, graphs and diagrams. On macOS, SemiBold matches the editor's text, which macOS draws a little heavier |

Set them in `config.el`, such as `(setq agent-ui-close-finished nil)`.

### Finished, it closes

A `steps`, `todo` or `progress` that finished well closes itself 10 seconds later. Finished well means every step done
or skipped, every item ticked, or the bar at its end.

- A line under it counts down, with a **Keep** button. It says "closing" when it's the canvas's last element and the
  canvas goes with it, or "removed" when the canvas stays. The pane closes with its last element.
- One that failed stays. A change meanwhile starts the countdown again, or stops it.
- The agent's `"close"` on an element decides for it: seconds, or `false` to keep it.
- A project panel never closes.
- An element that comes back with its resumed session stays, as if kept, until it changes.

## In the session's pane

A session's Agent UI is shown in its session's pane: the conversation on top, Agent UI at the bottom. Agent UI is as
high as what it shows needs, with no empty lines under its views, and at most half the pane. It grows and shrinks as its
views and their elements come and go; a height you give it stays until what it shows needs another.

| Key | Action |
|---|---|
| `q` (in a view) | Close it for good; the others are laid out again |
| `SPC w d` (in a view) | Hide it until the agent shows something on it (an update doesn't) |
| `SPC m u` (in the session or a view) | Hide Agent UI for the session, or show it again |

- **Views:** the session's canvas and its other ones (`ask`, `tests`...) are views. They're laid out to use the room: in
  columns, each a stack of views, as many columns as fit.
- A view needs 40 columns, or 80 when it shows a diff, code, a graph or diagram, a heatmap, a timeline or a comparison.
  Short views stack beside a tall one, and the session's own comes first.
- When the views need more than half the pane, the layout that hides the fewest of their lines wins.
- When the pane is too narrow for every view (a wide one in a pane under 80 columns), the ones that fit are shown. The
  others come back once the pane has room for them.
- Views are laid out again when they open or close, not while the agent updates them. They're also laid out again when
  the session's pane changes size: a pane beside it opened or closed, a split, Treemacs, the frame resized, a border
  dragged (once you let go).
- Each view scrolls and is selected on its own, with a bar over it naming it; the session's own reads `Canvas`. Under
  the views at the bottom is Doom's mode line, as tall as the panes' beside them. Under the leftmost it says
  `Agent UI · 2 views` where the major mode would be. The session's mode line stays under the conversation.
- A canvas showing a single panel with a title (a dashboard) has that title on its bar, not drawn over the panel too. A
  canvas in a pane of its own, such as a project panel, has it in its tab: `Agent UI: TITLE`. Once a second element is
  shown, the title is drawn over the panel again and the bar names the canvas. Snapshots and PDFs keep the title.
- [Tiling](editor.md#tiling) treats the session's pane as one pane, Agent UI with it: arranging, resizing, moving it to
  the main pane, fullscreen. Closing the conversation's pane closes its views.
- While the session is in no window (another buffer in its pane, another workspace), Agent UI waits and shows with the
  session.
- While hidden, Agent UI stays hidden as the agent shows things. A question shows it again, and the session too if it's
  in no window, as `C-c C-q` does.
- When the pane is too short for both (6 lines each), the view opens in a pane of its own.

| Setting | Default | What |
|---|---|---|
| `agent-ui-pane-max-share` | `0.5` | The most of the pane Agent UI takes |
| `agent-ui-pane-min-lines` | `6` | The fewest lines the conversation and Agent UI each keep |
| `agent-ui-grid-min-width` | `40` | The fewest columns a view gets |
| `agent-ui-grid-wide-width` | `80` | The fewest columns a view showing a wide type gets |
| `agent-ui-pane-mode-line` | `t` | Doom's mode line under the views; `nil`: Agent UI's own bar, a little shorter |

## Sections

A canvas can be divided into sections, from Lisp. An agent workflow's run does it: one pane, a section per job. Each
section starts with its divider, a rule across the pane with its title, its state's mark and a few words:

```text
Run doom-a1b: feature
▾ build ● 3m ─────────────────────────────────
Steps …
▸ review ◆ · 2 hidden ────────────────────────
▾ merge ✓ ────────────────────────────────────
```

The canvas's own elements come first, then each section's, in order. A section's elements are its own, and so are their
ids: `plan` in one section isn't `plan` in another.

| Key | Action |
|---|---|
| `TAB` or a click (on a divider) | Fold its section, or unfold it |
| `RET` (on a divider) | Call the section's `:open`; without one, fold it |

| Lisp | What |
|---|---|
| `(agent-ui-section CANVAS NAME :title :state :note :folded :open :after)` | Makes section NAME (letters, digits, `_ . -`), at the end or after section AFTER. Called again, it changes what's given. OPEN is a function that `RET` on its divider calls |
| `(agent-ui-show SPEC :canvas CANVAS :section NAME)` | Shows an element in it. `update`, `append`, `remove`, `get`, `elements` and `clear` take `:section` too |
| `(agent-ui-remove-section CANVAS NAME)` | Removes it, with its elements |
| `(agent-ui-sections CANVAS)` | Its sections: name, title, state, note, folded, the canvas it hosts, how many elements |
| `(agent-ui-host NAME CANVAS SECTION)` | Shows canvas NAME (a session's) in SECTION from now on |
| `(agent-ui-unhost NAME [KEEP])` | Gives NAME its own canvas back, its elements in the section removed. With KEEP, they stay there as the section's own |

- **States:** `running` `●` (glowing), `needs-you` `◆`, `waiting` `○`, `paused` `‖`, `done` `✓`, `failed` `✗`, or none.
  Hovering the mark shows its words.
- **Folding:** a folded section's divider says how many elements it hides. What comes in meanwhile stays hidden, except
  a question: it unfolds its section and comes into view. A search that finds something in a folded section unfolds it.
- **A session's canvas in a section** (`agent-ui-host`): everything the session shows goes there, its other canvases'
  elements too (`--canvas tests`, `--canvas ask`). It has no buffer or pane of its own; the canvases it had are emptied
  into the section and closed.
  - Its `list`, `get` and `clear` see that section only. Its links open the canvas it's in, on it.
  - Its buttons act in its session, and its questions wait for it (the session's mode line, `C-c C-q`). Once answered,
    they go as on its own canvas, with what it showed on `--canvas ask`.
  - When the session is killed, its elements there go, and the section stays. When the section is removed (or
    `agent-ui-unhost` is called), its next element opens its own canvas again.
  - What it shows there isn't kept with the session.
- **Clearing** a canvas removes its sections too. Clearing a section removes its elements only. A canvas with a section
  isn't empty, so it stays open.
- **A canvas of no session** (an agent workflow's run's pane) answers its own questions. `agent-ui-answer-function`, set
  in it, gets each answer instead of a session's prompt: the text an agent would read, and its element's key,
  `SECTION/ID`. A section hosting a session's canvas still answers to that session.
- **`agent-ui-closes-with`**, set to the key of one of the canvas's elements: when that element's countdown ends, the
  whole canvas closes, its sections too.
- An answer from a section names its element by its id, as its agent knows it, never by its key.

## Defining a type

Each type is defined once in Lisp, with `agent-ui-define`. The agent can make its own
([Types the agent makes](#types-the-agent-makes)).

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
  :prepare (lambda (element) ...)   ; optional: the element as it's kept
  :extend (lambda (old new ctx) ...) ; optional: its drawing edited, not drawn again
  :text (lambda (props ctx) ...)    ; a propertized string
  :gui  (lambda (props ctx) ...))   ; optional: a string with an image
```

- **`:props`** lists each property: its name, its kind (`string`, `number`, `boolean`, `list`, `(choice A B...)`), a
  line saying what it is (shown in the catalog the agent reads) and a default. A spec is checked against them before
  it's drawn.
- **`:check`** checks what a property's kind can't, such as a list's items or properties that go together. It signals
  `agent-ui-error` with what's wrong. It may return the properties normalized, such as a step's status as a symbol.
  Inside a list, JSON's `false` stays `:false`, for the type to show.
- **`:append`** says how `agent-ui append` adds to it, such as a table's rows by key. Without it, each list is added to.
- **`:prepare`** turns the element into what's kept, each time it's shown or changed. It's for what the element notes as
  time passes, such as a step's start and then how long it ran. Called again on its own result, it must change nothing.
- **`:extend`** is for elements that grow, such as a long log or table. When the element was drawn as OLD and is now NEW
  (lines appended to it), it returns edits that turn OLD's drawing into NEW's: `(replace LINE TEXT)`,
  `(delete LINE COUNT)`, `(insert BEFORE-END TEXT)`. Or it returns nil, to draw it again. An append then draws only
  what's appended. It's used only at the width and kind of frame the element was drawn for.
- **`:text` and `:gui`** take the element's properties (checked, defaults filled) and a context: `:width` in characters,
  `:graphic`, `:tick` for animations, the theme's colours. They return the text to insert and don't touch the buffer, so
  a type is tested by calling them.
- **Badges** for any type (`core.el`): `agent-ui-pill` is a rounded tag (a status, a label, a count in it), filled or
  outlined. `agent-ui-pie` shows a fraction as a pie. In a terminal they're text (`[bug 3]`, `◑`). In the GUI, an SVG as
  wide shows over that text (`svg.el`), sized from the context's `:char-width` and `:line-height`, in the theme's
  colours.
- **A type that asks** (picks, a note, an answer for the agent) uses `config/agent-ui/ask.el`. Its state is the
  element's own `:selected`, `:note-text` and `:answered`, saved with the session. `agent-ui-ask-pick-button`,
  `agent-ui-ask-all-none`, `agent-ui-ask-note-button` and `agent-ui-ask-answer-button` draw its buttons.
  `agent-ui-ask-answered-line` draws the answer once given (locked), and `agent-ui-ask-check` checks a selection.
  `choice` is made of them.

## The types

`agent-ui types TYPE` gives a type's every property, with an example. A `file` property is relative to the agent's
directory, and kept by its full name. A button (`agent-ui-button`) opens what an element shows: `RET` or a click on it.

### Types that show

| Type | What | Properties |
|---|---|---|
| `text` | A paragraph | `text`, `face` (plain, muted, success, warning, error) |
| `markdown` | Markdown, drawn as agent-shell draws replies. Its ```` ```mermaid ```` blocks are drawn as diagrams | `markdown` |
| `table` | Columns and rows that fit the width; a long cell wraps in its column. With a `key` column (index or name), appending a row with the same key replaces it. `s` on a column sorts by it. Each row can have buttons, with its cells in their prompts. With `select`, you pick rows ([Types that ask](#types-that-ask)) | `columns`, `rows`, `key`, `align`, `sort`, `descending`, `row-actions`, `select` |
| `progress` | A bar, or a run without an end, with its label after it (under it, wrapped, when too long). On a canvas, it shows its rate and time left from its updates over time, seconds apart. For work items minutes apart (bugs fixed one by one), a line under it shows the time elapsed (since its first value, or `started`), how long an item takes, the time left (a range when items vary a lot) and when it should end. An item's time is the median of the latest 8, leaving out pauses over 45 minutes (`agent-ui-progress-pause`). Once stopped, it shows the time it took. Its times are kept with it. With `pie`, it's drawn small on one line (`◑ 7/12  58%  linking`), with the time elapsed and left as room allows, and a pie in the GUI | `value`, `max`, `label`, `unit`, `status`, `started`, `pie` |
| `steps` | A checklist whose steps change state, a line each (long ones wrapped). Appending a step with the same name changes it. A step shows its time, timed from running to done (under 1.5 s, in milliseconds once finished), and its own steps under it. A step waiting for you shows ◆ in the warning colour, timed as running. With `approve`, it's a plan you approve first ([Types that ask](#types-that-ask)) | `steps`: `["name", {"name":..., "status": "pending/running/waiting/done/failed/skipped", "detail":..., "seconds":..., "steps": [...]}]`, `approve` |
| `chart` | Lines (several series; on a time axis, with `times`), bars (several series grouped, or stacked), a histogram or a sparkline. SVG in the GUI, characters in a terminal. Appending values makes it live | `kind`, `values` or `series`, `labels`, `unit`, `min`, `max`, `height`, `window`, `stacked`, `bins`, `times` |
| `image` | An image file (an `.excalidraw.svg` drawing too), or one from a URL. In the GUI, it's sized to the pane, and a URL's image is downloaded once with curl and kept in Doom's cache (`agent-ui/images/`). In a terminal, a line names it, with its alt beside it or under it. `RET` opens it | `file` or `url`, `alt`, `width` (percent), `height` (lines) |
| `math` | Formulas typeset from LaTeX math. In the GUI, an image typeset in the background when a tool is installed: MathJax through node (`npm install -g mathjax-full`, which `scripts/tools.sh` installs), or LaTeX and dvisvgm. It's sized to the font, in the theme's colour. In a terminal or without a tool, Unicode where it's simple (`∑ᵢ₌₁ⁿ i = (n(n+1))/2`), else the source | `tex`, `display` (block, inline) |
| `mermaid` | A Mermaid diagram (flowchart, sequence, states, ER, Gantt...). In the GUI, an image drawn in the background by `mmdc` ([Mermaid](mermaid.md)), in the theme's colours, at most the pane's width. It's drawn again when its diagram is updated or the theme changes. Until then, in a terminal or without `mmdc`, it shows its source; on an error, Mermaid's message | `diagram` |
| `countdown` | Time ticking while you wait: elapsed `since` a start, or left `until` an end. Each is a timestamp, epoch seconds, or seconds from now (made a time when shown). Its last `warn` seconds are in the warning colour, and past the end it says "ended 2m ago". In the GUI, a tile with the time big. It's redrawn only while its canvas is in a window | `since` or `until`, `label`, `warn` |
| `gauge` | One value against its range and thresholds: coverage against a target, a budget, a latency against an SLO. Zones are coloured by `thresholds`, each from its `at` up. The value is in its zone's colour, and the `target` is a mark. A bar in text, a half-circle arc in the GUI. Several fit side by side in a panel's row | `value`, `min`, `max`, `unit`, `label`, `thresholds`, `target` |
| `tags` | A row of chips (a project's labels, a run's statuses, filters in use), each in its face or colour, with a count in it. `[bug 12]` in a terminal, a rounded tag in the GUI. Chips wrap, and a chip is never split. A chip with a `prompt` is a button that puts it into the session's prompt. Appending a tag with the same label changes it. With `select`, you pick chips ([Types that ask](#types-that-ask)) | `tags` (`label`, `face`, `color`, `count`, `prompt`), `select` |
| `files` | Files with their state (changed, added, deleted, renamed, failing, passing) and counts, flat or as a tree by folder. `RET` folds a folder, or opens a file at its line. With `select`, you pick files | `files`, `tree`, `dir`, `select` |
| `stats` | A row of figures with their change (▲▼), green or red by whether a rise is good. Tiles in the GUI, side by side as text | `figures` |
| `log` | Lines coloured by level (found from their words, or given). Errors and warnings are counted, the last lines shown, long ones wrapped. It follows a file with `"into": "lines"`. A line can be in columns: its `time` (muted, shown when it changes), a `mark` (in its `mark-face`), its `source` (a job, a service, each in its colour), its `text` (pieces, each text or `{"text", "face"}`), `indent`, and `right` (how long it took, at its end). `{"gap": "17m"}` is a pause | `lines`, `show`, `keep`, `unit` (what it counts: events), `right` (at its counts' end: its span), `sources` (their order: their colours) |
| `activity` | What one thing is doing now, such as a script or an agent at work. A header line has its `mark`, its `owner` (in its colour, as a log's `sources`), its `label`, `detail` (muted) and `right` at its end. Under it, its last lines on a rail, each cut to the width (as a log's lines), `empty` while there are none, and a `footer` closing them | `label`, `mark`, `mark-face`, `owner`, `sources`, `detail`, `right`, `right-face`, `lines`, `show`, `empty`, `footer` |
| `timeline` | Tasks as bars on a time axis (seconds or timestamps), running ones growing, coloured by status, with a scale under them. Times under 1.5 s are in milliseconds (`agent-ui-milliseconds-below`). SVG in the GUI | `tasks` |
| `graph` | Nodes and edges, laid out in layers by itself (no Graphviz). In the GUI, boxes and curved arrows, shrunk to fit; in a pane too narrow, laid out downwards, or as text. As text, each node lists its arrows. Nodes are coloured by status | `nodes`, `edges`, `direction` |
| `code` | A snippet highlighted by its language's mode (a major mode for code or text, never a minor one), its lines numbered (long ones wrapped) and linked to its file (`RET` opens it there). Marked lines have notes. Or a file's lines, read when drawn | `code`, `file`, `from`, `to`, `language`, `marks` |
| `heatmap` | A grid of cells coloured by value (a scale: blue, green-red, red-green) or by state (passed, failed, flaky...), with a legend. In the GUI, SVG cells with their values. Columns whose labels don't fit are numbered, with a key under the grid | `rows`, `columns`, `values`, `scale` |
| `panel` | Elements laid out together in a border: a row (side by side, by weights) or a column. Panels nest, and a row too narrow stacks. In the GUI, a row with a chart, graph or image is one image, its children side by side; their buttons aren't clickable there. Chips and pies, a line high, stay in its text. Each child is an element of its own: updated, appended to, removed, shown again, snapshot and linked by its id. Its id is unique in the canvas; a child without one gets its place's (`PANEL.1`...). Its source runs with it | `children`, `layout`, `weights`, `border`, `min-width` |
| `diff` | Changes from a unified diff, by file (lines added and removed) and hunk: coloured, with line numbers, long lines wrapped. `RET` opens the file there. A source with `"into": "diff"` follows `git diff`. With `accept`, they're changes the agent proposes ([Types that ask](#types-that-ask)) | `diff`, `dir`, `accept` |
| `html` | A web page as a card: its title and the start of its text. `RET` opens it in WebKit in a pane (`config/html.el`), else in the browser | `file` or `url`, `lines` |

### Types that ask

The agent asks with these, on a canvas of its own ([A question waiting](#a-question-waiting)). Your answer goes into the
session's prompt and is sent to the agent at once, as `Answer to TYPE ID (question): …`. Most then show the answer,
locked.

| Key | Action |
|---|---|
| `RET` or a click | Pick an option, a row, a chip or a file, or press a button (Answer, Send, All / None, a note) |
| `M-↑` / `M-↓` (`K` / `J`) | Move the rank's item at the cursor |
| `x` | Drop a plan's step (struck through), or reject a diff's hunk. Again: back |
| `e` | Reword a plan's step |
| `h` / `l` (or `←` / `→`) | On a slider's track: move the knob a step |
| `H` / `L` | On a slider's track: move the knob ten steps |
| A click on a slider's track | Put the knob there |
| `RET` (on a form) | Fill it in, in a buffer of its own |
| `TAB` (in a form's buffer) | Go to the next field |
| `C-c C-c` (in a form's buffer) | Send it |
| `C-c C-k` (in a form's buffer) | Cancel, keeping what you typed |

| Type | What | Properties |
|---|---|---|
| `choice` | A question with options to pick, one or several, and a note. Answer sends `Answer to choice ID (question): …`, then it shows the answer | `question`, `options`, `multiple`, `note`, `selected` |
| `compare` | Alternatives side by side for you to pick the better: code versions, texts, approaches, diffs. Each option is an element in its column, under its mark, stacked when narrow (images too, in the GUI). A note. Answer sends `Answer to compare ID (question): B. Note: …` | `question`, `options` (`label`, `element`), `multiple`, `note` |
| `confirm` | A yes / no gate before something risky (deploying, deleting, pushing): its question and what will happen, as lines or a diff. High danger is in red. Proceed or Cancel sends `Answer to confirm ID (question): proceed` (or cancel), then it shows the answer. At high danger, Proceed asks you to type a word first (the branch's name; `yes`), and refuses another | `question`, `details`, `diff`, `danger`, `word`, `proceed`, `cancel` |
| `form` | Several fields you answer together, such as a new ticket's details: text, a number within a range, yes / no, one of its options, a file. On the canvas, its fields and values (long ones wrapped) and Fill in. Its buffer opens in a new pane, laid out for its width, with vui.el's fields, checked as you type. Sending it sends `Answer to form ID (question): {JSON of the values}`, then it shows the values | `question`, `fields` (`name`, `label`, `type`, `required`, `min`, `max`, `options`, `placeholder`, `value`) |
| `rank` | Items you put in order (priorities, the order to do things in), numbered, and a note. Answer sends `Answer to rank ID (question): in this order: C, A, B`, then it shows the order | `question`, `items`, `note` |
| `slider` | A number you tune in a range (a threshold, a timeout): its track, with the knob at its value. Set sends `Answer to slider ID (label): 42 ms`. With `live`, each value is sent once the knob rests, and there's no Set | `label`, `min`, `max`, `step`, `unit`, `value`, `live` |
| `todo` | A checklist you and the agent both tick. The agent ticks items by appending them, by label. You tick them (`RET`, a click) and add some (Add). Who did it shows after an item. Send your changes sends `Changes to todo ID by the user: done: …; not done: …; added: …`. It goes on after, never locked | `items` |
| `steps` with `approve` | A plan you approve first, its steps whole (a long one wrapped, not cut) and in the text's colour. `x` on any line of a step drops it, `e` rewords it, and you can add a note. Approve sends `Answer to steps ID (question): approved: 1. A; 2. B (edited, was: X). Dropped: C`, and the steps become that plan; then it goes, as every answered question does. Reject says so, with a note | `steps`, `approve` |
| `diff` with `accept` | Changes the agent proposes, each hunk accepted to begin with. `x` on a hunk (or `RET` on its mark) rejects it; again, takes it back. Accept all / Reject all. Send sends `Answer to diff ID (question): accepted: FILE @@ … @@; rejected: …`, with your comments | `diff`, `dir`, `accept` |
| `table`, `files`, `tags` with `select` | You pick rows, files or chips: marks, `RET` or a click, All / None, a note. A folder's mark picks its files, and a picked chip is filled. Send sends `Answer to ID (question): …` with the picked rows' keys, or the chips' labels | `select` |

## Examples

**A build.** Its bar moves as the agent learns more.

```sh
agent-ui show '{"id":"build","type":"progress","title":"Build","max":12}'
agent-ui update build '{"value":7,"label":"linking"}'
agent-ui update build '{"value":12,"status":"done","label":"done in 41s"}'
```

```text
Build
███████████████░░░░░░░░░░░  7/12  58%  linking
```

**Work items.** Bugs fixed one by one, minutes apart, the bar updated after each.

```sh
agent-ui show '{"id":"bugs","type":"progress","title":"Bug fixing","max":58,"unit":"bugs"}'
agent-ui update bugs '{"value":12,"label":"tiling: SPC w SPC"}'
```

```text
Bug fixing
████████▎░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  12/58 bugs  20%  tiling: SPC w SPC
1h 51m elapsed · ~9 min a bug (last 8) · ~6h 50m left, about 01:40
```

**Tests as they run.** One row per test, changing state by its key.

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

**A chart.** As text in a terminal, and as SVG in the GUI.

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

The agent's tool calls run one after another, so a bar it updates itself stands still while it waits on a long command.
An element's `source` has Emacs follow what changes instead.

| Source | What |
|---|---|
| `{"command": "make -j8"}` | A command Emacs runs, in the agent's directory (or `dir`). Its output is kept in a log the reply names. When it ends, its `done` or `failed` patch applies (`$code` is its exit code), or a progress bar's own if there's none |
| `{"file": "build.log", "from": "end"}` | A file followed as it grows. It's read from its start by default, and from its start again when it's written again |
| `{"poll": "df -h /", "every": 10}` | A command run every so many seconds |

Rules turn the source's lines into changes:

- Each line that matches a rule's `match` applies its `set` (an update) and its `append`. `match` is a regular
  expression as in `grep -E`.
- `"$1"` is a group's value, a number if it reads as one. `$N` inside text is replaced.
- `\r` ends a line too, as progress meters use it.
- `tail: N` sets a text element to the last N lines.
- A chunk of output is one update, however many lines it has.

```json
{"id": "build", "type": "progress", "title": "Build", "max": 1,
 "source": {"command": "ninja -C build", "match": "^\\[(\\d+)/(\\d+)\\] (.*)$",
            "set": {"value": "$1", "max": "$2", "label": "$3"}}}
```

- `agent-ui list` gives each source's state: running, its exit code, how many lines, its log. It also gives the error of
  a change the element refused, or why the source couldn't run. When its `dir` is missing, the element is shown without
  it, and `show`'s reply says so.
- A source stops when its element is removed or shown again, or its canvas is closed. Its log is deleted then.
- An update can't change a source; showing the element again does.

## MCP

Each agent-shell session also gets the operations as MCP tools, with their schemas: `show`, `update`, `append`,
`remove`, `clear`, `list`, `get`, `types`, `render`, `snapshot`, `batch`, `define`, `bug`, `panels`, `open` and `check`.
`show`'s description lists the types.

- The server is `cmd/agent-ui-mcp.el`, run by a batch Emacs (this Emacs's binary) that the agent starts. It's in
  `agent-shell-mcp-servers`, with the session's name and directory.
- Each call goes through `cmd/agent-ui`, so replies and errors are the command line's.
- What the session is told says the tools are there.

| Setting | Default | What |
|---|---|---|
| `+my/agent-ui-mcp` | `t` | Agent UI's MCP tools in each session. `(setq +my/agent-ui-mcp nil)` in `config.el` turns them off |

## Actions

Any element can have `actions`: buttons under it. Each has a `label` and the `prompt` it puts into the session's prompt
when pressed, for you to read and send.

| Key | Action |
|---|---|
| `RET` or a click (on a button) | Put its prompt into the session's prompt, or send it at once (`"submit": true`) |

- With `"submit": true`, the prompt is sent at once.
- A question's buttons (a choice's, compare's or rank's) sit beside its Answer, on its row, until it's answered.
- Hovering a button shows the prompt it puts there or sends. One with a `help` shows that instead (`RET: HELP`). That's
  for a canvas's own button, one its Lisp handles itself (`agent-ui-answer-function`), such as a run pane's Worktree,
  *open its worktree*.
- An element has at most 6, checked when it's shown.
- While the agent works, a prompt sent at once is queued until it's done. A prompt put into the prompt is offered to
  queue, and you can change it first.
- A snapshot leaves the buttons out; they stay on the canvas.

```json
{"id": "result", "type": "text", "text": "2 tests failed.", "face": "error",
 "actions": [{"label": "Fix them", "prompt": "Fix the 2 failing tests."},
             {"label": "Show the log", "prompt": "Show me the test log.", "submit": true}]}
```

```text
2 tests failed.
⏵ Fix them   ⏵ Show the log
```

## A question waiting

The agent asks on a canvas of its own, `--canvas ask` (`Agent UI: SESSION / ask`), a view in the session's pane. A
question takes the focus when it shows, and goes once you answer it.

| Key | Action |
|---|---|
| `C-c C-q` (`SPC m q`) in a session | Go to its question waiting: its view selected, the cursor on it |
| `M-x agent-ui-goto-question` | The same, from anywhere: in a canvas, its session's question; elsewhere, any session's |

- **Shown, it takes the focus:** its view is selected, with the cursor on the question, once you stop typing for a
  moment (1 second). So what you type in the session isn't taken by the canvas's keys. A resumed session's questions,
  coming back, don't take it.
- **Answered, it goes:** your answer goes straight to the agent, sent at once. There's no Enter to press, and no
  question waits in the prompt. While the agent still works (its sub-agents too), the answer is queued and sent once
  it's done.
- Once answered, the question leaves its canvas, with the elements shown with it (their `with` is its id). On the
  session's ask canvas, once no other question waits there, everything on it goes. Other elements stay.
- A canvas left empty is closed and its buffer killed, and the cursor goes back to the session.
- A plan you approved goes too. The agent shows its steps again as an ordinary checklist, ticked as it works.

If the agent's turn ends while a question on its session's canvases is still unanswered, you see it. A question is a
`choice`, a `confirm`, a `form`, a `rank`, a `slider` to set, a `compare`, a plan to approve, hunks to accept, rows to
pick in a `table` or `files`, chips to pick in `tags`, or any of them as a panel's child.

- The canvas's view is shown (if it was closed) and scrolled to the question, the cursor on it. The focus stays where it
  is.
- The session's mode line says `❓ question waiting` until it's answered, or its canvas is closed.
- A notification says so while Emacs isn't in front, instead of "finished" (`agent-ui-question` in `SPC t N`).
- Each question is brought up once, at the end of the first turn it's waiting at, not at every one after.

| Setting | Default | What |
|---|---|---|
| `agent-ui-focus-questions` | `t` | A question shown takes the focus. `nil`: the focus stays where it is |
| `agent-ui-focus-questions-delay` | `1.0` | Seconds without typing before it does |
| `agent-ui-close-answered` | `t` | An answered question leaves its canvas. `nil`: it stays there |

## Bugs in Agent UI

When Agent UI itself misbehaves (an element drawn wrong, an error, a property it lacks), it's filed into Agent UI's own
issues, never the project's. That's this config's Beads (`.beads/`), from the session you're in, whatever its project,
as a bug labelled `agent-ui`. Nothing is pushed anywhere.

| Key | Action |
|---|---|
| `b` (on an element in its canvas) | File a bug about it: what's wrong, what you expected |
| `M-x agent-ui-report-bug` | The same, from anywhere |
| `cmd/agent-ui bug JSON` | The agent files one (the MCP tool `bug`) |

- **The agent's report** has a `title`, `description`, `expected`, `workaround`, `element` (the id of the one showing
  it) and `repro` (an element showing it with neutral data). The agent is told to ask you first, then carry on with a
  workaround.
- **The issue** carries the element as shown (its JSON, its drawing, its error), the repro drawn as text, and the
  environment: GUI or terminal, the pane's width, Emacs's version, Agent UI's commit, the session.
- **A similar bug** already open (most of its title's words) gets the report as a note instead. `"new": true` files it
  anyway.
- **Filed,** it shows a message (`RET` right after it opens the issue), and a notification while Emacs isn't in front
  (`agent-ui-bug` in `SPC t N`).
- **Not filed** (no `.beads` there, no `bd`, or `bd` failing): nothing is filed, and the report comes back written. The
  agent gets it in its reply (`{"ok": false, "error": ..., "report": ...}`), for you to file by hand. You get it in a
  buffer, also copied. `agent-ui-bug-report-url` names where to report it then (none yet).

## Kept with the session

A session's canvas is saved as it changes, and comes back when the session is resumed.

| Key | Action |
|---|---|
| `SPC o c` | Start a session, or resume one (it asks): its canvas comes back as it was |

- It's saved a moment after it changes, the changes together, as its elements' JSON. It's kept in the session's
  `.agent-shell/agent-ui/`, named by its ACP session id, beside agent-shell's transcripts.
- When a session starts with that id (resumed: picked when `SPC o c` asks, or agent-shell's restart), its canvas comes
  back as it was, a progress bar's times too.
- Its elements' sources aren't started again, so a command isn't run twice.
- Closing a canvas, or its session, leaves what's saved. Clearing it saves it empty.
- Its other canvases are kept beside it (`ID@tests.json`, the name hex-escaped) and come back with it.

## Project panels

A project panel is a dashboard kept in a project's repository, and opened again later: after its buffer is closed, after
Emacs restarts. Its data is fetched afresh each time, and none of it is kept, unlike a session's canvas.

![A project panel: this Mac's CPU, every second](../examples/panel.png)

| Key | Action |
|---|---|
| `SPC o u` | Open one of the current project's panels, in a pane of its own (`M-x agent-ui-open-panel`) |
| `SPC o U` | The same, in the window you're in (`M-x agent-ui-open-panel-here`) |
| `gR` (in it) | Read its file again and run it anew |
| `SPC m e` (in it), or its notice's **Export PDF** | Save it as a PDF, as it shows now, beside its file |
| `S` (on a canvas) | Save the element at point as one of the project's panels |
| `q` (in it) | Close it |
| `M-x agent-ui-panel-forget-project` | Stop trusting one of the projects you trusted |
| `M-x +my/example-panel` | Try it: this config's `cpu` panel, in a project of its own |

- This config has two of its own in `.agent-ui/panels/`, on macOS and Linux, each filled every second. `cpu` (above)
  shows how busy the CPU is, its load, its last minute and the processes using it most. `memory` shows where the memory
  goes, its pressure and the processes holding the most.
- `SPC o u` lists the current project's panels. The one you pick opens in a canvas of its own,
  `Agent UI: NAME (PROJECT)`, in its own pane. Its directory is the project's root, and it belongs to no session. If
  it's open already, its pane is shown.
- `q` closes it and kills its buffer. Opened again later, after a restart too, it's read anew and drawn empty, and its
  code fills it.
- A notice at its top offers its PDF. **Export PDF** saves the panel as it shows now, in your theme's colours, as a
  one-page PDF beside its file: `.agent-ui/panels/NAME-DATE-TIME.pdf`. The echo area says where. It needs
  `rsvg-convert`, which `scripts/tools.sh` installs.

### Its file

Each panel is a file, `PROJECT/.agent-ui/panels/NAME.el`, committed with the project. It holds one form: what the panel
shows and the code that fills it, so its elements' ids are written and used in one place.

```elisp
;;; service.el --- Agent UI panel: the service -*- lexical-binding: t; -*-
(agent-ui-panel
 :version 1
 :ui (:type "panel" :id "service" :title "Service" :layout "row"
      :children ((:type "table" :id "ci" :title "CI" :columns ("Run" "Status"))
                 (:type "gauge" :id "dirty" :title "Unsaved buffers" :value 0 :max 20)))
 :every 30
 :fetch (lambda (panel) ...))
```

| Key | What |
|---|---|
| `:ui` | What it shows: an element as `show` takes it (as a plist), its data left out. It's read as data, never evaluated, so it's drawn before its code is trusted |
| `:every` | The seconds between fetches |
| `:fetch` | Fills it |
| `:start`, `:stop` | Run when it opens and when it closes |
| `:version` | `1` |

- `agent-ui check NAME` (the MCP tool `check`) checks a file as it's written, and runs nothing. It checks its `:ui` as
  `show` would, compiles its code (reporting its warnings), and finds the calls in it that wait, freezing Emacs
  (`shell-command-to-string`, `call-process`, `sleep-for`...).
- Compiling runs its macros (`eval-when-compile` too), so code you haven't let run isn't compiled; the reply says so.

### Its code

A panel's code runs as Emacs itself, and comes from a repository. So before it first runs, you're asked:

| Key | Action |
|---|---|
| `y` | Run it |
| `p` | Trust the project |
| `v` | View its file first, read-only, then be asked again |
| `n` | Not now: it's drawn and nothing runs, and it says so (`gR` asks again) |

- Its elements' `source`s are commands, so they count as its code too. They don't start before it may run.
- A yes is remembered by the file's content (sha256) and where it is, in Doom's `.local/etc/agent-ui/trusted-panels.eld`
  (`agent-ui-panel-trust-file`), not in the repository. The same file isn't asked about again, after a restart too.
- Once the file changes (a pull, an edit), you're asked again. The same file in another repository (a clone, a fork) is
  asked about there, since its scripts aren't the ones you let run.
- A trusted project's panels all run without asking, whatever their files become (while your agent builds one, say). The
  project's code is trusted, and so are the scripts they run. `M-x agent-ui-panel-forget-project` lists the trusted
  projects and stops trusting one.
- Then `:start` runs, `:fetch` runs at once and every `:every` seconds, and `:stop` runs when it closes. Each is called
  with the panel, in the project's root.
- It fills the panel with `agent-ui-panel-update` and `agent-ui-panel-append` (as `agent-ui update` and `append`, on its
  own elements), and `agent-ui-panel-get`.
- `agent-ui-panel-run` runs a command without waiting, however long it takes (a database's query: minutes). Its output
  goes to a function once it ends well, parsed when it reads as JSON. It's killed when the panel closes, or after its
  `:timeout`.
- An error in one of them is kept, and said in `*Messages*`. The others go on.

### While it's open

- While it's hidden (another tab in its pane, another workspace), it isn't fetched. Shown again, it's fetched at once.
- Its queries each load on their own. A query given the `:element` it fills has that element's title say it's loading,
  and for how long (`⟳ loading, 1m 12s`), while its last data stays. On a refresh, that waits until the query has taken
  half a second, so a quick one doesn't flicker. A failure is said there too.
- A query still running isn't started again. The others go on at their pace; a slow one never holds them up.
- Anything else that goes wrong is said on the panel, a line in the error face under it, until it goes well. So is a
  fetch that itself takes long (over 0.1 s), freezing Emacs meanwhile.
- `gR` reads its file again (edited) and runs it anew. If the file is wrong, it's said there, and the panel goes on as
  it was.

| Setting | Default | What |
|---|---|---|
| `agent-ui-panel-loading-delay` | `0.5` | Seconds a refreshing query runs before its element says it's loading |
| `agent-ui-panel-slow` | `0.1` | Seconds a fetch may take itself before it's said to be slow |
| `agent-ui-panel-trust-file` | `.local/etc/agent-ui/trusted-panels.eld` | Where the panels you let run are remembered |

### From the agent

- The agent lists the panels (`agent-ui panels`), opens one for you (`agent-ui open NAME`), and works on an open one
  with `--panel NAME` on any operation. With MCP, that's the tools `panels` and `open`, and the `panel` argument.
- `agent-ui open NAME` shows its pane without selecting it. If its code must be asked about, you're asked then.
- A panel's buttons put their prompt into the project's agent session, the latest one working in it.
- `S` on a canvas saves the element at point as one of the project's panels. Its file, `.agent-ui/panels/NAME.el`, is
  written with the element as it was first shown, before its updates and its sources' changes, so with no data. Its
  `:fetch` is empty, for you to write. It's trusted, since you made it.

## In the conversation

agent-shell owns its buffer's text, so an element isn't put there. It goes there in the ways agent-shell already has.

| Key | Action |
|---|---|
| `a` (on an element in a canvas) | Put it into its session's prompt, as text |
| `cmd/agent-ui snapshot ID` | The agent saves the element as an image, for its reply |

- **From the agent:** `agent-ui snapshot ID` saves the element as it's drawn, without its buttons, as an SVG in the
  session's `.agent-shell/images/`, and replies with a Markdown image link. In the agent's reply, agent-shell shows the
  image inline, and the transcript keeps it.
- The SVG keeps the text in its faces' colours, each word at its column. A bar's blocks are rectangles. Borders'
  box-drawing characters are lines through their cells, meeting from line to line. A chart's own SVG is nested in it.
- **From you:** `a` puts the element into the prompt as text: its id, its type, and its drawing in a code block.
- **Links:** `show`'s reply has the element's link, `agent-ui://canvas/NAME#ID`. In the agent's reply, as a Markdown
  link, agent-shell draws it. A click on it brings up the canvas's pane, selected, with the cursor on the element.

## Types the agent makes

When none of the types fits, the agent writes one: an Emacs Lisp file with one `agent-ui-define` and the definitions it
uses, each named after it (`agent-ui-NAME-...`). There's nothing else in it: no `setq`, nothing run at load, and
`require` of a few built-in libraries only. `agent-ui define FILE` stages it:

1. **Checked:** its forms are read. It must hold one type, its definitions named after it, and not a type already there
   (built in or kept).
2. **Compiled** by the byte compiler, with nothing written. Errors refuse it; warnings go back to the agent, by line.
3. **Loaded,** and **its example drawn.** The reply has that drawing as text (`preview`), so the agent sees what it
   made. An example that doesn't draw refuses it.

A refused type leaves nothing behind; a staged type it was replacing is back. A staged type is usable at once. A message
says the agent made one, and each canvas's header lists the types waiting.

| Key | Action |
|---|---|
| `R` (in a canvas) | List the types waiting for your review (`M-x agent-ui-review`) |
| `RET` | Its preview: what it is, its properties, its example drawn (as SVG if it has a GUI drawing), its code |
| `a` | Keep it: its file moves to `config/agent-ui/kept/` (in this config, in git) and loads at each start. An issue is filed in this config's Beads issues for its tests and documentation |
| `x` | Discard it: its file is deleted, and its elements are removed from the canvases |
| `v` | Its code, read-only |
| `q` | Close the list |

- Staged types wait in Doom's cache (`agent-ui/staged/`). After a restart they aren't loaded again, but stay listed for
  the review, which loads one to preview it.
- Kept types are part of the library like the others. The tests expect each type to have its tests and its section in
  the skill, which the filed issue is for.

## What the agent is told

While Emacs runs a server, what every session is told (its system prompt, or before its first message) has a paragraph
on Agent UI, in three parts:

- **What to show:** the canvas is where information goes. Whatever has a shape (figures, records, a comparison, a trend,
  a structure, steps, changes, output) goes there as the element that fits it. The reply keeps the words: what was
  found, what it means, what's next, and a line saying what's on the canvas. What a sentence or two holds stays in the
  reply alone.
  - Kinds of information are matched to elements: figures `stats` (one against a target `gauge`), records `table`, a
    trend or distribution `chart`, two dimensions `heatmap`, a structure or flow `graph` or `mermaid`, durations
    `timeline`, code `code`, changes `diff`, files `files`, output `log`, what one thing is doing now `activity`,
    categories `tags`, formulas `math`, a write-up `markdown`, a picture `image`, a page `html`, several together
    `panel`.
  - Plans go there without being asked: a plan or the current ticket's acceptance criteria as `steps`, a long run of
    work items as `progress`, updated after each one. A project's issues and their status don't, since you follow them
    in Beads' own list ([Issues](issues.md)).
  - This comes before what agent-shell's text says of tables, images and diagrams in replies: those are for when the
    canvas can't be used.
- **Asking:** a question goes on a canvas of its own (`--canvas ask`), as the interactive element that fits it. A list
  to pick from is a `choice` (or `select` on a table, files), alternatives to see a `compare`, something risky a
  `confirm`, a plan to agree on `steps` with `approve`, proposed changes a `diff` with `accept`, several values a
  `form`, an order a `rank`, a number a `slider`. Then the turn ends, and the answer is its next prompt.
  - Only a quick question (2 to 4 short options, nothing to show or compare) goes in the conversation, as
    AskUserQuestion (Claude Code's; another agent uses its own tool, if any), with agent-shell's forms on.
- **The command:** its full path with an example, and to read the skill before using it the first time. When Agent UI
  itself misbehaves, the agent is told to ask you and file it with `agent-ui bug`
  ([Bugs in Agent UI](#bugs-in-agent-ui)).

The MCP server's instructions, given to the agent too, say the same: information on the canvas, questions there beyond a
quick one, and its `bug` tool.

The skill, [skills/agent-ui/SKILL.md](../skills/agent-ui/SKILL.md), is read in parts, as the agent needs them:

- `SKILL.md`, read first, says when to use the canvas (information, plans, questions), the command, every type in a line
  by what it shows, and the everyday ones (`progress`, `steps`, `table`) with examples.
- Its `references/` hold the rest, each read only when a task needs it: asking you (`asking.md`), figures (`data.md`),
  content and layout (`content.md`), following a command (`sources.md`), a type of its own (`custom-types.md`), project
  panels (`panels.md`), a bug in Agent UI (`bugs.md`).
- A type's every property comes from `agent-ui types TYPE`.
- It's read from there, with nothing to install. Like other skills, it can be installed too ([AI agents](ai-agents.md)).
- Tests run each of its examples, so they stay right as the types change, and keep `SKILL.md` under 12 KB.

## Files

| Path | What |
|---|---|
| `config/agent-ui.el` | Settings and keys; loads `config/agent-ui/` |
| `config/agent-ui/core.el` | The registry, `agent-ui-define`, checking specs, errors contained |
| `config/agent-ui/canvas.el` | The canvas: its buffer, elements, redraws, sections |
| `config/agent-ui/request.el` | The command line's way in, finding the canvas |
| `config/agent-ui/agent.el` | agent-shell's sessions, a question waiting |
| `config/agent-ui/pane.el` | A session's canvases in its session's pane |
| `config/agent-ui/persist.el` | Kept with the session |
| `config/agent-ui/ask.el` | What the types that ask share: picking, a note, the answer |
| `config/agent-ui/finished.el` | A finished element closing itself |
| `config/agent-ui/source.el` | Sources: a command, a file, a poll |
| `config/agent-ui/panels.el` | Project panels |
| `config/agent-ui/snapshot.el` | In the conversation: snapshots, an element into the prompt |
| `config/agent-ui/bug.el` | Bugs in Agent UI |
| `config/agent-ui/staging.el`, `review.el` | Types the agent makes: staged, reviewed, kept or discarded |
| `config/agent-ui/kept/` | The types you kept (made when you keep one) |
| `config/agent-ui/elements.el`, `elements/` | The element types, a file each (`math`'s MathJax script in `elements/math/tex2svg.js`) |
| `cmd/agent-ui` | The command line |
| `cmd/agent-ui-mcp.el` | The MCP server: the same operations as tools |
| `examples/agent-ui.el` | The example: a session with its Agent UI, filled in as the agent works |
| `skills/agent-ui/SKILL.md`, `references/` | The skill, for the agent: the core read first, the rest when needed |

None of `config/agent-ui/` uses Doom. Only `config/agent-ui.el` does (its settings, keys, and the Beads issue for a kept
type), so the rest can become a package of its own.
