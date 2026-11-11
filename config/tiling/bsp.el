;;; $DOOMDIR/config/tiling/bsp.el -*- lexical-binding: t; -*-
;; The bsp strategy (Amethyst's Binary Space Partitioning): each new pane
;; halves the current one. Loaded from config/tiling.el.

;; BSP
;; No main pane: the panes are the leaves of a binary tree, each split in two
;; even halves along its longer side as it's seen (in pixels: a column is
;; about half as wide as a line is tall; on a text terminal, where a pixel is
;; a character, a line counted as two columns), side by side if wider than
;; tall, else one above the other. The tree is Emacs's own window tree: each split made with
;; `window-combination-limit' t has a parent of its own, two children. A new
;; pane halves the current one (the last one from a side panel), the new half
;; on the right or below. SPC w a lays the panes out as Amethyst builds the
;; tree from a list, each halving the last: a spiral, 1 | (2 / (3 | ...)).
;; A pane closed: Emacs gives its space to its sibling; every split laid out
;; again along its longer side then, the tree kept (Emacs can't turn a split
;; round: the panes made again, each showing what it showed). SPC w ] / [ the
;; current pane's split, SPC w } / { the one above it: not kept (Amethyst's
;; splits are all even), the next layout evens them out.

(defun +my/tiling--bsp-extent (window)
  "WINDOW's (WIDTH . HEIGHT) as it's seen (see above)."
  (if (display-graphic-p (window-frame window))
      (cons (window-pixel-width window) (window-pixel-height window))
    (cons (window-total-width window) (* 2 (window-total-height window)))))

(defun +my/tiling--bsp-side (window)
  "Where WINDOW's split puts its second half: right if WINDOW is wider than
tall as it's seen, else below."
  (let ((extent (+my/tiling--bsp-extent window)))
    (if (> (car extent) (cdr extent)) 'right 'below)))

(defun +my/tiling--bsp-p (window)
  "Non-nil if every split under WINDOW has two halves."
  (or (window-live-p window)
      (let ((children (+my/tiling--children window)))
        (and (= (length children) 2)
             (seq-every-p #'+my/tiling--bsp-p children)))))

(defun +my/tiling--bsp-turned-p (window)
  "Non-nil if a split under WINDOW doesn't run along its longer side."
  (and (not (window-live-p window))
       (or (not (eq (if (window-left-child window) 'right 'below) (+my/tiling--bsp-side window)))
           (seq-some #'+my/tiling--bsp-turned-p (+my/tiling--children window)))))

(defun +my/tiling--bsp-even (window)
  "Every split under WINDOW in two even halves."
  (unless (window-live-p window)
    (let* ((first (window-child window))
           (horizontal (and (window-left-child window) t))
           (half (/ (window-size window horizontal) 2)))
      (ignore-errors (window-resize first (- half (window-size first horizontal)) horizontal))
      (mapc #'+my/tiling--bsp-even (+my/tiling--children window)))))

;; SHAPES: a pane's state (`+my/tiling--state'), or [FIRST SECOND] for a
;; split's two halves.
(defun +my/tiling--bsp-shape (window)
  "The tree under WINDOW (every split two halves) as a shape."
  (if (window-live-p window)
      (+my/tiling--state window)
    (apply #'vector (mapcar #'+my/tiling--bsp-shape (+my/tiling--children window)))))

(defun +my/tiling--bsp-spiral (states)
  "The shape of STATES laid out as Amethyst's list: each halving the last."
  (if (cdr states)
      (vector (car states) (+my/tiling--bsp-spiral (cdr states)))
    (car states)))

(defun +my/tiling--bsp-build (window shape)
  "SHAPE laid out in WINDOW, a pane, each split along its longer side, even;
its panes in order."
  (if (vectorp shape)
      (let ((new (let ((window-combination-limit t))
                   (+my/tiling--split-window window nil (+my/tiling--bsp-side window)))))
        (append (+my/tiling--bsp-build window (aref shape 0))
                (+my/tiling--bsp-build new (aref shape 1))))
    (+my/tiling--restore window shape)
    (list window)))

(defun +my/tiling--bsp-fits-p (window count)
  "Non-nil if COUNT panes fit in WINDOW as the spiral: the last, halved COUNT
- 1 times, still at least `window-min-width' by `window-min-height'."
  (let ((columns (window-total-width window)) (lines (window-total-height window))
        (width (car (+my/tiling--bsp-extent window))) (height (cdr (+my/tiling--bsp-extent window))))
    (dotimes (_ (1- count))
      (if (> width height)
          (setq columns (/ columns 2) width (/ width 2))
        (setq lines (/ lines 2) height (/ height 2))))
    (and (>= columns window-min-width) (>= lines window-min-height))))

(defun +my/tiling--bsp-lay-out (panes shape)
  "PANES (their windows, in SHAPE's order) laid out as SHAPE in the first
one's place; the selected one's place selected again, the main one's marked
again. The panes made anew."
  (let ((index (seq-position panes (selected-window)))
        (main (seq-position panes nil (lambda (pane _) (window-parameter pane '+my/tiling-main))))
        (first (car panes)))
    (dolist (pane (cdr panes))
      (delete-window pane))
    (let ((new (+my/tiling--bsp-build first shape)))
      (when main
        (+my/tiling--mark-main (nth main new)))
      (select-window (nth (or index 0) new))
      new)))

;; THE STRATEGY'S FUNCTIONS (see `+my/tiling-strategies')
(defun +my/tiling-bsp-arrange (panes)
  "Lay PANES out as the spiral (see above), every split even; each shows what
it showed, the selected one stays so. No room for them all: said, nothing
changed."
  (unless (+my/tiling--bsp-fits-p (window-main-window) (length panes))
    (user-error "No room for %d panes" (length panes)))
  (let ((states (mapcar #'+my/tiling--state panes)))
    (+my/tiling--mark-main (car panes))
    (+my/tiling--bsp-lay-out panes (+my/tiling--bsp-spiral states))))

(defun +my/tiling-bsp-split (panes)
  "Halve the current pane (the last one, from a side panel) along its longer
side, the new half on the right or below. Return it."
  (let ((pane (if (memq (selected-window) panes) (selected-window) (car (last panes))))
        (window-combination-limit t))
    (+my/tiling--split-window pane nil (+my/tiling--bsp-side pane))))

(defun +my/tiling--bsp-resize (window direction said)
  "WINDOW's half of its split bigger (DIRECTION 1) or smaller (-1) by
`+my/tiling-resize-step' of the split; what to say: SAID, a format given its
share (a percentage)."
  (let ((parent (window-parent window)))
    (unless parent
      (user-error "No split above this one"))
    (let* ((horizontal (window-combined-p window t))
           (total (window-size parent horizontal))
           (before (window-size window horizontal)))
      (ignore-errors
        (window-resize window (* direction (max 1 (round (* +my/tiling-resize-step total)))) horizontal))
      (when (= before (window-size window horizontal))
        (user-error "No room to make it %s" (if (> direction 0) "bigger" "smaller")))
      (format said (round (* 100 (/ (float (window-size window horizontal)) total)))))))

(defun +my/tiling-bsp-resize-main (_panes direction)
  "SPC w ] / [: the current pane's half of its split bigger / smaller (see
above). What to say."
  (+my/tiling--bsp-resize (selected-window) direction "Pane: %d%% of its split"))

(defun +my/tiling-bsp-resize-pane (_panes pane direction)
  "SPC w } / {: the split PANE is in, its half of the split above it bigger /
smaller (see above). What to say."
  (+my/tiling--bsp-resize (window-parent pane) direction "Its split: %d%% of the one above"))

(defun +my/tiling-bsp-closed (_panes)
  "A pane closed: every split along its longer side again (the tree kept),
even; only when the panes are laid out as a binary tree."
  (let ((root (window-main-window)))
    (when (and (not (window-live-p root)) (+my/tiling--bsp-p root))
      (if (+my/tiling--bsp-turned-p root)
          (+my/tiling--bsp-lay-out (+my/tiling--panes) (+my/tiling--bsp-shape root))
        (+my/tiling--bsp-even root)))))
