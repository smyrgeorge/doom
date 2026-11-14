;;; $DOOMDIR/config/tiling/tall.el -*- lexical-binding: t; -*-
;; The tall strategy: the main pane on the left, the others stacked on the
;; right (config/tiling/stack.el). Loaded from config/tiling.el.

(defconst +my/tiling--tall
  '(:main left :ratio +my/tiling-tall-ratio :limits +my/tiling-tall-ratio-limits)
  "Tall's layout (config/tiling/stack.el).")

(defun +my/tiling--tall-p (root)
  "Non-nil if the panes under ROOT are laid out tall: one pane, or a pane on
the left of one column of panes."
  (+my/tiling--stack-p +my/tiling--tall root))

(defun +my/tiling-tall-arrange (panes)
  "Lay PANES out tall: the first one on the left, the others stacked on the
right at equal heights (but a pane resized); each shows what it showed, the
selected one stays so."
  (+my/tiling--stack-arrange +my/tiling--tall panes))

(defun +my/tiling-tall-fits-p (count)
  "Non-nil if COUNT panes fit laid out tall (config/tiling/stack.el)."
  (+my/tiling--stack-fits-p +my/tiling--tall (window-main-window) count))

(defun +my/tiling-tall-split (panes)
  "Open a pane, tall (see config/tiling.el): on the right of the only one, else
at the bottom of the stack; PANES arranged tall first if need be. Return it."
  (+my/tiling--stack-split +my/tiling--tall panes))

(defun +my/tiling-tall-resize-main (panes direction)
  "The main pane wider (DIRECTION 1) or narrower (-1), PANES arranged tall
first if need be; `+my/tiling-tall-ratio' kept. What to say."
  (+my/tiling--stack-resize-main +my/tiling--tall panes direction))

(defun +my/tiling-tall-resize-pane (panes pane direction)
  "PANE, one of the stack's, taller (DIRECTION 1) or shorter (-1), PANES
arranged tall first if need be. What to say."
  (+my/tiling--stack-resize-pane +my/tiling--tall panes pane direction))

(defun +my/tiling-tall-closed (panes)
  "A pane closed: the stack's panes at equal heights again (but one resized),
when PANES are laid out tall."
  (+my/tiling--stack-closed +my/tiling--tall panes))
