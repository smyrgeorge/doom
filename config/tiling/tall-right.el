;;; $DOOMDIR/config/tiling/tall-right.el -*- lexical-binding: t; -*-
;; The tall-right strategy: the main pane on the right.
;; Loaded from config/tiling.el.

;; TALL-RIGHT
;; Tall with its sides swapped: the main pane on the right, the others stacked
;; on the left, top to bottom as tall's (config/tiling/stack.el). Its main
;; pane is the last on the screen: put first (:order) for SPC w RET and SPC w
;; a. Its share of the width is tall's (`+my/tiling-tall-ratio'): switching
;; between them keeps it.

(defconst +my/tiling--tall-right
  '(:main right :ratio +my/tiling-tall-ratio :limits +my/tiling-tall-ratio-limits)
  "Tall-right's layout (config/tiling/stack.el).")

(defun +my/tiling-tall-right-order (panes)
  "PANES, the main pane (on the right) first."
  (+my/tiling--stack-order +my/tiling--tall-right panes))

(defun +my/tiling-tall-right-arrange (panes)
  "Lay PANES out tall-right: the first one on the right, the others stacked
on the left at equal heights (but a pane resized)."
  (+my/tiling--stack-arrange +my/tiling--tall-right panes))

(defun +my/tiling-tall-right-fits-p (count)
  "Non-nil if COUNT panes fit laid out tall-right (config/tiling/stack.el)."
  (+my/tiling--stack-fits-p +my/tiling--tall-right (window-main-window) count))

(defun +my/tiling-tall-right-split (panes)
  "Open a pane, tall-right: on the left of the only one, else at the bottom
of the stack on the left; PANES arranged tall-right first if need be. Return
it."
  (+my/tiling--stack-split +my/tiling--tall-right panes))

(defun +my/tiling-tall-right-resize-main (panes direction)
  "The main pane wider (DIRECTION 1) or narrower (-1), PANES arranged
tall-right first if need be; `+my/tiling-tall-ratio' kept. What to say."
  (+my/tiling--stack-resize-main +my/tiling--tall-right panes direction))

(defun +my/tiling-tall-right-resize-pane (panes pane direction)
  "PANE, one of the stack's, taller (DIRECTION 1) or shorter (-1), PANES
arranged tall-right first if need be. What to say."
  (+my/tiling--stack-resize-pane +my/tiling--tall-right panes pane direction))

(defun +my/tiling-tall-right-closed (panes)
  "A pane closed: the stack's panes at equal heights again (but one
resized), when PANES are laid out tall-right."
  (+my/tiling--stack-closed +my/tiling--tall-right panes))
