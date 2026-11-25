;;; $DOOMDIR/config/agent-workflow/beads.el -*- lexical-binding: t; -*-
;; The project's issues, as runs need them: an issue read (its title, text,
;; type, labels, its blockers still open), an epic's issues, and what the
;; engine writes on an issue. Loaded from config/agent-workflow.el, after
;; pool.el. No Doom here.
;;
;; bd runs in the project. The engine writes as `agent-workflow-bd-actor'
;; (agent-workflow): a run's state in the issue's metadata (workflow,
;; workflow_run, workflow_state, workflow_jobs), its job running as a label
;; (job:NAME), what each job said in its notes, its status; it closes it.
;; Agents never change the issue: only the engine does. Its writes wait for
;; nothing (WRITES, below); a read waits for bd, and for the writes queued
;; before it.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar agent-workflow-bd-actor "agent-workflow"
  "Who the engine's writes are in the issues' history (BEADS_ACTOR).")

;; ====== BD ======

(defun agent-workflow--bd-check (project)
  "A user error without bd, or Beads in PROJECT."
  (unless (executable-find "bd")
    (agent-workflow--refuse "No bd: a run's issues are Beads' (scripts/tools.sh installs it)"))
  (unless (file-directory-p (expand-file-name ".beads" project))
    (user-error "%s tracks no issues with Beads (bd init)" (file-name-nondirectory (directory-file-name project)))))

(defun agent-workflow--bd (project args &optional actor)
  "Run bd with ARGS in PROJECT as ACTOR (default: the engine), waiting for
it, and for the engine's writes queued before (it reads what they write):
\(STATUS . OUTPUT). A user error without bd, or Beads there."
  (agent-workflow--bd-check project)
  (agent-workflow-bd-writes-wait)
  (with-temp-buffer
    (let* ((default-directory (file-name-as-directory project))
           (process-environment (cons (concat "BEADS_ACTOR=" (or actor agent-workflow-bd-actor))
                                      process-environment))
           (status (apply #'process-file "bd" nil (list t nil) nil args)))
      (cons status (buffer-string)))))

(defun agent-workflow--bd-json (project &rest args)
  "bd's JSON for ARGS in PROJECT (--json added): alists, lists; a user error
if it fails."
  (pcase-let ((`(,status . ,output) (agent-workflow--bd project (append args '("--json")))))
    (unless (eql status 0)
      (user-error "bd %s: %s" (car args) (string-trim output)))
    (json-parse-string output :object-type 'alist :array-type 'list :null-object nil :false-object nil)))

;; ====== WRITES ======
;; What the engine writes on an issue (bd update, bd close) waits for
;; nothing: queued, then written by bd in the background, one after another,
;; in the order asked. Emacs waited on each, ~0.6 s (Dolt), seconds under
;; load, five in a row as a run came back (doom-8aj). A run's summary is
;; queued once while it waits (`agent-workflow--issue-summary'): made as its
;; turn comes, from the run as it is then, so a burst of changes is one
;; write. What fails is said, never an error: the run goes on (its journal
;; is the record). A read waits for what's queued (`agent-workflow--bd');
;; Emacs quitting, for what's left (`agent-workflow-quit-hook').

(defvar agent-workflow--bd-queue nil
  "The engine's writes waiting, first first: plists (:project :id :args, or
:make a function returning them as its turn comes, nil: nothing to write;
:key what it's queued once for).")

(defvar agent-workflow--bd-process nil
  "The write bd is doing, or nil.")

(defun agent-workflow--bd-later (project id &rest spec)
  "Write on issue ID of PROJECT, after those queued: SPEC, :args (bd's,
\(\"update\" ID ...)), or :make (a function returning them, called as its
turn comes) and :key (not queued again while one of KEY waits: `eq')."
  (let ((key (plist-get spec :key)))
    (unless (and key (seq-find (lambda (item) (eq (plist-get item :key) key)) agent-workflow--bd-queue))
      (setq agent-workflow--bd-queue
            (append agent-workflow--bd-queue (list (append (list :project project :id id) spec))))
      ;; Started once this turn is over: what it changes next joins it.
      (unless agent-workflow--bd-process
        (run-at-time 0 nil #'agent-workflow--bd-next)))))

(defun agent-workflow--bd-write (project id &rest args)
  "bd update ID ARGS in PROJECT, as the engine, queued (WRITES, above)."
  (agent-workflow--bd-later project id :args (append (list "update" id) args)))

(defun agent-workflow--bd-close (project id reason)
  "Issue ID of PROJECT closed for REASON, as the engine, queued (WRITES,
above): after what's written on it before."
  (agent-workflow--bd-later project id :args (list "close" id "--reason" reason)))

(defun agent-workflow--bd-next ()
  "The next write queued started, unless one is being written."
  (while (and agent-workflow--bd-queue (not agent-workflow--bd-process))
    (let* ((item (pop agent-workflow--bd-queue))
           (args (or (plist-get item :args)
                     (when-let* ((make (plist-get item :make))) (funcall make)))))
      (when args
        (setq agent-workflow--bd-process (agent-workflow--bd-start item args))))))

(defun agent-workflow--bd-start (item args)
  "bd ARGS started for queued ITEM, in its project, as the engine: its
process; nil, said, if bd can't run there."
  (let ((project (plist-get item :project))
        (what (format "bd %s %s" (car args) (plist-get item :id))))
    (condition-case err
        (progn
          (agent-workflow--bd-check project)
          (let* ((default-directory (file-name-as-directory project))
                 (process-environment (cons (concat "BEADS_ACTOR=" agent-workflow-bd-actor) process-environment))
                 (output (generate-new-buffer " *agent-workflow bd*" t)))
            (let ((process (make-process
                            :name "agent-workflow-bd" :buffer output :command (cons "bd" args)
                            :connection-type 'pipe :noquery t :file-handler t
                            :sentinel (lambda (process _event)
                                        (unless (process-live-p process)
                                          (agent-workflow--bd-ended process))))))
              (process-put process 'agent-workflow-what what)
              process)))
      (error (message "agent workflow: %s: %s" what (error-message-string err))
             nil))))

(defun agent-workflow--bd-ended (process)
  "PROCESS, a write, over: its failure said, the next write started. Once,
from its sentinel or from a wait, whichever comes first."
  (unless (process-get process 'agent-workflow-ended)
    (process-put process 'agent-workflow-ended t)
    (let ((output (process-buffer process)))
      (unless (eql (process-exit-status process) 0)
        (message "agent workflow: %s: %s" (process-get process 'agent-workflow-what)
                 (if (buffer-live-p output)
                     (string-trim (with-current-buffer output (buffer-string)))
                   (format "exit %s" (process-exit-status process)))))
      (when (buffer-live-p output) (kill-buffer output)))
    (when (eq agent-workflow--bd-process process)
      (setq agent-workflow--bd-process nil))
    (agent-workflow--bd-next)))

(defun agent-workflow-bd-writes-wait (&optional timeout)
  "Wait until the engine's writes queued are written, TIMEOUT seconds at
most (default 30): non-nil if they are. A write over is ended here, not
left to its sentinel: `accept-process-output' on a process that has
exited returns at once, its sentinel not run (it ran at 100% CPU, the
writes never over, until its time was up)."
  (let ((end (+ (float-time) (or timeout 30))))
    (while (and (or agent-workflow--bd-process agent-workflow--bd-queue) (< (float-time) end))
      (let ((process agent-workflow--bd-process))
        (cond ((null process) (agent-workflow--bd-next))
              ((process-live-p process) (accept-process-output process 0.05))
              (t (accept-process-output process 0) ; what it wrote last, read
                 (agent-workflow--bd-ended process)))))
    (not (or agent-workflow--bd-process agent-workflow--bd-queue))))

;; Emacs quits: what's queued written first (10 s at most).
(defun agent-workflow--bd-writes-quit-h ()
  "The engine's writes queued, written before Emacs quits (10 s at most)."
  (agent-workflow-bd-writes-wait 10))

(add-hook 'agent-workflow-quit-hook #'agent-workflow--bd-writes-quit-h)

;; ====== AN ISSUE ======

(defun agent-workflow-issue (project id)
  "Issue ID of PROJECT, read: a plist (:id :title :description
:acceptance :notes :type :priority :status :labels :blockers), its
blockers those it depends on still open. A user error if there's none."
  (let* ((found (agent-workflow--bd-json project "show" id))
         (issue (if (and (listp found) (consp (car found)) (not (symbolp (caar found)))) (car found) found)))
    (unless (alist-get 'id issue)
      (user-error "No issue %s" id))
    (list :id (alist-get 'id issue)
          :title (or (alist-get 'title issue) "")
          :description (or (alist-get 'description issue) "")
          :acceptance (or (alist-get 'acceptance_criteria issue) "")
          :notes (or (alist-get 'notes issue) "")
          :type (or (alist-get 'issue_type issue) "task")
          :priority (or (alist-get 'priority issue) 2)
          :status (or (alist-get 'status issue) "open")
          :labels (alist-get 'labels issue)
          :blockers (delq nil (mapcar (lambda (dependency)
                                        (and (equal (alist-get 'dependency_type dependency) "blocks")
                                             (not (equal (alist-get 'status dependency) "closed"))
                                             (alist-get 'id dependency)))
                                      (alist-get 'dependencies issue))))))

(defun agent-workflow-epic-issues (project id)
  "The open issues of PROJECT's epic ID (its descendants, not epics
themselves), their ids, in the order bd lists them."
  (delq nil (mapcar (lambda (issue)
                      (unless (equal (alist-get 'issue_type issue) "epic")
                        (alist-get 'id issue)))
                    (agent-workflow--bd-json project "list" "--parent" id "--status" "open,in_progress"
                                             "--limit" "0"))))

(defun agent-workflow-open-issues (project)
  "PROJECT's open issues: ((ID TITLE TYPE ISSUE) ...), as bd lists them,
ISSUE all bd says of it (an alist: its status, priority, labels...)."
  (mapcar (lambda (issue)
            (list (alist-get 'id issue) (alist-get 'title issue) (alist-get 'issue_type issue) issue))
          (agent-workflow--bd-json project "list" "--status" "open,in_progress" "--limit" "0")))
