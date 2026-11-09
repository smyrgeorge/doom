;;; $DOOMDIR/config/agent-ui/elements/table.el -*- lexical-binding: t; -*-
;; Agent UI's table: columns and rows, fitting the width. With a key column,
;; an appended row whose key is there replaces that row: a test's row goes from
;; running to failed. Loaded from
;; config/agent-ui/elements.el.
;;
;;    Test    │ Result │ Time
;;   ─────────┼────────┼──────
;;    lexer   │ passed │ 0.4s

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
                 (mapcar (lambda (a)
                           (let ((sym (cond ((stringp a) (intern-soft a)) ((symbolp a) a))))
                             (if (memq sym '(left right center nil))
                                 sym
                               (agent-ui--fail "table: align is left, right or center, not %s"
                                               (agent-ui--show-value a)))))
                         align)))
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

(defun agent-ui-table--text (props ctx)
  (let* ((columns (plist-get props :columns))
         (n (length columns))
         (all (plist-get props :rows))
         (rows (mapcar (lambda (row)
                         (let ((cells (mapcar #'agent-ui-cell row)))
                           (append cells (make-list (- n (length cells)) ""))))
                       (seq-take all agent-ui-max-rows)))
         (widths (agent-ui-table--widths columns rows (plist-get ctx :width)))
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
         (bar (propertize "│" 'face 'agent-ui-muted)))
    (cl-flet ((line (cells &optional face)
                (string-trim-right
                 (mapconcat #'identity
                            (cl-loop for cell in cells
                                     for width in widths
                                     for a in align
                                     collect (let ((text (agent-ui-pad cell width a))
                                                   (state (cdr (assoc (downcase cell) agent-ui-table--states))))
                                               (concat " " (propertize text 'face (or face state)) " ")))
                            bar))))
      (concat
       (line columns 'bold) "\n"
       ;; As wide as the lines: the last column's has no space after it.
       (propertize (mapconcat (lambda (w) (make-string (+ w 2) ?─))
                              (append (butlast widths) (list (1- (car (last widths)))))
                              "┼")
                   'face 'agent-ui-muted)
       (if rows
           (concat "\n" (mapconcat #'line rows "\n"))
         (concat "\n " (propertize "no rows yet" 'face 'agent-ui-muted)))
       (when (> (length all) (length rows))
         (concat "\n " (propertize (format "… %d rows more" (- (length all) (length rows)))
                                   'face 'agent-ui-muted)))))))

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
{\"rows\": [[\"parser\", \"failed\", \"1.2s\"]]}."
  :props ((columns list "The columns' names" :required t)
          (rows list "The rows, each an array of cells")
          (key any "The column (index from 0, or name) whose cell identifies a row")
          (align list "Each column's alignment: left, right, center (numbers: right)"))
  :example (:title "Tests" :columns ("Test" "Result" "Time") :key 0
            :rows (("lexer" "passed" "0.4s") ("parser" "running" nil)))
  :check #'agent-ui-table--check
  :append #'agent-ui-table--append
  :text #'agent-ui-table--text)
