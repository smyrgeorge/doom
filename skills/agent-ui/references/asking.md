# Asking the user

Part of the agent-ui skill: read [SKILL.md](../SKILL.md) first. A type's every property: `agent-ui types TYPE`.

A question goes on a canvas of its own, `--canvas ask`: its pane takes the user's focus, and once they answer, the
question goes and the canvas closes. Show it, say in a line of your reply that it's there, and **end your turn**: the
user is brought to it (a notification if they're away), and the answer comes as your next prompt, "Answer to TYPE ID
(QUESTION): ...". Ask one question at a time, and wait for the answer. A small question (2 to 4 options, nothing to
show): AskUserQuestion, in the conversation, if you have it.

### `choice`

A question for the user, when you need a decision: which approach, approve a plan. `options` are labels, or
`{"label", "detail"}`; one to pick, or several with `"multiple": true`; `"note": true` lets them add a note. They pick
(`RET`, a click) and press Answer: "Answer to choice ID (QUESTION): A, B. Note: ..." comes into your prompt (sent at
once with `"submit": true`). Then it shows the answer. Ask one question at a time, and wait for the answer.

```sh
agent-ui show --canvas ask '{"id":"fix","type":"choice","question":"The checker test expects the old message. Which fix?","options":[{"label":"Change the test","detail":"keeps the new message"},{"label":"Revert the message","detail":"as before"}],"note":true}'
```

### `compare`

When the options need showing, not naming ("which of these do you prefer?"): 2 to 4 `options`, each `{"label",
"element"}`, the element any type (code, markdown, a diff, text) drawn in its column, side by side (stacked when the
pane is narrow). The user picks one (`"multiple": true`: several) and says why: "Answer to compare ID (QUESTION): B.
Note: ..." comes into your prompt. Show it, say so in a line, end your turn.

```sh
agent-ui show --canvas ask '{"id":"ways","type":"compare","question":"Which version reads better?","options":[{"label":"A: a loop","element":{"type":"code","language":"python","code":"total = 0\nfor x in xs:\n    total += x"}},{"label":"B: sum","element":{"type":"code","language":"python","code":"total = sum(xs)"}}]}'
```

### `confirm`

Before something risky or hard to undo (a force-push, a deploy, deleting data, a migration): ask for a yes or no.
`question`, `details` (what will happen, a few lines) or a `diff`; `"danger": "high"` draws it in red and has the
user type `word` (the branch's name; "yes" if none) before Proceed goes through. "Answer to confirm ID (QUESTION):
proceed" (or cancel) comes as your next prompt, at once. Show it, say so in a line, end your turn, and do the risky
thing only on proceed.

```sh
agent-ui show --canvas ask '{"id":"push","type":"confirm","question":"Force-push to origin/main?","details":["Rewrites the last 3 commits","Work others pushed to main may be lost"],"danger":"high","word":"main"}'
```

### `form`

Several answers you need together (a new ticket's title, priority and type; a release's version and date): `fields`,
each `{"name", "label", "type", "required", "min", "max", "options", "placeholder", "value"}`; type `text` (the
default), `integer` or `number` (`min`, `max`), `boolean`, `select` (one of its `options`), `file`, `directory`;
`value` a default. The user fills it in (in a buffer of its own, checked as they type) and sends it: `Answer to form
ID (QUESTION): {"title": ..., "priority": 2, ...}` comes into your prompt (JSON: an empty field null, a
boolean true or false). Show it, say so in a line, end your turn. A single question: a `choice`.

```sh
agent-ui show --canvas ask '{"id":"ticket","type":"form","title":"New ticket","question":"What should the ticket say?","fields":[{"name":"title","label":"Title","required":true},{"name":"priority","label":"Priority","type":"integer","min":0,"max":4,"value":2},{"name":"type","label":"Type","type":"select","options":["bug","task","feature"]}]}'
```

### `rank`

The user puts items in order (what to do first, which matters most): `items` (labels, or `{"label", "detail"}`) in
your order; `"note": true` lets them add a note. They move items and press Answer: "Answer to rank ID (QUESTION): in
this order: C, A, B. Note: ..." comes into your prompt (sent at once with `"submit": true`). Show it, say so in a
line, end your turn; then work in that order.

```sh
agent-ui show --canvas ask '{"id":"prio","type":"rank","question":"What should I do first?","items":[{"label":"Fix the parser","detail":"the root cause"},"Update the docs","Release"]}'
```

### `slider`

A number the user tunes in a range, when the right value is theirs to judge (a threshold, a timeout, how many to
take): `label`, `min`, `max`, `step` (default 1), `unit`, `value` (where it starts). They move it and press Set:
"Answer to slider ID (LABEL): 42 ms" comes into your prompt. With `"live": true`, no Set: each value comes, once the
knob rests, as "Slider ID (LABEL) set to 42 ms", for something you redraw from it (a chart's threshold).

```sh
agent-ui show --canvas ask '{"id":"timeout","type":"slider","label":"Timeout","min":0,"max":120,"step":5,"unit":"s","value":30}'
```

### `todo`

A checklist you and the user both work through: a plan you agree on, what's left before a release. `items` are labels,
or `{"label", "done"}`. Tick one by appending it (by its label: `"done": false` unticks it); a new label adds it. The
user ticks items too and adds some; when they press Send, "Changes to todo ID by the user: done: A; not done: B;
added: C." comes into your prompt (sent at once with `"submit": true`): take it into account (an added item is
theirs to do with you). It's never locked. It stays on your own canvas.

```sh
agent-ui show '{"id":"plan","type":"todo","title":"The fix","items":["Reproduce the bug","Write a failing test","Fix the parser"]}'
agent-ui append plan '{"items":[{"label":"Reproduce the bug","done":true}]}'
```

## A plan to approve: `steps`

Before a larger change, show your plan as steps with `"approve": true` (or `{"question": ..., "submit": false}`) on
your own canvas, say so in a line, and end your turn. The user drops steps, rewords them, adds a note, then approves:
"Answer to steps ID (QUESTION): approved: 1. A; 2. B (edited, was: X). Dropped: C. Note: ..." comes as your next
prompt (sent at once). Answered, the plan may close (as every question does). To work through it, show the approved
steps again as an ordinary checklist (`steps`, the same id, their names as approved, no `approve`; it replaces the
plan if it's still there) and tick them as you go. Or "...: rejected. Note: why": rethink, don't start. A plan's
steps are shown whole (a long one wraps), so say each in full.

```sh
agent-ui show '{"id":"plan","type":"steps","title":"The fix","approve":true,"steps":["Reproduce the bug","Fix the parser","Update the docs","Release"]}'
```

## Picking from what's shown: `select`

A `table`'s rows, `files`, an `issues` board's cards or `tags`' chips: give the element `select`, `{"question",
"multiple", "note", "submit"}` (`multiple` for several, `note` for a note, `submit` to send at once). Marks come before
them, the user picks (RET, a click, All, None) and presses Send: "Answer to ID (QUESTION): ..." comes as your next
prompt, naming a table's `key` cells (else its first column's), the files' paths, the issues' ids, the chips' labels.
Say so in a line and end your turn:

```sh
agent-ui show '{"id":"bugs","type":"table","columns":["ID","P","Bug"],"key":"ID","rows":[["doom-1ms","P2","Tabs: a new buffer loses its tab"],["doom-3z6","P2","Large Markdown freezes Emacs"]],"select":{"question":"Which should I fix?","multiple":true,"note":true,"submit":true}}'
agent-ui show --canvas ask '{"id":"apply","type":"tags","tags":["bug","docs","agent-ui"],"select":{"question":"Which labels should the new ticket get?","multiple":true}}'
```

A folder of `files` (with `"tree": true`) picks its files: `"select":{"question":"Which should I change?","multiple":true}`.

## Changes to accept: `diff`

To propose changes before making them, show them as a diff with `"accept": true` (or `{"question": ..., "submit":
false}`), say so in a line, and end your turn. The user accepts or rejects each hunk (and may comment on lines):
"Answer to diff ID (QUESTION): accepted: src/parser.c @@ -40,2 +40,2 @@; rejected: ... Review of ID: ..." comes as
your next prompt. Apply only the accepted hunks, and take the comments into account.

```sh
agent-ui show '{"id":"fix","type":"diff","title":"Proposed fix","accept":true,"diff":"--- a/src/parser.c\n+++ b/src/parser.c\n@@ -40,2 +40,2 @@\n   int depth = 0;\n-  return NULL;\n+  return parse_term(p);\n"}'
```
