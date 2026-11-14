;;; $DOOMDIR/config/tiling/stack.el -*- lexical-binding: t; -*-
;; A main pane and a stack of the others: what the tall, tall-right and wide
;; strategies share, each a LAYOUT here. Loaded from config/tiling.el.

;; A LAYOUT
;; (:main SIDE :ratio VARIABLE :limits VARIABLE): the main pane on SIDE, the
;; stack beside it: left or right (tall, tall-right), the stack's panes one
;; above the other; above (wide), the stack below it, its panes side by side.
;; The main pane's share of the width (left, right) or of the height (above)
;; is VARIABLE's value, SPC w ] / [ within the limits (a cons) of the other.
;; Sizes along the stack (its panes' heights, or widths) are its LENGTH below.

(defun +my/tiling--across-p (layout)
  "Non-nil if LAYOUT's main pane and stack are side by side (the main pane's
size its width, the stack's panes one above the other); nil if one above
the other (wide)."
  (memq (plist-get layout :main) '(left right)))

(defun +my/tiling--stack-side (layout)
  "Where a pane beside LAYOUT's main pane opens: the stack's side."
  (pcase (plist-get layout :main)
    ('left 'right)
    ('right 'left)
    ('above 'below)))

(defun +my/tiling--stack-direction (layout)
  "Where the stack's next pane opens, from its last one."
  (if (+my/tiling--across-p layout) 'below 'right))

(defun +my/tiling--stack-length (layout pane)
  "PANE's size along LAYOUT's stack: its height, or its width (wide)."
  (window-size pane (not (+my/tiling--across-p layout))))

(defun +my/tiling--stack-least (layout)
  "The smallest size along LAYOUT's stack a pane gets."
  (if (+my/tiling--across-p layout) window-min-height window-min-width))

(defun +my/tiling--stack-parts (layout root)
  "(MAIN . STACK) of the panes under ROOT laid out as LAYOUT: its main pane,
and the stack's window (its only pane, or its panes' parent); nil if ROOT
isn't laid out so, or is one pane."
  (let* ((across (+my/tiling--across-p layout))
         (first (if across (window-left-child root) (window-top-child root)))
         (second (and first (window-next-sibling first))))
    (when (and second (null (window-next-sibling second)))
      (let ((main (if (eq (plist-get layout :main) 'right) second first))
            (stack (if (eq (plist-get layout :main) 'right) first second)))
        (when (and (window-live-p main)
                   (or (window-live-p stack)
                       (and (if across (window-top-child stack) (window-left-child stack))
                            (seq-every-p #'window-live-p (+my/tiling--children stack)))))
          (cons main stack))))))

(defun +my/tiling--stack-p (layout root)
  "Non-nil if the panes under ROOT are laid out as LAYOUT: one pane, or its
main pane beside one column (or row) of panes."
  (or (window-live-p root)
      (and (+my/tiling--stack-parts layout root) t)))

(defun +my/tiling--stack-panes (layout root)
  "The stack's panes under ROOT, laid out as LAYOUT, in order: top to bottom,
or left to right (none: one pane)."
  (when-let* ((stack (cdr (+my/tiling--stack-parts layout root))))
    (if (window-live-p stack) (list stack) (+my/tiling--children stack))))

(defun +my/tiling--stack-order (layout panes)
  "PANES (in order on the screen) with LAYOUT's main pane first, where SPC w
RET and SPC w a find it (tall-right's is on the right, the last on the
screen). Not laid out so: as they are, the first one the main."
  (let ((root (window-main-window (window-frame (car panes)))))
    (if-let* ((main (car (+my/tiling--stack-parts layout root))))
        (cons main (remq main panes))
      panes)))

(defun +my/tiling--stack-main-size (layout window)
  "The columns (or lines: wide) LAYOUT's main pane gets of WINDOW's (its
ratio)."
  (round (* (symbol-value (plist-get layout :ratio))
            (window-size window (+my/tiling--across-p layout)))))

;; THE STACK'S SIZES
;; A pane of the stack resized (SPC w } / {) keeps its share of the stack's
;; length (its height, or wide's width), a parameter of its window: SPC w a,
;; new panes and a closed pane even the others out around it. One at a time:
;; resizing another evens it out.

(defun +my/tiling--stack-sizes (layout stack)
  "Lay out the lengths of STACK (its panes, LAYOUT's): the one with a share
\(see above) that share of their length, the others equal; none: all equal.
Each at least its smallest (`+my/tiling--stack-least')."
  (let ((kept (seq-find (lambda (pane) (window-parameter pane '+my/tiling-share)) stack))
        (count (length stack))
        (horizontal (not (+my/tiling--across-p layout)))
        (least (+my/tiling--stack-least layout)))
    (when (> count 1)
      (balance-windows (window-parent (car stack)))
      (when kept
        (let* ((total (apply #'+ (mapcar (lambda (pane) (+my/tiling--stack-length layout pane)) stack)))
               (own (max least
                         (min (- total (* (1- count) least))
                              (round (* (window-parameter kept '+my/tiling-share) total)))))
               (rest (- total own))
               (others (1- count))
               (index -1)
               (sizes (mapcar (lambda (pane)
                                (if (eq pane kept)
                                    own
                                  (cl-incf index)
                                  (+ (/ rest others) (if (< index (% rest others)) 1 0))))
                              stack)))
          ;; In order: each pane's far edge where its size says, the panes
          ;; after it taking or giving the rows (columns).
          (cl-loop for pane in (butlast stack)
                   for size in sizes
                   do (ignore-errors
                        (adjust-window-trailing-edge
                         pane (- size (+my/tiling--stack-length layout pane)) horizontal))))))))

;; THE ROOM
;; COUNT panes fit when the stack's panes (all but the main one) each get at
;; least the smallest size along it: what SPC w SPC allows. SPC w a makes each
;; at its size, the stack's length shared out (halving the last pane in turn
;; runs out of room long before the stack does); no room for them all: said,
;; nothing changed.

(defun +my/tiling--stack-fits-p (layout window count)
  "Non-nil if COUNT panes fit in WINDOW laid out as LAYOUT (see above)."
  (<= (* (max 0 (1- count)) (+my/tiling--stack-least layout))
      (window-size window (not (+my/tiling--across-p layout)))))

(defun +my/tiling--stack-build (layout main count)
  "Split MAIN, the only pane, into LAYOUT's main pane (itself, its share) and
a stack of COUNT panes beside it, each its share of the stack's length; the
stack's panes, in order."
  (let* ((pane (split-window main (+my/tiling--stack-main-size layout main)
                             (+my/tiling--stack-side layout)))
         (length (+my/tiling--stack-length layout pane))
         (stack (list pane)))
    ;; Each in turn keeps its share, the rest going to the next one.
    (dotimes (index (1- count))
      (setq pane (split-window pane (+ (/ length count) (if (< index (% length count)) 1 0))
                               (+my/tiling--stack-direction layout)))
      (push pane stack))
    (nreverse stack)))

;; THE STRATEGY'S FUNCTIONS (see `+my/tiling-strategies'), given the layout
(defun +my/tiling--stack-arrange (layout panes)
  "Lay PANES out as LAYOUT: the first one the main pane, its share of the
width (wide: height), the others in the stack beside it at equal sizes (but
a pane resized, see above); each shows what it showed, the selected one
stays so. No room for them all (see THE ROOM): said (a user error), the
panes as they were."
  (unless (+my/tiling--stack-fits-p layout (window-main-window) (length panes))
    (user-error "No room for %d panes" (length panes)))
  (let* ((states (mapcar #'+my/tiling--state (cdr panes)))
         ;; The stack's shares (one resized), by place: kept.
         (shares (mapcar (lambda (pane) (window-parameter pane '+my/tiling-share)) (cdr panes)))
         (index (seq-position panes (selected-window)))
         (main (car panes))
         (before (current-window-configuration))
         new)
    ;; Whatever fails halfway (the panes deleted, not all made again): the
    ;; panes as they were.
    (condition-case err
        (progn
          (dolist (pane (cdr panes))
            (delete-window pane))
          (setq new (cons main (and states (+my/tiling--stack-build layout main (length states)))))
          (+my/tiling--mark-main main)
          (cl-mapc #'+my/tiling--restore (cdr new) states))
      (error (set-window-configuration before)
             (signal (car err) (cdr err))))
    (cl-mapc (lambda (pane share) (set-window-parameter pane '+my/tiling-share share)) (cdr new) shares)
    (+my/tiling--stack-sizes layout (cdr new))
    (select-window (nth (or index 0) new))))

(defun +my/tiling--split-window (window size side)
  "`split-window' WINDOW (SIZE, SIDE), no room for a new pane said."
  (condition-case nil
      (split-window window size side)
    (error (user-error "No room for another pane"))))

(defun +my/tiling--stack-split (layout panes)
  "Open a pane as LAYOUT has it: beside the only one (which stays the main
pane), else at the end of the stack (its bottom, or wide's right end);
PANES arranged so first if need be. Return it. No room for it: said (a user
error), the panes as they were."
  (unless (+my/tiling--stack-p layout (window-main-window))
    (+my/tiling--stack-arrange layout panes))
  (let ((root (window-main-window)))
    (if (window-live-p root)
        (prog1 (+my/tiling--split-window root (+my/tiling--stack-main-size layout root)
                                         (+my/tiling--stack-side layout))
          (+my/tiling--mark-main root))
      (let* ((stack (+my/tiling--stack-panes layout root))
             (last (car (last stack))))
        (when (< (apply #'+ (mapcar (lambda (pane) (+my/tiling--stack-length layout pane)) stack))
                 (* (1+ (length stack)) (+my/tiling--stack-least layout)))
          (user-error "No room for another pane"))
        ;; Even first: a pane bigger (SPC w }) left the last one too small to
        ;; split.
        (when (cdr stack)
          (balance-windows (window-parent last)))
        (let ((new (+my/tiling--split-window last nil (+my/tiling--stack-direction layout))))
          (set-window-parameter new '+my/tiling-share nil)
          (+my/tiling--stack-sizes layout (+my/tiling--stack-panes layout root))
          new)))))

(defun +my/tiling--stack-resize-main (layout panes direction)
  "LAYOUT's main pane bigger (DIRECTION 1) or smaller (-1) by
`+my/tiling-resize-step' of the width (wide: height), PANES arranged so
first if need be; its ratio set to it, so SPC w a and new panes keep it
\(within its limits). What to say: its share."
  (unless (+my/tiling--stack-p layout (window-main-window))
    (+my/tiling--stack-arrange layout panes))
  (let ((root (window-main-window))
        (ratio (plist-get layout :ratio))
        (limits (symbol-value (plist-get layout :limits)))
        (across (+my/tiling--across-p layout)))
    (when (window-live-p root)
      (user-error "Only one pane"))
    (set ratio (min (cdr limits)
                    (max (car limits)
                         (/ (round (* 100 (+ (symbol-value ratio) (* direction +my/tiling-resize-step))))
                            100.0))))
    (let ((main (car (+my/tiling--stack-parts layout root))))
      (window-resize main (- (+my/tiling--stack-main-size layout root) (window-size main across)) across))
    (format "Main pane: %d%% of the %s" (round (* 100 (symbol-value ratio))) (if across "width" "height"))))

(defun +my/tiling--stack-resize-pane (layout panes pane direction)
  "PANE, one of the stack's, bigger (DIRECTION 1) or smaller (-1) along it
\(taller, or wide's wider) by `+my/tiling-resize-step' of the stack's length,
the others of the stack at equal sizes; its share kept (see THE STACK'S
SIZES). PANES arranged as LAYOUT first if need be. The main pane, or the
stack's only one: as long as the frame, said. What to say: its share."
  (unless (+my/tiling--stack-p layout (window-main-window))
    (+my/tiling--stack-arrange layout panes)
    ;; Arranged: its place's new window.
    (setq pane (selected-window)))
  (let ((stack (+my/tiling--stack-panes layout (window-main-window)))
        (across (+my/tiling--across-p layout))
        (least (+my/tiling--stack-least layout)))
    (cond
     ((not (memq pane stack))
      (user-error (if across
                      "The main pane is as tall as the frame (SPC w ] / [ make it wider, narrower)"
                    "The main pane is as wide as the frame (SPC w ] / [ make it taller, shorter)")))
     ((null (cdr stack))
      (user-error (if across
                      (format "The only pane on the %s is as tall as the frame" (+my/tiling--stack-side layout))
                    "The only pane below is as wide as the frame")))
     (t
      (let* ((total (apply #'+ (mapcar (lambda (other) (+my/tiling--stack-length layout other)) stack)))
             (share (or (window-parameter pane '+my/tiling-share)
                        (/ (float (+my/tiling--stack-length layout pane)) total)))
             (biggest (/ (float (- total (* (1- (length stack)) least))) total))
             (smallest (/ (float least) total)))
        (dolist (other stack)
          (set-window-parameter other '+my/tiling-share nil))
        (set-window-parameter pane '+my/tiling-share
                              (min biggest (max smallest (+ share (* direction +my/tiling-resize-step)))))
        (+my/tiling--stack-sizes layout stack)
        (format "Pane: %d%% of the stack's %s"
                (round (* 100 (/ (float (+my/tiling--stack-length layout pane)) total)))
                (if across "height" "width")))))))

(defun +my/tiling--stack-closed (layout _panes)
  "A pane closed (see config/tiling.el): the stack's panes at equal sizes
again (but a pane resized: its share kept), the main pane's as it is; only
when the panes are laid out as LAYOUT."
  (let ((root (window-main-window)))
    (when (and (not (window-live-p root)) (+my/tiling--stack-p layout root))
      (+my/tiling--stack-sizes layout (+my/tiling--stack-panes layout root)))))
