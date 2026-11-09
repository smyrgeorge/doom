;;; $DOOMDIR/config/agent-ui/elements/chart.el -*- lexical-binding: t; -*-
;; Agent UI's chart: lines, bars or a sparkline. Loaded from
;; config/agent-ui/elements.el.
;;
;; One series of values or several. In a terminal, drawn with characters
;; (braille dots for lines, blocks for bars); in a graphic frame, as SVG in the
;; theme's colours, sized to the text. Values appended to it (a live chart)
;; keep their latest WINDOW.
;;
;;   180 ┤    ⢀⠔⠢⡀
;;       │ ⡠⠊    ⠈⠢⡀
;;    60 ┤⠊        ⠈⠢
;;       mon        thu

(require 'cl-lib)
(require 'subr-x)
(require 'svg)

(defconst agent-ui-chart-faces
  '(agent-ui-accent agent-ui-warning font-lock-constant-face agent-ui-success agent-ui-error
    font-lock-type-face)
  "Each series' face, in turn.")

(defconst agent-ui-chart--levels ["▁" "▂" "▃" "▄" "▅" "▆" "▇" "█"]
  "A sparkline's characters, lowest first.")

(defconst agent-ui-chart--eighths [" " "▏" "▎" "▍" "▌" "▋" "▊" "▉"]
  "A bar's last cell, by eighths.")

(defconst agent-ui-chart--dots [[#x01 #x02 #x04 #x40] [#x08 #x10 #x20 #x80]]
  "Braille's dots: [COLUMN][ROW], a character 2 dots wide and 4 high.")

;; ====== CHECKING ======

(defun agent-ui-chart--numbers (values what)
  (cl-loop for v in values
           for i from 1
           unless (numberp v)
           do (agent-ui--fail "chart: %s must be numbers; value %d is %s" what i (agent-ui--show-value v)))
  values)

(defun agent-ui-chart--series (props)
  "PROPS' values or series as a list of (:name NAME :values NUMBERS)."
  (let ((values (plist-get props :values))
        (series (plist-get props :series)))
    (when (and values series)
      (agent-ui--fail "chart: give values (one series) or series, not both"))
    (if series
        (cl-loop for s in series
                 for i from 1
                 collect (progn
                           (unless (agent-ui--plist-p s)
                             (agent-ui--fail "chart: series %d must be {\"name\": ..., \"values\": [...]}" i))
                           (cl-loop for (k _) on s by #'cddr
                                    unless (memq k '(:name :values))
                                    do (agent-ui--fail "chart: series %d has %s: a series has name, values"
                                                       i (agent-ui--show-value (substring (symbol-name k) 1))))
                           (let ((name (plist-get s :name)))
                             (unless (or (null name) (stringp name))
                               (agent-ui--fail "chart: series %d's name must be text" i))
                             (list :name name
                                   :values (agent-ui-chart--numbers
                                            (plist-get s :values)
                                            (format "series %d's values" i))))))
      (list (list :name nil :values (agent-ui-chart--numbers values "values"))))))

(defun agent-ui-chart--check (props)
  (let* ((series (agent-ui-chart--series props))
         (kind (plist-get props :kind))
         (window (plist-get props :window))
         (height (plist-get props :height)))
    (when (and (memq kind '(bar sparkline)) (> (length series) 1))
      (agent-ui--fail "chart: a %s chart has one series: give values" kind))
    (when (and window (< window 1))
      (agent-ui--fail "chart: window must be 1 or more, not %d" window))
    (unless (<= 2 height 40)
      (agent-ui--fail "chart: height must be from 2 to 40 lines, not %d" height))
    (let ((min (plist-get props :min)) (max (plist-get props :max)))
      (when (and min max (>= min max))
        (agent-ui--fail "chart: min must be below max")))
    (let* ((labels (mapcar #'agent-ui-cell (plist-get props :labels)))
           (keep (or window agent-ui-max-rows)))
      ;; The latest KEEP values; labels as many from the end as the longest
      ;; series lost.
      (let ((longest (apply #'max 0 (mapcar (lambda (s) (length (plist-get s :values))) series))))
        (when (> longest keep)
          (setq labels (if (> (length labels) keep) (last labels keep) labels))))
      (setq series (mapcar (lambda (s)
                             (let ((values (plist-get s :values)))
                               (plist-put (copy-sequence s) :values
                                          (if (> (length values) keep) (last values keep) values))))
                           series))
      (plist-put (plist-put props :series series) :labels labels))))

(defun agent-ui-chart--append (element patch)
  "ELEMENT with PATCH's values added: :values to its values; :series by name
to each's (a new name, a new series); :labels to its labels."
  (cl-loop for (k _) on patch by #'cddr
           unless (memq k '(:id :values :series :labels))
           do (agent-ui--fail "chart: only values, series and labels can be appended to"))
  (let ((result (copy-sequence element)))
    (when-let* ((values (plist-get patch :values)))
      (setq result (plist-put result :values (append (plist-get element :values) values))))
    (when-let* ((labels (plist-get patch :labels)))
      (setq result (plist-put result :labels (append (plist-get element :labels) labels))))
    (when-let* ((added (plist-get patch :series)))
      (let ((series (copy-sequence (plist-get element :series))))
        (dolist (s added)
          (let* ((name (and (agent-ui--plist-p s) (plist-get s :name)))
                 (at (cl-position name series :key (lambda (x) (and (agent-ui--plist-p x) (plist-get x :name)))
                                  :test #'equal)))
            (if at
                (setf (nth at series)
                      (plist-put (copy-sequence (nth at series)) :values
                                 (append (plist-get (nth at series) :values) (plist-get s :values))))
              (setq series (append series (list s))))))
        (setq result (plist-put result :series series))))
    result))

;; ====== SCALE ======

(defun agent-ui-chart--range (props)
  "(LOW . HIGH) the chart spans: PROPS' min and max, else its values' (bars
from 0)."
  (let* ((values (apply #'append (mapcar (lambda (s) (plist-get s :values)) (plist-get props :series))))
         (low (or (plist-get props :min)
                  (if (eq (plist-get props :kind) 'bar)
                      (min 0 (apply #'min 0 values))
                    (if values (apply #'min values) 0))))
         (high (or (plist-get props :max) (if values (apply #'max values) 1))))
    (cons low (if (<= high low) (+ low 1) high))))

(defun agent-ui-chart--number (props number)
  "NUMBER as the chart shows it, with PROPS' unit."
  (let ((unit (plist-get props :unit)))
    (concat (agent-ui-format-number number)
            (if (and unit (not (string-empty-p unit))) (concat " " unit) ""))))

(defun agent-ui-chart--face (index)
  (nth (mod index (length agent-ui-chart-faces)) agent-ui-chart-faces))

(defun agent-ui-chart--empty-p (props)
  (cl-every (lambda (s) (null (plist-get s :values))) (plist-get props :series)))

(defun agent-ui-chart--legend (props)
  "The series' names, each in its colour; nil if none is named."
  (let ((series (plist-get props :series)))
    (when (seq-some (lambda (s) (plist-get s :name)) series)
      (string-join (cl-loop for s in series
                            for i from 0
                            collect (concat (propertize "●" 'face (agent-ui-chart--face i)) " "
                                            (or (plist-get s :name) "")))
                   "  "))))

;; ====== AS TEXT ======

(defun agent-ui-chart--sparkline (props ctx)
  (let* ((values (plist-get (car (plist-get props :series)) :values))
         (range (agent-ui-chart--range props))
         (low (car range)) (span (float (- (cdr range) low)))
         (suffix (format "  last %s  min %s  max %s"
                         (agent-ui-chart--number props (car (last values)))
                         (agent-ui-format-number (apply #'min values))
                         (agent-ui-format-number (apply #'max values))))
         (room (max 4 (- (plist-get ctx :width) (string-width suffix))))
         (shown (last values room)))
    (concat (propertize (mapconcat (lambda (v)
                                     (aref agent-ui-chart--levels
                                           (max 0 (min 7 (floor (* 8 (/ (- v low) span)))))))
                                   shown "")
                        'face 'agent-ui-accent)
            (propertize suffix 'face 'agent-ui-muted))))

(defun agent-ui-chart--bar-text (props ctx)
  (let* ((values (plist-get (car (plist-get props :series)) :values))
         (labels (plist-get props :labels))
         (names (cl-loop for i from 0 below (length values)
                         collect (or (nth i labels) (number-to-string (1+ i)))))
         (width (plist-get ctx :width))
         (label-width (min (apply #'max 0 (mapcar #'string-width names)) (/ width 3)))
         (numbers (mapcar (lambda (v) (agent-ui-chart--number props v)) values))
         (value-width (apply #'max 0 (mapcar #'string-width numbers)))
         (bar-width (max 5 (- width label-width value-width 4)))
         (high (float (cdr (agent-ui-chart--range props)))))
    (mapconcat
     (lambda (i)
       (let* ((cells (* bar-width (max 0.0 (min 1.0 (/ (nth i values) high)))))
              (full (floor cells))
              (part (if (< full bar-width) (floor (* (- cells full) 8)) 0))
              (bar (concat (make-string full ?█)
                           (if (> part 0) (aref agent-ui-chart--eighths part) ""))))
         (concat (agent-ui-pad (nth i names) label-width) "  "
                 (propertize bar 'face 'agent-ui-accent)
                 (make-string (- bar-width (length bar)) ?\s) "  "
                 (agent-ui-pad (nth i numbers) value-width 'right))))
     (number-sequence 0 (1- (length values))) "\n")))

(defun agent-ui-chart--plot (series range columns rows)
  "SERIES' values drawn on a grid of braille characters, COLUMNS wide and
ROWS high, spanning RANGE (LOW . HIGH): (BITS . OWNERS), vectors by cell, each
cell's dots and the series that drew it last."
  (let* ((bits (make-vector (* columns rows) 0))
         (owners (make-vector (* columns rows) nil))
         (width (* 2 columns)) (height (* 4 rows))
         (low (car range)) (span (float (- (cdr range) (car range)))))
    (cl-flet ((dot (x y index)
                (let ((cell (+ (* (/ y 4) columns) (/ x 2))))
                  (aset bits cell (logior (aref bits cell)
                                          (aref (aref agent-ui-chart--dots (% x 2)) (% y 4))))
                  (aset owners cell index)))
              (y-of (v) (- height 1 (max 0 (min (1- height) (round (* (1- height) (/ (- v low) span))))))))
      (cl-loop
       for s in series
       for index from 0
       do (let* ((values (vconcat (plist-get s :values)))
                 (n (length values)))
            (cond
             ((= n 0))
             ((= n 1) (dot 0 (y-of (aref values 0)) index))
             (t
              (let ((x-of (lambda (i) (round (* i (/ (float (1- width)) (1- n))))))
                    (previous (y-of (aref values 0))))
                (dotimes (i (1- n))
                  (let ((x0 (funcall x-of i)) (x1 (funcall x-of (1+ i)))
                        (y0 (y-of (aref values i))) (y1 (y-of (aref values (1+ i)))))
                    (cl-loop for x from x0 to x1
                             do (let ((y (if (= x1 x0) y1
                                           (round (+ y0 (* (- y1 y0) (/ (float (- x x0)) (- x1 x0))))))))
                                  ;; Joined to the dot before: no gaps on a steep line.
                                  (cl-loop for yy from (min previous y) to (max previous y)
                                           do (dot x yy index))
                                  (setq previous y)))))))))))
    (cons bits owners)))

(defun agent-ui-chart--line-text (props ctx)
  (let* ((range (agent-ui-chart--range props))
         (high-label (agent-ui-chart--number props (cdr range)))
         (low-label (agent-ui-chart--number props (car range)))
         (label-width (max (string-width high-label) (string-width low-label)))
         (columns (max 4 (- (plist-get ctx :width) label-width 2)))
         (rows (plist-get props :height))
         (plot (agent-ui-chart--plot (plist-get props :series) range columns rows))
         (labels (plist-get props :labels))
         (legend (agent-ui-chart--legend props)))
    (concat
     (mapconcat
      (lambda (row)
        (concat
         (propertize (agent-ui-pad (cond ((= row 0) high-label) ((= row (1- rows)) low-label) (t ""))
                                   label-width 'right)
                     'face 'agent-ui-muted)
         (propertize (if (memq row (list 0 (1- rows))) " ┤" " │") 'face 'agent-ui-muted)
         (mapconcat (lambda (column)
                      (let* ((cell (+ (* row columns) column))
                             (bits (aref (car plot) cell)))
                        (if (= bits 0)
                            " "
                          (propertize (string (+ #x2800 bits))
                                      'face (agent-ui-chart--face (aref (cdr plot) cell))))))
                    (number-sequence 0 (1- columns)) "")))
      (number-sequence 0 (1- rows)) "\n")
     ;; The first and last labels, under the plot's ends.
     (when labels
       (let ((first (car labels))
             (last (if (cdr labels) (car (last labels)) "")))
         (concat "\n" (make-string (+ label-width 2) ?\s)
                 (propertize (agent-ui-pad first (- columns (string-width last) 1)) 'face 'agent-ui-muted)
                 " "
                 (propertize last 'face 'agent-ui-muted))))
     (when legend (concat "\n" (make-string (+ label-width 2) ?\s) legend)))))

(defun agent-ui-chart--text (props ctx)
  (if (agent-ui-chart--empty-p props)
      (propertize "no values yet" 'face 'agent-ui-muted)
    (pcase (plist-get props :kind)
      ('sparkline (agent-ui-chart--sparkline props ctx))
      ('bar (agent-ui-chart--bar-text props ctx))
      (_ (agent-ui-chart--line-text props ctx)))))

;; ====== AS SVG ======

(defun agent-ui-chart--color (face)
  "FACE's colour, for SVG (a grey where faces have none: in batch)."
  (let ((color (face-foreground face nil 'default)))
    (if (and color (string-prefix-p "#" color)) color
      (or (and color (not (string-prefix-p "unspecified" color)) color) "#888888"))))

(defun agent-ui-chart--image (svg)
  "SVG as text showing it."
  (propertize "chart" 'display (svg-image svg :scale 1 :ascent 'center)))

(defun agent-ui-chart--svg-text (svg ctx text x y &rest args)
  (apply #'svg-text svg text :x x :y y
         :font-size (round (* 0.8 (plist-get ctx :line-height)))
         :font-family (let ((family (face-attribute 'default :family nil t)))
                        (if (and (stringp family) (not (member family '("default" "unspecified"))))
                            family
                          "monospace"))
         args))

(defun agent-ui-chart--line-svg (props ctx)
  (let* ((cw (plist-get ctx :char-width))
         (lh (plist-get ctx :line-height))
         (range (agent-ui-chart--range props))
         (low (car range)) (span (float (- (cdr range) low)))
         (high-label (agent-ui-chart--number props (cdr range)))
         (low-label (agent-ui-chart--number props low))
         (label-width (* cw (+ 1 (max (string-width high-label) (string-width low-label)))))
         (labels (plist-get props :labels))
         (legend (seq-some (lambda (s) (plist-get s :name)) (plist-get props :series)))
         (width (* cw (plist-get ctx :width)))
         (plot-height (* lh (plist-get props :height)))
         ;; Room above the plot for its top label's letters.
         (top (round (* 0.8 lh)))
         (height (+ plot-height (if labels lh 0) (if legend lh 0) (/ lh 2)))
         (left (+ label-width cw))
         (right (- width cw))
         (muted (agent-ui-chart--color 'agent-ui-muted))
         (svg (svg-create width height)))
    (cl-flet ((y-of (v) (+ top (* (- plot-height top) (- 1 (/ (- v low) span))))))
      (svg-line svg left top left (+ top (- plot-height top)) :stroke muted :stroke-width 1)
      (agent-ui-chart--svg-text svg ctx high-label (- left (/ cw 2)) (+ top (/ lh 3))
                                :fill muted :text-anchor "end")
      (agent-ui-chart--svg-text svg ctx low-label (- left (/ cw 2)) plot-height
                                :fill muted :text-anchor "end")
      (cl-loop
       for s in (plist-get props :series)
       for index from 0
       do (let* ((values (plist-get s :values))
                 (n (length values))
                 (color (agent-ui-chart--color (agent-ui-chart--face index)))
                 (points (cl-loop for v in values
                                  for i from 0
                                  collect (cons (if (= n 1) left
                                                  (+ left (* (- right left) (/ (float i) (1- n)))))
                                                (y-of v)))))
            (if (= n 1)
                (svg-circle svg (caar points) (cdar points) 2.5 :fill color)
              (when points
                (svg-polyline svg points :fill "none" :stroke color :stroke-width 2
                              :stroke-linejoin "round" :stroke-linecap "round"))))))
    (when labels
      (agent-ui-chart--svg-text svg ctx (car labels) left (+ plot-height lh) :fill muted)
      (when (cdr labels)
        (agent-ui-chart--svg-text svg ctx (car (last labels)) right (+ plot-height lh)
                                  :fill muted :text-anchor "end")))
    (when legend
      (let ((x left)
            (y (+ plot-height (if labels lh 0) lh)))
        (cl-loop for s in (plist-get props :series)
                 for index from 0
                 do (let ((name (or (plist-get s :name) "")))
                      (svg-circle svg (+ x (/ cw 2)) (- y (/ lh 3)) (/ cw 2.5)
                                  :fill (agent-ui-chart--color (agent-ui-chart--face index)))
                      (agent-ui-chart--svg-text svg ctx name (+ x (* 1.5 cw)) y
                                                :fill (agent-ui-chart--color 'default))
                      (setq x (+ x (* cw (+ 4 (string-width name)))))))))
    (agent-ui-chart--image svg)))

(defun agent-ui-chart--bar-svg (props ctx)
  (let* ((cw (plist-get ctx :char-width))
         (lh (plist-get ctx :line-height))
         (values (plist-get (car (plist-get props :series)) :values))
         (labels (plist-get props :labels))
         (names (cl-loop for i from 0 below (length values)
                         collect (or (nth i labels) (number-to-string (1+ i)))))
         (numbers (mapcar (lambda (v) (agent-ui-chart--number props v)) values))
         (columns (plist-get ctx :width))
         (label-width (* cw (min (apply #'max 0 (mapcar #'string-width names)) (/ columns 3))))
         (value-width (* cw (apply #'max 0 (mapcar #'string-width numbers))))
         (width (* cw columns))
         (bar-left (+ label-width (* 2 cw)))
         (bar-width (max (* 5 cw) (- width bar-left value-width (* 2 cw))))
         (high (float (cdr (agent-ui-chart--range props))))
         (row (round (* 1.4 lh)))
         (svg (svg-create width (* row (length values))))
         (fg (agent-ui-chart--color 'default))
         (color (agent-ui-chart--color 'agent-ui-accent)))
    (cl-loop for v in values
             for name in names
             for number in numbers
             for i from 0
             do (let ((y (* i row))
                      (length (* bar-width (max 0.0 (min 1.0 (/ v high))))))
                  (agent-ui-chart--svg-text svg ctx (agent-ui-truncate name (/ label-width cw))
                                            0 (+ y (* 0.7 row)) :fill fg)
                  (svg-rectangle svg bar-left (+ y (* 0.2 row)) (max 1 length) (* 0.6 row)
                                 :fill color :rx 2)
                  (agent-ui-chart--svg-text svg ctx number (+ bar-left length cw) (+ y (* 0.7 row))
                                            :fill (agent-ui-chart--color 'agent-ui-muted))))
    (agent-ui-chart--image svg)))

(defun agent-ui-chart--gui (props ctx)
  (if (agent-ui-chart--empty-p props)
      (agent-ui-chart--text props ctx)
    (pcase (plist-get props :kind)
      ('bar (agent-ui-chart--bar-svg props ctx))
      ('line (agent-ui-chart--line-svg props ctx))
      ;; A sparkline is a line of text: as in a terminal.
      (_ (agent-ui-chart--text props ctx)))))

(agent-ui-define chart
  "A chart of numbers: KIND line (default; several series, each its colour),
bar (one series, a bar per value, LABELS naming them) or sparkline (one
line, the latest values). As SVG in a graphic frame, as characters in a
terminal. For a live chart, append values: {\"values\": [42]} (or
{\"series\": [{\"name\": \"p95\", \"values\": [42]}]}), WINDOW keeping the
latest so many."
  :props ((kind (choice line bar sparkline) "line, bar or sparkline" :default line)
          (values list "The numbers (one series)")
          (series list "Several series: [{\"name\": ..., \"values\": [...]}]")
          (labels list "Names for the values, in order (x axis; a bar's name)")
          (unit string "What the numbers count (ms, MB), after them")
          (min number "The lowest the axis shows (default: the values', bars from 0)")
          (max number "The highest the axis shows (default: the values')")
          (height integer "A line chart's height, in lines" :default 8)
          (window integer "Keep only the latest so many values (a live chart)"))
  :example (:title "p95 latency" :kind "bar" :unit "ms"
            :labels ("mon" "tue" "wed" "thu") :values (120 95 180 60))
  :check #'agent-ui-chart--check
  :append #'agent-ui-chart--append
  :text #'agent-ui-chart--text
  :gui #'agent-ui-chart--gui)
