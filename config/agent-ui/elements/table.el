;;; $DOOMDIR/config/agent-ui/elements/table.el -*- lexical-binding: t; -*-
;; Agent UI's table: columns and rows, fitting the width. With a key column,
;; an appended row whose key is there replaces that row: a test's row goes from
;; running to failed. Loaded from
;; config/agent-ui/elements.el.
;;
;;    Test    │ Result │ Time
;;   ─────────┼────────┼──────
;;    lexer   │ passed │ 0.4s
;;
;; Sorted by a column (sort; s on it in the canvas, again the other way), its
;; name marked ↑ or ↓. Row actions: buttons at each row's end, their prompts
;; filled with its cells ({Test}, {row}).

(require 'cl-lib)
(require 'subr-x)

(defconst agent-ui-table--states
  '(("passed" . agent-ui-success) ("pass" . agent-ui-success) ("ok" . agent-ui-success)
    ("done" . agent-ui-success) ("success" . agent-ui-success) ("succeeded" . agent-ui-success)
    ("✓" . agent-ui-success)
    ("failed" . agent-ui-error) ("fail" . agent-ui-error) ("error" . agent-ui-error)
    ("errored" . agent-ui-error) ("✗" . agent-ui-error)
    ("running" . agent-ui-accent)
    ("pending" . agent-ui-muted) ("skipped" . agent-ui-muted) ("waiting" . agent-ui-muted))
  "Cells reading so (any case) are coloured.")

(defun agent-ui-table--key-index (key columns)
  "KEY (a column's index or name, or nil) as an index of COLUMNS; an error
if there's no such column."
  (cond
   ((null key) nil)
   ((and (integerp key) (<= 0 key) (< key (length columns))) key)
   ((and (stringp key) (cl-position key columns :test #'equal)))
   (t (agent-ui--fail "table: key must be a column, its index (from 0) or name, not %s; columns: %s"
                      (agent-ui--show-value key)
                      (mapconcat (lambda (c) (format "%S" c)) columns ", ")))))

(defun agent-ui-table--check (props)
  (let* ((columns (plist-get props :columns))
         (n (length columns)))
    (unless (and columns (cl-every #'stringp columns))
      (agent-ui--fail "table: columns must be names: [\"Test\", \"Result\"]"))
    (cl-loop for row in (plist-get props :rows)
             for i from 1
             do (unless (and (listp row) (not (agent-ui--plist-p row)))
                  (agent-ui--fail "table: row %d must be an array of cells, not %s"
                                  i (agent-ui--show-value row)))
             (when (> (length row) n)
               (agent-ui--fail "table: row %d has %d cells, for %d columns" i (length row) n))
             (dolist (cell row)
               (when (consp cell)
                 (agent-ui--fail "table: row %d has %s: a cell is text, a number, true, false or null"
                                 i (agent-ui--show-value cell)))))
    (let ((align (plist-get props :align)))
      (when (> (length align) n)
        (agent-ui--fail "table: align has %d entries, for %d columns" (length align) n))
      (plist-put props :align
                 ;; By their names (intern-soft took a misspelt one, not yet
                 ;; a symbol, for nil: automatic); null: automatic.
                 (mapcar (lambda (a)
                           (cond ((null a) nil)
                                 ((member a '("left" "right" "center")) (intern a))
                                 ((memq a '(left right center)) a)
                                 (t (agent-ui--fail "table: align is left, right, center or null, not %s"
                                                    (agent-ui--show-value a)))))
                         align)))
    (when (plist-get props :sort)
      (condition-case err
          (agent-ui-table--key-index (plist-get props :sort) columns)
        (agent-ui-error
         (agent-ui--fail "%s" (string-replace "key must be" "sort must be" (agent-ui-error-message err))))))
    (when-let* ((actions (plist-get props :row-actions)))
      (condition-case err
          (agent-ui-check-actions actions)
        (agent-ui-error (agent-ui--fail "table: row-%s" (agent-ui-error-message err)))))
    (plist-put props :key (agent-ui-table--key-index (plist-get props :key) columns))))

(defun agent-ui-table--widths (header rows max-width)
  "Each column's width: its widest cell's, the widest cut down until the
table fits MAX-WIDTH (no column under 3)."
  (let* ((widths (apply #'cl-mapcar
                        (lambda (&rest cells) (apply #'max (mapcar #'string-width cells)))
                        header rows))
         (widths (vconcat widths)))
    ;; A table's width: each column and a space either side, a │ between,
    ;; less the last one's trailing space.
    (cl-flet ((total () (+ (cl-reduce #'+ widths) (* 3 (length widths)) -2)))
      (while (and (> (total) max-width)
                  (> (cl-reduce #'max widths) 3))
        (let ((widest (cl-position (cl-reduce #'max widths) widths)))
          (cl-decf (aref widths widest)))))
    (append widths nil)))

(defun agent-ui-table--fitting (header rows max-width)
  "How many of the columns (HEADER's, ROWS') fit MAX-WIDTH, each at its
narrowest (3 columns, or less if its cells are): those on the left, one at
least."
  (let* ((narrowest (apply #'cl-mapcar
                           (lambda (&rest cells) (min 3 (apply #'max (mapcar #'string-width cells))))
                           header rows))
         (k (length narrowest)))
    (while (and (> k 1)
                (> (+ (apply #'+ (seq-take narrowest k)) (* 3 k) -2) max-width))
      (cl-decf k))
    k))

(defun agent-ui-table--number (cell)
  "CELL's leading number (\"0.4s\": 0.4, \"1,204\": 1204), or nil."
  (when (string-match "\\`[-+]?[0-9][0-9,]*\\(?:\\.[0-9]+\\)?" cell)
    (string-to-number (string-replace "," "" (match-string 0 cell)))))

(defconst agent-ui-table--units '(("ms" . 0.001) ("s" . 1) ("min" . 60) ("m" . 60) ("h" . 3600) ("d" . 86400))
  "A duration's units, in seconds.")

(defun agent-ui-table--duration (cell)
  "CELL as a duration in seconds (\"2m 05s\", \"850ms\", \"1.2s\", \"1h\"), or
nil if it isn't one: numbers each with a unit, nothing else."
  (let ((rest (string-trim cell)) (seconds 0) (case-fold-search nil))
    (while (and rest (not (string-empty-p rest)))
      (if (string-match "\\`\\([0-9]+\\(?:\\.[0-9]+\\)?\\) ?\\(ms\\|min\\|[smhd]\\)\\b *" rest)
          (setq seconds (+ seconds (* (string-to-number (match-string 1 rest))
                                      (cdr (assoc (match-string 2 rest) agent-ui-table--units))))
                rest (substring rest (match-end 0)))
        (setq rest nil seconds nil)))
    (and (not (string-empty-p (string-trim cell))) seconds)))

(defun agent-ui-table--sorted (rows column descending)
  "ROWS (their cells as text) by COLUMN's cells: as durations if they all are
\(\"2m 05s\", \"850ms\"), else as numbers if they all start with one, else as
text; DESCENDING the other way; empty cells last."
  (let* ((cells (seq-remove #'string-empty-p (mapcar (lambda (r) (nth column r)) rows)))
         (durations (and cells (cl-every #'agent-ui-table--duration cells)))
         (numbers (and cells (cl-every #'agent-ui-table--number cells)))
         (before (lambda (a b)
                   (cond (durations (< (agent-ui-table--duration a) (agent-ui-table--duration b)))
                         (numbers (< (agent-ui-table--number a) (agent-ui-table--number b)))
                         (t (string< (downcase a) (downcase b)))))))
    (cl-stable-sort (copy-sequence rows)
                    (lambda (ra rb)
                      (let ((a (nth column ra)) (b (nth column rb)))
                        (cond ((string-empty-p a) nil)
                              ((string-empty-p b) t)
                              (descending (funcall before b a))
                              (t (funcall before a b))))))))

(defun agent-ui-table--fill (prompt columns row)
  "PROMPT with {COLUMN} as ROW's cell in that column, {row} as all of them."
  (replace-regexp-in-string
   "{\\([^{}]+\\)}"
   (lambda (match)
     (let ((name (match-string 1 match)))
       (cond
        ((equal name "row")
         (mapconcat #'identity
                    (cl-loop for c in columns for cell in row
                             collect (if (string-empty-p c) cell (format "%s: %s" c cell)))
                    ", "))
        ((cl-position name columns :test #'equal) (nth (cl-position name columns :test #'equal) row))
        (t match))))
   prompt t t))

(defun agent-ui-table--row-buttons (actions columns row)
  "ACTIONS as buttons for ROW: their prompts filled with its cells."
  (mapconcat
   (lambda (action)
     (let ((prompt (agent-ui-table--fill (plist-get action :prompt) columns row))
           (submit (eq (plist-get action :submit) t)))
       (agent-ui-button (propertize (concat "⏵ " (plist-get action :label)) 'face 'agent-ui-action)
                        (lambda () (funcall agent-ui-action-function prompt submit))
                        (format "RET: %s \"%s\"" (if submit "send" "put into the prompt")
                                (truncate-string-to-width prompt 60 nil nil "…")))))
   actions "  "))

(defun agent-ui-table--cell (value)
  "VALUE as a cell's text, on one line: a line break shown as ⏎, a tab as a
space (they broke the table's lines and its border)."
  (replace-regexp-in-string
   "\t" " " (replace-regexp-in-string "\r?\n" "⏎" (agent-ui-cell value))))

(defun agent-ui-table--text (props ctx)
  (let* ((columns (plist-get props :columns))
         (n (length columns))
         (all (mapcar (lambda (row)
                        (let ((cells (mapcar #'agent-ui-table--cell row)))
                          (append cells (make-list (- n (length cells)) ""))))
                      (plist-get props :rows)))
         (sort (agent-ui-table--key-index (plist-get props :sort) columns))
         (descending (eq (plist-get props :descending) t))
         (rows (seq-take (if sort (agent-ui-table--sorted all sort descending) all) agent-ui-max-rows))
         ;; The sorted column's name marked.
         (header (cl-loop for c in columns for i from 0
                          collect (if (eql i sort) (concat c (if descending " ↓" " ↑")) c)))
         ;; Its rows' buttons: not in a still picture (a snapshot).
         (actions (and (not (plist-get ctx :still)) (plist-get props :row-actions)))
         (actions-width (if actions
                            (+ 2 (apply #'+ (mapcar (lambda (a) (+ 4 (string-width (plist-get a :label)))) actions)))
                          0))
         ;; Buttons at a row's end only while its cells keep their widths
         ;; beside them; else on a line of their own under it (they squeezed
         ;; the cells to 3 columns and the rows past the width).
         (beside (and actions
                      (let ((full (agent-ui-table--widths header rows most-positive-fixnum)))
                        (<= (+ (apply #'+ full) (* 3 (length full)) -2 actions-width)
                            (plist-get ctx :width)))))
         (room (max 4 (- (plist-get ctx :width) (if beside actions-width 0))))
         ;; The columns that fit (the others left out, said under it).
         (shown (agent-ui-table--fitting header rows room))
         (widths (agent-ui-table--widths (seq-take header shown)
                                         (mapcar (lambda (r) (seq-take r shown)) rows)
                                         room))
         (align (cl-loop for i below n
                         collect (or (nth i (plist-get props :align))
                                     ;; Numbers to the right.
                                     (let ((cells (seq-remove #'string-empty-p
                                                              (mapcar (lambda (r) (nth i r)) rows))))
                                       (if (and cells
                                                (cl-every (lambda (c) (string-match-p "\\`[-+]?[0-9.,]+%?\\'" c))
                                                          cells))
                                           'right
                                         'left)))))
         (bar (propertize "│" 'face 'agent-ui-muted))
         ;; The sorted column's name cut, its arrow kept (cut, it went first).
         (header (cl-loop for c in header for name in columns for w in widths for i from 0
                          collect (if (and (eql i sort) (> (string-width c) w))
                                      (concat (agent-ui-truncate name (max 1 (- w 2)))
                                              (if descending " ↓" " ↑"))
                                    c))))
    (cl-flet ((line (cells &optional face)
                ;; Each cell its column's (`s' there sorts by it).
                (mapconcat #'identity
                           (cl-loop for cell in cells
                                    for width in widths
                                    for a in align
                                    for i from 0
                                    collect (let ((text (agent-ui-pad cell width a))
                                                  (state (cdr (assoc (downcase cell) agent-ui-table--states))))
                                              (propertize (concat " " (propertize text 'face (or face state)) " ")
                                                          'agent-ui-table-column i)))
                           bar)))
      (concat
       ;; No column named: no header, the rows alone.
       (unless (cl-every #'string-empty-p columns)
         (concat
          (string-trim-right (line header 'bold)) "\n"
          ;; As wide as the lines: the last column's has no space after it.
          (propertize (mapconcat (lambda (w) (make-string (+ w 2) ?─))
                                 (append (butlast widths) (list (1- (car (last widths)))))
                                 "┼")
                      'face 'agent-ui-muted)
          "\n"))
       (if rows
           (mapconcat (lambda (row)
                        (cond
                         (beside (concat (line row) " " (agent-ui-table--row-buttons actions columns row)))
                         (actions (concat (string-trim-right (line row)) "\n "
                                          (agent-ui-truncate (agent-ui-table--row-buttons actions columns row)
                                                             (1- (plist-get ctx :width)))))
                         (t (string-trim-right (line row)))))
                      rows "\n")
         (concat " " (propertize "no rows yet" 'face 'agent-ui-muted)))
       (when (> (length all) (length rows))
         (concat "\n " (propertize (format "… %d rows more" (- (length all) (length rows)))
                                   'face 'agent-ui-muted)))
       (when (< shown n)
         (concat "\n " (propertize (agent-ui-truncate (format "… %d more %s: %s" (- n shown) (if (= (- n shown) 1) "column" "columns")
                                                               (string-join (nthcdr shown columns) ", "))
                                                       (1- (plist-get ctx :width)))
                                   'face 'agent-ui-muted)))))))

;; ====== SORTING IN THE CANVAS ======

(declare-function agent-ui--element-at-point "agent-ui/snapshot")

(defun agent-ui-table-sort ()
  "Sort the table at point by the column at point; again, the other way.
Kept as its sort and descending (the agent sees it)."
  (interactive)
  (let ((column (get-text-property (point) 'agent-ui-table-column)))
    (unless column
      (user-error "No table's column here"))
    (let* ((id (agent-ui--element-at-point))
           (element (agent-ui-get id :canvas (current-buffer)))
           (columns (plist-get element :columns))
           (current (ignore-errors (agent-ui-table--key-index (plist-get element :sort) columns)))
           (descending (and (eql current column) (not (eq (plist-get element :descending) t))))
           (name (nth column columns)))
      (agent-ui-update id (list :sort (if (and (not (string-empty-p name))
                                               (= (cl-count name columns :test #'equal) 1))
                                          name
                                        column)
                                :descending (and descending t))
                       :canvas (current-buffer))
      (message "Sorted by %s, %s" (if (string-empty-p name) (format "column %d" (1+ column)) name)
               (if descending "descending" "ascending")))))

(keymap-set agent-ui-canvas-mode-map "s" #'agent-ui-table-sort)

(defun agent-ui-table--append (element patch)
  "ELEMENT with PATCH's rows: with a key column, a row whose key is there
replaces that row; the others after."
  (cl-loop for (k _) on patch by #'cddr
           unless (memq k '(:id :rows))
           do (agent-ui--fail "table: only rows can be appended to"))
  (let* ((key (agent-ui-table--key-index (plist-get element :key) (plist-get element :columns)))
         (rows (copy-sequence (plist-get element :rows))))
    (dolist (row (plist-get patch :rows))
      (let ((at (and key (listp row)
                     (cl-position (agent-ui-cell (nth key row)) rows
                                  :key (lambda (r) (and (listp r) (agent-ui-cell (nth key r))))
                                  :test #'equal))))
        (if at
            (setf (nth at rows) row)
          (setq rows (append rows (list row))))))
    (plist-put (copy-sequence element) :rows rows)))

(agent-ui-define table
  "A table: COLUMNS (their names) and ROWS (arrays of cells: text, numbers,
true, false, null), fitting the width; cells reading passed, failed,
running, pending... are coloured. With KEY (a column's index or name),
appending a row whose key is there replaces that row: append
{\"rows\": [[\"parser\", \"failed\", \"1.2s\"]]}. SORT orders its rows by a
column (DESCENDING the other way); ROW-ACTIONS are buttons on each row
putting a prompt with its cells into the session's prompt."
  :props ((columns list "The columns' names (all \"\": no header, the rows alone)" :required t)
          (rows list "The rows, each an array of cells")
          (key any "The column (index from 0, or name) whose cell identifies a row")
          (align list "Each column's alignment: left, right, center (numbers: right)")
          (sort any "The column (index from 0, or name) its rows are sorted by (s on a column in the canvas)")
          (descending boolean "Sorted the other way: largest first")
          (row-actions list "Buttons on each row: [{\"label\", \"prompt\", \"submit\"}], the prompt's {Column} its cell, {row} all"))
  :example (:title "Tests" :columns ("Test" "Result" "Time") :key 0
            :rows (("lexer" "passed" "0.4s") ("parser" "running" nil)))
  :check #'agent-ui-table--check
  :append #'agent-ui-table--append
  :text #'agent-ui-table--text)
