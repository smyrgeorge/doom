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

## Its code

Before its code first runs, the user is asked to let it (it runs as Emacs itself; its elements' `source`s are its
code too: not started before), and again after each change to its file: after you edit it, they're asked once more,
unless they trusted the whole project (its panels then run, whatever they become). Then `:start`, `:fetch` at once
and every `:every` seconds, `:stop` when it closes: each
called with `panel`, in the project's root (`default-directory`). An error in one is kept and said; the others go on.
Its code fills it with:

- `(agent-ui-panel-update panel ID :prop value ...)`: as `agent-ui update` (a value nil: back to its default).
- `(agent-ui-panel-append panel ID :rows rows)`: as `agent-ui append` (a table's rows by key, a chart's values).
- `(agent-ui-panel-get panel ID)`: the element's properties now.
- `(agent-ui-panel-run panel COMMAND (lambda (output) ...) :element ID :timeout SECONDS)`: COMMAND (a list, or a
  string for the shell) run in the root, **without waiting**, however long it takes (a database's query: minutes);
  the function called with its output once it ends well: parsed JSON when it reads so (objects as alists,
  `(alist-get 'name r)`; arrays as lists), else its text. Any command, any language: a script of the project's too.
  Killed when the panel closes; with `:timeout`, after so many seconds.

**Each query on its own.** Give each `agent-ui-panel-run` the `:element` it fills: while it runs, that element's
title says it's loading and for how long (`⟳ loading, 1m 12s`; a refresh, once it's taken half a second), its last
data still shown; its failure (its exit, what it said; a timeout) is said on its title, until it goes well. A query
still running isn't started again by the next fetch; the others are, each at its own pace: a slow one never holds the
others. Several queries in one panel: one `agent-ui-panel-run` each, in the same `:fetch`. Without `:element`, its
failure is said under the panel.

It's fetched only while it's shown (hidden, it waits; shown again, it's fetched at once). After you edit its file,
the user presses `gR` on it to read it again.

Its code never waits (Emacs is frozen meanwhile, every `:every` seconds; a fetch over 0.1 s itself is said on it): no `shell-command-to-string`,
`call-process`, `process-lines`, `url-retrieve-synchronously`, `sleep-for`. Emacs's own state it reads at once (its
buffers, `project-current`, `vc`, flymake's diagnostics). Define nothing global: its helpers go inside the form
(`cl-labels`).

```elisp
 :every 30
 :fetch (lambda (panel)
          (agent-ui-panel-run panel '("gh" "run" "list" "-L" "5" "--json" "number,conclusion")
            (lambda (runs)
              (agent-ui-panel-update panel "ci"
                :rows (mapcar (lambda (r) (list (format "#%s" (alist-get 'number r))
                                                (or (alist-get 'conclusion r) "running")))
                              runs))))
          (agent-ui-panel-update panel "dirty"
            :value (length (seq-filter #'buffer-modified-p (project-buffers (project-current))))))
```

## Opening it, working on it

`agent-ui panels` lists the project's panels (and which are open); `agent-ui open NAME` opens one in the user's Emacs,
in its own pane (the MCP tools `panels` and `open`). Its reply's `trusted` false: the user is being asked to let its
code run. `--panel NAME` (the tools' `panel`) makes any operation work on an open panel: `agent-ui list --panel
service`, `agent-ui get --panel service`. Its elements' buttons (`actions`) put their prompt into the
project's agent session, the latest. The user can also save an element of a canvas as a panel (`S`): its file
written with the element as it was first shown and an empty `:fetch`, for you to fill in.

## Reading it

To know what a panel shows, read its data: `agent-ui get --panel NAME` (the MCP tool `get` with its `panel`), every
element with its properties and values as JSON, or one (`agent-ui get ID --panel NAME`). Never take a snapshot of it
to look at it: that's a picture, for the conversation. `--changed` gives only the elements changed since your last
read (and `removed`: those gone), for a panel you watch while you work. The reply says when it last fetched
(`fetched`, seconds ago). A panel the user isn't looking at fetches nothing; reading it fetches it first when its
data is older than its `:every`, and the command answers once its queries end (10 s at most:
`AGENT_UI_WAIT`). The same works on your canvas: `agent-ui get [ID]`.

## Checking it

`agent-ui check NAME` (the MCP tool `check`) checks the file as you write it, nothing shown, nothing run: its `:ui` as
`show` would, its code compiled. The reply has the compiler's `warnings`, and `blocking`: calls that wait
(`shell-command-to-string`, `call-process`, `process-lines`, `sleep-for`...), Emacs frozen while they run. Fix them
all; check again until both are empty. Compiling runs its macros: code the user hasn't let run yet isn't compiled,
the reply's `not-compiled` saying so (its `warnings` the compiler's once they have).
