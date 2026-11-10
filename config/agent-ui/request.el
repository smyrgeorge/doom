;;; $DOOMDIR/config/agent-ui/request.el -*- lexical-binding: t; -*-
;; Agent UI's way in for the command line (cmd/agent-ui): a request in a
;; folder, its reply written there. Loaded from config/agent-ui.el, after
;; canvas.el. No Doom here (see docs/agent-ui.md).
;;
;; cmd/agent-ui makes a folder holding:
;;   request   lines: the operation, an id, the agent's session
;;             ($AGENT_UI_SESSION), its working directory, its options
;;             (render's ansi), the session's other canvas it's for
;;             (--canvas NAME), the project's open panel it's for (--panel
;;             NAME), each empty when none
;;   payload   the agent's JSON, as it gave it (absent if none)
;; and runs emacsclient --eval '(agent-ui-request "FOLDER")'. Emacs writes
;; reply (JSON: {"ok": true, ...} or {"ok": false, "error": "..."}) there,
;; which the script prints. No JSON is quoted into Lisp, whatever it holds.
;;
;; A session has its canvas and, named, others ("SESSION / tests"), each in
;; its own pane: --canvas NAME, or "canvas": NAME in the JSON (an element's,
;; a change's, a batch's operation's), says which.

(require 'cl-lib)
(require 'subr-x)

;; ====== VARIABLES ======

(defcustom agent-ui-command
  (expand-file-name "../../cmd/agent-ui"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "cmd/agent-ui: the command line agents run (as the agent is told)."
  :type 'file :group 'agent-ui)

(defvar agent-ui-canvas-function #'agent-ui-request-canvas
  "Called with the agent's session (a string, or nil) and its working
directory (or nil); returns the canvas its request is for (a buffer, or a
canvas's name). config/agent-ui/agent.el finds agent-shell's sessions.")

(defvar agent-ui--request-options nil
  "While a request is answered: its options (strings: \"ansi\").")

(defvar agent-ui--request-canvas nil
  "While a request is answered: its session's canvas (its other canvases'
names start with it).")

(defvar agent-ui--request-cwd nil
  "While a request is answered: the agent's directory (its sources' default).")

(defconst agent-ui-operations
  '("show" "update" "append" "remove" "clear" "list" "types" "batch" "render" "define" "snapshot" "bug" "check" "panels" "open")
  "What cmd/agent-ui does.")

;; ====== THE CANVAS ======

(defun agent-ui-request-canvas (session _cwd)
  "The canvas for an agent's request: its SESSION's, else the default."
  (if (and session (not (string-empty-p session)))
      session
    agent-ui-default-canvas))

;; ====== OPERATIONS ======

(defun agent-ui--payload-object (payload what)
  "PAYLOAD if it's a JSON object (nil: {}, or null); else an error for WHAT."
  (unless (or (null payload) (agent-ui--plist-p payload))
    (agent-ui--fail "%s: give a JSON object, not %s" what (agent-ui--show-value payload)))
  payload)

(defun agent-ui--take-canvas (payload)
  "PAYLOAD's \"canvas\", if it's an object with one: (NAME . PAYLOAD without
it); else (nil . PAYLOAD)."
  (if (and (agent-ui--plist-p payload) (plist-member payload :canvas))
      (let ((name (plist-get payload :canvas)))
        (unless (or (null name) (stringp name))
          (agent-ui--fail "canvas: give a name, not %s" (agent-ui--show-value name)))
        (cons name (agent-ui--plist-delete payload :canvas)))
    (cons nil payload)))

(defun agent-ui--need-id (op id)
  (when (or (null id) (string-empty-p id))
    (agent-ui--fail "%s: which element? give its id" op))
  id)

(defun agent-ui-do (op id payload canvas)
  "Do OP (one of `agent-ui-operations', a string) on CANVAS, with ID and
PAYLOAD (parsed JSON) as it needs; returns the reply, a plist for
`agent-ui-to-json'. Signals `agent-ui-error' if it can't."
  (pcase op
    ("show"
     (let ((element (agent-ui--payload-object payload "show")))
       (when (and id (not (string-empty-p id)))
         (setq element (plist-put (copy-sequence element) :id id)))
       ;; A source runs in the agent's directory, unless it says.
       (let ((source (plist-get element :source)))
         (when (and (agent-ui--plist-p source) (not (plist-get source :dir)) agent-ui--request-cwd)
           (setq element (plist-put (copy-sequence element) :source
                                    (plist-put (copy-sequence source) :dir agent-ui--request-cwd)))))
       (let* ((id (agent-ui-show element :canvas canvas))
              (log (and (fboundp 'agent-ui-source-status)
                        (plist-get (agent-ui-source-status id :canvas canvas) :log))))
         (append (list :ok t :id id)
                 ;; A link to it, for the agent's reply (config/agent-ui/snapshot.el).
                 (when (fboundp 'agent-ui-link)
                   (list :link (agent-ui-link (with-current-buffer (agent-ui--buffer canvas)
                                                agent-ui--canvas-name)
                                              id)))
                 (when log (list :log log))))))
    ("update"
     (list :ok t :id (agent-ui-update (agent-ui--need-id op (or id (plist-get payload :id)))
                                      (agent-ui--payload-object payload "update")
                                      :canvas canvas)))
    ("append"
     (list :ok t :id (agent-ui-append (agent-ui--need-id op (or id (plist-get payload :id)))
                                      (agent-ui--payload-object payload "append")
                                      :canvas canvas)))
    ("remove"
     (list :ok t :id (agent-ui-remove (agent-ui--need-id op (or id (plist-get payload :id)))
                                      :canvas canvas)))
    ("clear"
     (agent-ui-clear :canvas canvas)
     (list :ok t))
    ("list"
     (list :ok t :elements
           (vconcat (mapcar (lambda (e)
                              (let ((source (and (fboundp 'agent-ui-source-status)
                                                 (agent-ui-source-status (plist-get e :id) :canvas canvas))))
                                (append e (when source (list :source source)))))
                            (agent-ui-elements :canvas canvas)))))
    ("render"
     ;; Drawn as text at the canvas's width (its window's, else the default):
     ;; for the agent to see what it draws.
     (let* ((element (agent-ui--payload-object payload "render"))
            (type (agent-ui-type (plist-get element :type)))
            (buffer (and (agent-ui--live-canvas-p canvas) (agent-ui--buffer canvas)))
            (window (and buffer (get-buffer-window buffer t))))
       (agent-ui-check type element)
       (let ((text (agent-ui-render element
                                    (agent-ui-context
                                     :width (if window (1- (window-max-chars-per-line window))
                                              agent-ui-default-width)))))
         ;; --ansi: in its faces' colours, for a terminal.
         (list :ok t :text (if (and (member "ansi" agent-ui--request-options) (fboundp 'agent-ui-ansi))
                               (agent-ui-ansi text)
                             (substring-no-properties text))))))
    ("snapshot"
     (append (list :ok t)
             (agent-ui-snapshot (agent-ui--need-id op id) :canvas canvas :directory agent-ui--request-cwd)))
    ;; The project's panels (config/agent-ui/panels.el): which, opening one.
    ("panels"
     (list :ok t :panels
           (vconcat (mapcar (lambda (name)
                              (list :name name
                                    :open (if (ignore-errors (agent-ui-panel-canvas name agent-ui--request-cwd)) t :false)))
                            (agent-ui-panels agent-ui--request-cwd)))))
    ("open"
     (when (or (null id) (string-empty-p id))
       (agent-ui--fail "open: which panel? agent-ui open NAME%s"
                       (if-let* ((panels (agent-ui-panels agent-ui--request-cwd)))
                           (format " (this project's: %s)" (string-join panels ", "))
                         "")))
     (let* ((canvas (agent-ui-open-panel id agent-ui--request-cwd t))
            (file (agent-ui-panels--file (buffer-local-value 'agent-ui-panels--state canvas))))
       (list :ok t :panel id :canvas (buffer-name canvas)
             ;; Not: the user is asked to let its code run, now (a panel
             ;; with no code: nothing to ask).
             :trusted (if (or (agent-ui-panel-trusted-p file)
                              (let ((read (agent-ui-panel-read file)))
                                (not (agent-ui-panels--code-p (plist-get read :form) (plist-get read :ui)))))
                          t :false))))
    ;; A project panel's file checked, nothing run (config/agent-ui/panels.el).
    ("check"
     (when (or (null id) (string-empty-p id))
       (agent-ui--fail "check: which panel? agent-ui check NAME%s"
                       (if-let* ((panels (agent-ui-panels agent-ui--request-cwd)))
                           (format " (this project's: %s)" (string-join panels ", "))
                         "")))
     (agent-ui-panel-check (agent-ui-panel-file id agent-ui--request-cwd)))
    ;; A bug in Agent UI itself, filed in its own issues (config/agent-ui/bug.el).
    ("bug"
     (agent-ui-bug-reply (agent-ui--payload-object payload "bug") canvas))
    ("define"
     (unless (and (stringp payload) (not (string-empty-p (string-trim payload))))
       (agent-ui--fail "define: give a type's code (a file, or on stdin)"))
     (append (list :ok t) (agent-ui-stage payload)))
    ("types"
     (let ((catalog (agent-ui-catalog)))
       (when (and id (not (string-empty-p id)))
         (agent-ui-type id)             ; an error naming the types
         (setq catalog (seq-filter (lambda (e) (equal (plist-get e :name) id)) catalog)))
       (list :ok t :types (vconcat catalog))))
    ("batch"
     (unless (and (listp payload) (not (agent-ui--plist-p payload)))
       (agent-ui--fail "batch: give a JSON array of operations, each {\"op\": ..., ...}"))
     (let ((results (mapcar (lambda (item) (agent-ui--batch-item item canvas)) payload)))
       (list :ok (if (cl-every (lambda (r) (eq (plist-get r :ok) t)) results) t :false)
             :results (vconcat results))))
    (_
     (agent-ui--fail "unknown operation %s; operations: %s"
                     (agent-ui--show-value op) (string-join agent-ui-operations ", ")))))

(defun agent-ui--batch-item (item canvas)
  "One operation of a batch: ITEM, {\"op\": OP, ...} with what OP takes
\(show: the element; update, append: the id and the change; remove: the id)."
  (condition-case err
      (let* ((item (agent-ui--payload-object item "batch"))
             (op (plist-get item :op))
             (taken (agent-ui--take-canvas (agent-ui--plist-delete item :op)))
             (rest (cdr taken))
             ;; Its own canvas, if it names one: its session's other.
             (canvas (if (and (car taken) agent-ui--request-canvas)
                         (agent-ui-sub-canvas agent-ui--request-canvas (car taken))
                       canvas)))
        (cond
         ((not (stringp op))
          (agent-ui--fail "batch: each operation has \"op\": show, update, append or remove"))
         ((member op '("batch" "types" "list" "render" "define" "snapshot" "bug" "check" "panels" "open"))
          (agent-ui--fail "batch: %s isn't done in a batch" op)))
        (agent-ui-do op (plist-get rest :id)
                     (if (equal op "show") rest (agent-ui--plist-delete rest :id))
                     canvas))
    (error (list :ok :false :error (agent-ui-error-message err)))))

;; ====== THE REQUEST ======

(defun agent-ui--read-file (file)
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (buffer-string)))

(defun agent-ui-request (folder)
  "Answer cmd/agent-ui's request in FOLDER (see the top of this file):
its reply written there, as JSON. Never signals: an error is the reply."
  (let ((reply
         (condition-case err
             (let* ((lines (split-string (agent-ui--read-file (expand-file-name "request" folder))
                                         "\n"))
                    (op (nth 0 lines))
                    (id (nth 1 lines))
                    (session (nth 2 lines))
                    (cwd (nth 3 lines))
                    (options (split-string (or (nth 4 lines) "") " " t))
                    (part (nth 5 lines))
                    (panel (nth 6 lines))
                    (payload-file (expand-file-name "payload" folder))
                    (payload (when (file-exists-p payload-file)
                               (let ((json (string-trim (agent-ui--read-file payload-file))))
                                 (cond
                                  ((string-empty-p json) (agent-ui--fail "%s: no JSON given" op))
                                  ;; A type's code, not JSON.
                                  ((equal op "define") json)
                                  (t (agent-ui-parse-json json))))))
                    ;; Its canvas named in its JSON (not a batch's: each
                    ;; operation its own), else on its command line.
                    (taken (if (member op '("show" "update" "append" "render" "bug"))
                               (agent-ui--take-canvas payload)
                             (cons nil payload)))
                    (payload (cdr taken))
                    (part (or (car taken) part))
                    (base (funcall agent-ui-canvas-function
                                   (unless (equal session "") session)
                                   (unless (equal cwd "") cwd)))
                    (base-name (if (bufferp base) (buffer-local-value 'agent-ui--canvas-name base) base))
                    (canvas (cond
                             ;; One of the project's panels, open.
                             ((not (member panel '(nil "")))
                              (agent-ui-panel-canvas panel (unless (equal cwd "") cwd)))
                             ((member part '(nil "")) base)
                             (t (agent-ui-sub-canvas base-name part)))))
               (let* ((agent-ui--request-options options)
                      (agent-ui--request-canvas base-name)
                      (agent-ui--request-cwd (unless (equal cwd "") cwd))
                      (agent-ui-file-directory (and agent-ui--request-cwd
                                                    (file-name-as-directory agent-ui--request-cwd))))
                 (agent-ui-do op (unless (equal id "") id) payload canvas)))
           (error (list :ok :false :error (agent-ui-error-message err))))))
    (with-temp-file (expand-file-name "reply" folder)
      (setq-local coding-system-for-write 'utf-8)
      (insert (json-serialize (agent-ui-to-json reply)) "\n"))
    t))
