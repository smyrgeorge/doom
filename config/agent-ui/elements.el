;;; $DOOMDIR/config/agent-ui/elements.el -*- lexical-binding: t; -*-
;; Agent UI's element types, a file each in config/agent-ui/elements/, each
;; defined with `agent-ui-define' (core.el). Loaded from config/agent-ui.el,
;; after core.el. No Doom here (see docs/agent-ui.md).

(load! "elements/text")
(load! "elements/markdown")
(load! "elements/progress")
(load! "elements/steps")
(load! "elements/table")
(load! "elements/chart")
(load! "elements/image")
(load! "elements/html")
(load! "elements/diff")
(load! "elements/choice")
(load! "elements/todo")
(load! "elements/confirm")
(load! "elements/form")
(load! "elements/rank")
(load! "elements/slider")
(load! "elements/tags")
(load! "elements/files")
(load! "elements/stats")
(load! "elements/log")
(load! "elements/timeline")
(load! "elements/graph")
(load! "elements/code")
(load! "elements/issues")
(load! "elements/heatmap")
(load! "elements/panel")
;; Its options are elements of the others, laid out as a panel's row: last.
(load! "elements/compare")
