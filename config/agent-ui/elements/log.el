;;; $DOOMDIR/config/agent-ui/elements/log.el -*- lexical-binding: t; -*-
;; Agent UI's log: lines, each coloured by its level. Loaded from
;; config/agent-ui/elements.el.
;;
;; LINES (text: one per line; or a list of them) as they come, the last KEEP
;; kept; each line's level found by its words (error, fatal, panic, failed;
;; warn; info; debug, trace: case aside) or given as {"level", "text"}: by
;; the same words, case aside, and syslog's, Datadog's and Java's names
;; (warn, WARNING, fatal, crit, alert, trace, ok...).
;; Errors red, warnings yellow, debug muted; a line above counts them. With
;; a source, appended as they come: {"file": "app.log", "from": "end",
;; "into": "lines"}, or rules appending {"lines": ["$0"]}.
;;
;;   2 errors · 1 warning · 120 lines
;;   12:01:03 INFO  listening on :8080
;;   12:01:09 ERROR db: connection refused
;;
;; A line in columns, given its parts: {"time", "mark", "mark-face",
;; "source", "text", "right", "indent", "level"}: its time muted, shown
;; when it changes; its mark coloured (mark-face); its source (a job, a
;; service) in its own colour (by its place in SOURCES, else by its name);
;; its text (a list of pieces, each text or {"text", "face"}), indented;
;; RIGHT muted at the line's end (how long it took). {"gap": "17m"}: a
;; pause between two lines, not counted. RIGHT on the log: its counts
;; line's end (its span); UNIT what it counts (events).
;;
;;   ✗ 1 error · 6 events                            16:22 – 16:41 · 19m
;;   16:22  ▸  green    started
;;          ›  green      watch started
;;          ┊  17m
;;   16:39  ✗  green      watch exited 1                         16m 32s

(require 'cl-lib)
(require 'subr-x)

(defun agent-ui-log--words (&rest words)
  "A regexp of WORDS, whole: not beside a letter, a digit or _ (with \\b,
error_count was an error)."
  (concat "\\(?:\\`\\|[^[:alnum:]_]\\)" (regexp-opt words) "\\(?:[^[:alnum:]_]\\|\\'\\)"))

(defconst agent-ui-log--levels
  (list (list 'error (agent-ui-log--words "error" "err" "fatal" "panic" "failed" "failure" "exception" "critical")
              'agent-ui-error)
        (list 'warning (agent-ui-log--words "warn" "warning" "deprecated") 'agent-ui-warning)
        (list 'debug (agent-ui-log--words "debug" "trace") 'agent-ui-muted)
        (list 'info (agent-ui-log--words "info" "notice") nil))
  "Levels, the words finding them (in this order), their faces.")

(defconst agent-ui-log--none
  (concat "\\(?:\\`\\|[^[:alnum:]_.]\\)\\(?:0\\|no\\) +"
          "\\(?:failed\\|failures?\\|errors?\\|warnings?\\)\\(?:(s)\\)?\\_>"
          ;; Plural only: \"ERROR: 0 is not a port\" is one.
          "\\|\\_<\\(?:failed\\|failures\\|errors\\|warnings\\) *[:=] *0\\(?:[^[:alnum:]_.]\\|\\'\\)")
  "A count of none, not an error nor a warning: cargo's \"0 failed\", \"no
errors\", Maven's \"Errors: 0\", \"0 Warning(s)\".")

(defun agent-ui-log--level (text)
  "TEXT's level, by its words (counts of none aside); nil if none."
  (let* ((case-fold-search t)
         (text (replace-regexp-in-string agent-ui-log--none " " text)))
    (car (seq-find (lambda (l) (string-match-p (nth 1 l) text)) agent-ui-log--levels))))

(defconst agent-ui-log--given-words
  '(("emerg" . error) ("emergency" . error) ("alert" . error) ("crit" . error) ("severe" . error)
    ("ok" . info) ("fine" . debug) ("finer" . debug) ("finest" . debug))
  "Levels a line is given by, not found in its text: syslog's, Datadog's,
Java's (alert, ok, fine in a line's text are no level).")

(defun agent-ui-log--given (level)
  "A line's given LEVEL (text or a symbol: error, warn, WARNING, fatal,
trace, Datadog's statuses...) as a level, read by the words a line's text is
and `agent-ui-log--given-words', case aside; nil if none."
  (when-let* ((name (cond ((stringp level) level)
                          ((and level (symbolp level)) (symbol-name level)))))
    (or (cdr (assoc-string (string-trim name) agent-ui-log--given-words t))
        (agent-ui-log--level name))))

(defun agent-ui-log--plain (text)
  "TEXT without a terminal's escape sequences: colours (tools forcing them
showed ^[[31m...), cursor moves, titles and links."
  (replace-regexp-in-string
   "\e\\(?:\\[[0-?]*[ -/]*[@-~]\\|\\][^\a\e]*\\(?:\a\\|\e\\\\\\)?\\|[@-Z\\\\-_]\\)" "" text t t))

(defun agent-ui-log--as-list (lines)
  "LINES, text or a list, as a list: empty text, none."
  (cond ((not (stringp lines)) lines)
        ((string-empty-p (string-trim-right lines "\n+")) nil)
        (t (split-string (string-trim-right lines "\n+") "\n"))))

(defvar agent-ui-log--parsed (make-hash-table :test #'equal :weakness 'key)
  "Lines already read, as (LEVEL . TEXT), by the line as given: a long log
drawn again (a line appended) reads each of its lines once.")

(defconst agent-ui-log--faces
  '(("plain") ("muted" . agent-ui-muted) ("accent" . agent-ui-accent) ("success" . agent-ui-success)
    ("warning" . agent-ui-warning) ("error" . agent-ui-error) ("bold" . agent-ui-title))
  "The faces a line's mark and its text's pieces are given by.")

(defcustom agent-ui-log-source-faces
  '(font-lock-keyword-face font-lock-function-name-face font-lock-constant-face font-lock-variable-name-face)
  "The colours of a log's sources (its jobs, its services), in turn: by
their place in its SOURCES, else by their names."
  :type '(repeat face)
  :group 'agent-ui)

(defconst agent-ui-log--columns '(:time :mark :source :right :indent :gap)
  "A line's parts that make it one in columns (its text a list, too).")

(defun agent-ui-log--face (name)
  "The face NAME (text or a symbol: muted, error...) says; nil for plain or
none."
  (and name (cdr (assoc (format "%s" name) agent-ui-log--faces))))

(defun agent-ui-log--columns-p (entry)
  "Whether ENTRY, a line as given, is one in columns."
  (and (consp entry)
       (or (seq-some (lambda (key) (plist-member entry key)) agent-ui-log--columns)
           (consp (plist-get entry :text)))))

(defun agent-ui-log--pieces (text face)
  "TEXT, a line's (text, or a list of pieces: text, or {text, face}), as one
string, each piece in its face; TEXT that's one piece, in FACE."
  (if (consp text)
      (mapconcat (lambda (piece)
                   (if (consp piece)
                       (let ((string (agent-ui-log--plain (agent-ui-cell (plist-get piece :text))))
                             (face (agent-ui-log--face (plist-get piece :face))))
                         (if face (propertize string 'face face) string))
                     (agent-ui-log--plain (agent-ui-cell piece))))
                 text "")
    (let ((string (agent-ui-log--plain (agent-ui-cell (or text "")))))
      (if face (propertize string 'face face) string))))

(defun agent-ui-log--line (entry)
  "ENTRY, a line as given (text, {level, text}, or one in columns), as
\(LEVEL . TEXT); one in columns as (LEVEL . PARTS), PARTS a plist (:text,
its pieces in their faces; :time :mark :mark-face :source :right :indent);
a pause (gap . (:gap TEXT))."
  (or (gethash entry agent-ui-log--parsed)
      (puthash entry
               (cond ((stringp entry)
                      (let ((text (agent-ui-log--plain entry)))
                        (cons (agent-ui-log--level text) text)))
                     ((plist-get entry :gap)
                      (cons 'gap (list :gap (agent-ui-cell (plist-get entry :gap)))))
                     ((agent-ui-log--columns-p entry)
                      (let ((level (agent-ui-log--given (plist-get entry :level))))
                        (cons level
                              (list :text (agent-ui-untabify
                                           (agent-ui-log--pieces (plist-get entry :text)
                                                                 (nth 2 (assq level agent-ui-log--levels))))
                                    :time (and (plist-get entry :time) (agent-ui-cell (plist-get entry :time)))
                                    :mark (and (plist-get entry :mark) (agent-ui-cell (plist-get entry :mark)))
                                    :mark-face (agent-ui-log--face (plist-get entry :mark-face))
                                    :source (and (plist-get entry :source) (agent-ui-cell (plist-get entry :source)))
                                    :right (and (plist-get entry :right) (agent-ui-cell (plist-get entry :right)))
                                    :indent (or (plist-get entry :indent) 0)))))
                     (t
                      (cons (agent-ui-log--given (plist-get entry :level))
                            (agent-ui-log--plain (agent-ui-cell (plist-get entry :text))))))
               agent-ui-log--parsed)))

(defun agent-ui-log--lines (props)
  "PROPS' lines as (LEVEL . TEXT), the last KEEP."
  (last (mapcar #'agent-ui-log--line (agent-ui-log--as-list (plist-get props :lines)))
        (plist-get props :keep)))

(defun agent-ui-log--check (props)
  (let ((raw (plist-get props :lines)))
    (unless (or (stringp raw) (listp raw))
      (agent-ui--fail "log: lines is text or a list"))
    (when (listp raw)
      (cl-loop for e in raw
               for i from 1
               unless (or (stringp e) (and (agent-ui--plist-p e) (or (plist-get e :text) (plist-get e :gap))))
               do (agent-ui--fail "log: line %d must be text, or {\"level\", \"text\"}" i)
               when (and (consp e) (plist-get e :level) (not (agent-ui-log--given (plist-get e :level))))
               do (agent-ui--fail "log: line %d's level %S is none of error, warning, info, debug (nor their words: warn, fatal, critical, trace, notice...)"
                                  i (plist-get e :level))
               when (consp e)
               do (agent-ui-log--check-parts e i))))
  (unless (listp (plist-get props :sources))
    (agent-ui--fail "log: sources is a list of names"))
  (unless (<= 1 (plist-get props :keep) 5000)
    (agent-ui--fail "log: keep is 1 to 5000 lines"))
  ;; Below 0: no lines shown, silently.
  (when (< (plist-get props :show) 0)
    (agent-ui--fail "log: show must be 0 or more, not %d" (plist-get props :show)))
  props)

(defun agent-ui-log--check-parts (entry i)
  "ENTRY, line I of a log, its parts checked: its faces, its indent, its
text's pieces."
  (dolist (key '(:mark-face))
    (when-let* ((face (plist-get entry key)))
      (unless (assoc (format "%s" face) agent-ui-log--faces)
        (agent-ui--fail "log: line %d's %s %S is none of %s" i (substring (symbol-name key) 1) face
                        (mapconcat #'car agent-ui-log--faces ", ")))))
  (when-let* ((indent (plist-get entry :indent)))
    (unless (and (integerp indent) (<= 0 indent 4))
      (agent-ui--fail "log: line %d's indent is 0 to 4, not %S" i indent)))
  (let ((text (plist-get entry :text)))
    (when (consp text)
      (cl-loop for piece in text
               unless (or (stringp piece) (numberp piece) (and (agent-ui--plist-p piece) (plist-get piece :text)))
               do (agent-ui--fail "log: line %d's text is text, or a list of pieces: text, or {\"text\", \"face\"}" i)
               when (and (consp piece) (plist-get piece :face) (not (assoc (format "%s" (plist-get piece :face)) agent-ui-log--faces)))
               do (agent-ui--fail "log: line %d's piece's face %S is none of %s" i (plist-get piece :face)
                                  (mapconcat #'car agent-ui-log--faces ", "))))))

(defun agent-ui-log--append (element patch)
  "ELEMENT with PATCH's lines after its own (text or lists, either)."
  (cl-loop for (k _) on patch by #'cddr
           unless (memq k '(:id :lines :right))
           do (agent-ui--fail "log: only lines can be appended to (its right, its counts line's end, replaced with them)"))
  (let ((all (append (agent-ui-log--as-list (plist-get element :lines))
                     (agent-ui-log--as-list (plist-get patch :lines))))
        (element (copy-sequence element)))
    (when (plist-member patch :right)
      (setq element (plist-put element :right (plist-get patch :right))))
    (plist-put element :lines (last all 5000))))

(defun agent-ui-log--counts (lines width &optional unit right)
  "LINES' counts line, WIDTH wide at most: the last left out while it doesn't
fit (the lines', the warnings'), the errors' cut last (never cut: 30 columns
at 15). UNIT: what a line is (line; pauses aside); RIGHT: muted, at its end
if it fits. A log in columns (one of LINES is): its errors and warnings
marked as its lines are (✗ 2 errors, ◆ 1 warning)."
  (let* ((errors (cl-count 'error lines :key #'car))
         (warnings (cl-count 'warning lines :key #'car))
         (count (cl-count-if-not (lambda (line) (eq (car line) 'gap)) lines))
         (unit (or unit "line"))
         (marked (seq-some (lambda (line) (consp (cdr line))) lines))
         (parts (delq nil (list (and (> errors 0) (propertize (format "%s%d error%s" (if marked "✗ " "") errors
                                                                      (if (= errors 1) "" "s"))
                                                              'face 'agent-ui-error))
                                (and (> warnings 0) (propertize (format "%s%d warning%s" (if marked "◆ " "") warnings
                                                                        (if (= warnings 1) "" "s"))
                                                                'face 'agent-ui-warning))
                                (propertize (format "%d %s%s" count unit (if (= count 1) "" "s"))
                                            'face 'agent-ui-muted))))
         (sep (propertize " · " 'face 'agent-ui-muted)))
    (while (and (cdr parts) (> (string-width (string-join parts sep)) width))
      (setq parts (butlast parts)))
    (let ((left (agent-ui-truncate (string-join parts sep) width)))
      (if (and (stringp right) (not (string-empty-p right))
               (<= (+ (string-width left) 3 (string-width right)) width))
          (concat left (make-string (- width (string-width left) (string-width right)) ?\s)
                  (propertize right 'face 'agent-ui-muted))
        left))))

(defun agent-ui-log--line-text (line width)
  "LINE, (LEVEL . TEXT), drawn WIDTH wide at most, in its level's face: too
long, wrapped, its next lines indented 2 (it was cut with …, its rest
nowhere; `agent-ui-max-cell-lines' lines at most)."
  (let* ((face (nth 2 (assq (car line) agent-ui-log--levels)))
         (text (agent-ui-untabify (cdr line)))
         (text (if (<= (string-width text) width)
                   text
                 (let ((lines (agent-ui-wrap-lines text (max 1 (- width 2)))))
                   (concat (car lines) (mapconcat (lambda (l) (concat "\n  " l)) (cdr lines) ""))))))
    (if face (propertize text 'face face) text)))

(defun agent-ui-log--layout (props lines)
  "The columns of LINES (parsed, those shown) of a log with PROPS: (TIME MARK
SOURCE), each its width, 0 if none of them has it (a source's: SOURCES'
widest too, if it has them)."
  (let ((time 0) (mark 0)
        (source (apply #'max 0 (mapcar (lambda (name) (string-width (agent-ui-cell name)))
                                       (plist-get props :sources)))))
    (dolist (line lines)
      (let ((parts (cdr line)))
        (when (consp parts)
          (if (eq (car line) 'gap)
              (setq mark (max mark 1))
            (when-let* ((s (plist-get parts :time))) (setq time (max time (string-width s))))
            (when-let* ((s (plist-get parts :mark))) (setq mark (max mark (string-width s))))
            (when-let* ((s (plist-get parts :source))) (setq source (max source (string-width s))))))))
    (list time mark source)))

(defun agent-ui-log--source-face (source props)
  "SOURCE's colour in a log with PROPS: by its place in its SOURCES, else by
its name."
  (let ((faces agent-ui-log-source-faces))
    (when faces
      (nth (mod (or (cl-position source (mapcar #'agent-ui-cell (plist-get props :sources)) :test #'equal)
                    (sxhash-equal source))
                (length faces))
           faces))))

(defun agent-ui-log--columns-text (line previous layout props width)
  "LINE, (LEVEL . PARTS), in LAYOUT's columns, WIDTH wide: its time unless
PREVIOUS (the line before's time) is the same; a pause, ┊ and how long."
  (pcase-let* ((`(,tw ,mw ,sw) layout)
               (parts (cdr line))
               (column (lambda (text cells face)
                         (if (> cells 0)
                             (concat (let ((text (agent-ui-pad (or text "") cells)))
                                       (if (and face text) (propertize text 'face face) text))
                                     "  ")
                           ""))))
    (if (eq (car line) 'gap)
        (agent-ui-truncate (concat (funcall column nil tw nil) (funcall column "┊" mw 'agent-ui-muted)
                                   (propertize (plist-get parts :gap) 'face 'agent-ui-muted))
                           width)
      (let* ((time (plist-get parts :time))
             (head (concat (funcall column (and time (not (equal time previous)) time) tw 'agent-ui-muted)
                           (funcall column (plist-get parts :mark) mw (plist-get parts :mark-face))
                           (funcall column (plist-get parts :source) sw
                                    (and (plist-get parts :source)
                                         (agent-ui-log--source-face (plist-get parts :source) props)))
                           (make-string (* 2 (plist-get parts :indent)) ?\s)))
             (hang (string-width head))
             (right (plist-get parts :right))
             (right (and right (not (string-empty-p right))
                         (>= (- width hang (string-width right) 2) 12)
                         (propertize right 'face 'agent-ui-muted)))
             (room (max 1 (- width hang (if right (+ 2 (string-width right)) 0))))
             (text (plist-get parts :text))
             (lines (if (<= (string-width text) room) (list text) (agent-ui-wrap-lines text room)))
             (first (concat head (car lines))))
        (concat (if right
                    (concat first (make-string (max 2 (- width (string-width first) (string-width right))) ?\s) right)
                  first)
                (mapconcat (lambda (l) (concat "\n" (make-string hang ?\s) l)) (cdr lines) ""))))))

(defun agent-ui-log--drawn (props lines width)
  "LINES (parsed, those shown) of a log with PROPS, each drawn WIDTH wide (a
wrapped one several lines): plain ones as they are, those in columns in
theirs, each one's time shown when it isn't the one before's."
  (let ((layout (agent-ui-log--layout props lines))
        (previous nil))
    (mapcar (lambda (line)
              (if (consp (cdr line))
                  (prog1 (agent-ui-log--columns-text line previous layout props width)
                    (unless (eq (car line) 'gap)
                      (setq previous (plist-get (cdr line) :time))))
                (setq previous nil)
                (agent-ui-log--line-text line width)))
            lines)))

(defun agent-ui-log--draw (props ctx)
  (let ((lines (agent-ui-log--lines props))
        (width (plist-get ctx :width)))
    (if (null lines)
        (propertize "no lines yet" 'face 'agent-ui-muted)
      (concat (agent-ui-log--counts lines width (plist-get props :unit) (plist-get props :right))
              "\n"
              (string-join (agent-ui-log--drawn props (last lines (plist-get props :show)) width) "\n")))))

(defun agent-ui-log--extend (old new ctx)
  "OLD's drawing edited into NEW's, NEW being OLD with lines appended,
fewer than it shows (else nil: drawn again): its counts line again, the
lines shown no more dropped from the top, those kept that are drawn
otherwise now (its time shown, its columns wider) again in their place, the
new ones at the end. Nil if one kept takes more or fewer lines now."
  (let* ((old-entries (agent-ui-log--as-list (plist-get old :lines)))
         (new-entries (agent-ui-log--as-list (plist-get new :lines)))
         (added (- (length new-entries) (length old-entries)))
         (show (plist-get new :show)))
    (when (and old-entries
               (< 0 added show)
               (eql show (plist-get old :show))
               (eql (plist-get new :keep) (plist-get old :keep))
               (equal (plist-get new :sources) (plist-get old :sources))
               ;; Its old lines, the new ones' start.
               (cl-every #'equal old-entries new-entries))
      (let* ((width (plist-get ctx :width))
             (new-lines (agent-ui-log--lines new))
             (old-drawn (agent-ui-log--drawn old (last (agent-ui-log--lines old) show) width))
             (new-drawn (agent-ui-log--drawn new (last new-lines show) width))
             (kept (- (length new-drawn) added))
             (drop (- (length old-drawn) kept))
             (height (lambda (text) (1+ (cl-count ?\n text))))
             (counts (agent-ui-log--counts new-lines width (plist-get new :unit) (plist-get new :right)))
             (edits (list (list 'replace 0 counts)))
             (line 1)
             ;; Its drawing's length, as `agent-ui--cap' would measure it.
             (size (lambda (counts drawn)
                     (+ (length counts) 1 (apply #'+ (mapcar #'length drawn)) (max 0 (1- (length drawn)))))))
        ;; Either drawing past the cut (`agent-ui-max-chars'): what's in the
        ;; buffer is cut, these edits aren't: drawn again whole.
        (when (or (> (funcall size counts new-drawn) agent-ui-max-chars)
                  (> (funcall size (agent-ui-log--counts (agent-ui-log--lines old) width (plist-get old :unit)
                                                         (plist-get old :right))
                                   old-drawn)
                     agent-ui-max-chars))
          (setq edits nil))
        (when (and edits (> drop 0))
          (let ((count (apply #'+ (mapcar height (seq-take old-drawn drop)))))
            (when (> count 0) (push (list 'delete 1 count) edits))))
        (catch 'whole
          (unless edits (throw 'whole nil))
          (cl-loop for was in (nthcdr drop old-drawn)
                   for is in new-drawn
                   do (cond ((equal-including-properties was is))
                            ((/= (funcall height was) (funcall height is)) (throw 'whole nil))
                            (t (cl-loop for a in (split-string was "\n")
                                        for b in (split-string is "\n")
                                        for n from line
                                        unless (equal-including-properties a b)
                                        do (push (list 'replace n b) edits))))
                   do (setq line (+ line (funcall height is))))
          (push (list 'insert 0 (string-join (nthcdr kept new-drawn) "\n")) edits)
          (nreverse edits))))))

(agent-ui-define log
  "Lines of output, each coloured by its level (found by its words: error,
fatal, panic, failed; warn; info; debug, trace; or given as {\"level\",
\"text\"}, by the same words, case aside: warn, WARNING, fatal, trace...),
errors and warnings counted above, the last SHOW shown (KEEP
kept). LINES is text (a line each) or a list. A line in columns: its time
\(muted, shown when it changes), its mark (coloured by mark-face), its
source (a job, a service: each its colour), its text (pieces, each text or
{\"text\", \"face\"}), indented, its right (muted, at its end: how long it
took); {\"gap\": \"17m\"} a pause. Follow a log as it grows with a source:
{\"file\": \"app.log\", \"from\": \"end\", \"into\": \"lines\"}; append adds
lines (and replaces its right)."
  :props ((lines any "The lines: text, one per line, or a list (text, {\"level\", \"text\"}, or a line in columns: {\"time\", \"mark\", \"mark-face\", \"source\", \"text\", \"right\", \"indent\", \"level\"}; {\"gap\": \"17m\"} a pause)" :default "")
          (show integer "How many of the last lines are shown" :default 15)
          (keep integer "How many lines are kept (counted)" :default 1000)
          (unit string "What a line is, counted above them (event: 12 events)" :default "line")
          (right string "Muted at the counts line's end (its span: 16:22 – 17:24)")
          (sources list "Its lines' sources in order: each its colour, their column as wide as the widest"))
  :example (:title "server.log"
            :lines "12:01:03 INFO  listening on :8080\n12:01:07 WARN  slow query: 1.2s\n12:01:09 ERROR db: connection refused")
  :check #'agent-ui-log--check
  :append #'agent-ui-log--append
  :extend #'agent-ui-log--extend
  :text #'agent-ui-log--draw)
