;;; $DOOMDIR/config/agent-ui/elements/log.el -*- lexical-binding: t; -*-
;; Agent UI's log: lines, each coloured by its level. Loaded from
;; config/agent-ui/elements.el.
;;
;; LINES (text: one per line; or a list of them) as they come, the last KEEP
;; kept; each line's level found by its words (error, fatal, panic, failed;
;; warn; info; debug, trace: case aside) or given as {"level", "text"}.
;; Errors red, warnings yellow, debug muted; a line above counts them. With
;; a source, appended as they come: {"file": "app.log", "from": "end",
;; "into": "lines"}, or rules appending {"lines": ["$0"]}.
;;
;;   2 errors · 1 warning · 120 lines
;;   12:01:03 INFO  listening on :8080
;;   12:01:09 ERROR db: connection refused

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

(defun agent-ui-log--line (entry)
  "ENTRY, a line as given (text, or {level, text}), as (LEVEL . TEXT)."
  (or (gethash entry agent-ui-log--parsed)
      (puthash entry
               (if (stringp entry)
                   (let ((text (agent-ui-log--plain entry)))
                     (cons (agent-ui-log--level text) text))
                 (cons (let ((l (plist-get entry :level))) (if (stringp l) (intern l) l))
                       (agent-ui-log--plain (agent-ui-cell (plist-get entry :text)))))
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
               unless (or (stringp e)
                          (and (agent-ui--plist-p e) (plist-get e :text)
                               (or (null (plist-get e :level))
                                   (assq (let ((l (plist-get e :level))) (if (stringp l) (intern-soft l) l))
                                         agent-ui-log--levels))))
               do (agent-ui--fail "log: line %d must be text, or {\"level\": error/warning/info/debug, \"text\": ...}" i))))
  (unless (<= 1 (plist-get props :keep) 5000)
    (agent-ui--fail "log: keep is 1 to 5000 lines"))
  ;; Below 0: no lines shown, silently.
  (when (< (plist-get props :show) 0)
    (agent-ui--fail "log: show must be 0 or more, not %d" (plist-get props :show)))
  props)

(defun agent-ui-log--append (element patch)
  "ELEMENT with PATCH's lines after its own (text or lists, either)."
  (cl-loop for (k _) on patch by #'cddr
           unless (memq k '(:id :lines))
           do (agent-ui--fail "log: only lines can be appended to"))
  (let ((all (append (agent-ui-log--as-list (plist-get element :lines))
                     (agent-ui-log--as-list (plist-get patch :lines)))))
    (plist-put (copy-sequence element) :lines (last all 5000))))

(defun agent-ui-log--counts (lines width)
  "LINES' counts line, WIDTH wide at most: the last left out while it doesn't
fit (the lines', the warnings'), the errors' cut last (never cut: 30 columns
at 15)."
  (let* ((errors (cl-count 'error lines :key #'car))
         (warnings (cl-count 'warning lines :key #'car))
         (parts (delq nil (list (and (> errors 0) (propertize (format "%d error%s" errors (if (= errors 1) "" "s"))
                                                              'face 'agent-ui-error))
                                (and (> warnings 0) (propertize (format "%d warning%s" warnings (if (= warnings 1) "" "s"))
                                                                'face 'agent-ui-warning))
                                (propertize (format "%d line%s" (length lines) (if (= (length lines) 1) "" "s"))
                                            'face 'agent-ui-muted))))
         (sep (propertize " · " 'face 'agent-ui-muted)))
    (while (and (cdr parts) (> (string-width (string-join parts sep)) width))
      (setq parts (butlast parts)))
    (agent-ui-truncate (string-join parts sep) width)))

(defun agent-ui-log--line-text (line width)
  "LINE, (LEVEL . TEXT), drawn WIDTH wide at most, in its level's face."
  (let ((face (nth 2 (assq (car line) agent-ui-log--levels)))
        (text (agent-ui-truncate (agent-ui-untabify (cdr line)) width)))
    (if face (propertize text 'face face) text)))

(defun agent-ui-log--draw (props ctx)
  (let ((lines (agent-ui-log--lines props))
        (width (plist-get ctx :width)))
    (if (null lines)
        (propertize "no lines yet" 'face 'agent-ui-muted)
      (concat (agent-ui-log--counts lines width)
              "\n"
              (mapconcat (lambda (line) (agent-ui-log--line-text line width))
                         (last lines (plist-get props :show)) "\n")))))

(defun agent-ui-log--extend (old new ctx)
  "OLD's drawing edited into NEW's, NEW being OLD with lines appended,
fewer than it shows (else nil: drawn again): its counts line again, the
lines shown no more dropped from the top, the new ones at the end."
  (let* ((old-entries (agent-ui-log--as-list (plist-get old :lines)))
         (new-entries (agent-ui-log--as-list (plist-get new :lines)))
         (added (- (length new-entries) (length old-entries)))
         (show (plist-get new :show)))
    (when (and old-entries
               (< 0 added show)
               (eql show (plist-get old :show))
               (eql (plist-get new :keep) (plist-get old :keep))
               ;; Its old lines, the new ones' start.
               (cl-every #'equal old-entries new-entries))
      (let* ((width (plist-get ctx :width))
             (old-lines (agent-ui-log--lines old))
             (new-lines (agent-ui-log--lines new))
             (drop (- (+ (min show (length old-lines)) added) (min show (length new-lines)))))
        (delq nil
              (list (list 'replace 0 (agent-ui-log--counts new-lines width))
                    (and (> drop 0) (list 'delete 1 drop))
                    (list 'insert 0 (mapconcat (lambda (line) (agent-ui-log--line-text line width))
                                               (last new-lines added) "\n"))))))))

(agent-ui-define log
  "Lines of output, each coloured by its level (found by its words: error,
fatal, panic, failed; warn; info; debug, trace; or given as {\"level\",
\"text\"}), errors and warnings counted above, the last SHOW shown (KEEP
kept). LINES is text (a line each) or a list. Follow a log as it grows
with a source: {\"file\": \"app.log\", \"from\": \"end\", \"into\": \"lines\"};
append adds lines."
  :props ((lines any "The lines: text, one per line, or a list (text, or {\"level\", \"text\"})" :default "")
          (show integer "How many of the last lines are shown" :default 15)
          (keep integer "How many lines are kept (counted)" :default 1000))
  :example (:title "server.log"
            :lines "12:01:03 INFO  listening on :8080\n12:01:07 WARN  slow query: 1.2s\n12:01:09 ERROR db: connection refused")
  :check #'agent-ui-log--check
  :append #'agent-ui-log--append
  :extend #'agent-ui-log--extend
  :text #'agent-ui-log--draw)
