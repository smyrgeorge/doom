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

;; THE STACK'S HEIGHTS
;; A pane of the stack resized (SPC w } / {) keeps its share of the stack's
;; height, a parameter of its window: SPC w a, new panes and a closed pane even
;; the others out around it. One at a time: resizing another evens it out.

(defun +my/tiling--tall-stack (root)
  "The stack's panes under ROOT, laid out tall, top to bottom (none: one
pane)."
  (unless (window-live-p root)
    (let ((stack (window-next-sibling (window-left-child root))))
      (if (window-live-p stack) (list stack) (+my/tiling--children stack)))))

(defun +my/tiling--tall-heights (stack)
  "Lay out the heights of STACK (its panes): the one with a share (see
above) that share of their height, the others equal; none: all equal. Each
at least `window-min-height'."
  (let ((kept (seq-find (lambda (pane) (window-parameter pane '+my/tiling-share)) stack))
        (count (length stack)))
    (when (> count 1)
      (balance-windows (window-parent (car stack)))
      (when kept
        (let* ((total (apply #'+ (mapcar #'window-total-height stack)))
               (own (max window-min-height
                         (min (- total (* (1- count) window-min-height))
                              (round (* (window-parameter kept '+my/tiling-share) total)))))
               (rest (- total own))
               (others (1- count))
               (index -1)
               (heights (mapcar (lambda (pane)
                                  (if (eq pane kept)
                                      own
                                    (cl-incf index)
                                    (+ (/ rest others) (if (< index (% rest others)) 1 0))))
                                stack)))
          ;; Top down: each pane's bottom edge where its height says, the
          ;; panes below taking or giving the rows.
          (cl-loop for pane in (butlast stack)
                   for height in heights
                   do (ignore-errors
                        (adjust-window-trailing-edge pane (- height (window-total-height pane))))))))))

(defun +my/tiling-tall-arrange (panes)
  "Lay PANES out tall: the first one on the left, the others stacked on the
right at equal heights (but a pane resized, see above); each shows what it
showed, the selected one stays so."
  (let* ((states (mapcar #'+my/tiling--state (cdr panes)))
         ;; The stack's shares (one resized), by place: kept.
         (shares (mapcar (lambda (pane) (window-parameter pane '+my/tiling-share)) (cdr panes)))
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
    (cl-mapc (lambda (pane share) (set-window-parameter pane '+my/tiling-share share)) (cdr new) shares)
    (+my/tiling--tall-heights (cdr new))
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
                       ;; Even first: a pane taller (SPC w }) left the
                       ;; bottom one too small to split.
                       (balance-windows stack)
                       (car (last (+my/tiling--children stack)))))
             (new (split-window bottom nil 'below)))
        (set-window-parameter new '+my/tiling-share nil)
        (+my/tiling--tall-heights (+my/tiling--tall-stack root))
        new))))

(defun +my/tiling-tall-resize-main (panes direction)
  "The main pane wider (DIRECTION 1) or narrower (-1) by
`+my/tiling-resize-step' of the width, PANES arranged tall first if need be;
`+my/tiling-tall-ratio' set to it, so SPC w a and new panes keep it (within
`+my/tiling-tall-ratio-limits'). What to say: its share of the width."
  (unless (+my/tiling--tall-p (window-main-window))
    (+my/tiling-tall-arrange panes))
  (let ((root (window-main-window)))
    (when (window-live-p root)
      (user-error "Only one pane"))
    (setq +my/tiling-tall-ratio
          (min (cdr +my/tiling-tall-ratio-limits)
               (max (car +my/tiling-tall-ratio-limits)
                    (/ (round (* 100 (+ +my/tiling-tall-ratio (* direction +my/tiling-resize-step))))
                       100.0))))
    (let ((main (window-left-child root)))
      (window-resize main (- (+my/tiling--main-width root) (window-total-width main)) t))
    (format "Main pane: %d%% of the width" (round (* 100 +my/tiling-tall-ratio)))))

(defun +my/tiling-tall-resize-pane (panes pane direction)
  "PANE, one of the stack's, taller (DIRECTION 1) or shorter (-1) by
`+my/tiling-resize-step' of the stack's height, the others of the stack at
equal heights; its share kept (see THE STACK'S HEIGHTS). PANES arranged tall
first if need be. The main pane, or the stack's only one: as tall as the
frame, said. What to say: its share of the stack's height."
  (unless (+my/tiling--tall-p (window-main-window))
    (+my/tiling-tall-arrange panes)
    ;; Arranged: its place's new window.
    (setq pane (selected-window)))
  (let ((stack (+my/tiling--tall-stack (window-main-window))))
    (cond
     ((not (memq pane stack))
      (user-error "The main pane is as tall as the frame (SPC w ] / [ make it wider, narrower)"))
     ((null (cdr stack))
      (user-error "The only pane on the right is as tall as the frame"))
     (t
      (let* ((total (apply #'+ (mapcar #'window-total-height stack)))
             (share (or (window-parameter pane '+my/tiling-share)
                        (/ (float (window-total-height pane)) total)))
             (biggest (/ (float (- total (* (1- (length stack)) window-min-height))) total))
             (smallest (/ (float window-min-height) total)))
        (dolist (other stack)
          (set-window-parameter other '+my/tiling-share nil))
        (set-window-parameter pane '+my/tiling-share
                              (min biggest (max smallest (+ share (* direction +my/tiling-resize-step)))))
        (+my/tiling--tall-heights stack)
        (format "Pane: %d%% of the stack's height"
                (round (* 100 (/ (float (window-total-height pane)) total)))))))))

(defun +my/tiling-tall-closed (_panes)
  "A pane closed (see config/tiling.el): the stack's panes at equal heights
again (but a pane resized: its share kept), the main pane's width as it is;
only when the panes are laid out tall."
  (let ((root (window-main-window)))
    (when (and (not (window-live-p root)) (+my/tiling--tall-p root))
      (+my/tiling--tall-heights (+my/tiling--tall-stack root)))))
