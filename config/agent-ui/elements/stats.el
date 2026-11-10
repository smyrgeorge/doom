;;; $DOOMDIR/config/agent-ui/elements/stats.el -*- lexical-binding: t; -*-
;; Agent UI's stats: a row of figures, each with its change. Loaded from
;; config/agent-ui/elements.el.
;;
;; A figure: {"label", "value", "unit", "change", "good"}: VALUE (a number or
;; text) with its UNIT, CHANGE (a number: ▲ or ▼ with it; text: as it is),
;; GOOD "up" (default), "down" or "none": whether a rise is good (green) or
;; bad (red). Side by side, as many as fit, then wrapping; in the GUI, tiles
;; (SVG). The summary at the top of a canvas.
;;
;;   Coverage          Tests            Build
;;   87.1% ▲2.3        412 ✓            29 s ▼12

(require 'cl-lib)
(require 'subr-x)
(require 'svg)

(defun agent-ui-stats--figure (entry index)
  (cl-flet ((bad (what) (agent-ui--fail "stats: figure %d %s" index what)))
    (unless (agent-ui--plist-p entry)
      (bad "must be {\"label\": ..., \"value\": ...}"))
    (cl-loop for (k _) on entry by #'cddr
             unless (memq k '(:label :value :unit :change :good))
             do (bad (format "has %s: a figure has label, value, unit, change, good"
                             (agent-ui--show-value (substring (symbol-name k) 1)))))
    (unless (stringp (plist-get entry :label)) (bad "has no label"))
    (unless (or (numberp (plist-get entry :value)) (stringp (plist-get entry :value))) (bad "has no value"))
    (let ((good (or (plist-get entry :good) "up")))
      (unless (member good '("up" "down" "none" up down none))
        (bad "'s good is up, down or none"))
      (plist-put (copy-sequence entry) :good (if (stringp good) (intern good) good)))))

(defun agent-ui-stats--check (props)
  (plist-put props :figures (cl-loop for f in (plist-get props :figures)
                                     for i from 1 collect (agent-ui-stats--figure f i))))

(defun agent-ui-stats--value (figure)
  (concat (agent-ui-cell (plist-get figure :value))
          (if-let* ((unit (plist-get figure :unit))) (concat (if (string-match-p "\\`[%°]" unit) "" " ") unit) "")))

(defun agent-ui-stats--change (figure)
  "FIGURE's change as text and its face: (TEXT . FACE), or nil."
  (let ((change (plist-get figure :change))
        (good (plist-get figure :good)))
    (cond
     ((numberp change)
      (let* ((up (> change 0))
             (face (cond ((= change 0) 'agent-ui-muted) ((eq good 'none) 'agent-ui-muted)
                         ((eq up (eq good 'up)) 'agent-ui-success)
                         (t 'agent-ui-error))))
        (cons (concat (cond ((> change 0) "▲") ((< change 0) "▼") (t "="))
                      (if (= change 0) "" (agent-ui-format-number (abs change))))
              face)))
     ((stringp change) (cons change 'agent-ui-muted)))))

(defun agent-ui-stats--text (props ctx)
  (let* ((figures (plist-get props :figures))
         (width (plist-get ctx :width))
         (cells (mapcar (lambda (f)
                          (let ((change (agent-ui-stats--change f)))
                            (list (propertize (plist-get f :label) 'face 'agent-ui-muted)
                                  (concat (propertize (agent-ui-stats--value f) 'face 'bold)
                                          (if change (concat " " (propertize (car change) 'face (cdr change))) "")))))
                        figures))
         (cell-width (min (max 12 (+ 3 (apply #'max 0 (mapcar (lambda (c) (max (string-width (car c)) (string-width (cadr c)))) cells))))
                          width))
         (per-row (max 1 (/ width cell-width))))
    (if (null figures)
        (propertize "no figures" 'face 'agent-ui-muted)
      (mapconcat
       (lambda (row)
         (concat (string-trim-right (mapconcat (lambda (c) (agent-ui-pad (car c) cell-width)) row ""))
                 "\n"
                 (string-trim-right (mapconcat (lambda (c) (agent-ui-pad (cadr c) cell-width)) row ""))))
       (seq-partition cells per-row) "\n\n"))))

(defun agent-ui-stats--tile (f cw lh tile-width)
  "Figure F's tile laid out in TILE-WIDTH pixels: (VALUE CHANGE UNDER), its
value and change cut to fit, UNDER non-nil when the change goes on a line of
its own under the value (they didn't fit side by side). Widths as drawn:
the value's font 1.25 of a line (a character ~0.75 of it), the change's 0.8
\(~0.5)."
  (let* ((inner (- tile-width (* 2 cw)))
         (value (agent-ui-truncate (agent-ui-stats--value f) (max 1 (floor inner (* 0.75 lh)))))
         (value-width (* 0.75 lh (string-width value)))
         (change (agent-ui-stats--change f))
         (beside (and change (floor (- inner value-width cw) (* 0.5 lh)))))
    (cond ((null change) (list value nil nil))
          ((>= beside (string-width (car change))) (list value change nil))
          (t (list value
                   (cons (agent-ui-truncate (car change) (max 1 (floor inner (* 0.5 lh)))) (cdr change))
                   t)))))

(defun agent-ui-stats--gui (props ctx)
  (let* ((figures (plist-get props :figures))
         (cw (plist-get ctx :char-width))
         (lh (plist-get ctx :line-height))
         (width (* cw (plist-get ctx :width)))
         (gap cw)
         (tile-width (max (* 16 cw) (min (* 26 cw) (/ (- width gap) (max 1 (length figures))))))
         (per-row (max 1 (/ (+ width gap) (+ tile-width gap))))
         ;; Each row's tiles laid out; a row 4 lines tall when a change went
         ;; under its value, else 3.
         (rows (mapcar (lambda (row)
                         (mapcar (lambda (f) (cons f (agent-ui-stats--tile f cw lh tile-width))) row))
                       (seq-partition figures per-row)))
         (heights (mapcar (lambda (row) (* lh (if (seq-some (lambda (tile) (nth 3 tile)) row) 4 3))) rows))
         (svg (svg-create width (- (apply #'+ (mapcar (lambda (h) (+ h gap)) heights)) gap)))
         (fg (agent-ui-chart--color 'default))
         (muted (agent-ui-chart--color 'agent-ui-muted))
         (fill (agent-ui-progress--blend (or (face-background 'default nil t) "black") fg 0.07)))
    (if (null figures)
        (agent-ui-stats--text props ctx)
      (let ((y 0))
        (cl-loop for row in rows
                 for tile-height in heights
                 do (cl-loop for (f value change under) in row
                             for c from 0
                             do (let ((x (* c (+ tile-width gap))))
                                  (svg-rectangle svg x y tile-width tile-height :rx 6 :fill fill)
                                  (agent-ui-chart--svg-text svg ctx (agent-ui-truncate (plist-get f :label)
                                                                               ;; In the label's own width (its font
                                                                               ;; 0.8 of a line: wider than a cell).
                                                                               (floor (- tile-width (* 2 cw)) (* 0.5 lh)))
                                                            (+ x cw) (+ y (* 0.95 lh)) :fill muted)
                                  (svg-text svg value :x (+ x cw) :y (+ y (* 2.4 lh))
                                            :font-size (round (* 1.25 lh)) :font-weight "bold" :fill fg
                                            :font-family (or (face-attribute 'default :family nil t) "monospace"))
                                  (when change
                                    (if under
                                        (agent-ui-chart--svg-text svg ctx (car change) (+ x cw) (+ y (* 3.4 lh))
                                                                  :fill (agent-ui-chart--color (cdr change)))
                                      (agent-ui-chart--svg-text svg ctx (car change) (- (+ x tile-width) cw) (+ y (* 2.4 lh))
                                                                :fill (agent-ui-chart--color (cdr change))
                                                                :text-anchor "end")))))
                 do (setq y (+ y tile-height gap))))
      (agent-ui-chart--image svg))))

(agent-ui-define stats
  "A row of figures, each with its change: the summary at the top of a
canvas. A figure is {\"label\", \"value\", \"unit\", \"change\", \"good\"}:
CHANGE a number (▲ or ▼ with it) or text; GOOD \"up\" (default: a rise is
good, green), \"down\" (a rise is bad, red) or \"none\". Tiles in the GUI;
side by side, wrapping, as text."
  :props ((figures list "The figures: {\"label\", \"value\", \"unit\", \"change\", \"good\"}"))
  :example (:figures ((:label "Coverage" :value 87.1 :unit "%" :change 2.3)
                      (:label "Tests" :value 412 :change "all pass")
                      (:label "Build" :value 29 :unit "s" :change -12 :good "down")))
  :check #'agent-ui-stats--check
  :text #'agent-ui-stats--text
  :gui #'agent-ui-stats--gui)
