;;; $DOOMDIR/config/agent-workflow/beads.el -*- lexical-binding: t; -*-
;; Beads, agent workflow's issue tracker here (`agent-workflow-trackers'): a
;; project with .beads/ has its runs on its issues, read and written by bd.
;; Loaded from config/agent-workflow.el (registered there).
;;
;; The engine writes as `+my/agent-workflow-bd-actor' (agent-workflow): its
;; run's summary in the issue's metadata (workflow, workflow_run,
;; workflow_state, workflow_jobs) and the job running as a label (job:NAME),
;; what each job said in its notes, its status; it closes it. An agent of a
;; run is told its bd commands run as ISSUE/JOB (BEADS_ACTOR), on the
;; project's issues (BEADS_DIR: it works in a worktree), and may run bd show
;; without asking. Its writes wait for nothing (WRITES); a read waits for bd,
;; and for the writes queued before it.

(defconst +my/agent-workflow-beads-types
  '("bug" "feature" "task" "epic" "chore" "decision" "spike" "story" "milestone")
  "Beads' issue types: a workflow's for: names one of them.")

;; ====== BD ======

(defun +my/agent-workflow-beads-p (project)
  "Non-nil if Beads tracks PROJECT's issues (bd, and .beads/ there)."
  (and (executable-find "bd") (file-directory-p (expand-file-name ".beads" project))))

(defun +my/agent-workflow--bd (project args &optional actor)
  "Run bd with ARGS in PROJECT as ACTOR (default: the engine), waiting for it,
and for the engine's writes queued before (it reads what they write):
\(STATUS . OUTPUT)."
  (+my/agent-workflow-bd-writes-wait)
  (with-temp-buffer
    (let* ((default-directory (file-name-as-directory project))
           (process-environment (cons (concat "BEADS_ACTOR=" (or actor +my/agent-workflow-bd-actor))
                                      process-environment))
           (status (apply #'process-file "bd" nil (list t nil) nil args)))
      (cons status (buffer-string)))))

(defun +my/agent-workflow--bd-json (project &rest args)
  "The JSON bd gives for ARGS in PROJECT (--json added): alists, lists; a
user error if it fails."
  (pcase-let ((`(,status . ,output) (+my/agent-workflow--bd project (append args '("--json")))))
    (unless (eql status 0)
      (user-error "bd %s: %s" (car args) (string-trim output)))
    (json-parse-string output :object-type 'alist :array-type 'list :null-object nil :false-object nil)))

;; ====== AN ISSUE ======

(defvar +my/agent-workflow--beads-labels (make-hash-table :test #'equal)
  "The labels each issue was last seen with: (PROJECT . ID) -> labels.
Read with it, changed as a summary is written: the job:NAME ones it has.")

(defun +my/agent-workflow--beads-plist (issue)
  "ISSUE, bd's JSON (an alist), as a tracker gives it (a plist), :data it."
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
                                    (alist-get 'dependencies issue)))
        :data issue))

(defun +my/agent-workflow-beads-issue (project id)
  "Issue ID of PROJECT as bd shows it (a tracker's :issue), or nil."
  (let* ((found (+my/agent-workflow--bd-json project "show" id))
         (issue (if (and (listp found) (consp (car found)) (not (symbolp (caar found)))) (car found) found)))
    (when (alist-get 'id issue)
      (puthash (cons project id) (alist-get 'labels issue) +my/agent-workflow--beads-labels)
      (+my/agent-workflow--beads-plist issue))))

(defun +my/agent-workflow-beads-issues (project)
  "PROJECT's open issues, as bd lists them (a tracker's :issues)."
  (mapcar #'+my/agent-workflow--beads-plist
          (+my/agent-workflow--bd-json project "list" "--status" "open,in_progress" "--limit" "0")))

(defun +my/agent-workflow-beads-children (project id)
  "The open issues of PROJECT's epic ID (its descendants, not epics
themselves), their ids, in bd's order (a tracker's :children)."
  (delq nil (mapcar (lambda (issue)
                      (unless (equal (alist-get 'issue_type issue) "epic")
                        (alist-get 'id issue)))
                    (+my/agent-workflow--bd-json project "list" "--parent" id "--status" "open,in_progress"
                                                 "--limit" "0"))))

;; ====== WRITES ======
;; What the engine writes on an issue (bd update, bd close) waits for
;; nothing: queued, then written by bd in the background, one after another,
;; in the order asked. Emacs waited on each, ~0.6 s (Dolt), seconds under
;; load, five in a row as a run came back. A run's summary is queued once
;; while it waits: a newer one replaces it, its arguments made as its turn
;; comes, so a burst of changes is one write. What fails is said, never an
;; error: the run goes on (its journal is the record). A read waits for
;; what's queued; Emacs quitting, for what's left (the tracker's :wait).

(defvar +my/agent-workflow--bd-queue nil
  "The engine's writes waiting, first first: plists (:project :id :args, or
:summary, a run's to write (its arguments made as its turn comes)).")

(defvar +my/agent-workflow--bd-process nil
  "The write bd is doing, or nil.")

(defun +my/agent-workflow--bd-later (project id &rest spec)
  "Write on issue ID of PROJECT, after those queued: SPEC, :args (bd's,
\(\"update\" ID ...)), or :summary (a run's: replacing one of ID's queued)."
  (let ((waiting (and (plist-get spec :summary)
                      (seq-find (lambda (item) (and (plist-get item :summary)
                                                    (equal (plist-get item :project) project)
                                                    (equal (plist-get item :id) id)))
                                +my/agent-workflow--bd-queue))))
    (if waiting
        (plist-put waiting :summary (plist-get spec :summary))
      (setq +my/agent-workflow--bd-queue
            (append +my/agent-workflow--bd-queue (list (append (list :project project :id id) spec))))
      ;; Started once this turn is over: what it changes next joins it.
      (unless +my/agent-workflow--bd-process
        (run-at-time 0 nil #'+my/agent-workflow--bd-next)))))

(defun +my/agent-workflow--summary-args (project id summary)
  "The arguments of bd writing SUMMARY (a run's, `agent-workflow-run-summary')
on issue ID of PROJECT: its metadata, the label of the job running
\(job:NAME), the others it's known to have taken off."
  (let* ((running (plist-get summary :running))
         (key (cons project id))
         (labels (seq-filter (lambda (label) (string-prefix-p "job:" label))
                             (gethash key +my/agent-workflow--beads-labels)))
         (args (list "--set-metadata" (concat "workflow=" (plist-get summary :workflow))
                     "--set-metadata" (format "workflow_run=%d" (plist-get summary :run))
                     "--set-metadata" (concat "workflow_state=" (plist-get summary :state))
                     "--set-metadata"
                     (concat "workflow_jobs="
                             (mapconcat (lambda (job) (format "%s:%s" (car job) (cdr job)))
                                        (plist-get summary :jobs) ",")))))
    (dolist (label labels)
      (unless (equal label (and running (concat "job:" running)))
        (setq args (append args (list "--remove-label" label)))))
    (when (and running (not (member (concat "job:" running) labels)))
      (setq args (append args (list "--add-label" (concat "job:" running)))))
    (puthash key (append (seq-remove (lambda (label) (string-prefix-p "job:" label))
                                     (gethash key +my/agent-workflow--beads-labels))
                         (and running (list (concat "job:" running))))
             +my/agent-workflow--beads-labels)
    (append (list "update" id) args)))

(defun +my/agent-workflow--bd-next ()
  "The next write queued started, unless one is being written."
  (while (and +my/agent-workflow--bd-queue (not +my/agent-workflow--bd-process))
    (let* ((item (pop +my/agent-workflow--bd-queue))
           (args (or (plist-get item :args)
                     (when-let* ((summary (plist-get item :summary)))
                       (+my/agent-workflow--summary-args (plist-get item :project) (plist-get item :id) summary)))))
      (when args
        (setq +my/agent-workflow--bd-process (+my/agent-workflow--bd-start item args))))))

(defun +my/agent-workflow--bd-start (item args)
  "Start bd ARGS for queued ITEM, in its project, as the engine: its process;
nil, said, if bd can't run there."
  (let ((project (plist-get item :project))
        (what (format "bd %s %s" (car args) (plist-get item :id))))
    (if (not (+my/agent-workflow-beads-p project))
        (progn (message "agent workflow: %s: %s tracks no issues with Beads" what
                        (file-name-nondirectory (directory-file-name project)))
               nil)
      (condition-case err
          (let* ((default-directory (file-name-as-directory project))
                 (process-environment (cons (concat "BEADS_ACTOR=" +my/agent-workflow-bd-actor) process-environment))
                 (output (generate-new-buffer " *agent-workflow bd*" t))
                 (process (make-process
                           :name "agent-workflow-bd" :buffer output :command (cons "bd" args)
                           :connection-type 'pipe :noquery t :file-handler t
                           :sentinel (lambda (process _event)
                                       (unless (process-live-p process)
                                         (+my/agent-workflow--bd-ended process))))))
            (process-put process '+my/what what)
            process)
        (error (message "agent workflow: %s: %s" what (error-message-string err))
               nil)))))

(defun +my/agent-workflow--bd-ended (process)
  "PROCESS, a write, over: its failure said, the next write started.
Once, from its sentinel or from a wait, whichever comes first."
  (unless (process-get process '+my/ended)
    (process-put process '+my/ended t)
    (let ((output (process-buffer process)))
      (unless (eql (process-exit-status process) 0)
        (message "agent workflow: %s: %s" (process-get process '+my/what)
                 (if (buffer-live-p output)
                     (string-trim (with-current-buffer output (buffer-string)))
                   (format "exit %s" (process-exit-status process)))))
      (when (buffer-live-p output) (kill-buffer output)))
    (when (eq +my/agent-workflow--bd-process process)
      (setq +my/agent-workflow--bd-process nil))
    (+my/agent-workflow--bd-next)))

(defun +my/agent-workflow-bd-writes-wait (&optional timeout)
  "Wait until the engine's writes queued are written, TIMEOUT seconds at most
\(default 30): non-nil if they are (a tracker's :wait).
Only bd's output is read, no timer run: as a synchronous bd, nothing else
happens meanwhile (a read in the middle of the engine's code; Emacs
quitting, its runs being saved). Reading every process's let an agent's
turn end in that wait (Emacs quitting, the run saved with its agent's turn
over, not interrupted). A write over is ended here, not left to its
sentinel: `accept-process-output' on a process that has exited returns at
once, its sentinel not run (it ran at 100% CPU, the writes never over,
until its time was up)."
  (let ((end (+ (float-time) (or timeout 30))))
    (while (and (or +my/agent-workflow--bd-process +my/agent-workflow--bd-queue) (< (float-time) end))
      (let ((process +my/agent-workflow--bd-process))
        (cond ((null process) (+my/agent-workflow--bd-next))
              ((process-live-p process) (accept-process-output process 0.05 nil 1))
              (t (accept-process-output process 0 nil 1) ; what it wrote last, read
                 (+my/agent-workflow--bd-ended process)))))
    (not (or +my/agent-workflow--bd-process +my/agent-workflow--bd-queue))))

(defun +my/agent-workflow-beads-update (project id changes)
  "CHANGES written on issue ID of PROJECT, queued (a tracker's :update):
:status, :notes (appended), :summary (a run's)."
  (when-let* ((status (plist-get changes :status)))
    (+my/agent-workflow--bd-later project id :args (list "update" id "--status" status)))
  (when-let* ((notes (plist-get changes :notes)))
    (+my/agent-workflow--bd-later project id :args (list "update" id "--append-notes" notes)))
  (when-let* ((summary (plist-get changes :summary)))
    (+my/agent-workflow--bd-later project id :summary summary)))

(defun +my/agent-workflow-beads-close (project id reason)
  "Issue ID of PROJECT closed for REASON, queued after what's written on it
before (a tracker's :close)."
  (+my/agent-workflow--bd-later project id :args (list "close" id "--reason" reason)))

;; ====== AN AGENT ON ONE ======

(defun +my/agent-workflow-beads-environment (project id job)
  "The agent and scripts doing JOB on issue ID of PROJECT: their bd commands
as ID/JOB (Beads' history says which job did what), on the project's issues
\(it works in a worktree). A tracker's :environment."
  (list (concat "BEADS_ACTOR=" id "/" job)
        (concat "BEADS_DIR=" (expand-file-name ".beads" project))))

(defun +my/agent-workflow-beads-context (_project id job)
  "What the agent doing JOB on issue ID is told of Beads (a tracker's :context)."
  (format "Its issue is Beads': bd show %s reads it; your bd commands run as %s/%s (BEADS_ACTOR)."
          id id job))

;; ====== THE TRACKER ======

(defconst +my/agent-workflow-beads-tracker
  (list :name "Beads"
        :detect #'+my/agent-workflow-beads-p
        :issue #'+my/agent-workflow-beads-issue
        :issues #'+my/agent-workflow-beads-issues
        :children #'+my/agent-workflow-beads-children
        :update #'+my/agent-workflow-beads-update
        :close #'+my/agent-workflow-beads-close
        :wait #'+my/agent-workflow-bd-writes-wait
        :types +my/agent-workflow-beads-types
        :environment #'+my/agent-workflow-beads-environment
        :tools '("Bash(bd show:*)")
        :context #'+my/agent-workflow-beads-context)
  "Beads as an issue tracker of agent workflow's (see above).")

;; ====== THE ISSUE PICKER ======
;; M-x agent-workflow-run-ticket: each issue as the issue list draws it
;; (config/beads/look.el, once it's loaded): a status icon, a priority badge
;; and a type icon before it, its labels as tags after.

(defvar +my/beads--statuses)

(defun +my/agent-workflow-issue-affixes (issue statuses)
  "ISSUE's (PREFIX . SUFFIX), as the issue list draws it, STATUSES the open
issues' (those blocking it); the package's own look without the list's
\(`agent-workflow-issue-affixes'), or for an issue that isn't Beads'."
  (let ((info (plist-get issue :data)))
    (if (not (and (fboundp '+my/beads-format-status) (consp info)))
        (agent-workflow-issue-affixes issue statuses)
      ;; The statuses' faces: beads.el's, in the theme's colours once loaded
      ;; (config/beads/theme.el); the list may not have been opened yet.
      (let ((+my/beads--statuses statuses)
            (labels (alist-get 'labels info)))
        (require 'beads-faces nil t)
        (cons (concat (string-pad (+my/beads-format-status info) 2)
                      (+my/beads-format-priority info) " "
                      (+my/beads-format-type info) " ")
              (when labels
                (concat "  " (mapconcat #'+my/beads--label-tag labels " "))))))))
