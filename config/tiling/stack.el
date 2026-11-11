;;; $DOOMDIR/config/tiling/stack.el -*- lexical-binding: t; -*-
;; A main pane and a stack of the others: what the tall and tall-right
;; strategies share (Amethyst's Tall, Tall-Right), each a LAYOUT here.
;; Loaded from config/tiling.el.

;; A LAYOUT
;; (:main SIDE :ratio VARIABLE :limits VARIABLE): the main pane on SIDE, left
;; or right, the stack beside it, its panes one above the other; the main
;; pane's share of the width VARIABLE's value, SPC w ] / [ within the limits
;; (a cons) of the other one.

(defun +my/tiling--stack-side (layout)
  "Where a pane beside LAYOUT's main pane opens: the stack's side."
  (pcase (plist-get layout :main)
    ('left 'right)
    ('right 'left)))

(defun +my/tiling--stack-parts (layout root)
  "(MAIN . STACK) of the panes under ROOT laid out as LAYOUT: its main pane,
and the stack's window (its only pane, or its panes' parent); nil if ROOT
isn't laid out so, or is one pane."
  (let* ((first (window-left-child root)) ; side by side
         (second (and first (window-next-sibling first))))
    (when (and second (null (window-next-sibling second)))
      (let ((main (if (eq (plist-get layout :main) 'right) second first))
            (stack (if (eq (plist-get layout :main) 'right) first second)))
        (when (and (window-live-p main)
                   (or (window-live-p stack)
                       (and (window-top-child stack) ; one above the other
                            (seq-every-p #'window-live-p (+my/tiling--children stack)))))
          (cons main stack))))))

(defun +my/tiling--stack-p (layout root)
  "Non-nil if the panes under ROOT are laid out as LAYOUT: one pane, or its
main pane beside one column of panes."
  (or (window-live-p root)
      (and (+my/tiling--stack-parts layout root) t)))

(defun +my/tiling--stack-panes (layout root)
  "The stack's panes under ROOT, laid out as LAYOUT, top to bottom (none: one
pane)."
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
  "The columns LAYOUT's main pane gets of WINDOW's (its ratio)."
  (round (* (symbol-value (plist-get layout :ratio)) (window-total-width window))))

;; THE STACK'S HEIGHTS
;; A pane of the stack resized (SPC w } / {) keeps its share of the stack's
;; height, a parameter of its window: SPC w a, new panes and a closed pane even
;; the others out around it. One at a time: resizing another evens it out.

(defun +my/tiling--stack-heights (stack)
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

;; THE STRATEGY'S FUNCTIONS (see `+my/tiling-strategies'), given the layout
(defun +my/tiling--stack-arrange (layout panes)
  "Lay PANES out as LAYOUT: the first one the main pane, its share of the
width, the others stacked beside it at equal heights (but a pane resized,
see above); each shows what it showed, the selected one stays so."
  (let* ((states (mapcar #'+my/tiling--state (cdr panes)))
         ;; The stack's shares (one resized), by place: kept.
         (shares (mapcar (lambda (pane) (window-parameter pane '+my/tiling-share)) (cdr panes)))
         (index (seq-position panes (selected-window)))
         (main (car panes))
         (new (list main)))
    (dolist (pane (cdr panes))
      (delete-window pane))
    (+my/tiling--mark-main main)
    (when states
      (let ((pane (split-window main (+my/tiling--stack-main-size layout main)
                                (+my/tiling--stack-side layout))))
        (push pane new)
        (dotimes (_ (1- (length states)))
          (setq pane (split-window pane nil 'below))
          (push pane new))
        ;; The stack's panes at equal heights. One alone: its parent is the
        ;; main pane's too, whose share of the width that would undo.
        (when (cdr states)
          (balance-windows (window-parent pane)))))
    (setq new (nreverse new))
    (cl-mapc #'+my/tiling--restore (cdr new) states)
    (cl-mapc (lambda (pane share) (set-window-parameter pane '+my/tiling-share share)) (cdr new) shares)
    (+my/tiling--stack-heights (cdr new))
    (select-window (nth (or index 0) new))))

(defun +my/tiling--split-window (window size side)
  "`split-window' WINDOW (SIZE, SIDE), no room for a new pane said."
  (condition-case nil
      (split-window window size side)
    (error (user-error "No room for another pane"))))

(defun +my/tiling--stack-split (layout panes)
  "Open a pane as LAYOUT has it: beside the only one (which stays the main
pane), else at the bottom of the stack; PANES arranged so first if need be.
Return it. No room for it: said (a user error), the panes as they were."
  (unless (+my/tiling--stack-p layout (window-main-window))
    (+my/tiling--stack-arrange layout panes))
  (let ((root (window-main-window)))
    (if (window-live-p root)
        (prog1 (+my/tiling--split-window root (+my/tiling--stack-main-size layout root)
                                         (+my/tiling--stack-side layout))
          (+my/tiling--mark-main root))
      (let* ((stack (+my/tiling--stack-panes layout root))
             (bottom (car (last stack))))
        (when (< (apply #'+ (mapcar #'window-total-height stack))
                 (* (1+ (length stack)) window-min-height))
          (user-error "No room for another pane"))
        ;; Even first: a pane taller (SPC w }) left the bottom one too small
        ;; to split.
        (when (cdr stack)
          (balance-windows (window-parent bottom)))
        (let ((new (+my/tiling--split-window bottom nil 'below)))
          (set-window-parameter new '+my/tiling-share nil)
          (+my/tiling--stack-heights (+my/tiling--stack-panes layout root))
          new)))))

(defun +my/tiling--stack-resize-main (layout panes direction)
  "LAYOUT's main pane wider (DIRECTION 1) or narrower (-1) by
`+my/tiling-resize-step' of the width, PANES arranged so first if need be;
its ratio set to it, so SPC w a and new panes keep it (within its limits).
What to say: its share of the width."
  (unless (+my/tiling--stack-p layout (window-main-window))
    (+my/tiling--stack-arrange layout panes))
  (let ((root (window-main-window))
        (ratio (plist-get layout :ratio))
        (limits (symbol-value (plist-get layout :limits))))
    (when (window-live-p root)
      (user-error "Only one pane"))
    (set ratio (min (cdr limits)
                    (max (car limits)
                         (/ (round (* 100 (+ (symbol-value ratio) (* direction +my/tiling-resize-step))))
                            100.0))))
    (let ((main (car (+my/tiling--stack-parts layout root))))
      (window-resize main (- (+my/tiling--stack-main-size layout root) (window-total-width main)) t))
    (format "Main pane: %d%% of the width" (round (* 100 (symbol-value ratio))))))

(defun +my/tiling--stack-resize-pane (layout panes pane direction)
  "PANE, one of the stack's, taller (DIRECTION 1) or shorter (-1) by
`+my/tiling-resize-step' of the stack's height, the others of the stack at
equal heights; its share kept (see THE STACK'S HEIGHTS). PANES arranged as
LAYOUT first if need be. The main pane, or the stack's only one: as tall as
the frame, said. What to say: its share of the stack's height."
  (unless (+my/tiling--stack-p layout (window-main-window))
    (+my/tiling--stack-arrange layout panes)
    ;; Arranged: its place's new window.
    (setq pane (selected-window)))
  (let ((stack (+my/tiling--stack-panes layout (window-main-window))))
    (cond
     ((not (memq pane stack))
      (user-error "The main pane is as tall as the frame (SPC w ] / [ make it wider, narrower)"))
     ((null (cdr stack))
      (user-error "The only pane on the %s is as tall as the frame" (+my/tiling--stack-side layout)))
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
        (+my/tiling--stack-heights stack)
        (format "Pane: %d%% of the stack's height"
                (round (* 100 (/ (float (window-total-height pane)) total)))))))))

(defun +my/tiling--stack-closed (layout _panes)
  "A pane closed (see config/tiling.el): the stack's panes at equal heights
again (but a pane resized: its share kept), the main pane's width as it is;
only when the panes are laid out as LAYOUT."
  (let ((root (window-main-window)))
    (when (and (not (window-live-p root)) (+my/tiling--stack-p layout root))
      (+my/tiling--stack-heights (+my/tiling--stack-panes layout root)))))
