;;; $DOOMDIR/config/agent-ui/source.el -*- lexical-binding: t; -*-
;; Agent UI's sources: an element following a command, a file or a polled
;; command, updated from its output. Loaded from config/agent-ui.el.
;;
;; The agent's tool calls run one after another: a bar it updates itself
;; stands still while it waits on a long command. Given a source, Emacs does
;; the following instead: an element's "source" is
;;   {"command": "make -j8"}               run by Emacs, in "dir" (default: the
;;                                         agent's directory), its output kept
;;                                         in a log the reply names
;;   {"file": "build.log", "from": "end"}  a file followed as it grows
;;   {"poll": "df -h /", "every": 10}      run every so many seconds
;; with "rules": each line of output that matches a rule's "match" (a regular
;; expression as in grep -E / PCRE: groups, \d \s \w, |, ?, +, *, {n,m})
;; changes the element: "set" (as an update) and "append" (as an append),
;; their strings "$1" (a group: a number if it reads as one), "$0" (the
;; match), or text with $N in it. "tail": N sets a text element's text to the
;; last N lines; "into": PROP sets PROP to all of them (a diff's diff, as a
;; poll of git diff gives it), or the last N with tail. When a command ends: "done" (exit 0) or "failed" (else),
;; patches with $code; a progress bar is done or failed by itself. A source
;; stops when its element is removed or shown again, or its canvas closed.
;; No Doom here.

(require 'cl-lib)
(require 'subr-x)

;; ====== VARIABLES ======

(defcustom agent-ui-source-log-directory
  (expand-file-name "agent-ui/" temporary-file-directory)
  "Where commands' output is kept, for the agent to read."
  :type 'directory :group 'agent-ui)

(defcustom agent-ui-source-file-interval 0.5
  "Seconds between looks at a followed file."
  :type 'number :group 'agent-ui)

(defconst agent-ui-source--keys
  '(:command :file :poll :dir :every :rules :match :set :append :tail :into :done :failed :from)
  "What a source may have.")

(cl-defstruct (agent-ui-source--state (:constructor agent-ui-source--make-state))
  "A source following, for an element of a canvas."
  kind what dir every rules tail into done failed process timer log (partial "") lines exit error
  (count 0) offset)

(defvar-local agent-ui-source--states nil
  "In a canvas: its sources, by element id.")

;; ====== REGULAR EXPRESSIONS ======

(defun agent-ui-source-regexp (pcre)
  "PCRE (its common part: grep -E's, with \\d \\s \\w \\b (?:...)) as an
Emacs regexp."
  (let ((i 0) (n (length pcre)) (out nil) (in-class nil))
    (while (< i n)
      (let ((c (aref pcre i)))
        (cond
         ((and (eq c ?\\) (< (1+ i) n))
          (cl-incf i)
          (let ((d (aref pcre i)))
            (push (pcase d
                    (?d (if in-class "0-9" "[0-9]"))
                    (?D "[^0-9]")
                    (?s (if in-class " \t\n\r\f" "[[:space:]]"))
                    (?S "[^[:space:]]")
                    (?w (if in-class "[:alnum:]_" "[[:alnum:]_]"))
                    (?W "[^[:alnum:]_]")
                    (?b "\\b")
                    (?t "\t") (?n "\n") (?r "\r")
                    ;; An escaped character: itself.
                    (_ (if in-class (string d) (regexp-quote (string d)))))
                  out)))
         (in-class
          (when (eq c ?\]) (setq in-class nil))
          (push (string c) out))
         ((eq c ?\[)
          (setq in-class t)
          (push "[" out)
          (when (and (< (1+ i) n) (eq (aref pcre (1+ i)) ?^))
            (push "^" out) (cl-incf i))
          ;; A ] first is itself.
          (when (and (< (1+ i) n) (eq (aref pcre (1+ i)) ?\]))
            (push "]" out) (cl-incf i)))
         ((eq c ?\()
          (if (and (< (+ i 2) n) (eq (aref pcre (1+ i)) ??) (eq (aref pcre (+ i 2)) ?:))
              (progn (push "\\(?:" out) (cl-incf i 2))
            (push "\\(" out)))
         ((eq c ?\)) (push "\\)" out))
         ((eq c ?|) (push "\\|" out))
         ((eq c ?{) (push "\\{" out))
         ((eq c ?}) (push "\\}" out))
         (t (push (string c) out))))
      (cl-incf i))
    (apply #'concat (nreverse out))))

;; ====== CHECKING A SOURCE ======

(defun agent-ui-source--patch (value what)
  (unless (or (null value) (agent-ui--plist-p value))
    (agent-ui--fail "source: %s must be an object of properties, not %s" what (agent-ui--show-value value)))
  value)

(defun agent-ui-source--rule (rule index)
  "RULE (:match :set :append) with its match as an Emacs regexp."
  (unless (agent-ui--plist-p rule)
    (agent-ui--fail "source: rule %d must be {\"match\": ..., \"set\"/\"append\": ...}" index))
  (cl-loop for (k _) on rule by #'cddr
           unless (memq k '(:match :set :append))
           do (agent-ui--fail "source: rule %d has %s: a rule has match, set, append"
                              index (agent-ui--show-value (substring (symbol-name k) 1))))
  (let ((match (plist-get rule :match)))
    (unless (stringp match)
      (agent-ui--fail "source: rule %d has no match (a regular expression)" index))
    (unless (or (plist-get rule :set) (plist-get rule :append))
      (agent-ui--fail "source: rule %d changes nothing: give set or append" index))
    (let ((regexp (agent-ui-source-regexp match)))
      (condition-case err
          (string-match-p regexp "")
        (invalid-regexp
         (agent-ui--fail "source: rule %d's match %S isn't a regular expression: %s"
                         index match (cadr err))))
      (list :regexp regexp
            :set (agent-ui-source--patch (plist-get rule :set) "set")
            :append (agent-ui-source--patch (plist-get rule :append) "append")))))

(defun agent-ui-source-check (source)
  "SOURCE (an element's :source) checked: as an `agent-ui-source--state',
not started. Signals `agent-ui-error' saying what's wrong."
  (unless (agent-ui--plist-p source)
    (agent-ui--fail "source: give an object: {\"command\": ...}, {\"file\": ...} or {\"poll\": ...}"))
  (cl-loop for (k _) on source by #'cddr
           unless (memq k agent-ui-source--keys)
           do (agent-ui--fail "source: unknown key %s; its keys: command, file, poll, dir, every, rules, match, set, append, tail, into, done, failed, from"
                              (agent-ui--show-value (substring (symbol-name k) 1))))
  (let* ((kinds (seq-filter (lambda (k) (plist-get source k)) '(:command :file :poll)))
         (kind (car kinds))
         (what (plist-get source kind))
         (tail (plist-get source :tail))
         (every (plist-get source :every))
         (rules (if (plist-get source :rules)
                    (plist-get source :rules)
                  (when (or (plist-get source :match) (plist-get source :set) (plist-get source :append))
                    (list (list :match (plist-get source :match) :set (plist-get source :set)
                                :append (plist-get source :append)))))))
    (unless (= (length kinds) 1)
      (agent-ui--fail "source: give one of command, file, poll"))
    (unless (and (stringp what) (not (string-empty-p what)))
      (agent-ui--fail "source: %s must be text" (substring (symbol-name kind) 1)))
    (when (and (plist-get source :rules) (plist-get source :match))
      (agent-ui--fail "source: give rules, or one rule's match, set, append: not both"))
    (unless (or rules tail (plist-get source :into) (eq kind :command))
      (agent-ui--fail "source: give rules (or tail, into): what of its output changes the element?"))
    (when (and (plist-get source :into)
               (not (and (stringp (plist-get source :into))
                         (string-match-p "\\`[a-z][a-z0-9-]*\\'" (plist-get source :into)))))
      (agent-ui--fail "source: into names a property: \"diff\", \"text\""))
    (when (and tail (not (and (integerp tail) (<= 1 tail 200))))
      (agent-ui--fail "source: tail is how many lines, 1 to 200"))
    (when (and every (not (and (numberp every) (>= every 1))))
      (agent-ui--fail "source: every is seconds, 1 or more"))
    (when (and every (not (eq kind :poll)))
      (agent-ui--fail "source: every is a poll's"))
    (when (and (or (plist-get source :done) (plist-get source :failed)) (not (eq kind :command)))
      (agent-ui--fail "source: done and failed are a command's"))
    (when (and (plist-get source :from) (not (member (plist-get source :from) '("start" "end"))))
      (agent-ui--fail "source: from is start or end"))
    (agent-ui-source--make-state
     :kind (intern (substring (symbol-name kind) 1))
     :what what
     :dir (let ((dir (plist-get source :dir)))
            (and (stringp dir) (file-name-as-directory (expand-file-name dir))))
     :rules (cl-loop for rule in rules for i from 1 collect (agent-ui-source--rule rule i))
     :tail tail
     :into (plist-get source :into)
     :done (agent-ui-source--patch (plist-get source :done) "done")
     :failed (agent-ui-source--patch (plist-get source :failed) "failed")
     :offset (if (equal (plist-get source :from) "end") 'end 0)
     :every (or every 5))))

(setq agent-ui-check-source-function #'agent-ui-source-check)

;; ====== FROM OUTPUT TO CHANGES ======

(defun agent-ui-source--value (text)
  "TEXT, a group's: a number if it reads as one."
  (cond ((null text) nil)
        ((string-match-p "\\`-?[0-9]+\\(?:\\.[0-9]+\\)?\\'" text) (string-to-number text))
        (t text)))

(defun agent-ui-source--fill (template groups)
  "TEMPLATE with GROUPS (an alist: \"0\"... \"9\", \"code\" to text) in it:
a string that's only \"$N\" its value, $N in other text replaced; objects and
arrays filled through."
  (cond
   ((stringp template)
    (if (string-match "\\`\\$\\([0-9]\\|code\\)\\'" template)
        (agent-ui-source--value (cdr (assoc (match-string 1 template) groups)))
      (replace-regexp-in-string "\\$\\([0-9]\\|code\\)"
                                (lambda (m) (or (cdr (assoc (substring m 1) groups)) ""))
                                template t t)))
   ((agent-ui--plist-p template)
    (cl-loop for (k v) on template by #'cddr nconc (list k (agent-ui-source--fill v groups))))
   ((consp template) (mapcar (lambda (v) (agent-ui-source--fill v groups)) template))
   (t template)))

(defun agent-ui-source--groups (line)
  "The last match's groups in LINE, as `agent-ui-source--fill' takes them."
  (cl-loop for i from 0 to 9
           collect (cons (number-to-string i) (match-string i line))))

(defun agent-ui-source--apply (state lines)
  "LINES through STATE's rules: (SET . APPEND), the patches they make (a
later line's set over an earlier's; appends added up)."
  (let ((set nil) (append nil))
    (dolist (line lines)
      (dolist (rule (agent-ui-source--state-rules state))
        (when (string-match (plist-get rule :regexp) line)
          (let ((groups (agent-ui-source--groups line)))
            (when-let* ((s (plist-get rule :set)))
              (cl-loop for (k v) on (agent-ui-source--fill s groups) by #'cddr
                       do (setq set (plist-put set k v))))
            (when-let* ((a (plist-get rule :append)))
              (cl-loop for (k v) on (agent-ui-source--fill a groups) by #'cddr
                       do (setq append (plist-put append k (append (plist-get append k)
                                                                   (if (listp v) v (list v)))))))))))
    (cons set append)))

(defun agent-ui-source--change (canvas id set append)
  "Element ID of CANVAS changed by SET (an update) and APPEND."
  (when set (agent-ui-update id set :canvas canvas))
  (when append (agent-ui-append id append :canvas canvas)))

(defun agent-ui-source--state (canvas id)
  (and (buffer-live-p canvas)
       (with-current-buffer canvas
         (and agent-ui-source--states (gethash id agent-ui-source--states)))))

(defun agent-ui-source--feed (canvas id text &optional final)
  "TEXT, more of the output of element ID's source in CANVAS: its complete
lines (all of them if FINAL) through the rules, the element changed."
  (when-let* ((state (agent-ui-source--state canvas id)))
    (let* ((all (concat (agent-ui-source--state-partial state) text))
           (pieces (split-string all "\r\n\\|[\r\n]"))
           (lines (if final (seq-remove #'string-empty-p pieces) (butlast pieces))))
      (setf (agent-ui-source--state-partial state) (if final "" (car (last pieces))))
      (cl-incf (agent-ui-source--state-count state) (length lines))
      (condition-case err
          (pcase-let ((`(,set . ,append) (agent-ui-source--apply state lines)))
            ;; tail: the last lines; into: all of them (the latest 5000), into
            ;; that property (text by default).
            (let ((tail (agent-ui-source--state-tail state))
                  (into (agent-ui-source--state-into state)))
              (when (and (or tail into) (or lines final))
                (let ((kept (last (append (agent-ui-source--state-lines state) lines) (or tail 5000))))
                  (setf (agent-ui-source--state-lines state) kept)
                  (setq set (plist-put set (intern (concat ":" (or into "text")))
                                       (string-join kept "\n"))))))
            (agent-ui-source--change canvas id set append))
        (error (setf (agent-ui-source--state-error state) (agent-ui-error-message err)))))))

;; ====== FOLLOWING ======

(defun agent-ui-source--log (text log)
  (when log
    (let ((coding-system-for-write 'utf-8))
      (write-region text nil log t 'silent))))

(defun agent-ui-source--element-type (canvas id)
  (ignore-errors (plist-get (agent-ui-get id :canvas canvas) :type)))

(defun agent-ui-source--exited (canvas id code)
  "Element ID's command ended with CODE: its last lines, then its done or
failed patch (a progress bar's own if none)."
  (when-let* ((state (agent-ui-source--state canvas id)))
    (agent-ui-source--feed canvas id "" t)
    (setf (agent-ui-source--state-exit state) code
          (agent-ui-source--state-process state) nil)
    (let* ((progress (equal (agent-ui-source--element-type canvas id) "progress"))
           (patch (if (zerop code)
                      (or (agent-ui-source--state-done state)
                          (and progress '(:status "done")))
                    (or (agent-ui-source--state-failed state)
                        (and progress '(:status "failed" :label "exited with $code"))))))
      (when patch
        (condition-case err
            (agent-ui-update id (agent-ui-source--fill patch (list (cons "code" (number-to-string code))))
                             :canvas canvas)
          (error (setf (agent-ui-source--state-error state) (agent-ui-error-message err))))))))

(defun agent-ui-source--run (canvas id state command &optional on-exit)
  "Run COMMAND for element ID's STATE (in its dir), its output fed (and
logged), ON-EXIT called with its exit code."
  (let* ((default-directory (or (agent-ui-source--state-dir state) default-directory))
         (process
          (make-process
           :name (format "agent-ui-%s" id)
           :command (list shell-file-name shell-command-switch command)
           :connection-type 'pipe :noquery t
           :coding 'utf-8
           :filter (lambda (_process output)
                     (agent-ui-source--log output (agent-ui-source--state-log state))
                     (agent-ui-source--feed canvas id output))
           :sentinel (lambda (process _event)
                       (when (memq (process-status process) '(exit signal))
                         (when on-exit (funcall on-exit (process-exit-status process))))))))
    (setf (agent-ui-source--state-process state) process)
    process))

(defun agent-ui-source--poll (canvas id)
  "Element ID's poll, once (not while the last one runs)."
  (when-let* ((state (agent-ui-source--state canvas id)))
    (unless (process-live-p (agent-ui-source--state-process state))
      ;; Each run's lines: its tail its own.
      (setf (agent-ui-source--state-lines state) nil)
      (agent-ui-source--run canvas id state (agent-ui-source--state-what state)
                            (lambda (code)
                              (agent-ui-source--feed canvas id "" t)
                              (setf (agent-ui-source--state-exit state) code))))))

(defun agent-ui-source--look (canvas id)
  "Element ID's file: what it gained since the last look, fed."
  (when-let* ((state (agent-ui-source--state canvas id)))
    (let* ((file (expand-file-name (agent-ui-source--state-what state)
                                   (agent-ui-source--state-dir state)))
           (size (file-attribute-size (file-attributes file)))
           (offset (agent-ui-source--state-offset state)))
      (cond
       ((null size))
       ;; From its end: what's there now doesn't count.
       ((eq offset 'end) (setf (agent-ui-source--state-offset state) size))
       (t
        ;; Truncated (written again): from its start.
        (when (< size offset) (setq offset 0))
        (setf (agent-ui-source--state-offset state) size)
        (when (> size offset)
          (agent-ui-source--feed canvas id
                                 (with-temp-buffer
                                   (let ((coding-system-for-read 'utf-8))
                                     (insert-file-contents file nil offset size))
                                   (buffer-string)))))))))

(defun agent-ui-source-stop (id)
  "Stop element ID's source, in the current canvas."
  (when-let* ((state (and agent-ui-source--states (gethash id agent-ui-source--states))))
    (when (process-live-p (agent-ui-source--state-process state))
      (delete-process (agent-ui-source--state-process state)))
    (when (timerp (agent-ui-source--state-timer state))
      (cancel-timer (agent-ui-source--state-timer state)))
    (remhash id agent-ui-source--states)))

(defun agent-ui-source--start (id element)
  "Element ID (shown in the current canvas) follows its :source, if it has
one; the one it followed before, stopped."
  (agent-ui-source-stop id)
  (when-let* ((source (plist-get element :source)))
    (let ((state (agent-ui-source-check source))
          (canvas (current-buffer)))
      (unless agent-ui-source--states
        (setq agent-ui-source--states (make-hash-table :test #'equal)))
      (unless (agent-ui-source--state-dir state)
        (setf (agent-ui-source--state-dir state) (file-name-as-directory default-directory)))
      (puthash id state agent-ui-source--states)
      (pcase (agent-ui-source--state-kind state)
        ('command
         (make-directory agent-ui-source-log-directory t)
         (setf (agent-ui-source--state-log state)
               (make-temp-file (expand-file-name (format "%s-" id) agent-ui-source-log-directory) nil ".log"))
         (agent-ui-source--run canvas id state (agent-ui-source--state-what state)
                               (lambda (code) (agent-ui-source--exited canvas id code))))
        ('file
         (setf (agent-ui-source--state-timer state)
               (run-with-timer 0 agent-ui-source-file-interval #'agent-ui-source--look canvas id)))
        ('poll
         (setf (agent-ui-source--state-timer state)
               (run-with-timer 0 (agent-ui-source--state-every state) #'agent-ui-source--poll canvas id)))))))

(add-hook 'agent-ui-shown-functions #'agent-ui-source--start)
(add-hook 'agent-ui-removed-functions #'agent-ui-source-stop)

(cl-defun agent-ui-source-status (id &key canvas)
  "Element ID's source as it goes, a plist for the agent: :kind, :running,
:exit, :lines (how many), :log, :error; nil if it has none."
  (when (agent-ui--live-canvas-p canvas)
    (when-let* ((state (agent-ui-source--state (agent-ui--buffer canvas) id)))
      (append
       (list :kind (symbol-name (agent-ui-source--state-kind state))
             ;; A command until its end is handled (its last lines, exit code
             ;; and patch: `agent-ui-source--exited' clears its process), not
             ;; only until it's dead: its sentinel runs a moment after.
             :running (if (or (timerp (agent-ui-source--state-timer state))
                              (if (eq (agent-ui-source--state-kind state) 'command)
                                  (agent-ui-source--state-process state)
                                (process-live-p (agent-ui-source--state-process state))))
                          t :false)
             :lines (agent-ui-source--state-count state))
       (when (agent-ui-source--state-exit state) (list :exit (agent-ui-source--state-exit state)))
       (when (agent-ui-source--state-log state) (list :log (agent-ui-source--state-log state)))
       (when (agent-ui-source--state-error state) (list :error (agent-ui-source--state-error state)))))))
