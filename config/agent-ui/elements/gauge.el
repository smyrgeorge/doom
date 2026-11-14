;;; $DOOMDIR/config/agent-ui/elements/gauge.el -*- lexical-binding: t; -*-
;; Agent UI's gauge: one value against its range and thresholds (coverage
;; against a target, a budget used, a latency against an SLO). Loaded from
;; config/agent-ui/elements.el.
;;
;; THRESHOLDS are zones: each {at, face} colours from AT up to the next one
;; (coverage: error at 0, warning at 70, success at 80; a latency: success at
;; 0, warning at 200, error at 500). The value is in its zone's colour. In
;; text, a bar: its fill in that colour, the rest of its track in each zone's
;; (dimmed), the TARGET a ┃; in the GUI, a half-circle arc, the value in it.
;;
;;   Coverage  ███████████████████░░░░┃░░░░  78%  target 80%

(require 'cl-lib)
(require 'subr-x)

(defun agent-ui-gauge--zones (props)
  "PROPS' thresholds as ((AT . FACE)...), by AT."
  (sort (mapcar (lambda (th) (cons (plist-get th :at) (or (agent-ui-face (plist-get th :face)) 'default)))
                (plist-get props :thresholds))
        (lambda (a b) (< (car a) (car b)))))

(defun agent-ui-gauge--face (zones value)
  "The face of VALUE's zone in ZONES: the last one starting at or below it;
the accent's below them all."
  (or (cdr (car (last (seq-filter (lambda (z) (<= (car z) value)) zones))))
      'agent-ui-accent))

(defun agent-ui-gauge--shown (props value)
  "VALUE with PROPS' unit: \"78%\", \"230 ms\"."
  (let ((unit (plist-get props :unit)))
    (concat (agent-ui-format-number value)
            (cond ((null unit) "")
                  ((equal unit "%") "%")
                  (t (concat " " unit))))))

(defun agent-ui-gauge--check (props)
  (let ((min (plist-get props :min))
        (max (plist-get props :max)))
    (unless (< min max)
      (agent-ui--fail "gauge: min must be below max"))
    (cl-loop for th in (plist-get props :thresholds)
             for i from 1
             unless (and (agent-ui--plist-p th) (numberp (plist-get th :at))
                         (member (format "%s" (plist-get th :face))
                                 '("plain" "muted" "success" "warning" "error" "accent")))
             do (agent-ui--fail "gauge: threshold %d is {\"at\": a number, \"face\": success, warning, error...}" i)))
  props)

(defun agent-ui-gauge--fraction (props value)
  (let ((min (plist-get props :min)) (max (plist-get props :max)))
    (max 0.0 (min 1.0 (/ (float (- value min)) (- max min))))))

;; ====== AS TEXT ======

(defun agent-ui-gauge--bar (props width)
  "PROPS' bar, WIDTH cells: filled to its value in its zone's face, the
rest of the track in each zone's, dimmed; its target a ┃."
  (let* ((min (plist-get props :min)) (max (plist-get props :max))
         (value (plist-get props :value))
         (zones (agent-ui-gauge--zones props))
         (face (agent-ui-gauge--face zones value))
         (filled (round (* width (agent-ui-gauge--fraction props value))))
         (target (plist-get props :target))
         (target-cell (and target (min (1- width) (floor (* width (agent-ui-gauge--fraction props target)))))))
    (apply #'concat
           (cl-loop for i below width
                    collect (cond
                             ((eql i target-cell) (propertize "┃" 'face 'bold))
                             ((< i filled) (propertize "█" 'face face))
                             (t (let ((at (+ min (* (- max min) (/ (+ i 0.5) width)))))
                                  (propertize "░" 'face (if zones (agent-ui-gauge--face zones at) 'agent-ui-muted)))))))))

(defun agent-ui-gauge--text (props ctx)
  "Its label, its bar (8 cells at least, 40 at most), its value and target:
on a line while they fit, the target left out first; else the label on a
line of its own above (it was left out: \"lines covered\" gone at 24)."
  (let* ((width (plist-get ctx :width))
         (value (plist-get props :value))
         (face (agent-ui-gauge--face (agent-ui-gauge--zones props) value))
         (shown (propertize (agent-ui-gauge--shown props value) 'face `(:inherit ,face :weight bold)))
         (target (and (plist-get props :target)
                      (propertize (concat "target " (agent-ui-gauge--shown props (plist-get props :target)))
                                  'face 'agent-ui-muted)))
         (label (plist-get props :label))
         (full (concat "  " shown (if target (concat "  " target) "")))
         (short (concat "  " shown))
         ;; The room for the bar beside AFTER and maybe the label.
         (room (lambda (after beside) (- width (string-width after) (if beside (+ 2 (string-width label)) 0))))
         (after (cond ((and label (>= (funcall room full t) 8)) full)
                      ((and label (>= (funcall room short t) 8)) short)
                      ((>= (funcall room full nil) 8) full)
                      (t short)))
         (beside (and label (>= (funcall room after t) 8)))
         (bar-width (max 3 (min 40 (funcall room after beside)))))
    (concat (cond (beside (concat label "  "))
                  (label (concat (agent-ui-truncate label width) "\n"))
                  (t ""))
            (agent-ui-gauge--bar props bar-width)
            (agent-ui-truncate after (max 0 (- width bar-width (if beside (+ 2 (string-width label)) 0)))))))

;; ====== AS SVG ======

(defun agent-ui-gauge--point (cx cy r f)
  "The point of a half circle (CX CY, R) at fraction F, from its left."
  (let ((angle (* float-pi (- 1 f))))
    (cons (+ cx (* r (cos angle))) (- cy (* r (sin angle))))))

(defun agent-ui-gauge--arc (svg cx cy r from to color width)
  "An arc of the half circle from fraction FROM to TO in COLOR, WIDTH wide."
  (when (> to from)
    (let ((a (agent-ui-gauge--point cx cy r from))
          (b (agent-ui-gauge--point cx cy r to)))
      (svg-node svg 'path :fill "none" :stroke color :stroke-width width
                :d (format "M %.2f %.2f A %.2f %.2f 0 0 1 %.2f %.2f" (car a) (cdr a) r r (car b) (cdr b))))))

(defun agent-ui-gauge--gui (props ctx)
  (let* ((cw (plist-get ctx :char-width))
         (lh (plist-get ctx :line-height))
         (w (min (* cw (plist-get ctx :width)) (* 30 cw)))
         (stroke (max 4 (round (* 0.55 lh))))
         (r (- (/ w 2.0) stroke))
         ;; The arc, its ends' numbers under it, then the label's row.
         (h (round (+ r stroke (* 2.3 lh))))
         (cx (/ w 2.0))
         (cy (+ r (/ stroke 2.0) 2))
         (min (plist-get props :min)) (max (plist-get props :max))
         (value (plist-get props :value))
         (zones (agent-ui-gauge--zones props))
         (face (agent-ui-gauge--face zones value))
         (bg (agent-ui-background))
         (font (agent-ui--svg-font))
         (svg (svg-create w h)))
    (if (< r (* 2 cw))
        (agent-ui-gauge--text props ctx)
      ;; Its track: each zone in its colour, dimmed (no zones: muted).
      (if (null zones)
          (agent-ui-gauge--arc svg cx cy r 0 1 (agent-ui-blend bg (agent-ui-color 'agent-ui-muted) 0.5) stroke)
        (cl-loop for (zone . rest) on (cons (cons min (cdr (car zones))) zones)
                 for from = (agent-ui-gauge--fraction props (car zone))
                 for to = (if rest (agent-ui-gauge--fraction props (car (car rest))) 1.0)
                 do (agent-ui-gauge--arc svg cx cy r from to
                                         (agent-ui-blend bg (agent-ui-color (agent-ui-gauge--face zones (car zone))) 0.3)
                                         stroke)))
      ;; Its value.
      (agent-ui-gauge--arc svg cx cy r 0 (agent-ui-gauge--fraction props value) (agent-ui-color face) stroke)
      ;; Its target: a tick across the track.
      (when-let* ((target (plist-get props :target)))
        (let ((in (agent-ui-gauge--point cx cy (- r stroke) (agent-ui-gauge--fraction props target)))
              (out (agent-ui-gauge--point cx cy (+ r stroke) (agent-ui-gauge--fraction props target))))
          (svg-line svg (car in) (cdr in) (car out) (cdr out) :stroke (agent-ui-color 'default) :stroke-width 2)))
      ;; Its value inside the arc: smaller if it's wider than the arc's
      ;; inside (it was clipped both sides, or ran over the arc).
      (let ((shown (agent-ui-gauge--shown props value)))
        (svg-text svg shown :x cx :y (- cy (* 0.15 lh)) :text-anchor "middle"
                  :font-size (round (agent-ui-svg-fit-size shown (* 1.3 lh) (* 1.8 (- r stroke))))
                  :font-weight "bold" :font-family font :fill (agent-ui-color face)))
      (let ((under (string-join (delq nil (list (plist-get props :label)
                                                (and (plist-get props :target)
                                                     (concat "target " (agent-ui-gauge--shown props (plist-get props :target))))))
                                " · ")))
        (unless (string-empty-p under)
          ;; Cut to the width: a character of its font (0.75 of a line)
          ;; about 0.47 of a line wide.
          (svg-text svg (agent-ui-truncate under (floor w (* 0.47 lh)))
                    :x cx :y (+ cy (* 2.0 lh)) :text-anchor "middle"
                    :font-size (round (* 0.75 lh)) :font-family font :fill (agent-ui-color 'agent-ui-muted))))
      ;; Its range's ends under the arc's: smaller if they'd meet.
      (let* ((ends (concat (agent-ui-format-number min) "  " (agent-ui-format-number max)))
             (size (agent-ui-svg-fit-size ends (* 0.7 lh) (+ (* 2 r) stroke))))
        (dolist (end (list (cons min "start") (cons max "end")))
          (svg-text svg (agent-ui-format-number (car end))
                    :x (if (equal (cdr end) "start") (- cx r (/ stroke 2.0)) (+ cx r (/ stroke 2.0)))
                    :y (+ cy (* 0.9 lh)) :text-anchor (cdr end)
                    :font-size (round size) :font-family font :fill (agent-ui-color 'agent-ui-muted))))
      (propertize "gauge" 'display (agent-ui-svg-image svg)))))

(agent-ui-define gauge
  "One value against its range and thresholds: coverage against a target, a
budget used, a latency against an SLO. VALUE of MIN (0) to MAX (100), UNIT,
LABEL; THRESHOLDS are zones, each {\"at\", \"face\"} colouring from AT up to
the next (success, warning, error...); TARGET a mark. A bar in text, an arc
in the GUI; several side by side in a panel's row."
  :props ((value number "The value" :required t)
          (min number "Its range's start" :default 0)
          (max number "Its range's end" :default 100)
          (unit string "Its unit: %, ms, MB")
          (label string "What it measures")
          (thresholds list "Zones: [{\"at\": 0, \"face\": \"error\"}, {\"at\": 80, \"face\": \"success\"}]")
          (target number "A mark: the target, the limit"))
  :example (:title "Coverage" :value 78 :unit "%" :target 80 :label "lines covered"
            :thresholds ((:at 0 :face "error") (:at 70 :face "warning") (:at 80 :face "success")))
  :check #'agent-ui-gauge--check
  :text #'agent-ui-gauge--text
  :gui #'agent-ui-gauge--gui)
