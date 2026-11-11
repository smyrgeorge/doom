;;; $DOOMDIR/config/tiling/wide.el -*- lexical-binding: t; -*-
;; The wide strategy: the main pane on top, the others in a row below.
;; Loaded from config/tiling.el.

;; WIDE
;; Tall turned on its side (config/tiling/stack.el): the main pane on top, as
;; wide as the frame, its share of the height `+my/tiling-wide-ratio'; the
;; others side by side below it, left to right in the order opened, at equal
;; widths. Columns are narrow: a row fills up sooner than tall's stack (no
;; room: said).

(defconst +my/tiling--wide
  '(:main above :ratio +my/tiling-wide-ratio :limits +my/tiling-wide-ratio-limits)
  "Wide's layout (config/tiling/stack.el).")

(defun +my/tiling-wide-arrange (panes)
  "Lay PANES out wide: the first one on top, the others in a row below it at
equal widths (but a pane resized)."
  (+my/tiling--stack-arrange +my/tiling--wide panes))

(defun +my/tiling-wide-split (panes)
  "Open a pane, wide: below the only one, else at the right end of the row
below; PANES arranged wide first if need be. Return it."
  (+my/tiling--stack-split +my/tiling--wide panes))

(defun +my/tiling-wide-resize-main (panes direction)
  "The main pane taller (DIRECTION 1) or shorter (-1), PANES arranged wide
first if need be; `+my/tiling-wide-ratio' kept. What to say."
  (+my/tiling--stack-resize-main +my/tiling--wide panes direction))

(defun +my/tiling-wide-resize-pane (panes pane direction)
  "PANE, one of the row's, wider (DIRECTION 1) or narrower (-1), PANES
arranged wide first if need be. What to say."
  (+my/tiling--stack-resize-pane +my/tiling--wide panes pane direction))

(defun +my/tiling-wide-closed (panes)
  "A pane closed: the row's panes at equal widths again (but one resized),
when PANES are laid out wide."
  (+my/tiling--stack-closed +my/tiling--wide panes))
