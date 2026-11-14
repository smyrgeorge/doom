;;; $DOOMDIR/config/agent-ui/elements/heatmap.el -*- lexical-binding: t; -*-
;; Agent UI's heatmap: a grid of cells coloured by their values. Loaded from
;; config/agent-ui/elements.el.
;;
;; ROWS and COLUMNS (labels), VALUES a row of cells for each row: a number,
;; coloured on a scale from the lowest to the highest (SCALE "blue": low
;; faint, high strong; "green-red": low good, high bad; "red-green": the
;; other way), or a word coloured by its state (passed, failed, flaky,
;; skipped...), or null (empty). Text: coloured blocks, a legend under them;
;; GUI: SVG cells with their values. A test's results by OS and version,
;; flaky tests by day.
;;
;;              mon tue wed
;;   lexer      ███ ███ ███
;;   checker    ███ ░░░ ███

(require 'cl-lib)
(require 'subr-x)
(require 'svg)
(require 'color)

(defconst agent-ui-heatmap--states
  '(("passed" . agent-ui-success) ("pass" . agent-ui-success) ("ok" . agent-ui-success)
    ("failed" . agent-ui-error) ("fail" . agent-ui-error) ("error" . agent-ui-error)
    ("flaky" . agent-ui-warning) ("slow" . agent-ui-warning)
    ("skipped" . agent-ui-muted) ("pending" . agent-ui-muted))
  "Cells reading so: their colour.")

(defun agent-ui-heatmap--check (props)
  (let ((rows (plist-get props :rows)) (columns (plist-get props :columns)) (values (plist-get props :values)))
    (unless (and rows (cl-every #'stringp rows)) (agent-ui--fail "heatmap: rows must be labels"))
    (unless (and columns (cl-every #'stringp columns)) (agent-ui--fail "heatmap: columns must be labels"))
    (unless (= (length values) (length rows))
      (agent-ui--fail "heatmap: values has %d rows, for %d row labels" (length values) (length rows)))
    (cl-loop for row in values for i from 1
             do (unless (and (listp row) (= (length row) (length columns)))
                  (agent-ui--fail "heatmap: values' row %d has %s cells, for %d columns"
                                  i (if (listp row) (length row) "no") (length columns)))
             (dolist (cell row)
               (unless (or (null cell) (numberp cell) (stringp cell))
                 (agent-ui--fail "heatmap: values' row %d has %s: a cell is a number, a word or null"
                                 i (agent-ui--show-value cell))))))
  props)

(defun agent-ui-heatmap--range (props)
  (let ((numbers (seq-filter #'numberp (apply #'append (plist-get props :values)))))
    (if numbers (cons (apply #'min numbers) (apply #'max numbers)) (cons 0 1))))

(defun agent-ui-heatmap--hex (face)
  (let ((c (face-foreground face nil 'default)))
    (if (and (stringp c) (string-prefix-p "#" c)) c
      (pcase face ('agent-ui-success "#98be65") ('agent-ui-error "#ff6c6b") ('agent-ui-warning "#ecbe7b")
             ('agent-ui-accent "#51afef") (_ "#5b6268")))))

(defun agent-ui-heatmap--mix (a b share)
  (let ((ra (color-name-to-rgb a)) (rb (color-name-to-rgb b)))
    (if (and ra rb (string-prefix-p "#" a) (string-prefix-p "#" b))
        (apply #'color-rgb-to-hex (append (cl-mapcar (lambda (x y) (+ (* x (- 1 share)) (* y share))) ra rb) '(2)))
      b)))

(defun agent-ui-heatmap--color (props cell range)
  "CELL's colour (#RRGGBB), or nil (empty)."
  (cond
   ((null cell) nil)
   ((stringp cell)
    (agent-ui-heatmap--hex (or (cdr (assoc (downcase cell) agent-ui-heatmap--states)) 'agent-ui-accent)))
   (t
    (let* ((share (/ (- cell (car range)) (float (max 1e-9 (- (cdr range) (car range))))))
           (bg (let ((b (face-background 'default nil t))) (if (and (stringp b) (string-prefix-p "#" b)) b "#282c34"))))
      (pcase (plist-get props :scale)
        ('green-red (agent-ui-heatmap--mix (agent-ui-heatmap--hex 'agent-ui-success) (agent-ui-heatmap--hex 'agent-ui-error) share))
        ('red-green (agent-ui-heatmap--mix (agent-ui-heatmap--hex 'agent-ui-error) (agent-ui-heatmap--hex 'agent-ui-success) share))
        (_ (agent-ui-heatmap--mix bg (agent-ui-heatmap--hex 'agent-ui-accent) (+ 0.15 (* 0.85 share)))))))))

(defun agent-ui-heatmap--legend (props range width)
  "The legend: the scale's ends, and each word used with its colour, packed
into lines of WIDTH; an item (a swatch and its word) never split (wrapped
as text, a swatch was left at a line's end, its word on the next)."
  (let* ((values (apply #'append (plist-get props :values)))
         (numbers (seq-filter #'numberp values))
         (words (delete-dups (seq-filter #'stringp values)))
         (items (append
                 (when numbers
                   (list (concat (propertize (agent-ui-format-number (car range)) 'face 'agent-ui-muted) " "
                                 (mapconcat (lambda (i) (propertize "█" 'face (list :foreground (agent-ui-heatmap--color
                                                                                                props (+ (car range) (* i 0.25 (- (cdr range) (car range))))
                                                                                                range))))
                                            '(0 1 2 3 4) "")
                                 " " (propertize (agent-ui-format-number (cdr range)) 'face 'agent-ui-muted))))
                 (mapcar (lambda (w) (concat (propertize "█" 'face (list :foreground (agent-ui-heatmap--color props w range)))
                                             " " (propertize w 'face 'agent-ui-muted)))
                         words))))
    (agent-ui-heatmap--pack items width)))

(defun agent-ui-heatmap--pack (items width)
  "ITEMS on lines of WIDTH, two spaces between them, an item never split."
  (let ((lines nil) (line nil))
    (dolist (item items)
      (if (and line (> (+ (string-width line) 2 (string-width item)) width))
          (progn (push line lines) (setq line item))
        (setq line (if line (concat line "  " item) item))))
    (when line (push line lines))
    (mapconcat (lambda (l) (agent-ui-truncate l width)) (nreverse lines) "\n")))

(defun agent-ui-heatmap--heads (columns room)
  "COLUMNS' labels over their cells, ROOM columns each: cut to it; or, cut
under 5 columns or read alike, their numbers (all \"c…\"), their labels
then in a key (`agent-ui-heatmap--key'). (HEADS . NUMBERED)."
  (let ((cut (mapcar (lambda (c) (agent-ui-truncate c (max 1 room))) columns)))
    (if (or (equal cut columns)
            (and (>= room 5) (= (length (delete-dups (copy-sequence cut))) (length cut))))
        (cons cut nil)
      (cons (mapcar #'number-to-string (number-sequence 1 (length columns))) t))))

(defun agent-ui-heatmap--key (columns width)
  "The columns' numbers and their labels (\"1 linux  2 macos\"), packed into
lines of WIDTH: under a grid whose labels don't fit their cells, which are
numbered (cut, they all read \"c…\")."
  (agent-ui-heatmap--pack (cl-loop for c in columns for i from 1
                                   collect (concat (propertize (number-to-string i) 'face 'bold) " "
                                                   (propertize c 'face 'agent-ui-muted)))
                          width))

(defun agent-ui-heatmap--latest (props room)
  "PROPS with its latest columns only, those fitting ROOM columns at 3 each
\(one at least), and how many earlier ones were left out: (PROPS . OUT). A
month of days ran 97 columns wide at 60."
  (let* ((columns (plist-get props :columns))
         (k (max 1 (min (length columns) (floor room 3))))
         (out (- (length columns) k)))
    (if (zerop out)
        (cons props 0)
      (cons (plist-put (plist-put (copy-sequence props) :columns (nthcdr out columns))
                       :values (mapcar (lambda (row) (nthcdr out row)) (plist-get props :values)))
            out))))

(defun agent-ui-heatmap--left-out (out width)
  "The line saying OUT earlier columns were left out, in WIDTH; nil if none."
  (when (> out 0)
    (propertize (agent-ui-truncate (format "… %d earlier %s left out" out (if (= out 1) "column" "columns")) width)
                'face 'agent-ui-muted)))

(defun agent-ui-heatmap--text (props ctx)
  (let* ((range (agent-ui-heatmap--range props))
         (label-width (min (apply #'max (mapcar #'string-width (plist-get props :rows))) (/ (plist-get ctx :width) 3)))
         ;; The latest columns that fit (a cell 3 columns at least).
         (latest (agent-ui-heatmap--latest props (- (plist-get ctx :width) label-width 1)))
         (props (car latest))
         (rows (plist-get props :rows)) (columns (plist-get props :columns))
         ;; A cell: its block, then a space; its label within the block,
         ;; the cells as wide as the widest label, if there's room (they were
         ;; 6 at most: "macos…" with 72 columns free).
         (cell (max 3 (min (1+ (apply #'max (mapcar #'string-width columns)))
                           (/ (- (plist-get ctx :width) label-width 2) (max 1 (length columns))))))
         (heads (agent-ui-heatmap--heads columns (1- cell)))
         (block (lambda (color) (if color (propertize (make-string (1- cell) ?█) 'face (list :foreground color))
                                  (propertize (make-string (1- cell) ?·) 'face 'agent-ui-muted)))))
    (concat
     (make-string (+ label-width 2) ?\s)
     (string-trim-right (mapconcat (lambda (c) (agent-ui-pad c cell)) (car heads) ""))
     "\n"
     (mapconcat (lambda (row)
                  (concat (agent-ui-pad (car row) label-width) "  "
                          (mapconcat (lambda (v) (funcall block (agent-ui-heatmap--color props v range)))
                                     (cdr row) " ")))
                (cl-mapcar #'cons rows (plist-get props :values)) "\n")
     (when-let* ((note (agent-ui-heatmap--left-out (cdr latest) (plist-get ctx :width))))
       (concat "\n" note))
     (if (cdr heads) (concat "\n" (agent-ui-heatmap--key columns (plist-get ctx :width))) "")
     ;; The legend: the scale's ends, or the words used, fitted to the width.
     "\n"
     (agent-ui-heatmap--legend props range (plist-get ctx :width)))))

(defun agent-ui-heatmap--gui (props ctx)
  (let* ((cw (plist-get ctx :char-width)) (lh (plist-get ctx :line-height))
         (range (agent-ui-heatmap--range props))
         (label-w (* cw (+ 2 (min (apply #'max (mapcar #'string-width (plist-get props :rows)))
                                  (/ (plist-get ctx :width) 3)))))
         ;; The latest columns that fit (a cell 3 columns at least).
         (latest (agent-ui-heatmap--latest props (- (plist-get ctx :width) (/ label-w cw))))
         (props (car latest))
         (rows (plist-get props :rows)) (columns (plist-get props :columns))
         ;; Cells 8 columns wide, or as the widest label, if there's room.
         (label (car (seq-sort-by #'string-width #'> (copy-sequence columns))))
         (cell-w (max (* 3 cw) (min (max (* 8 cw) (+ (agent-ui-svg-text-width label (* 0.8 lh)) 6))
                                    (/ (- (* cw (plist-get ctx :width)) label-w) (max 1 (length columns))))))
         ;; Its labels a little smaller if that fits them (0.6 of a line
         ;; at least), else cut or numbered (`agent-ui-heatmap--heads').
         (size (max (* 0.6 lh) (agent-ui-svg-fit-size label (* 0.8 lh) (- cell-w 4))))
         (heads (agent-ui-heatmap--heads columns (floor (+ (/ (- cell-w 4) (* 0.6 size)) 1e-6))))
         (cell-h (round (* 1.5 lh)))
         (top (round (* 1.4 lh)))
         (svg (svg-create (+ label-w (* cell-w (length columns))) (+ top (* cell-h (length rows)))))
         (muted (agent-ui-chart--color 'agent-ui-muted)) (fg (agent-ui-chart--color 'default)))
    (cl-loop for c in (car heads) for j from 0
             do (svg-text svg c :x (+ label-w (* j cell-w) (/ cell-w 2)) :y (* 0.9 lh)
                          :font-size (round size) :font-family (agent-ui--svg-font)
                          :fill muted :text-anchor "middle"))
    (cl-loop for r in rows for row in (plist-get props :values) for i from 0
             do (let ((y (+ top (* i cell-h))))
                  ;; Cut to its column (whole, it ran through the cells).
                  (agent-ui-chart--svg-text svg ctx (agent-ui-truncate r (max 1 (- (/ label-w cw) 2)))
                                            0 (+ y (* 0.68 cell-h)) :fill fg)
                  (cl-loop for v in row for j from 0
                           do (let ((color (agent-ui-heatmap--color props v range))
                                    (x (+ label-w (* j cell-w))))
                                (svg-rectangle svg (+ x 1) (+ y 1) (- cell-w 2) (- cell-h 2) :rx 3
                                               :fill (or color "none") :stroke (if color "none" muted) :stroke-opacity 0.4)
                                ;; Its number, if it fits the cell (~0.5 of a
                                ;; line a character): else its colour says it
                                ;; (numbers overlapped the next cell's).
                                (when (and v (numberp v)
                                           (<= (* 0.5 lh (string-width (agent-ui-format-number v))) (- cell-w 4)))
                                  (agent-ui-chart--svg-text svg ctx (agent-ui-format-number v) (+ x (/ cell-w 2)) (+ y (* 0.68 cell-h))
                                                            :fill (if (> (/ (- v (car range)) (float (max 1e-9 (- (cdr range) (car range))))) 0.55)
                                                                      "#1b1b1b" fg)
                                                            :text-anchor "middle"))))))
    (concat (agent-ui-chart--image svg) "\n"
            (if-let* ((note (agent-ui-heatmap--left-out (cdr latest) (plist-get ctx :width)))) (concat note "\n") "")
            (if (cdr heads) (concat (agent-ui-heatmap--key columns (plist-get ctx :width)) "\n") "")
            ;; The legend, as text: all its lines (only its last was kept).
            (agent-ui-heatmap--legend props range (plist-get ctx :width)))))

(agent-ui-define heatmap
  "A grid of cells coloured by their values: ROWS and COLUMNS (labels),
VALUES a row of cells for each row: a number, coloured on a SCALE from the
lowest to the highest (\"blue\": low faint, high strong; \"green-red\":
low good, high bad; \"red-green\"), a word coloured by its state (passed,
failed, flaky, skipped...), or null. A legend under it; SVG cells with
their values in the GUI. A test's results by OS and version, flaky tests
by day, durations by job and branch."
  :props ((rows list "The rows' labels" :required t)
          (columns list "The columns' labels" :required t)
          (values list "A row of cells for each row: numbers, words, nulls" :required t)
          (scale (choice blue green-red red-green) "How numbers are coloured" :default blue))
  :example (:title "Test runs by OS"
            :rows ("lexer" "parser" "checker") :columns ("linux" "macos" "windows")
            :values (("passed" "passed" "passed") ("passed" "flaky" "passed") ("failed" "passed" "skipped")))
  :check #'agent-ui-heatmap--check
  :text #'agent-ui-heatmap--text
  :gui #'agent-ui-heatmap--gui)
