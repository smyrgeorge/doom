;;; $DOOMDIR/config/agent-ui/bug.el -*- lexical-binding: t; -*-
;; Agent UI's own bugs, filed from any session. Loaded from
;; config/agent-ui.el, after snapshot.el. No Doom here (see docs/agent-ui.md).
;;
;; When Agent UI itself misbehaves (a wrong drawing, an error, a property
;; missing), the agent (cmd/agent-ui bug, the MCP tool bug) or the user (b on
;; an element in a canvas, M-x agent-ui-report-bug) files it in the library's
;; own issues, found from where its code is: never the work project's.
;; `agent-ui-bug-function' files it (config/agent-ui.el sets it); without it,
;; or when it fails, nothing is filed and the report is given back, written,
;; to report by hand.
;;
;; A report: its title and what's wrong (what was expected, the workaround
;; used), a repro (an element showing the bug with neutral data: its JSON,
;; drawn as text), the live element (its JSON, its drawing, its error), and
;; the environment (GUI or terminal, the pane's width, Emacs's version, the
;; library's commit, the session).

(require 'cl-lib)
(require 'subr-x)

;; ====== VARIABLES ======

(defvar agent-ui-bug-function nil
  "Files a bug in Agent UI's own issues: called with its title, its
description (Markdown), the library's directory (its issues are found from
there) and whether to file it as new even if a similar one is open. Returns
\(:id ID :new BOOL :dir DIR): the issue, whether it's new (nil: the report
added to a similar open one), the issues' folder. Signals an error saying
what's missing when it can't (no issues set up, no bd, bd failing). nil:
none, every report given back to report by hand.")

(defcustom agent-ui-bug-report-url nil
  "Where to report Agent UI's bugs by hand, said when one can't be filed
\(a web page's address); nil: none yet."
  :type '(choice (const nil) string) :group 'agent-ui)

(defvar agent-ui-bug-filed-functions nil
  "Called when a bug was filed, with its issue's id, its title, whether it's
new (nil: the report added to a similar open one) and the issues' folder.")

(defconst agent-ui-library-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Agent UI's code: its own issues are found from here.")

(defconst agent-ui--bug-keys '(:title :description :expected :workaround :element :repro :new)
  "What a bug report (the agent's JSON) has.")

;; Not filed: its data (MESSAGE REPORT), the report written to file by hand.
(define-error 'agent-ui-bug-not-filed "Agent UI's bug wasn't filed" 'agent-ui-error)

;; ====== THE REPORT ======

(defun agent-ui--fence (language text)
  "TEXT in a Markdown code block of LANGUAGE, its fence longer than any run
of backticks in it."
  (let ((longest 2) (start 0))
    (while (string-match "`+" text start)
      (setq longest (max longest (- (match-end 0) (match-beginning 0)))
            start (match-end 0)))
    (let ((fence (make-string (1+ longest) ?`)))
      (concat fence language "\n" (string-trim-right text "\n+") "\n" fence))))

(defun agent-ui--json-text (value)
  "VALUE (an element) as JSON text."
  (decode-coding-string (json-serialize (agent-ui-to-json value)) 'utf-8))

(defun agent-ui--draw-error (element ctx)
  "The error drawing ELEMENT in CTX (an unknown type, a property wrong, its
drawing failing), or nil: `agent-ui-render' draws it in its place."
  (condition-case err
      (let* ((type (agent-ui-type (plist-get element :type)))
             (props (agent-ui-check type element))
             (draw (or (and (plist-get ctx :graphic) (agent-ui-type-gui type))
                       (agent-ui-type-text type))))
        (funcall draw props ctx)
        nil)
    (error (agent-ui-error-message err))))

(defun agent-ui--bug-title (title)
  "TITLE on one line, led by \"Agent UI: \" as the library's issues are."
  (let ((title (string-trim (replace-regexp-in-string "[ \t\n\r]+" " " title))))
    (if (string-prefix-p "agent ui:" (downcase title)) title (concat "Agent UI: " title))))

(defun agent-ui--library-commit ()
  "The library's commit (git's short hash, and whether its files changed
since), or nil if it isn't in git."
  (let ((default-directory agent-ui-library-directory))
    (when-let* ((hash (ignore-errors (car (process-lines "git" "rev-parse" "--short" "HEAD")))))
      (if (eql 1 (ignore-errors (call-process "git" nil nil nil "diff" "--quiet" "HEAD" "--" ".")))
          (concat hash ", with changes since")
        hash))))

(defun agent-ui--canvas-environment (buffer)
  "Where canvas BUFFER (or nil: none) is shown: (GRAPHIC . WIDTH), its
pane's width in columns, as its elements are drawn."
  (let* ((window (and (buffer-live-p buffer) (get-buffer-window buffer t)))
         (frame (if window (window-frame window) (selected-frame))))
    (cons (display-graphic-p frame)
          (if window (max 10 (1- (window-max-chars-per-line window))) agent-ui-default-width))))

(cl-defun agent-ui-bug-report (props &key canvas session cwd by)
  "The bug PROPS tells of (the agent's JSON: title, description, expected,
workaround, element, repro) as (TITLE . DESCRIPTION), the description
Markdown: what's wrong, the repro drawn, the live element of CANVAS, the
environment; SESSION, CWD and BY (who files it) said there. Signals
`agent-ui-error' when PROPS are wrong."
  (unless (agent-ui--plist-p props)
    (agent-ui--fail "bug: give a JSON object: {\"title\": ..., \"description\": ...}"))
  (cl-loop for (key _) on props by #'cddr
           unless (memq key agent-ui--bug-keys)
           do (agent-ui--fail "bug: unknown property %s; a bug has: %s"
                              (agent-ui--show-value (substring (symbol-name key) 1))
                              (mapconcat (lambda (k) (substring (symbol-name k) 1)) agent-ui--bug-keys ", ")))
  (dolist (key '(:title :description))
    (let ((value (plist-get props key)))
      (unless (and (stringp value) (not (string-blank-p value)))
        (agent-ui--fail "bug: %s is required (text)" (substring (symbol-name key) 1)))))
  (dolist (key '(:expected :workaround :element))
    (let ((value (plist-get props key)))
      (unless (or (null value) (stringp value))
        (agent-ui--fail "bug: %s must be text, not %s" (substring (symbol-name key) 1)
                        (agent-ui--show-value value)))))
  (let* ((repro (plist-get props :repro))
         (id (let ((e (plist-get props :element))) (and e (not (string-blank-p e)) e)))
         (buffer (and canvas (agent-ui--live-canvas-p canvas) (agent-ui--buffer canvas)))
         (live (and id (agent-ui-get id :canvas canvas)))
         (environment (agent-ui--canvas-environment buffer))
         (width (cdr environment))
         (text-ctx (agent-ui-context :width width))
         (shown-ctx (agent-ui-context :width width :graphic (car environment)))
         (commit (agent-ui--library-commit)))
    ;; The repro: an element of a known type, drawn (its error drawn in its
    ;; place, if it fails: that may be the bug).
    (when repro
      (unless (agent-ui--plist-p repro)
        (agent-ui--fail "bug: repro is an element, {\"type\": ..., ...}, not %s" (agent-ui--show-value repro)))
      (agent-ui-type (plist-get repro :type)))
    (cons
     (agent-ui--bug-title (plist-get props :title))
     (string-join
      (delq nil
            (list
             (string-trim (plist-get props :description))
             (when-let* ((expected (plist-get props :expected)))
               (concat "**Expected:** " (string-trim expected)))
             (when-let* ((workaround (plist-get props :workaround)))
               (concat "**Workaround:** " (string-trim workaround)))
             (when repro
               (concat "## Repro\n\n" (agent-ui--fence "json" (agent-ui--json-text repro))
                       (format "\n\nDrawn as text at %d columns:\n\n" width)
                       (agent-ui--fence "text" (substring-no-properties (agent-ui-render repro text-ctx)))
                       (when-let* ((error (agent-ui--draw-error repro shown-ctx)))
                         (concat "\n\nDrawing it fails: " error))))
             (when live
               (concat (format "## The element as shown: %s (%s)\n\n" id (plist-get live :type))
                       (agent-ui--fence "json" (agent-ui--json-text live))
                       "\n\n"
                       (agent-ui--fence "text" (substring-no-properties (agent-ui-render live text-ctx)))
                       (when-let* ((error (agent-ui--draw-error live shown-ctx)))
                         (concat "\n\nDrawing it fails: " error))))
             (concat "## Environment\n\n"
                     (string-join
                      (delq nil
                            (list (format "- Filed by %s%s" (or by "the agent")
                                          (if session (format " (session %s)" session) ""))
                                  (format "- %s, the pane %d columns wide"
                                          (if (car environment) "A graphic frame (GUI)" "A terminal") width)
                                  (format "- Emacs %s" emacs-version)
                                  (format "- Agent UI: %s%s" (abbreviate-file-name agent-ui-library-directory)
                                          (if commit (format ", at %s" commit) ""))
                                  (when cwd (format "- The session's directory: %s" (abbreviate-file-name cwd)))))
                      "\n"))))
      "\n\n"))))

;; ====== FILING IT ======

(defun agent-ui--bug-not-filed (why title description)
  "Signal `agent-ui-bug-not-filed': nothing filed, WHY, the report (TITLE,
DESCRIPTION) given back to report by hand."
  (signal 'agent-ui-bug-not-filed
          (list (format "Agent UI's bug wasn't filed: %s. Report it by hand%s: the report is written"
                        why (if agent-ui-bug-report-url (concat " at " agent-ui-bug-report-url) ""))
                (concat "# " title "\n\n" description "\n"))))

(cl-defun agent-ui-file-bug (props &key canvas session cwd by)
  "File the bug PROPS tells of (see `agent-ui-bug-report'): with
`agent-ui-bug-function', in the library's own issues. Returns (:id ID :new
BOOL :dir DIR :title TITLE). Signals `agent-ui-bug-not-filed' (its data:
the message, the report) when it can't be filed, `agent-ui-error' when
PROPS are wrong."
  (pcase-let* ((`(,title . ,description) (agent-ui-bug-report props :canvas canvas :session session
                                                              :cwd cwd :by by))
               (filed (if (not agent-ui-bug-function)
                          (agent-ui--bug-not-filed "nothing files them here (agent-ui-bug-function)"
                                                   title description)
                        (condition-case err
                            (funcall agent-ui-bug-function title description agent-ui-library-directory
                                     (eq (plist-get props :new) t))
                          (error (agent-ui--bug-not-filed (agent-ui-error-message err) title description))))))
    (run-hook-with-args 'agent-ui-bug-filed-functions
                        (plist-get filed :id) title (plist-get filed :new) (plist-get filed :dir))
    (append filed (list :title title))))

;; ====== THE USER'S WAY: b ON AN ELEMENT ======

(defun agent-ui--bug-show-report (message report)
  "Not filed: MESSAGE said, REPORT shown in a buffer and copied, to report
by hand."
  (kill-new report)
  (with-current-buffer (get-buffer-create "*Agent UI: bug report*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert report))
    (if (fboundp 'markdown-mode) (markdown-mode) (text-mode))
    (goto-char (point-min))
    (display-buffer (current-buffer)))
  (message "%s (shown, and copied)" message))

(defun agent-ui-report-bug (what expected)
  "File a bug in Agent UI's own issues: WHAT's wrong, what you EXPECTED
\(may be empty). In a canvas, about the element at point: its JSON and its
drawing go with it. Not filed (no issues set up): the report shown and
copied, to report by hand."
  (interactive (list (read-string "What's wrong in Agent UI? ")
                     (read-string "What did you expect? (RET: skip) ")))
  (when (string-blank-p what)
    (user-error "Say what's wrong"))
  (let* ((in-canvas (derived-mode-p 'agent-ui-canvas-mode))
         (id (and in-canvas (ignore-errors (agent-ui--element-at-point))))
         (props (append (list :title (car (split-string (string-trim what) "\n"))
                              :description what)
                        (unless (string-blank-p expected) (list :expected expected))
                        (when id (list :element id)))))
    (condition-case err
        (let* ((filed (agent-ui-file-bug props :canvas (and in-canvas (current-buffer)) :by "the user"
                                         :session (and in-canvas agent-ui--canvas-name)))
               (issue (plist-get filed :id))
               (dir (plist-get filed :dir))
               (map (make-sparse-keymap)))
          (keymap-set map "RET" (lambda () (interactive) (funcall agent-ui-open-issue-function issue dir)))
          (set-transient-map map)
          (message "%s %s: %s (RET: open it)"
                   (if (plist-get filed :new) "Filed" "Added to the similar open bug")
                   issue (plist-get filed :title)))
      (agent-ui-bug-not-filed (agent-ui--bug-show-report (nth 1 err) (nth 2 err))))))

(keymap-set agent-ui-canvas-mode-map "b" #'agent-ui-report-bug)

;; ====== THE AGENT'S WAY: cmd/agent-ui bug ======

(defun agent-ui-bug-reply (props canvas)
  "The reply to the agent's bug (PROPS, for its CANVAS): filed, or not
filed with the report written, to give the user."
  (condition-case err
      (let ((filed (agent-ui-file-bug props :canvas canvas :by "the agent"
                                      :session (bound-and-true-p agent-ui--request-canvas)
                                      :cwd (bound-and-true-p agent-ui--request-cwd))))
        (message "Agent UI: the agent %s %s: %s"
                 (if (plist-get filed :new) "filed" "added to the similar open bug")
                 (plist-get filed :id) (plist-get filed :title))
        (append (list :ok t :issue (plist-get filed :id) :new (if (plist-get filed :new) t :false))
                (unless (plist-get filed :new)
                  (list :note "A similar bug is open: your report was added to its notes (\"new\": true files it anyway)"))))
    (agent-ui-bug-not-filed (list :ok :false :error (nth 1 err) :report (nth 2 err)))))
