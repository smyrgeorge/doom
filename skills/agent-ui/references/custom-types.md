# A type of your own

Part of the agent-ui skill: read [SKILL.md](../SKILL.md) first.

When none of the types fits (a dial, a calendar, a seating plan...), write one: an Emacs Lisp file with **one**
`agent-ui-define`, and the definitions it uses, **each named after it** (`agent-ui-NAME-...`), nothing else (no
`setq`, no code run at load; `require` only cl-lib, subr-x, seq, map, pcase, rx, svg). Then `agent-ui define FILE`.
It's checked, compiled, loaded, and its `:example` drawn: the reply has that drawing (`preview`) and the compiler's
`warnings`. Fix and define it again until it's right; it's usable at once. The user then keeps it (loaded at each
start) or discards it (its elements go with it): say what you made and why.

```elisp
;;; dial.el --- Agent UI type dial -*- lexical-binding: t; -*-

(defun agent-ui-dial--text (props ctx)
  "PROPS drawn in CTX's width: [#####.....] 50% LABEL."
  (let* ((value (plist-get props :value))
         (cells (min 20 (max 5 (- (plist-get ctx :width) 30))))
         (full (round (* cells (/ value 100.0)))))
    (concat "[" (propertize (make-string full ?#) 'face 'agent-ui-accent)
            (make-string (- cells full) ?.) "] "
            (format "%d%%" value)
            (if-let* ((label (plist-get props :label))) (concat "  " label) ""))))

(agent-ui-define dial
  "A dial: VALUE percent, with a LABEL."
  :props ((value integer "Percent, 0 to 100" :default 0)
          (label string "What it measures"))
  :example (:value 42 :label "disk")
  :check (lambda (props)
           (unless (<= 0 (plist-get props :value) 100)
             (agent-ui--fail "dial: value must be from 0 to 100"))
           props)
  :text #'agent-ui-dial--text)
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
- Helpers: `agent-ui-pad`, `agent-ui-truncate`, `agent-ui-wrap`, `agent-ui-wrap-hanging` (a list item's or an indented
  line's rest under its text), `agent-ui-format-number`, `agent-ui-spinner`,
  `(agent-ui-button-row BUTTONS WIDTH)` (buttons on a line, broken between them to the width: never one line wider);
  badges: `(agent-ui-pill LABEL CTX :face F :filled t :count N)` a rounded tag, `(agent-ui-pie FRACTION CTX FACE)` a
  pie (their text in a terminal, an SVG over it in the GUI). For a type
  that asks the user (picks, a note, an answer into your prompt): `agent-ui-ask-pick-button`, `agent-ui-ask-mark`,
  `agent-ui-ask-all-none`, `agent-ui-ask-note-button`, `agent-ui-ask-answer-button`, `agent-ui-ask-answered-line`,
  its state in the element's `selected`, `note-text`, `answered` (see docs/agent-ui.md).
