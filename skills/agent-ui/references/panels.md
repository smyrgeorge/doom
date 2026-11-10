# Project panels

Part of the agent-ui skill: read [SKILL.md](../SKILL.md) first. A type's every property: `agent-ui types TYPE`.

A panel kept in a project's repository, to open again later (after its buffer is closed, after Emacs restarts): what
it shows and the code that fills it, in one file, `PROJECT/.agent-ui/panels/NAME.el`, committed with the project.
Nothing of its data is kept: each time it opens, its code fetches it afresh. For a dashboard the user wants for a
project (a service's CI and errors, a release's state), not for what you show while you work (that's your canvas).

## Its file

One form, `agent-ui-panel`:

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

- `:ui`: what it shows, an element as `show` takes it, written as a plist (`:type "table"`, lists in parentheses,
  `t` and `:false`), usually a `panel` of children. No data in it (empty rows, values at 0): its code fills it. Give
  every element its code changes an `id`. It's read as data, never evaluated: it's drawn even before the user trusts
  its code.
- `:every`: seconds between fetches (a number); none: fetched once, when it opens.
- `:fetch`: a function of the panel, filling it; `:start` and `:stop`: run when it opens and closes.
- `:version`: 1.

## Checking it

`agent-ui check NAME` (the MCP tool `check`) checks the file as you write it, nothing shown, nothing run: its `:ui` as
`show` would, its code compiled. The reply has the compiler's `warnings`, and `blocking`: calls that wait
(`shell-command-to-string`, `call-process`, `process-lines`, `sleep-for`...), Emacs frozen while they run. Fix them
all; check again until both are empty.
