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
    (plist-put props :key (agent-ui-table--key-index (plist-get props :key) columns))
    ;; Asking the user to pick rows (doom-ord): its settings; what's picked,
    ;; each a row's key cell (or its first).
    (when-let* ((select (plist-get props :select)))
      (agent-ui-ask-select-check "table" select)
      (agent-ui-ask-check "table" (plist-get props :selected) (agent-ui-table--answers props)
                          (eq (plist-get select :multiple) t)))
    props))

(defun agent-ui-table--answer-index (props)
  "The column a picked row answers with: its key, else its first."
  (or (plist-get props :key) 0))

(defun agent-ui-table--answers (props)
  "Each row's answer, if picked (its key cell, else its first), in order."
  (let ((i (agent-ui-table--answer-index props)))
    (mapcar (lambda (row) (agent-ui-table--cell (nth i row))) (plist-get props :rows))))

(defun agent-ui-table--cell-widths (header rows)
  "Each column's cells' widths, from HEADER's and ROWS' (their cells' widths,
measured once): a list per column, its header's first."
  (apply #'cl-mapcar #'list header rows))

(defconst agent-ui-table--longest-state
  (apply #'max (mapcar (lambda (s) (length (car s))) agent-ui-table--states))
  "The longest cell coloured by its state: longer ones aren't looked up.")

(defun agent-ui-table--narrowest (width)
  "The narrowest a column is cut to in a table WIDTH columns wide: 8, less
when narrow (6 at 24), 3 at least. Narrower, every cell read \"do…\":
columns are left out instead (said under it)."
  (max 3 (min 8 (/ width 4))))

(defun agent-ui-table--narrowests (columns key max-width)
  "Each of COLUMNS' narrowest (their cells' widths, `--cell-widths') in
MAX-WIDTH: its widest cell's, at most `agent-ui-table--narrowest'; KEY's (the
column naming a row) whole, up to MAX-WIDTH."
  (let ((narrowest (agent-ui-table--narrowest max-width)))
    (cl-loop for cells in columns
             for i from 0
             collect (min (apply #'max cells) (if (eql i key) max-width narrowest)))))

(defun agent-ui-table--widths (columns max-width &optional narrowests)
  "Each column's width (COLUMNS: their cells' widths, `--cell-widths'): its
widest cell's, the widest cut down until the table fits MAX-WIDTH, none
under its NARROWESTS' (`--narrowests'), else under 3."
  (let* ((widths (vconcat (mapcar (lambda (cells) (apply #'max cells)) columns)))
         (floors (vconcat (or narrowests (make-list (length widths) 3)))))
    ;; A table's width: each column and a space either side, a │ between,
    ;; less the last one's trailing space.
    (cl-flet ((total () (+ (cl-reduce #'+ widths) (* 3 (length widths)) -2))
              ;; The widest column wider than FLOOR (its own, or 3).
              (widest (own)
                (let ((best nil))
                  (dotimes (i (length widths))
                    (when (and (> (aref widths i) (max 3 (if own (aref floors i) 3)))
                               (or (null best) (> (aref widths i) (aref widths best))))
                      (setq best i)))
                  best)))
      (let (cut)
        (while (and (> (total) max-width)
                    (setq cut (or (widest t) (widest nil))))
          (cl-decf (aref widths cut)))))
    (append widths nil)))

(defun agent-ui-table--fitting (narrowests max-width)
  "How many columns fit MAX-WIDTH, each at its NARROWESTS' (`--narrowests'):
those on the left, one at least."
  (let ((k (length narrowests)))
    (while (and (> k 1)
                (> (+ (apply #'+ (seq-take narrowests k)) (* 3 k) -2) max-width))
      (cl-decf k))
    k))

(defun agent-ui-table--number (cell)
  "CELL as a number, if it's one, with a unit or % maybe (\"0.4s\": 0.4,
\"1,204\": 1204, \"12 MB\": 12), or nil (\"2026-11-14\", \"12:01:03\",
\"1.2.10\": their leading numbers alone sorted them wrong)."
  (when (string-match "\\`[-+]?[0-9][0-9,]*\\(?:\\.[0-9]+\\)?\\(?: ?\\(?:%\\|[[:alpha:]][[:alpha:]/]*\\)\\)?\\'"
                      (string-trim cell))
    (string-to-number (string-replace "," "" (string-trim cell)))))

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
\(\"2m 05s\", \"850ms\"), else as numbers if they all are (a unit or % after
them maybe), else as text, the numbers in it by their value (dates, times,
versions: 1.2.9 before 1.2.10); DESCENDING the other way; empty cells last."
  (let* ((cells (seq-remove #'string-empty-p (mapcar (lambda (r) (nth column r)) rows)))
         (durations (and cells (cl-every #'agent-ui-table--duration cells)))
         (numbers (and cells (cl-every #'agent-ui-table--number cells)))
         (before (lambda (a b)
                   (cond (durations (< (agent-ui-table--duration a) (agent-ui-table--duration b)))
                         (numbers (< (agent-ui-table--number a) (agent-ui-table--number b)))
                         (t (string-version-lessp (downcase a) (downcase b)))))))
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
space (they broke the table's lines and its border). Most have neither: as
they are (a copy for each, a table's drawing was most of its time in
collecting garbage)."
  (let ((text (agent-ui-cell value)))
    (if (not (string-match-p "[\t\n\r]" text))
        text
      (replace-regexp-in-string
       "\t" " " (replace-regexp-in-string "\r?\n" "⏎" text)))))

(defvar agent-ui-table--layouts (make-hash-table :test #'eq :weakness 'key)
  "The layouts tables were drawn in (`agent-ui-table--layout-key'), by their
rows (the list): an append draws only its rows if the layout stays.")

(defun agent-ui-table--layout (props ctx)
  "How PROPS' table is laid out in CTX: a plist of its parts (its cells as
text, the rows drawn and their cells' widths, its header, columns shown,
widths, alignments, buttons beside or under)."
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
         ;; Each cell measured once.
         (measured (mapcar (lambda (row) (mapcar #'string-width row)) rows))
         (cell-widths (agent-ui-table--cell-widths (mapcar #'string-width header) measured))
         (beside (and actions
                      (let ((full (agent-ui-table--widths cell-widths most-positive-fixnum)))
                        (<= (+ (apply #'+ full) (* 3 (length full)) -2 actions-width)
                            (plist-get ctx :width)))))
         (room (max 4 (- (plist-get ctx :width) (if beside actions-width 0))))
         ;; The columns that fit, each at its narrowest (the key column
         ;; whole, the others 8 wide, less when narrow): the others left
         ;; out, said under it (cut to 3, every cell read "do…").
         (narrowests (agent-ui-table--narrowests cell-widths (agent-ui-table--answer-index props) room))
         (shown (agent-ui-table--fitting narrowests room))
         (widths (agent-ui-table--widths (seq-take cell-widths shown) room (seq-take narrowests shown)))
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
         ;; The sorted column's name cut, its arrow kept (cut, it went first).
         (header (cl-loop for c in header for name in columns for w in widths for i from 0
                          collect (if (and (eql i sort) (> (string-width c) w))
                                      (concat (agent-ui-truncate name (max 1 (- w 2)))
                                              (if descending " ↓" " ↑"))
                                    c))))
    (list :columns columns :n n :all all :rows rows :measured measured :header header
          :actions actions :beside beside :shown shown :widths widths :align align
          ;; Asking: the rows pickable (not once answered, nor in a still picture).
          :props props :select (plist-get props :select)
          :pick (and (plist-get props :select) (not (plist-get props :answered)) (not (plist-get ctx :still))))))

(defun agent-ui-table--layout-key (layout ctx)
  "What of LAYOUT its drawn lines depend on (an append keeps them if it's
the same): the width, the header, the columns shown, their widths and
alignments, the buttons."
  (list (plist-get ctx :width) (plist-get layout :header) (plist-get layout :shown)
        (plist-get layout :widths) (plist-get layout :align)
        (and (plist-get layout :actions) t) (plist-get layout :beside)))

(defun agent-ui-table--left-out (layout ctx)
  "The line saying which columns LAYOUT leaves out (nil: none), wrapped to
CTX's width under its start: each named (cut, the last ones weren't)."
  (let ((n (plist-get layout :n))
        (shown (plist-get layout :shown)))
    (when (< shown n)
      (propertize
       (concat " " (replace-regexp-in-string
                    "\n" "\n   " (agent-ui-wrap (format "… %d more %s: %s" (- n shown)
                                                       (if (= (- n shown) 1) "column" "columns")
                                                       (string-join (nthcdr shown (plist-get layout :columns)) ", "))
                                               (- (plist-get ctx :width) 3))))
       'face 'agent-ui-muted))))

(defun agent-ui-table--build (layout ctx rows measured &optional full)
  "ROWS' lines (MEASURED their cells' widths) laid out as LAYOUT says; FULL:
the whole table, its header, \"no rows yet\" and what's left out too."
  (let ((columns (plist-get layout :columns))
        (n (plist-get layout :n))
        (all (plist-get layout :all))
        (header (plist-get layout :header))
        (actions (plist-get layout :actions))
        (beside (plist-get layout :beside))
        (shown (plist-get layout :shown))
        (widths (plist-get layout :widths))
        (align (plist-get layout :align))
        ;; Asking (select): a mark before each row, the row a button picking it.
        (select (plist-get layout :select))
        (props (plist-get layout :props)))
    ;; Its text made plain in a buffer, where its cells' faces and columns go
    ;; noted, then put on the string taken out once: each made once (joined
    ;; as strings, every cell's properties were copied at each join; put in
    ;; the buffer, they were made twice: most of the drawing went in
    ;; collecting that garbage). The same hidden buffer each time (made and
    ;; killed each time, it cost as much again), no change hooks.
    (let ((marks nil) (text nil))
      (with-current-buffer (get-buffer-create " *agent-ui-table*")
        (setq-local buffer-undo-list t)
        (let ((inhibit-modification-hooks t))
          (erase-buffer)
          (cl-flet ((line (cells &optional face trim measured)
                      ;; Each cell its column's (`s' there sorts by it); MEASURED
                      ;; its cells' widths (else measured here); TRIM: the line's
                      ;; trailing spaces left out, its marks cut there.
                      (let ((start (point)))
                        (cl-loop for cell in cells
                                 for cell-width in (or measured (mapcar #'string-width cells))
                                 for width in widths
                                 for a in align
                                 for i from 0
                                 do (let* ((cut (> cell-width width))
                                           (text (if cut (agent-ui-truncate cell width) cell))
                                           (space (- width (if cut (string-width text) cell-width)))
                                           (left (pcase a ('right space) ('center (/ space 2)) (_ 0)))
                                           ;; Its colour by its whole text ("passed" cut).
                                           (state (and (<= (length cell) agent-ui-table--longest-state)
                                                       (cdr (assoc-string cell agent-ui-table--states t)))))
                                      (unless (= i 0)
                                        (push (list (point) (1+ (point)) 'face 'agent-ui-muted) marks)
                                        (insert "│"))
                                      (let ((from (point)))
                                        (insert " " (make-string left ?\s) text (make-string (- space left) ?\s) " ")
                                        (push (list from (point) 'agent-ui-table-column i) marks)
                                        (when (or face state)
                                          (push (list (1+ from) (1- (point)) 'face (or face state)) marks)))))
                        (when trim
                          (let ((end (point)))
                            (skip-chars-backward " \t\n\r" start)
                            (delete-region (point) end))
                          ;; This line's marks (the latest) cut at its end.
                          (let ((cut (point)) (kept nil))
                            (while (and marks (>= (caar marks) start))
                              (let ((m (pop marks)))
                                (cond ((>= (car m) cut))
                                      ((> (cadr m) cut) (push (list (car m) cut (nth 2 m) (nth 3 m)) kept))
                                      (t (push m kept)))))
                            (setq marks (nconc (nreverse kept) marks)))))))
            ;; No column named: no header, the rows alone.
            (when (and full (not (cl-every #'string-empty-p columns)))
              (when select (insert "    "))
              (line header 'bold t)
              (insert "\n" (if select "    " "")
                      ;; As wide as the lines: the last column's has no space after it.
                      (propertize (mapconcat (lambda (w) (make-string (+ w 2) ?─))
                                             (append (butlast widths) (list (1- (car (last widths)))))
                                             "┼")
                                  'face 'agent-ui-muted)
                      "\n"))
            (if rows
                (cl-loop for row in rows
                         for row-widths in measured
                         for first = t then nil
                         do (unless first (insert "\n"))
                         (let* ((row-start (point))
                                (answer (and select (nth (agent-ui-table--answer-index props) row)))
                                (multiple (and select (eq (plist-get select :multiple) t)))
                                ;; The row (its mark and cells, not its buttons) a
                                ;; button picking it, while it can be.
                                (pickable (lambda ()
                                            (when (plist-get layout :pick)
                                              (let ((end (point))
                                                    (toggled (agent-ui-ask-toggled props answer multiple)))
                                                (dolist (prop (list (list 'agent-ui-action
                                                                          (lambda () (agent-ui-ask-change
                                                                                      ctx (list :selected toggled))))
                                                                    (list 'keymap agent-ui-button-map)
                                                                    (list 'mouse-face 'highlight)
                                                                    (list 'help-echo (if multiple "RET: (un)check it"
                                                                                       "RET: choose it"))))
                                                  (push (list row-start end (car prop) (cadr prop)) marks)))))))
                           (when select
                             (insert (agent-ui-ask-mark (agent-ui-ask-picked-p props answer) multiple) " "))
                           (cond
                            (beside (line row nil nil row-widths)
                                    (funcall pickable)
                                    (insert " " (agent-ui-table--row-buttons actions columns row)))
                            (actions (line row nil t row-widths)
                                     (funcall pickable)
                                     (insert "\n " (agent-ui-truncate (agent-ui-table--row-buttons actions columns row)
                                                                      (1- (plist-get ctx :width)))))
                            (t (line row nil t row-widths)
                               (funcall pickable)))))
              (insert " " (propertize "no rows yet" 'face 'agent-ui-muted)))
            (when (and full (> (length all) (length rows)))
              (insert "\n " (propertize (format "… %d rows more" (- (length all) (length rows)))
                                        'face 'agent-ui-muted)))
            (when-let* ((left-out (and full (agent-ui-table--left-out layout ctx))))
              (insert "\n" left-out))
            (setq text (buffer-string))
            (erase-buffer))))
      ;; Its cells' and bars' properties, on the string itself.
      (dolist (m marks)
        (put-text-property (1- (nth 0 m)) (1- (nth 1 m)) (nth 2 m) (nth 3 m) text))
      text)))


(defun agent-ui-table--text (props ctx)
  (let* ((select (plist-get props :select))
         (width (plist-get ctx :width))
         ;; Asking: a mark's 4 columns before each row.
         (inner (if select (plist-put (copy-sequence ctx) :width (max 10 (- width 4))) ctx))
         (layout (agent-ui-table--layout props inner)))
    ;; Its layout kept, by its rows: an append draws only its rows if it
    ;; stays (`agent-ui-table--extend').
    (puthash (plist-get props :rows) (agent-ui-table--layout-key layout inner) agent-ui-table--layouts)
    (let ((table (agent-ui-table--build layout inner (plist-get layout :rows) (plist-get layout :measured) t)))
      (if (not select)
          table
        (agent-ui-ask-around props ctx table (agent-ui-table--answers props))))))

(defun agent-ui-table--extend (old new ctx)
  "OLD's drawing edited into NEW's, NEW being OLD with rows appended (else
nil: drawn again): the new rows' lines put after the others (before what's
left out), if the layout stays (no column wider, nor aligned otherwise, the
buttons where they were), nothing sorts them, and all are drawn."
  (let ((old-rows (plist-get old :rows))
        (new-rows (plist-get new :rows)))
    (when (and old-rows
               ;; Asking: drawn again (its marks and buttons).
               (not (plist-get new :select))
               (> (length new-rows) (length old-rows))
               (<= (length new-rows) agent-ui-max-rows)
               (not (plist-get new :sort))
               (equal (agent-ui--plist-delete old :rows) (agent-ui--plist-delete new :rows))
               (cl-every #'equal old-rows new-rows))
      (let* ((before (gethash old-rows agent-ui-table--layouts))
             (layout (agent-ui-table--layout new ctx))
             (key (agent-ui-table--layout-key layout ctx)))
        (when (equal before key)
          (puthash new-rows key agent-ui-table--layouts)
          (let ((added (- (length new-rows) (length old-rows))))
            (list (list 'insert (let ((left-out (agent-ui-table--left-out layout ctx)))
                                  (if left-out (1+ (cl-count ?\n left-out)) 0))
                        (agent-ui-table--build layout ctx (last (plist-get layout :rows) added)
                                               (last (plist-get layout :measured) added))))))))))

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
putting a prompt with its cells into the session's prompt. SELECT asks the
user to pick rows (which to fix): marks before them, Send puts \"Answer to
ID (QUESTION): their keys\" into your prompt."
  :props ((columns list "The columns' names (all \"\": no header, the rows alone)" :required t)
          (rows list "The rows, each an array of cells")
          (key any "The column (index from 0, or name) whose cell identifies a row")
          (align list "Each column's alignment: left, right, center (numbers: right)")
          (sort any "The column (index from 0, or name) its rows are sorted by (s on a column in the canvas)")
          (descending boolean "Sorted the other way: largest first")
          (row-actions list "Buttons on each row: [{\"label\", \"prompt\", \"submit\"}], the prompt's {Column} its cell, {row} all")
          (select any "Ask the user to pick rows: {\"question\", \"multiple\", \"note\", \"submit\"}; the answer names their KEY cells (else the first)")
          (selected list "The rows picked so far (their key cells): a default, or the user's")
          (note-text string "The user's note")
          (answered string "The answer given (then it can't be changed)"))
  :example (:title "Tests" :columns ("Test" "Result" "Time") :key 0
            :rows (("lexer" "passed" "0.4s") ("parser" "running" nil)))
  :check #'agent-ui-table--check
  :append #'agent-ui-table--append
  :extend #'agent-ui-table--extend
  :text #'agent-ui-table--text)
