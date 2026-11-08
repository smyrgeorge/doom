;;; $DOOMDIR/config/tiling/tall.el -*- lexical-binding: t; -*-
;; The tall strategy (Amethyst's Tall).
;; Loaded from config/tiling.el.

;; TALL
(defun +my/tiling--tall-p (root)
  "Non-nil if the panes under ROOT are laid out tall: one pane, or a pane on
the left of one column of panes."
  (or (window-live-p root)
      (let* ((main (window-left-child root)) ; side by side
             (stack (and main (window-next-sibling main))))
        (and (window-live-p main)
             stack
             (null (window-next-sibling stack))
             (or (window-live-p stack)
                 (and (window-top-child stack) ; one above the other
                      (seq-every-p #'window-live-p (+my/tiling--children stack))))))))

(defun +my/tiling--main-width (window)
  "The columns the main pane gets of WINDOW's (see `+my/tiling-tall-ratio')."
  (round (* +my/tiling-tall-ratio (window-total-width window))))

(defun +my/tiling-tall-arrange (panes)
  "Lay PANES out tall: the first one on the left, the others stacked on the
right at equal heights; each shows what it showed, the selected one stays so."
  (let* ((states (mapcar #'+my/tiling--state (cdr panes)))
         (index (seq-position panes (selected-window)))
         (main (car panes))
         (new (list main)))
    (dolist (pane (cdr panes))
      (delete-window pane))
    (when states
      (let ((pane (split-window main (+my/tiling--main-width main) 'right)))
        (push pane new)
        (dotimes (_ (1- (length states)))
          (setq pane (split-window pane nil 'below))
          (push pane new))
        (when (window-parent pane)
          (balance-windows (window-parent pane)))))
    (setq new (nreverse new))
    (cl-mapc #'+my/tiling--restore (cdr new) states)
    (select-window (nth (or index 0) new))))

(defun +my/tiling-tall-split (panes)
  "Open a pane, tall (see config/tiling.el): on the right of the only one, else
at the bottom of the stack; PANES arranged tall first if need be. Return it."
  (unless (+my/tiling--tall-p (window-main-window))
    (+my/tiling-tall-arrange panes))
  (let ((root (window-main-window)))
    (if (window-live-p root)
        (split-window root (+my/tiling--main-width root) 'right)
      (let* ((stack (window-next-sibling (window-left-child root)))
             (bottom (if (window-live-p stack)
                         stack
                       (car (last (+my/tiling--children stack)))))
             (new (split-window bottom nil 'below)))
        (balance-windows (window-parent new))
        new))))

(defun +my/tiling-tall-resize (panes delta)
  "The main pane DELTA (a share of the width, e.g. 0.05) bigger, PANES
arranged tall first if need be; `+my/tiling-tall-ratio' set to it, so SPC w a
and new panes keep it (within `+my/tiling-tall-ratio-limits'). The ratio."
  (unless (+my/tiling--tall-p (window-main-window))
    (+my/tiling-tall-arrange panes))
  (let ((root (window-main-window)))
    (when (window-live-p root)
      (user-error "Only one pane"))
    (setq +my/tiling-tall-ratio
          (min (cdr +my/tiling-tall-ratio-limits)
               (max (car +my/tiling-tall-ratio-limits)
                    (/ (round (* 100 (+ +my/tiling-tall-ratio delta))) 100.0))))
    (let ((main (window-left-child root)))
      (window-resize main (- (+my/tiling--main-width root) (window-total-width main)) t))
    +my/tiling-tall-ratio))
