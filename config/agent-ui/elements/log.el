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

(defconst agent-ui-log--levels
  '((error "\\b\\(?:error\\|err\\|fatal\\|panic\\|failed\\|failure\\|exception\\|critical\\)\\b" agent-ui-error)
    (warning "\\b\\(?:warn\\|warning\\|deprecated\\)\\b" agent-ui-warning)
    (debug "\\b\\(?:debug\\|trace\\)\\b" agent-ui-muted)
    (info "\\b\\(?:info\\|notice\\)\\b" nil))
  "Levels, the words finding them (in this order), their faces.")

(defun agent-ui-log--level (text)
  "TEXT's level, by its words; nil if none."
  (let ((case-fold-search t))
    (car (seq-find (lambda (l) (string-match-p (nth 1 l) text)) agent-ui-log--levels))))

(defun agent-ui-log--as-list (lines)
  "LINES, text or a list, as a list: empty text, none."
  (cond ((not (stringp lines)) lines)
        ((string-empty-p (string-trim-right lines "\n+")) nil)
        (t (split-string (string-trim-right lines "\n+") "\n"))))

(defun agent-ui-log--lines (props)
  "PROPS' lines as (LEVEL . TEXT), the last KEEP."
  (let* ((raw (plist-get props :lines))
         (entries (agent-ui-log--as-list raw))
         (lines (mapcar (lambda (e)
                          (if (stringp e)
                              (cons (agent-ui-log--level e) e)
                            (cons (let ((l (plist-get e :level))) (if (stringp l) (intern l) l))
                                  (agent-ui-cell (plist-get e :text)))))
                        entries)))
    (last lines (plist-get props :keep))))

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

(defun agent-ui-log--draw (props ctx)
  (let* ((lines (agent-ui-log--lines props))
         (width (plist-get ctx :width))
         (count (lambda (level) (cl-count level lines :key #'car)))
         (errors (funcall count 'error))
         (warnings (funcall count 'warning))
         (shown (last lines (plist-get props :show))))
    (if (null lines)
        (propertize "no lines yet" 'face 'agent-ui-muted)
      (concat
       (string-join
        (delq nil (list (and (> errors 0) (propertize (format "%d error%s" errors (if (= errors 1) "" "s")) 'face 'agent-ui-error))
                        (and (> warnings 0) (propertize (format "%d warning%s" warnings (if (= warnings 1) "" "s"))
                                                        'face 'agent-ui-warning))
                        (propertize (format "%d line%s" (length lines) (if (= (length lines) 1) "" "s")) 'face 'agent-ui-muted)))
        (propertize " · " 'face 'agent-ui-muted))
       "\n"
       (mapconcat (lambda (line)
                    (let ((face (nth 2 (assq (car line) agent-ui-log--levels)))
                          (text (agent-ui-truncate (string-replace "\t" "    " (cdr line)) width)))
                      (if face (propertize text 'face face) text)))
                  shown "\n")))))

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
  :text #'agent-ui-log--draw)
