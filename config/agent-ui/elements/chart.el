;;; $DOOMDIR/config/agent-ui/elements/chart.el -*- lexical-binding: t; -*-
;; Agent UI's chart: lines, bars, a histogram or a sparkline. Loaded from
;; config/agent-ui/elements.el.
;;
;; One series of values or several: bars grouped by label, or stacked. A
;; histogram counts its values in bins. A line chart's values may have times:
;; placed by them, an axis of ticks under it (minutes, hours, days). In a terminal, drawn with characters
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
(require 'parse-time)

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

(defun agent-ui-chart--time (time)
  "TIME (seconds since 1970, or an ISO 8601 date and time) in seconds; nil
if it's neither."
  (cond
   ((numberp time) (float time))
   ((stringp time)
    (let ((text (if (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" time)
                    (concat time "T00:00:00")
                  time)))
      (ignore-errors (float-time (parse-iso8601-time-string text)))))))

(defun agent-ui-chart--check (props)
  (let* ((series (agent-ui-chart--series props))
         (kind (plist-get props :kind))
         (window (plist-get props :window))
         (height (plist-get props :height)))
    (when (and (memq kind '(histogram sparkline)) (> (length series) 1))
      (agent-ui--fail "chart: a %s chart has one series: give values" kind))
    (let ((bins (plist-get props :bins)))
      (when (and bins (not (<= 1 bins 50)))
        (agent-ui--fail "chart: bins must be from 1 to 50, not %d" bins)))
    (when (and window (< window 1))
      (agent-ui--fail "chart: window must be 1 or more, not %d" window))
    (unless (<= 2 height 40)
      (agent-ui--fail "chart: height must be from 2 to 40 lines, not %d" height))
    (let ((min (plist-get props :min)) (max (plist-get props :max)))
      (when (and min max (>= min max))
        (agent-ui--fail "chart: min must be below max")))
    (let* ((labels (mapcar #'agent-ui-cell (plist-get props :labels)))
           (times (cl-loop for time in (plist-get props :times)
                           for i from 1
                           collect (or (agent-ui-chart--time time)
                                       (agent-ui--fail "chart: time %d is %s: a date and time (2026-11-10T14:30:00) or seconds since 1970"
                                                       i (agent-ui--show-value time)))))
           ;; A histogram keeps all its values: it counts them.
           (keep (or window (if (eq kind 'histogram) 100000 agent-ui-max-rows))))
      ;; The latest KEEP values; labels as many from the end as the longest
      ;; series lost.
      (let ((longest (apply #'max 0 (mapcar (lambda (s) (length (plist-get s :values))) series))))
        (when (> longest keep)
          (setq labels (if (> (length labels) keep) (last labels keep) labels)
                times (if (> (length times) keep) (last times keep) times))))
      (setq series (mapcar (lambda (s)
                             (let ((values (plist-get s :values)))
                               (plist-put (copy-sequence s) :values
                                          (if (> (length values) keep) (last values keep) values))))
                           series))
      ;; A time for each value (fewer broke the drawing, more squeezed the
      ;; line): an append of values without their times, refused.
      (let ((values (apply #'max 0 (mapcar (lambda (s) (length (plist-get s :values))) series))))
        (when (and times (/= (length times) values))
          (agent-ui--fail "chart: %d values but %d times: give a time for each value (append them together)"
                          values (length times))))
      (plist-put (plist-put (plist-put props :series series) :labels labels) :times times))))

(defun agent-ui-chart--append (element patch)
  "ELEMENT with PATCH's values added: :values to its values; :series by name
to each's (a new name, a new series); :labels to its labels."
  (cl-loop for (k _) on patch by #'cddr
           unless (memq k '(:id :values :series :labels :times))
           do (agent-ui--fail "chart: only values, series, labels and times can be appended to"))
  (let ((result (copy-sequence element)))
    (when-let* ((values (plist-get patch :values)))
      (setq result (plist-put result :values (append (plist-get element :values) values))))
    (when-let* ((labels (plist-get patch :labels)))
      (setq result (plist-put result :labels (append (plist-get element :labels) labels))))
    (when-let* ((times (plist-get patch :times)))
      (setq result (plist-put result :times (append (plist-get element :times) times))))
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

(defun agent-ui-chart--stacked-p (props)
  "Whether PROPS are bars of several series, stacked."
  (and (eq (plist-get props :kind) 'bar) (eq (plist-get props :stacked) t)
       (cdr (plist-get props :series)) t))

(defun agent-ui-chart--totals (series)
  "SERIES' values added up, label by label (negatives as 0)."
  (let ((n (apply #'max 0 (mapcar (lambda (s) (length (plist-get s :values))) series))))
    (cl-loop for i below n
             collect (apply #'+ (mapcar (lambda (s) (max 0 (or (nth i (plist-get s :values)) 0))) series)))))

(defun agent-ui-chart--above (low)
  "A number clearly above LOW, for a range of equal values: LOW + 1, or more
for a huge LOW (1e17 + 1 is 1e17 as a float: a span of 0, and the drawing
broke)."
  (let ((high (+ low (max 1 (* 1e-6 (abs low))))))
    (if (> high low) high (+ low (abs low)))))

(defun agent-ui-chart--range (props)
  "(LOW . HIGH) the chart spans: PROPS' min and max, else its values' (bars
from 0)."
  (let* ((values (if (agent-ui-chart--stacked-p props)
                     (agent-ui-chart--totals (plist-get props :series))
                   (apply #'append (mapcar (lambda (s) (plist-get s :values)) (plist-get props :series)))))
         (low (or (plist-get props :min)
                  (if (eq (plist-get props :kind) 'bar)
                      (min 0 (apply #'min 0 values))
                    (if values (apply #'min values) 0))))
         (high (or (plist-get props :max) (if values (apply #'max values) 1))))
    (cons low (if (<= high low) (agent-ui-chart--above low) high))))

(defun agent-ui-chart--bar-from (props)
  "Where PROPS' bars start: their min if given (ignored, bars started at 0
whatever it said), else 0; stacked bars at 0 (their parts add up from it)."
  (if (and (plist-get props :min) (not (agent-ui-chart--stacked-p props)))
      (plist-get props :min)
    0))

(defun agent-ui-chart--bar-scale (props width)
  "How long a bar of 1 is, WIDTH long from where bars start to the highest:
0 if nothing's above that (it divided by 0, and the drawing broke: values
all 0 or below)."
  (let ((high (cdr (agent-ui-chart--range props)))
        (from (agent-ui-chart--bar-from props)))
    (if (> high from) (/ width (float (- high from))) 0.0)))

(defun agent-ui-chart--number (props number)
  "NUMBER as the chart shows it, with PROPS' unit."
  (let ((unit (plist-get props :unit)))
    (concat (agent-ui-format-number number)
            (if (and unit (not (string-empty-p unit))) (concat " " unit) ""))))

(defun agent-ui-chart--face (index)
  (nth (mod index (length agent-ui-chart-faces)) agent-ui-chart-faces))

(defun agent-ui-chart--empty-p (props)
  (cl-every (lambda (s) (null (plist-get s :values))) (plist-get props :series)))

(defun agent-ui-chart--legend-rows (series columns)
  "SERIES' names packed into rows of COLUMNS: ((INDEX . NAME) ...) each, an
item 4 columns and its name (a dot, a space; two between items), a name cut
to fit a row (one row, never cut, ran past the width)."
  (let ((rows nil) (row nil) (used 0))
    (cl-loop for s in series
             for i from 0
             do (let* ((name (agent-ui-truncate (or (plist-get s :name) "") (max 1 (- columns 4))))
                       (w (+ 4 (string-width name))))
                  (when (and row (> (+ used w) (+ columns 2)))
                    (push (nreverse row) rows)
                    (setq row nil used 0))
                  (push (cons i name) row)
                  (setq used (+ used w))))
    (when row (push (nreverse row) rows))
    (nreverse rows)))

(defun agent-ui-chart--legend (props columns)
  "The series' names, each in its colour, as lines of COLUMNS; nil if none is
named."
  (let ((series (plist-get props :series)))
    (when (seq-some (lambda (s) (plist-get s :name)) series)
      (mapcar (lambda (row)
                (mapconcat (lambda (item) (concat (propertize "●" 'face (agent-ui-chart--face (car item))) " " (cdr item)))
                           row "  "))
              (agent-ui-chart--legend-rows series columns)))))

;; ====== AS TEXT ======

(defun agent-ui-chart--sparkline (props ctx)
  (let* ((values (plist-get (car (plist-get props :series)) :values))
         (range (agent-ui-chart--range props))
         (low (car range)) (span (float (- (cdr range) low)))
         (width (plist-get ctx :width))
         ;; Its figures, the last ones left out until the line fits (its
         ;; suffix was never cut: 46 columns at 30).
         (parts (list (format "last %s" (agent-ui-chart--number props (car (last values))))
                      (format "min %s" (agent-ui-format-number (apply #'min values)))
                      (format "max %s" (agent-ui-format-number (apply #'max values)))))
         (suffix (progn
                   (while (and parts (> (+ 4 2 (string-width (string-join parts "  "))) width))
                     (setq parts (butlast parts)))
                   (if parts (concat "  " (string-join parts "  ")) "")))
         (room (max 1 (- width (string-width suffix))))
         (shown (last values room)))
    (concat (propertize (mapconcat (lambda (v)
                                     (aref agent-ui-chart--levels
                                           (max 0 (min 7 (floor (* 8 (/ (- v low) span)))))))
                                   shown "")
                        'face 'agent-ui-accent)
            (propertize suffix 'face 'agent-ui-muted))))

(defun agent-ui-chart--bar-rows (props)
  "PROPS' bars, a row each: (NAME SEGMENTS NUMBER), SEGMENTS ((VALUE .
SERIES-INDEX) ...) from the left. One series: a bar per value; several,
grouped: a bar per series under each label (its name on the first);
stacked: a bar per label, its series end to end, their total its number."
  (let* ((series (plist-get props :series))
         (n (apply #'max 0 (mapcar (lambda (s) (length (plist-get s :values))) series)))
         (labels (plist-get props :labels))
         (from (agent-ui-chart--bar-from props))
         (value (lambda (s i) (max 0 (- (or (nth i (plist-get s :values)) 0) from)))))
    (cl-loop
     for i below n
     for name = (or (nth i labels) (number-to-string (1+ i)))
     append (cond
             ((agent-ui-chart--stacked-p props)
              (list (list name
                          (cl-loop for s in series for k from 0 collect (cons (funcall value s i) k))
                          (agent-ui-chart--number props (apply #'+ (mapcar (lambda (s) (funcall value s i)) series))))))
             (t
              (cl-loop for s in series
                       for k from 0
                       collect (list (if (= k 0) name "")
                                     (list (cons (funcall value s i) k))
                                     (agent-ui-chart--number props (or (nth i (plist-get s :values)) 0)))))))))

(defun agent-ui-chart--bar-cells (segments scale width)
  "SEGMENTS ((VALUE . INDEX) ...) as text, SCALE cells a unit, at most WIDTH
cells: each in its series' colour, whole cells but the last one's end (by
eighths)."
  (let* ((end (min width (* scale (apply #'+ (mapcar #'car segments)))))
         (at 0) (sum 0) (parts nil))
    (cl-loop for (v . k) in segments
             for rest on segments
             do (setq sum (+ sum v))
             (let* ((last (null (cdr rest)))
                    ;; Earlier parts end at a whole cell before their end
                    ;; (rounded up, a part could pass the bar's end: a stacked
                    ;; 99.5 came out longer than a 100).
                    (to (if last end (min width (floor (* scale sum)))))
                    (full (- (floor to) at))
                    (part (if (and last (< (floor to) width)) (floor (* (- to (floor to)) 8)) 0))
                    (text (concat (make-string (max 0 full) ?█)
                                  (if (> part 0) (aref agent-ui-chart--eighths part) ""))))
               (push (propertize text 'face (agent-ui-chart--face k)) parts)
               (setq at (+ at (max 0 full) (if (> part 0) 1 0)))))
    (let ((bar (apply #'concat (nreverse parts))))
      (concat bar (make-string (max 0 (- width (string-width bar))) ?\s)))))

(defun agent-ui-chart--bar-text (props ctx)
  (let* ((rows (agent-ui-chart--bar-rows props))
         (width (plist-get ctx :width))
         (label-width (min (apply #'max 0 (mapcar (lambda (r) (string-width (car r))) rows)) (/ width 3)))
         ;; Values a third of the width at most, cut (a long unit ran the
         ;; lines past the width); the bar a column at least.
         (value-width (min (apply #'max 0 (mapcar (lambda (r) (string-width (nth 2 r))) rows)) (/ width 3)))
         (bar-width (max 1 (- width label-width value-width 4)))
         (scale (agent-ui-chart--bar-scale props bar-width))
         (legend (and (cdr (plist-get props :series)) (agent-ui-chart--legend props (- width label-width 2)))))
    (concat
     (mapconcat
      (lambda (row)
        (concat (agent-ui-pad (agent-ui-truncate (car row) label-width) label-width) "  "
                (agent-ui-chart--bar-cells (nth 1 row) scale bar-width) "  "
                (agent-ui-pad (agent-ui-truncate (nth 2 row) value-width) value-width 'right)))
      rows "\n")
     (mapconcat (lambda (line) (concat "\n" (make-string (+ label-width 2) ?\s) line)) legend ""))))

(defun agent-ui-chart--plot (series range columns rows &optional xs)
  "SERIES' values drawn on a grid of braille characters, COLUMNS wide and
ROWS high, spanning RANGE (LOW . HIGH): (BITS . OWNERS), vectors by cell, each
cell's dots and the series that drew it last. XS: each value's place
across, 0 to 1 (by its time); else evenly."
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
             ((= n 1) (dot (if xs (round (* (car xs) (1- width))) 0) (y-of (aref values 0)) index))
             (t
              (let ((x-of (lambda (i) (if xs
                                          (round (* (nth i xs) (1- width)))
                                        (round (* i (/ (float (1- width)) (1- n)))))))
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

(defconst agent-ui-chart--steps
  '(1 2 5 10 15 30 60 120 300 600 900 1800 3600 7200 10800 21600 43200 86400 172800 604800 2592000)
  "A time axis's steps between ticks, in seconds: the first that fits.")

(defun agent-ui-chart--xs (props)
  "Each value's place across (0 to 1) by its time; nil without times."
  (when-let* ((times (plist-get props :times))
              ((cdr times)))
    (let ((t0 (apply #'min times)) (t1 (apply #'max times)))
      (mapcar (lambda (time) (if (= t1 t0) 0.0 (/ (- time t0) (- t1 t0)))) times))))

(defun agent-ui-chart--by-time (props)
  "PROPS with its points in time order: its times ascending, each series'
values and its labels moved with them (newest first, as git log gives
them, the text's plot drew nothing: it went left to right only)."
  (let ((times (plist-get props :times)))
    (if (or (null (cdr times)) (apply #'<= times))
        props
      (let* ((order (sort (number-sequence 0 (1- (length times)))
                          (lambda (a b) (< (nth a times) (nth b times)))))
             (pick (lambda (list) (if (and list (= (length list) (length times)))
                                      (mapcar (lambda (i) (nth i list)) order)
                                    list))))
        (thread-first (copy-sequence props)
                      (plist-put :times (funcall pick times))
                      (plist-put :labels (funcall pick (plist-get props :labels)))
                      (plist-put :series (mapcar (lambda (s) (plist-put (copy-sequence s) :values
                                                                        (funcall pick (plist-get s :values))))
                                                 (plist-get props :series))))))))

(defun agent-ui-chart--ticks (t0 t1 most)
  "Ticks between times T0 and T1, at most MOST, at round times (local
midnights, hours, minutes): ((PLACE . LABEL) ...), PLACE 0 to 1."
  (when (> t1 t0)
    (let* ((step (or (seq-find (lambda (s) (<= (/ (- t1 t0) s) most)) agent-ui-chart--steps)
                     (car (last agent-ui-chart--steps))))
           (offset (or (car (current-time-zone (seconds-to-time t0))) 0))
           (format (cond ((< step 60) "%H:%M:%S") ((< step 86400) "%H:%M") (t "%b %d")))
           (time (- (* step (ceiling (+ t0 offset) step)) offset))
           (ticks nil))
      (while (<= time t1)
        (push (cons (/ (- time t0) (float (- t1 t0))) (format-time-string format (seconds-to-time time))) ticks)
        (setq time (+ time step)))
      (nreverse ticks))))

(defun agent-ui-chart--time-axis (props columns)
  "Under a plot COLUMNS wide: its axis, ┬ at each tick, and the ticks'
labels under them (none on another's), as two lines; nil without times."
  (when-let* ((times (plist-get props :times))
              ((cdr times))
              (ticks (agent-ui-chart--ticks (apply #'min times) (apply #'max times)
                                            (max 2 (/ columns 10)))))
    (let ((axis (make-vector columns ?─))
          (labels (make-string columns ?\s))
          (free 0))
      (dolist (tick ticks)
        (let* ((column (min (1- columns) (floor (* (car tick) (1- (* 2 columns))) 2)))
               (label (cdr tick))
               (start (max 0 (min (- columns (length label)) (- column (/ (length label) 2))))))
          (aset axis column ?┬)
          (when (>= start free)
            (setq labels (concat (substring labels 0 start) label
                                 (substring labels (min (length labels) (+ start (length label))))))
            (setq free (+ start (length label) 1)))))
      (cons (concat axis) (string-trim-right labels)))))

(defun agent-ui-chart--line-text (props ctx)
  (let* ((range (agent-ui-chart--range props))
         (high-label (agent-ui-chart--number props (cdr range)))
         (low-label (agent-ui-chart--number props (car range)))
         ;; The axis's labels a third of the width at most, cut.
         (label-width (min (max (string-width high-label) (string-width low-label))
                           (max 1 (/ (plist-get ctx :width) 3))))
         (high-label (agent-ui-truncate high-label label-width))
         (low-label (agent-ui-truncate low-label label-width))
         (columns (max 4 (- (plist-get ctx :width) label-width 2)))
         (rows (plist-get props :height))
         (plot (agent-ui-chart--plot (plist-get props :series) range columns rows (agent-ui-chart--xs props)))
         (labels (plist-get props :labels))
         (time-axis (agent-ui-chart--time-axis props columns))
         (legend (agent-ui-chart--legend props columns)))
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
     ;; Times: an axis of ticks, labelled.
     (when time-axis
       (concat "\n" (propertize (concat (make-string label-width ?\s) " └" (car time-axis)) 'face 'agent-ui-muted)
               "\n" (propertize (concat (make-string (+ label-width 2) ?\s) (cdr time-axis)) 'face 'agent-ui-muted)))
     ;; The first and last labels, under the plot's ends.
     (when (and labels (not time-axis))
       ;; The last no more than half the plot (it was never cut: past the
       ;; width), the first in the rest.
       (let ((first (car labels))
             (last (if (cdr labels) (agent-ui-truncate (car (last labels)) (max 1 (/ (1- columns) 2))) "")))
         (concat "\n" (make-string (+ label-width 2) ?\s)
                 (propertize (agent-ui-pad first (- columns (string-width last) 1)) 'face 'agent-ui-muted)
                 " "
                 (propertize last 'face 'agent-ui-muted))))
     (mapconcat (lambda (line) (concat "\n" (make-string (+ label-width 2) ?\s) line)) legend ""))))

(defun agent-ui-chart--text (props ctx)
  (if (agent-ui-chart--empty-p props)
      (propertize "no values yet" 'face 'agent-ui-muted)
    (pcase (plist-get props :kind)
      ('sparkline (agent-ui-chart--sparkline props ctx))
      ('bar (agent-ui-chart--bar-text props ctx))
      ('histogram (agent-ui-chart--bar-text (agent-ui-chart--histogram props) ctx))
      (_ (agent-ui-chart--line-text (agent-ui-chart--by-time props) ctx)))))

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
         ;; The axis's labels a third of the width at most, cut (a long unit
         ;; put the plot's left past its right, outside the image).
         (label-columns (min (max (string-width (agent-ui-chart--number props (cdr range)))
                                  (string-width (agent-ui-chart--number props low)))
                             (max 1 (/ (plist-get ctx :width) 3))))
         (high-label (agent-ui-truncate (agent-ui-chart--number props (cdr range)) label-columns))
         (low-label (agent-ui-truncate (agent-ui-chart--number props low) label-columns))
         (label-width (* cw (+ 1 label-columns)))
         (labels (plist-get props :labels))
         (xs (agent-ui-chart--xs props))
         (times (and xs (plist-get props :times)))
         (width (* cw (plist-get ctx :width)))
         (left (+ label-width cw))
         (right (- width cw))
         ;; The legend's rows (it was one, past the image's right edge).
         (legend (and (seq-some (lambda (s) (plist-get s :name)) (plist-get props :series))
                      (agent-ui-chart--legend-rows (plist-get props :series) (floor (- right left) cw))))
         (plot-height (* lh (plist-get props :height)))
         ;; Room above the plot for its top label's letters.
         (top (round (* 0.8 lh)))
         (height (+ plot-height (if (or labels times) lh 0) (* lh (length legend)) (/ lh 2)))
         (muted (agent-ui-chart--color 'agent-ui-muted))
         (svg (svg-create width height)))
    ;; Within the plot, past min or max at its edge (as in text: it left the
    ;; image, and crossed the labels' row).
    (cl-flet ((y-of (v) (+ top (* (- plot-height top) (- 1 (max 0 (min 1 (/ (- v low) span))))))))
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
                                  collect (cons (cond
                                                 (xs (+ left (* (- right left) (or (nth i xs) 1.0))))
                                                 ((= n 1) left)
                                                 (t (+ left (* (- right left) (/ (float i) (1- n))))))
                                                (y-of v)))))
            (if (= n 1)
                (svg-circle svg (caar points) (cdar points) 2.5 :fill color)
              (when points
                (svg-polyline svg points :fill "none" :stroke color :stroke-width 2
                              :stroke-linejoin "round" :stroke-linecap "round"))))))
    ;; Times: an axis under the plot, its ticks labelled (none on another's).
    (when times
      (svg-line svg left plot-height right plot-height :stroke muted :stroke-width 1)
      (let ((free 0))
        (dolist (tick (agent-ui-chart--ticks (apply #'min times) (apply #'max times)
                                             (max 2 (/ (plist-get ctx :width) 10))))
          (let* ((x (+ left (* (- right left) (car tick))))
                 (half (* cw (/ (string-width (cdr tick)) 2.0)))
                 (center (max (+ left half) (min (- right half) x))))
            (svg-line svg x plot-height x (+ plot-height (/ lh 4)) :stroke muted :stroke-width 1)
            (when (>= (- center half) free)
              (agent-ui-chart--svg-text svg ctx (cdr tick) center (+ plot-height lh)
                                        :fill muted :text-anchor "middle")
              (setq free (+ center half cw)))))))
    (when (and labels (not times))
      ;; Each in half the plot's width less a gap (~0.5 of a line a
      ;; character): whole, they were drawn over each other.
      (let ((half (max 1 (floor (- (/ (- right left) 2.0) cw) (* 0.5 lh)))))
        (agent-ui-chart--svg-text svg ctx (agent-ui-truncate (car labels) (if (cdr labels) half (* 2 half)))
                                  left (+ plot-height lh) :fill muted)
        (when (cdr labels)
          (agent-ui-chart--svg-text svg ctx (agent-ui-truncate (car (last labels)) half) right (+ plot-height lh)
                                    :fill muted :text-anchor "end"))))
    (cl-loop for row in legend
             for y from (+ plot-height (if (or labels times) lh 0) lh) by lh
             do (let ((x left))
                  (dolist (item row)
                    (svg-circle svg (+ x (/ cw 2)) (- y (/ lh 3)) (/ cw 2.5)
                                :fill (agent-ui-chart--color (agent-ui-chart--face (car item))))
                    (agent-ui-chart--svg-text svg ctx (cdr item) (+ x (* 1.5 cw)) y
                                              :fill (agent-ui-chart--color 'default))
                    (setq x (+ x (* cw (+ 4 (string-width (cdr item)))))))))
    (agent-ui-chart--image svg)))

(defun agent-ui-chart--bar-svg (props ctx)
  (let* ((cw (plist-get ctx :char-width))
         (lh (plist-get ctx :line-height))
         (rows (agent-ui-chart--bar-rows props))
         (columns (plist-get ctx :width))
         (label-width (* cw (min (apply #'max 0 (mapcar (lambda (r) (string-width (car r))) rows)) (/ columns 3))))
         ;; Values a third of the width at most, cut; the bar a column at least.
         (value-columns (min (apply #'max 0 (mapcar (lambda (r) (string-width (nth 2 r))) rows)) (/ columns 3)))
         (value-width (* cw value-columns))
         (width (* cw columns))
         (bar-left (+ label-width (* 2 cw)))
         (bar-width (max cw (- width bar-left value-width (* 2 cw))))
         (scale (agent-ui-chart--bar-scale props bar-width))
         (series (plist-get props :series))
         ;; Grouped: a group's bars closer, a gap between groups.
         (grouped (and (cdr series) (not (agent-ui-chart--stacked-p props))))
         (row (round (* (if grouped 1.1 1.4) lh)))
         (gap (if grouped (round (* 0.5 lh)) 0))
         ;; The legend's rows (it was one, past the image's right edge).
         (legend (and (cdr series) (seq-some (lambda (s) (plist-get s :name)) series)
                      (agent-ui-chart--legend-rows series (floor (- width bar-left) cw))))
         (ys (let ((y 0))
               (mapcar (lambda (r)
                         (when (and grouped (not (string-empty-p (car r))) (> y 0)) (cl-incf y gap))
                         (prog1 y (cl-incf y row)))
                       rows)))
         (height (+ (if rows (+ (car (last ys)) row) 0)
                    (if legend (+ (round (* 1.4 lh)) (* lh (1- (length legend)))) 0)))
         (svg (svg-create width height))
         (fg (agent-ui-chart--color 'default))
         (muted (agent-ui-chart--color 'agent-ui-muted)))
    (cl-loop for r in rows
             for y in ys
             do (let ((x bar-left))
                  (unless (string-empty-p (car r))
                    (agent-ui-chart--svg-text svg ctx (agent-ui-truncate (car r) (/ label-width cw))
                                              0 (+ y (* 0.7 row)) :fill fg))
                  (dolist (segment (nth 1 r))
                    (let ((length (min (- (+ bar-left bar-width) x) (* scale (car segment)))))
                      (when (> length 0)
                        (svg-rectangle svg x (+ y (* 0.2 row)) (max 1 length) (* 0.6 row)
                                       :fill (agent-ui-chart--color (agent-ui-chart--face (cdr segment)))
                                       :rx (if (cdr (nth 1 r)) 0 2))
                        (setq x (+ x length)))))
                  (agent-ui-chart--svg-text svg ctx (agent-ui-truncate (nth 2 r) value-columns)
                                            (+ (max x (+ bar-left 1)) cw) (+ y (* 0.7 row))
                                            :fill muted)))
    (cl-loop for row in legend
             for y from (- height (round (* 0.4 lh)) (* lh (1- (length legend)))) by lh
             do (let ((x bar-left))
                  (dolist (item row)
                    (svg-circle svg (+ x (/ cw 2)) (- y (/ lh 3)) (/ cw 2.5)
                                :fill (agent-ui-chart--color (agent-ui-chart--face (car item))))
                    (agent-ui-chart--svg-text svg ctx (cdr item) (+ x (* 1.5 cw)) y :fill fg)
                    (setq x (+ x (* cw (+ 4 (string-width (cdr item)))))))))
    (agent-ui-chart--image svg)))

;; ====== A HISTOGRAM ======

(defun agent-ui-chart--histogram (props)
  "PROPS, a histogram's, as bars: its values counted in BINS (default: the
square root of how many, 5 to 20) of equal width, MIN to MAX (default:
its values'), each labelled with its range."
  (let* ((values (plist-get (car (plist-get props :series)) :values))
         (low (or (plist-get props :min) (apply #'min values)))
         (high (or (plist-get props :max) (apply #'max values)))
         (high (if (<= high low) (agent-ui-chart--above low) high))
         (bins (or (plist-get props :bins) (max 5 (min 20 (ceiling (sqrt (length values)))))))
         (step (/ (- high low) (float bins)))
         (counts (make-vector bins 0)))
    (dolist (v values)
      (when (<= low v high)
        (cl-incf (aref counts (min (1- bins) (floor (/ (- v low) step)))))))
    ;; Its min and max are its bins' span, not the counts' axis.
    (append (list :kind 'bar :unit nil :min nil :max nil
                  :series (list (list :name nil :values (append counts nil)))
                  :labels (cl-loop for i below bins
                                   collect (format "%s–%s"
                                                   (agent-ui-format-number (+ low (* i step)))
                                                   (agent-ui-chart--number props (+ low (* (1+ i) step))))))
            props)))

(defun agent-ui-chart--gui (props ctx)
  (if (agent-ui-chart--empty-p props)
      (agent-ui-chart--text props ctx)
    (pcase (plist-get props :kind)
      ('bar (agent-ui-chart--bar-svg props ctx))
      ('histogram (agent-ui-chart--bar-svg (agent-ui-chart--histogram props) ctx))
      ('line (agent-ui-chart--line-svg (agent-ui-chart--by-time props) ctx))
      ;; A sparkline is a line of text: as in a terminal.
      (_ (agent-ui-chart--text props ctx)))))

(agent-ui-define chart
  "A chart of numbers: KIND line (default; several series, each its colour;
TIMES placing the values on a time axis), bar (a bar per value, LABELS
naming them; several series grouped under each label, or STACKED),
histogram (its values counted in BINS) or sparkline (one line, the latest
values). As SVG in a graphic frame, as characters in a
terminal. For a live chart, append values: {\"values\": [42]} (or
{\"series\": [{\"name\": \"p95\", \"values\": [42]}]}), WINDOW keeping the
latest so many."
  :props ((kind (choice line bar histogram sparkline) "line, bar, histogram or sparkline" :default line)
          (values list "The numbers (one series)")
          (series list "Several series: [{\"name\": ..., \"values\": [...]}]")
          (labels list "Names for the values, in order (x axis; a bar's name)")
          (unit string "What the numbers count (ms, MB), after them")
          (min number "The lowest the axis shows: bars start at it, but stacked ones (default: the values', bars from 0)")
          (max number "The highest the axis shows (default: the values')")
          (height integer "A line chart's height, in lines" :default 8)
          (window integer "Keep only the latest so many values (a live chart)")
          (stacked boolean "Bars of several series end to end, a bar per label (else grouped)")
          (bins integer "A histogram's bins (default: from how many values, 5 to 20)")
          (times list "Each value's time (ISO 8601, or seconds since 1970): a line chart's time axis"))
  :example (:title "p95 latency" :kind "bar" :unit "ms"
            :labels ("mon" "tue" "wed" "thu") :values (120 95 180 60))
  :check #'agent-ui-chart--check
  :append #'agent-ui-chart--append
  :text #'agent-ui-chart--text
  :gui #'agent-ui-chart--gui)
