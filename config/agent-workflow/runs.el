;;; $DOOMDIR/config/agent-workflow/runs.el -*- lexical-binding: t; -*-
;; Runs: a workflow working on an issue, its jobs in the order their needs
;; say, Emacs the engine. Loaded from config/agent-workflow.el, after
;; beads.el. No Doom here.
;;
;; You start a run (M-x agent-workflow-run-ticket, cmd/agent-workflow run):
;; an issue, open, without a run of its own, with its workflow (yours, its
;; workflow:NAME label's, or the one for its type). A blocked one is queued
;; until its blockers close. A workflow that takes no ticket (ticket: false)
;; has its own run (M-x agent-workflow-run, cmd/agent-workflow run
;; --workflow NAME): its name where an issue's id goes (its folder,
;; worktree, log), its branch run/NAME-N, no Beads; one at a time. A
;; workflow with runs-in: checkout works in your checkout instead, on its
;; branch: no worktree or branch of its own, a job that edits waiting while
;; it has changes not committed, one such run at a time. Runs on different issues go at once, as the
;; pool allows; the first in line is the highest priority, then the one you
;; started first.
;;
;; A run's jobs: one starts once its needs are done, its if (Lisp, evaluated
;; then) holding, else it's skipped; those that don't need each other run at
;; once, as the pool allows. They share the issue's branch: a job whose
;; agents may edit takes its worktree, one at a time, the next one waiting;
;; one that only reads (its agents can't edit, or scripts) works on a
;; snapshot of the branch, a worktree of its own (worktree.el), beside them.
;; Each says which commit it saw. A job's steps run in order; a job with an
;; agent step holds its agent to its last step, the next agent step a
;; message in its session. An agent step ends when its agent says so
;; (cmd/agent-workflow done OUTCOME "notes", its turn ending after); a turn
;; ending without it: the run waits for you. A job's last step done, its
;; outcome says what follows (continue; rerun JOB later: doom-38o.6), its
;; agent stops, the next jobs start. Every job done or skipped: the run is.
;;
;; Its state is its journal, .agent-shell/agent-workflow/runs/ISSUE/N/
;; journal.jsonl, each event a JSON line appended as it happens; state.json
;; beside it, the run as it stands (a cache: rebuilt from the journal);
;; workflow.yml, the workflow as it started. On the issue, the engine writes
;; a summary (beads.el): in_progress, its metadata, the job running as a
;; label, what each job said in its notes.
;;
;; Its parts: this file, a run and its jobs; queue.el, starting runs, their
;; queue and limits, the commands starting them; where.el, where its work
;; is; back.el, going back, its loops, your answers; answers.el, its agent
;; asking you, approval.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'json)
(require 'map)
(require 'crm)                          ; crm-separator, let-bound: special first

(declare-function agent-shell-insert "agent-shell")
(declare-function agent-shell--prompt-queue-enqueue "agent-shell-prompt-queue")
(declare-function shell-maker-busy "shell-maker")
(declare-function agent-workflow--fix "agent-workflow/steps")
(declare-function agent-workflow-run-spent-now "agent-workflow/budget")
(declare-function agent-workflow--budget-more "agent-workflow/budget")
(declare-function agent-workflow--cancel "agent-workflow/resume")
(declare-function agent-workflow--continue-job "agent-workflow/resume")
(declare-function agent-workflow--ensure-restored "agent-workflow/resume")
(defvar agent-workflow--paused)

;; ====== A RUN ======

(cl-defstruct (agent-workflow-run (:constructor agent-workflow-run--make)
                                  (:copier nil))
  project                ; its project's main checkout
  issue                  ; its issue's id; a workflow's own run (ticket: false): its workflow's name
  n                      ; which run of the issue (or workflow): 1, 2...
  dir                    ; its folder: its journal, state, workflow
  workflow               ; its workflow, as it started (a plist)
  info                   ; its issue as it started (a plist: beads.el)
  state                  ; queued, running, waiting (for you), done, cancelled, failed
  why                    ; what it waits for, in words; nil
  jobs                   ; each job's state: ((NAME . PLIST)...)
  order                  ; when it was started: the queue's second key
  edges                  ; its loops: ((\"review>build\" . (:count N :notes (...)))...)
  (total 0)              ; how many times its agents sent it back, since you said go on
  spent                  ; what its agents gone spent: (:cost N :tokens N)
  (active 0)             ; seconds it ran, not waiting for you (but this stretch)
  active-since           ; when this stretch of it running began, or nil
  more                   ; what you added to its budget: (:cost :tokens :time)
  warned                 ; non-nil once told it's near its budget
  blocked                ; its issue's blockers, new since it started (watch.el)
  pane                   ; its pane's canvas, a buffer, while it has one (pane.el)
  base                   ; where its branch started: (:branch B :commit C); (:branch nil :commit nil) unknown
  branch-end)            ; its branch once it's done: (:branch B :deleted t :into MAIN :head C) or (:branch B :why WHY)

(defvar agent-workflow--runs nil
  "Every run of this Emacs, as they were started.")

(defvar agent-workflow--run-count 0
  "Runs started so far: each one's order.")

(defvar agent-workflow-run-functions nil
  "Called with a run whenever it changes (its state, a job's).")

(defvar agent-workflow-journal-functions nil
  "Called with a run, an event's name and its data (a plist) once the event
is in the run's journal.")

(defvar agent-workflow-started-functions nil
  "Called with each run `agent-workflow-run-ticket' or `agent-workflow-run'
started, and whether it was started from the shell
\(`agent-workflow-from-shell').")

(defvar agent-workflow-from-shell nil
  "Non-nil while runs are started from the shell (cmd/agent-workflow run):
no pane opens for them.")

(defconst agent-workflow--ended '(done cancelled failed)
  "A run's states once it's over.")

(defun agent-workflow-runs-of (&optional project)
  "The runs (PROJECT: only its), as they were started."
  (seq-filter (lambda (run) (or (null project) (equal (agent-workflow-run-project run) project)))
              agent-workflow--runs))

(defun agent-workflow-run-of (project issue)
  "ISSUE's run in PROJECT not over yet, or nil."
  (seq-find (lambda (run) (and (equal (agent-workflow-run-issue run) issue)
                               (not (memq (agent-workflow-run-state run) agent-workflow--ended))))
            (agent-workflow-runs-of project)))

(defun agent-workflow--job (run job)
  "RUN's state of JOB: a plist (:status pending|running|waiting|done|skipped|failed|cancelled
:step :agent :outcome :notes :finished :session :why :dir :commit :snapshot
:pool :round :back :start-commit). :why: what it waits for (for you, or
pending: for an agent, the branch); :dir: where it works; :commit: the one
it saw there; :snapshot: a reading job's (DIR BRANCH COMMIT); :pool: its
step waiting for an agent; :round: how many times it's run; :back: how it
was sent back (:step :note :by :session); :start-commit: the branch's
commit as its round started."
  (alist-get job (agent-workflow-run-jobs run) nil nil #'equal))

(defun agent-workflow--job-set (run job &rest pairs)
  "Set PAIRS (key, value...) in RUN's state of JOB."
  (let ((state (agent-workflow--job run job)))
    (while pairs
      (setq state (plist-put state (pop pairs) (pop pairs))))
    (setf (alist-get job (agent-workflow-run-jobs run) nil nil #'equal) state)))

(defun agent-workflow--job-spec (run job)
  "JOB of RUN's workflow, as read (a plist)."
  (alist-get job (plist-get (agent-workflow-run-workflow run) :jobs) nil nil #'equal))

(defun agent-workflow-run-name (run)
  "How RUN is known: \"doom-a1b · feature\"; a workflow's own run (no
ticket): \"github · run 3\"."
  (if (agent-workflow-run-ticket-p run)
      (format "%s · %s" (agent-workflow-run-issue run) (plist-get (agent-workflow-run-workflow run) :name))
    (format "%s · run %d" (agent-workflow-run-issue run) (agent-workflow-run-n run))))

(defun agent-workflow-run-ticket-p (run)
  "Non-nil if RUN is on a ticket (an issue of Beads'); nil for a workflow's
own run (ticket: false): its workflow's name stands for the issue's id (its
folder, worktree, log), its branch run/NAME-N, no Beads."
  (not (plist-get (agent-workflow-run-workflow run) :ticketless)))

(defun agent-workflow--run-bd-write (run &rest args)
  "bd update RUN's issue with ARGS (`agent-workflow--bd-write'); a run with
no ticket: nothing."
  (when (agent-workflow-run-ticket-p run)
    (apply #'agent-workflow--bd-write (agent-workflow-run-project run) (agent-workflow-run-issue run) args)))

(defun agent-workflow-run-checkout-p (run)
  "Non-nil if RUN works in your checkout (runs-in: checkout): its jobs that
edit there, on its current branch; no worktree, no branch of its own."
  (plist-get (agent-workflow-run-workflow run) :checkout))

(defun agent-workflow--work-directory (run)
  "Where RUN's jobs that edit work: your checkout (runs-in: checkout), else
its issue's worktree."
  (if (agent-workflow-run-checkout-p run)
      (file-name-as-directory (agent-workflow-run-project run))
    (agent-workflow-worktree-directory (agent-workflow-run-project run) (agent-workflow-run-issue run))))

(defun agent-workflow--checkout-branch (project)
  "The branch PROJECT's checkout is on; nil if it's detached."
  (let ((default-directory (file-name-as-directory project)))
    (let ((name (car (agent-workflow--git-lines "branch" "--show-current"))))
      (and name (not (string-empty-p name)) name))))

(defun agent-workflow--checkout-dirty-p (project)
  "Non-nil if PROJECT's checkout has changes not committed (untracked files
too; what git ignores not)."
  (let ((default-directory (file-name-as-directory project)))
    (and (agent-workflow--git-lines "status" "--porcelain") t)))

(defun agent-workflow--run-branch (run)
  "The branch RUN's worktree is made on, if it's its own: run/NAME-N for a
run with no ticket; nil for one on a ticket (its issue's), or in your
checkout (none made)."
  (unless (or (agent-workflow-run-ticket-p run) (agent-workflow-run-checkout-p run))
    (format "run/%s-%d" (agent-workflow-run-issue run) (agent-workflow-run-n run))))

(defun agent-workflow--run-branch-made (run)
  "RUN's branch, made: its name, or nil."
  (let ((project (agent-workflow-run-project run)))
    (if-let* ((own (agent-workflow--run-branch run)))
        (let ((default-directory project))
          (and (agent-workflow--git-lines "rev-parse" "--verify" "--quiet" (concat "refs/heads/" own)) own))
      (agent-workflow-issue-branch-made project (agent-workflow-run-issue run)))))

(defun agent-workflow--run-worktree (run)
  "RUN's worktree, made if it isn't there (`agent-workflow-worktree'):
\(DIR . BRANCH). In your checkout: it, and the branch it's on."
  (if (agent-workflow-run-checkout-p run)
      (cons (agent-workflow--work-directory run) (agent-workflow--checkout-branch (agent-workflow-run-project run)))
    (agent-workflow--run-worktree-made run)))

(defun agent-workflow--run-worktree-made (run)
  "RUN's own worktree, made if it isn't there: (DIR . BRANCH)."
  (let ((info (agent-workflow-run-info run)))
    (agent-workflow-worktree (agent-workflow-run-project run) (agent-workflow-run-issue run)
                             :type (plist-get info :type) :title (plist-get info :title)
                             :branch (agent-workflow--run-branch run))))

;; ====== ITS JOURNAL ======

(defun agent-workflow--runs-directory (project)
  "Where PROJECT's runs keep their state."
  (expand-file-name "runs" (expand-file-name agent-workflow-local-directory project)))

(defun agent-workflow--now ()
  "Now, as the journal has it: ISO 8601, UTC."
  (format-time-string "%FT%T%z" nil t))

(defun agent-workflow--journal (run event &rest data)
  "Append EVENT (a string) with DATA (keys and values, as JSON takes them)
to RUN's journal. DATA naming a step of a job (:job, :step) has its name
too (:name), if it has one."
  (when-let* (((not (plist-member data :name)))
              (job (plist-get data :job))
              (index (plist-get data :step))
              ((natnump index))
              (name (plist-get (nth index (plist-get (agent-workflow--job-spec run job) :steps)) :name)))
    (setq data (append data (list :name name))))
  (let ((coding-system-for-write 'utf-8-unix)
        (create-lockfiles nil))
    (write-region (concat (json-serialize (append (list :t (agent-workflow--now) :ev event)
                                                  (agent-workflow--json-ready data)))
                          "\n")
                  nil (expand-file-name "journal.jsonl" (agent-workflow-run-dir run)) t 'silent))
  (run-hook-with-args 'agent-workflow-journal-functions run event data))

(defun agent-workflow--json-ready (plist)
  "PLIST with its nil values as JSON's null."
  (cl-loop for (key value) on plist by #'cddr
           append (list key (if (null value) :null value))))

(defun agent-workflow--to-json (value)
  "VALUE as JSON takes it: a plist an object, a list an array, a symbol
its name, nil null, t true; an alist of numbers ((0 . 2)) an object."
  (cond
   ((null value) :null)
   ((eq value t) t)
   ((or (stringp value) (numberp value)) value)
   ((keywordp value) (substring (symbol-name value) 1))
   ((symbolp value) (symbol-name value))
   ((and (consp value) (keywordp (car value)))
    (cl-loop for (key val) on value by #'cddr append (list key (agent-workflow--to-json val))))
   ((and (consp value) (consp (car value)) (numberp (caar value)))
    (cl-loop for (key . val) in value append (list (intern (format ":%s" key)) (agent-workflow--to-json val))))
   ((consp value) (vconcat (mapcar #'agent-workflow--to-json value)))
   (t (format "%s" value))))

(defconst agent-workflow--saved-job-keys
  '(:status :step :round :outcome :notes :session :start-commit :end-commit :commit :dir :snapshot :approved :ask
    :why :tries :user-note :back :head :own)
  "What of a job's state state.json keeps: all it needs to come back.")

(defun agent-workflow--save-state (run)
  "RUN as it stands written to its state.json: what the views read, and
all it needs to come back after Emacs stops (resume.el)."
  (let ((coding-system-for-write 'utf-8-unix)
        (create-lockfiles nil))
    (with-temp-file (expand-file-name "state.json" (agent-workflow-run-dir run))
      (insert (json-serialize
               (agent-workflow--json-ready
                (list :issue (agent-workflow-run-issue run)
                      :run (agent-workflow-run-n run)
                      :workflow (plist-get (agent-workflow-run-workflow run) :name)
                      :state (symbol-name (agent-workflow-run-state run))
                      :why (agent-workflow-run-why run)
                      :order (agent-workflow-run-order run)
                      :total (agent-workflow-run-total run)
                      :spent (agent-workflow--to-json (agent-workflow-run-spent-now run))
                      :more (agent-workflow--to-json (agent-workflow-run-more run))
                      :warned (if (agent-workflow-run-warned run) t :false)
                      :base (agent-workflow--to-json (agent-workflow-run-base run))
                      :branch-end (agent-workflow--to-json (agent-workflow-run-branch-end run))
                      :info (agent-workflow--to-json (agent-workflow-run-info run))
                      :edges (vconcat (mapcar (lambda (edge) (list :edge (car edge)
                                                                   :count (plist-get (cdr edge) :count)
                                                                   :notes (vconcat (plist-get (cdr edge) :notes))))
                                              (seq-filter #'cdr (agent-workflow-run-edges run))))
                      :jobs (vconcat
                             (mapcar (lambda (job)
                                       (let ((state (cdr job)))
                                         (append
                                          (list :name (car job)
                                                :agent (if-let* ((agent (plist-get state :agent)))
                                                           (agent-workflow-agent-name agent)
                                                         :null))
                                          (cl-loop for key in agent-workflow--saved-job-keys
                                                   append (list key (agent-workflow--to-json
                                                                     (if (and (eq key :session) (plist-get state :agent))
                                                                         (or (agent-workflow-agent-session (plist-get state :agent))
                                                                             (plist-get state :session))
                                                                       (plist-get state key))))))))
                                     (agent-workflow-run-jobs run))))))
              "\n"))))

(defun agent-workflow--changed (run)
  "RUN changed: its state saved, `agent-workflow-run-functions' told."
  (agent-workflow--save-state run)
  (run-hook-with-args 'agent-workflow-run-functions run))

(defun agent-workflow--set-state (run state &optional why)
  "RUN now in STATE, waiting for WHY (words) if it waits; journaled when it
changes. Over (done, cancelled, failed), it stays so: only sending it back
\(`agent-workflow--back', a done run) brings it back."
  (unless (or (and (eq (agent-workflow-run-state run) state) (equal (agent-workflow-run-why run) why))
              (memq (agent-workflow-run-state run) agent-workflow--ended))
    ;; Its time: counted while it runs or waits for an agent, not for you.
    (let ((active (memq state '(running queued))))
      (cond ((and active (not (agent-workflow-run-active-since run)))
             (setf (agent-workflow-run-active-since run) (float-time)))
            ((and (not active) (agent-workflow-run-active-since run))
             (cl-incf (agent-workflow-run-active run) (- (float-time) (agent-workflow-run-active-since run)))
             (setf (agent-workflow-run-active-since run) nil))))
    (setf (agent-workflow-run-state run) state
          (agent-workflow-run-why run) why)
    (agent-workflow--journal run "state" :state (symbol-name state) :why why)
    (agent-workflow--changed run)))

;; ====== ON THE ISSUE ======

(defun agent-workflow--issue-summary (run)
  "RUN's summary written on its issue: its metadata, the label of the job
running (job:NAME), the others' taken off. No ticket: nothing."
  (when (agent-workflow-run-ticket-p run)
    (agent-workflow--issue-summary-write run)))

(defun agent-workflow--issue-summary-write (run)
  "RUN's summary written on its issue (`agent-workflow--issue-summary')."
  (let* ((running (car (seq-find (lambda (job) (eq (plist-get (cdr job) :status) 'running))
                                 (agent-workflow-run-jobs run))))
         (labels (seq-filter (lambda (label) (string-prefix-p "job:" label))
                             (plist-get (agent-workflow-run-info run) :labels)))
         (args (list "--set-metadata" (concat "workflow=" (plist-get (agent-workflow-run-workflow run) :name))
                     "--set-metadata" (format "workflow_run=%d" (agent-workflow-run-n run))
                     "--set-metadata" (concat "workflow_state=" (symbol-name (agent-workflow-run-state run)))
                     "--set-metadata"
                     (concat "workflow_jobs="
                             (mapconcat (lambda (job) (format "%s:%s" (car job) (plist-get (cdr job) :status)))
                                        (agent-workflow-run-jobs run) ",")))))
    (dolist (label labels)
      (unless (equal label (and running (concat "job:" running)))
        (setq args (append args (list "--remove-label" label)))))
    (when (and running (not (member (concat "job:" running) labels)))
      (setq args (append args (list "--add-label" (concat "job:" running)))))
    (setf (plist-get (agent-workflow-run-info run) :labels)
          (append (seq-remove (lambda (label) (string-prefix-p "job:" label))
                              (plist-get (agent-workflow-run-info run) :labels))
                  (and running (list (concat "job:" running)))))
    (apply #'agent-workflow--bd-write (agent-workflow-run-project run) (agent-workflow-run-issue run) args)))

;; ====== IF ======

(defmacro agent-workflow--with-helpers (run &rest body)
  "BODY with RUN's helpers, as if: and elisp: steps have them: (issue-id),
\(issue-type) (a symbol), (issue-labels), (issue-priority), (issue-title),
\(job-outcome \='JOB), (job-status \='JOB)."
  (declare (indent 1))
  (let ((info (make-symbol "info")) (run-var (make-symbol "run")))
    `(let* ((,run-var ,run)
            (,info (agent-workflow-run-info ,run-var)))
       (cl-letf (((symbol-function 'issue-id) (lambda () (plist-get ,info :id)))
                 ((symbol-function 'issue-type) (lambda () (and (plist-get ,info :type) (intern (plist-get ,info :type)))))
                 ((symbol-function 'issue-labels) (lambda () (plist-get ,info :labels)))
                 ((symbol-function 'issue-priority) (lambda () (plist-get ,info :priority)))
                 ((symbol-function 'issue-title) (lambda () (plist-get ,info :title)))
                 ((symbol-function 'job-outcome)
                  (lambda (name) (plist-get (agent-workflow--job ,run-var (format "%s" name)) :outcome)))
                 ((symbol-function 'job-status)
                  (lambda (name) (plist-get (agent-workflow--job ,run-var (format "%s" name)) :status))))
         ,@body))))

(defun agent-workflow--if-holds (run job)
  "Non-nil if JOB of RUN has no if:, or its Lisp holds, evaluated now with
the run's helpers: (issue-id), (issue-type) (a symbol), (issue-labels),
\(issue-priority), (issue-title), (job-outcome \='JOB), (job-status \='JOB).
An error in it: the run waits for you, saying so."
  (let ((form (plist-get (agent-workflow--job-spec run job) :if)))
    (or (null form)
        (condition-case err
            (agent-workflow--with-helpers run
              (eval (car (read-from-string form)) t))
          (error
           (agent-workflow--wait run job (format "%s: its if failed: %s" job (error-message-string err)))
           (throw 'wait nil))))))

;; ====== A JOB ======

(defvar agent-workflow-step-functions nil
  "How a step of each kind runs, but agent steps: ((KIND . FUNCTION)...),
FUNCTION called with the run, the job's name, the step (a plist) and its
index, and calling `agent-workflow-step-ended' once it's over.")

(defun agent-workflow--job-start (run job)
  "JOB of RUN starts: where it works (the issue's worktree, or a reading
job's snapshot of its branch), the commit it sees there; its first step."
  (let* ((info (agent-workflow-run-info run))
         (project (agent-workflow-run-project run))
         (issue (agent-workflow-run-issue run))
         (edits (agent-workflow--job-edits-p run job))
         ;; Where its branch starts, before it's made: your checkout's
         ;; branch and commit (unknown: a branch made before).
         (_ (unless (agent-workflow-run-base run)
              (setf (agent-workflow-run-base run)
                    (or (if (agent-workflow-run-checkout-p run)
                            (list :branch (agent-workflow--checkout-branch project)
                                  :commit (let ((default-directory project)) (agent-workflow--git "rev-parse" "HEAD")))
                          (agent-workflow-worktree-base project issue (agent-workflow--run-branch run)))
                        (list :branch nil :commit nil)))))
         (where (if edits
                    (let ((worktree (agent-workflow--run-worktree run)))
                      (list (car worktree) (cdr worktree)
                            (let ((default-directory (car worktree))) (agent-workflow--git "rev-parse" "HEAD"))))
                  (agent-workflow-snapshot project issue job :type (plist-get info :type)
                                           :title (plist-get info :title) :branch (agent-workflow--run-branch run)
                                           :from (and (agent-workflow-run-checkout-p run)
                                                      (agent-workflow--run-worktree run))))))
    ;; The branch where this round of it starts: what discarding goes back to.
    (agent-workflow--job-set run job :start-commit
                             (let ((default-directory (car (agent-workflow--run-worktree run))))
                               (agent-workflow--git "rev-parse" "HEAD")))
    (agent-workflow--job-set run job :status 'running :step 0 :why nil :dir (nth 0 where) :commit (nth 2 where)
                             :snapshot (and (not edits) where)
                             :round (or (plist-get (agent-workflow--job run job) :round) 1))
    (agent-workflow--journal run "job-started" :job job :commit (nth 2 where) :edits (if edits t :false)
                             :round (plist-get (agent-workflow--job run job) :round))
    (agent-workflow--refresh run)
    (agent-workflow--issue-summary run)
    (agent-workflow--changed run)
    ;; Sent back to a step: this round starts there, the next ones from
    ;; the first (its note and session kept for its agent step).
    (let ((back (plist-get (agent-workflow--job run job) :back)))
      (when (plist-get back :step)
        (agent-workflow--job-set run job :back (plist-put (copy-sequence back) :step nil)))
      (agent-workflow--step-start run job (or (plist-get back :step) 0)))))

(defun agent-workflow--step-start (run job index)
  "Step INDEX of JOB of RUN starts."
  (let* ((step (nth index (plist-get (agent-workflow--job-spec run job) :steps)))
         (kind (plist-get step :kind)))
    (agent-workflow--job-set run job :step index :finished nil)
    (agent-workflow--journal run "step-starting" :job job :step index :kind (symbol-name kind))
    ;; Its pane redrawn (the step running now), its state saved.
    (agent-workflow--changed run)
    (if (eq kind 'agent)
        (agent-workflow--agent-step run job step index)
      (if-let* ((function (alist-get kind agent-workflow-step-functions)))
          (funcall function run job step index)
        (agent-workflow--wait run job (format "%s: its %s step can't run yet" job kind))))))

(defun agent-workflow--wait (run job why)
  "JOB of RUN waits for you, as does RUN: WHY, in words."
  (agent-workflow--job-set run job :status 'waiting :why why)
  (agent-workflow--journal run "waiting" :job job :why why)
  (agent-workflow--refresh run))

(defun agent-workflow--run-values (run)
  "RUN's variables' values for an agent step: its issue's, what its jobs
said."
  (let ((info (agent-workflow-run-info run)))
    (append (and (not (agent-workflow-run-ticket-p run))
                 ;; No ticket: {issue} is the run's name; its fields empty.
                 (list (cons "issue" (agent-workflow-run-name run))))
            (list (cons "issue.title" (if (agent-workflow-run-ticket-p run) (plist-get info :title) ""))
                  (cons "issue.description" (plist-get info :description))
                  (cons "issue.acceptance" (plist-get info :acceptance))
                  (cons "issue.notes" (plist-get info :notes))
                  (cons "try" "1") (cons "output" ""))
            (cl-loop for (job . state) in (agent-workflow-run-jobs run)
                     append (list (cons (format "jobs.%s.outcome" job) (or (plist-get state :outcome) ""))
                                  (cons (format "jobs.%s.notes" job) (or (plist-get state :notes) "")))))))

(defun agent-workflow--job-values (run job)
  "JOB of RUN's own variables' values: its round, the note it was sent
back with."
  (let ((state (agent-workflow--job run job)))
    (list (cons "round" (number-to-string (or (plist-get state :round) 1)))
          (cons "note" (or (plist-get (plist-get state :back) :note) "")))))

(defun agent-workflow--prompt (run job step)
  "What the agent of STEP (of JOB of RUN) is told to start with: the step's
prompt, else its job on the issue; sent back to it, your note and what its
branch has now first."
  (let* ((info (agent-workflow-run-info run))
         (back (plist-get (agent-workflow--job run job) :back))
         (prompt (or (plist-get step :prompt)
                     (format "Do your job, %s, on %s: %s.\n\n%s" job (agent-workflow-run-issue run)
                             (plist-get info :title) (plist-get info :description)))))
    (when-let* ((yours (plist-get (agent-workflow--job run job) :user-note)))
      (setq prompt (format "The user's note for you: %s\n\n%s" yours prompt)))
    (cond
     ((not back) prompt)
     ((plist-get back :interrupted)
      (format "Your job, %s, was interrupted (Emacs stopped) and goes on now.\n\nWhat the branch has now:\n%s\n\nThen, as before:\n\n%s"
              job (agent-workflow--branch-now run job) prompt))
     (t
      (format "%s sent the work back to you, %s (round %d)%s.\n\nWhat the branch has now:\n%s\n\nThen, as before:\n\n%s"
              (if (equal (plist-get back :by) "you") "The user" (plist-get back :by))
              job (or (plist-get (agent-workflow--job run job) :round) 1)
              (if (string-empty-p (or (plist-get back :note) "")) ""
                (concat ", with this note: " (plist-get back :note)))
              (agent-workflow--branch-now run job) prompt)))))

(defun agent-workflow--branch-now (run job)
  "What JOB of RUN's place has now, in a few lines: its last commits, its
changes not committed."
  (let ((default-directory (or (plist-get (agent-workflow--job run job) :dir)
                               (agent-workflow--work-directory run))))
    (string-join (delq nil (list (string-join (agent-workflow--git-lines "log" "--oneline" "-5") "\n")
                                 (let ((changes (agent-workflow--git-lines "status" "--short")))
                                   (and changes (concat "Not committed:\n" (string-join changes "\n"))))))
                 "\n")))

(defun agent-workflow--agent-step (run job step index)
  "The agent step STEP (INDEX of JOB of RUN): the job's agent told it, or
one started for it. The pool full: the run waits, queued, for an agent."
  (let* ((held (plist-get (agent-workflow--job run job) :agent))
         (values (append (agent-workflow--job-values run job) (agent-workflow--run-values run)))
         (outcomes (mapcar #'car (plist-get (agent-workflow--job-spec run job) :outcomes))))
    (if (and held (buffer-live-p (agent-workflow-agent-buffer held)))
        (progn
          (setf (agent-workflow-agent-values held) values)
          (agent-workflow-send held (agent-workflow-fill (agent-workflow--prompt run job step)
                                                         (agent-workflow--agent-values held)))
          (agent-workflow--journal run "step-started" :job job :step index :agent (agent-workflow-agent-name held)))
      (if-let* ((why (agent-workflow--no-agent run job)))
          ;; A later step's agent, the pool full meanwhile, or its workflow
          ;; at its limit: it waits for one, looked at again as one stops.
          (progn
            (agent-workflow--job-set run job :pool index :why why)
            (agent-workflow--refresh run))
        (condition-case err
            (let* ((info (agent-workflow-run-info run))
                   (agent (agent-workflow-start-agent
                           :project (agent-workflow-run-project run) :issue (agent-workflow-run-issue run)
                           :job job :definition (plist-get step :agent)
                           :model (plist-get step :model) :effort (plist-get step :effort)
                           :type (plist-get info :type) :title (plist-get info :title)
                           :branch (agent-workflow--run-branch run)
                           :place (and (agent-workflow-run-checkout-p run) (agent-workflow--run-worktree run))
                           :values values :outcomes outcomes
                           :prompt (agent-workflow--prompt run job step)
                           :snapshot (plist-get (agent-workflow--job run job) :snapshot)
                           :resume (plist-get (plist-get (agent-workflow--job run job) :back) :session))))
              ;; Its notes told: a later step of it isn't sent back.
              (agent-workflow--job-set run job :agent agent :back nil :user-note nil)
              (agent-workflow--journal run "step-started" :job job :step index
                                       :agent (agent-workflow-agent-name agent)
                                       :definition (plist-get step :agent)
                                       :branch (agent-workflow-agent-branch agent)))
          (error (agent-workflow--wait run job (format "%s: its agent didn't start: %s" job
                                                       (error-message-string err)))))))))

;; ====== AN AGENT'S STEP ENDING ======

(defun agent-workflow--agent-run (agent)
  "The run AGENT works for, and its job holding it: (RUN . JOB), or nil."
  (seq-some (lambda (run)
              (seq-some (lambda (job) (and (eq (plist-get (cdr job) :agent) agent) (cons run (car job))))
                        (agent-workflow-run-jobs run)))
            agent-workflow--runs))

(defun agent-workflow-done (agent outcome notes)
  "AGENT's step is done, with OUTCOME (done, or one of its job's outcomes)
and NOTES (what the next jobs and you need to know): journaled, written on
the issue; the run goes on once its turn ends (now, if it has). Return
\(RUN JOB OUTCOME). A user error if AGENT works for no run, or OUTCOME isn't
one."
  (pcase-let* ((`(,run . ,job) (or (agent-workflow--agent-run agent)
                                   (user-error "%s works for no run" (agent-workflow-agent-name agent))))
               (allowed (cons "done" (mapcar #'car (plist-get (agent-workflow--job-spec run job) :outcomes))))
               (outcome (if (or (null outcome) (string-empty-p outcome)) "done" outcome))
               (notes (string-trim (or notes ""))))
    (unless (member outcome allowed)
      (user-error "Outcome %s: not one of %s" outcome (string-join allowed ", ")))
    (unless (memq (plist-get (agent-workflow--job run job) :status) '(running waiting))
      (agent-workflow--refuse "%s's job %s isn't running" (agent-workflow-run-issue run) job))
    (agent-workflow--job-set run job :outcome outcome :notes (and (not (string-empty-p notes)) notes)
                             :finished t :session (agent-workflow-agent-session agent))
    (agent-workflow--journal run "step-ended" :job job :step (plist-get (agent-workflow--job run job) :step)
                             :outcome outcome :notes notes :session (agent-workflow-agent-session agent))
    (agent-workflow--run-bd-write run "--append-notes" (format "%s (%s): %s" job outcome (if (string-empty-p notes) "-" notes)))
    (agent-workflow--changed run)
    ;; Its turn over already (it said so outside one, or after its hand
    ;; was raised): on at once, once this reply's sent.
    (unless (let ((buffer (agent-workflow-agent-buffer agent)))
              (and (buffer-live-p buffer) (with-current-buffer buffer (shell-maker-busy))))
      (run-at-time 0 nil #'agent-workflow--step-finished run job))
    (list run job outcome)))

(defun agent-workflow--save-all ()
  "Every run's state saved, its agents' sessions' ids in it (to resume
them). In `agent-workflow-quit-hook'."
  (dolist (run agent-workflow--runs)
    (unless (memq (agent-workflow-run-state run) agent-workflow--ended)
      (dolist (job (agent-workflow-run-jobs run))
        (when-let* ((agent (plist-get (cdr job) :agent))
                    (session (agent-workflow-agent-session agent)))
          (agent-workflow--job-set run (car job) :session session)))
      (ignore-errors (agent-workflow--save-state run)))))

(add-hook 'agent-workflow-quit-hook #'agent-workflow--save-all)

(defun agent-workflow--agent-event (agent event)
  "An event of AGENT's session: its turn over, its session gone; it asks
you, answered (see ITS AGENT ASKS); its session's id kept once it's known.
In `agent-workflow-agent-event-functions'."
  ;; Its turn over, or its session: nothing it asked waits any more.
  (when-let* (((memq (map-elt event :event) '(turn-complete error clean-up)))
              (run (agent-workflow--agent-asks-over agent)))
    (agent-workflow--refresh run))
  (pcase (map-elt event :event)
    ('permission-request
     (agent-workflow--agent-asks agent 'permission (map-elt (map-elt (map-elt event :data) :tool-call) :title)))
    ('elicitation-request
     (agent-workflow--agent-asks agent 'question (map-elt (map-elt event :data) :message)
                                 (map-elt (map-elt event :data) :request-id)))
    ((or 'permission-response 'elicitation-response)
     (agent-workflow--agent-answered agent))
    ('init-finished
     (when-let* ((found (agent-workflow--agent-run agent))
                 (session (agent-workflow-agent-session agent)))
       (agent-workflow--job-set (car found) (cdr found) :session session)
       (agent-workflow--save-state (car found))))
    ('turn-complete (agent-workflow--turn-over agent))
    ;; Its turn failed: as one ended without done, saying why.
    ('error
     (when-let* ((found (agent-workflow--agent-run agent)))
       (pcase-let ((`(,run . ,job) found))
         (when (and (memq (plist-get (agent-workflow--job run job) :status) '(running waiting))
                    (agent-workflow--agent-at-work-p run job))
           (if (plist-get (agent-workflow--job run job) :finished)
               (agent-workflow--step-finished run job)
             (agent-workflow--wait run job (format "%s: its agent's turn failed: %s" job
                                                   (or (map-elt (map-elt event :data) :message) "an error"))))))))
    ('clean-up
     (when-let* ((found (agent-workflow--agent-run agent)))
       (unless (plist-get (agent-workflow--job (car found) (cdr found)) :finished)
         (agent-workflow--wait (car found) (cdr found) (format "%s: its agent's session ended" (cdr found))))))))

(defun agent-workflow--agent-at-work-p (run job)
  "Whether JOB of RUN has its agent at work: fixing a failed step (not
while its on-fail script does), resolving a merge's conflicts, or its step
is an agent's. Not while a
script step runs, its agent kept for its next fix: a turn of its then (a
background command of its done, waking it) is none of the run's."
  (let* ((state (agent-workflow--job run job))
         (step (nth (or (plist-get state :step) 0) (plist-get (agent-workflow--job-spec run job) :steps))))
    ;; Its on-fail script at work first: not its agent.
    (and (not (plist-get state :fix-script))
         (or (plist-get state :retry) (plist-get state :resolving) (eq (plist-get step :kind) 'agent)))))

(defun agent-workflow--turn-over (agent)
  "AGENT's turn is over: its step goes on if it said done, else its run
waits for you. Its agent not at work (`agent-workflow--agent-at-work-p'):
nothing."
  (when-let* ((found (agent-workflow--agent-run agent)))
    (pcase-let ((`(,run . ,job) found))
      (when (and (memq (plist-get (agent-workflow--job run job) :status) '(running waiting))
                 (agent-workflow--agent-at-work-p run job))
        (if (plist-get (agent-workflow--job run job) :finished)
            (agent-workflow--step-finished run job)
          (agent-workflow--wait run job (format "%s: its agent ended its turn without saying it's done" job)))))))

(defun agent-workflow-step-ended (run job)
  "A step of JOB of RUN (not an agent's) is over: the next one, or the job's
end."
  (agent-workflow--job-set run job :finished t)
  (agent-workflow--step-finished run job))

(defun agent-workflow--step-finished (run job)
  "JOB of RUN's step is over: its next step starts, or the job ends."
  (let ((state (agent-workflow--job run job)))
    (when (and (plist-get state :finished) (memq (plist-get state :status) '(running waiting)))
      (agent-workflow--job-set run job :finished nil :status 'running :why nil)
      (agent-workflow--refresh run)
      (cond
       ;; A conflict its agent resolved: the run goes back to its first job
       ;; that edits, its checks and its review run again on it.
       ((and (plist-get state :resolving) (agent-workflow--first-editing run job))
        (agent-workflow--job-set run job :resolving nil :retry nil)
        ;; Its agent's rebase: the jobs' commits there anew (watch.el).
        (agent-workflow--rebased run)
        (agent-workflow--back run (agent-workflow--first-editing run job)
                             :note (format "The branch was rebased onto the main branch, its conflicts resolved by %s's agent: see that your work still holds." job)
                             :by job))
       ;; A step its agent fixed: run again, from its retry-from step.
       ((plist-get state :retry)
        (let* ((index (plist-get state :retry))
               (from (agent-workflow--retry-from run job index)))
          (agent-workflow--job-set run job :retry nil :resolving nil)
          (unless (= from index)
            (let ((steps (plist-get (agent-workflow--job-spec run job) :steps)))
              (agent-workflow--journal run "retry-from" :job job :step index
                                       :from from :from-name (plist-get (nth from steps) :name))))
          (agent-workflow--step-start run job from)))
       ;; Its result waits for your OK, if its step or job says so.
       ((agent-workflow--needs-approval-p run job)
        (agent-workflow--ask-approval run job))
       (t
        (let ((next (1+ (plist-get state :step))))
          (agent-workflow--job-set run job :approved nil)
          (if (nth next (plist-get (agent-workflow--job-spec run job) :steps))
              (agent-workflow--step-start run job next)
            (agent-workflow--job-end run job))))))))

(defun agent-workflow--retry-from (run job index)
  "Where step INDEX of JOB of RUN, fixed, runs again from: its retry-from
step (an earlier one), else itself."
  (let ((from (plist-get (nth index (plist-get (agent-workflow--job-spec run job) :steps)) :retry-from)))
    (if (and (integerp from) (<= 0 from index)) from index)))

(defun agent-workflow--first-editing (run job)
  "RUN's first job that edits and ran, not JOB: where a resolved conflict
goes back to."
  (car (seq-find (lambda (other) (and (not (equal (car other) job))
                                      (memq (plist-get (cdr other) :status) '(done running waiting))
                                      (agent-workflow--job-edits-p run (car other))))
                 (agent-workflow-run-jobs run))))

(defun agent-workflow--job-end (run job)
  "JOB of RUN's last step is over: its outcome says what follows; its agent
stops."
  (let* ((state (agent-workflow--job run job))
         (outcome (or (plist-get state :outcome) "done"))
         (then (cdr (assoc outcome (plist-get (agent-workflow--job-spec run job) :outcomes)))))
    (pcase then
      ((or 'nil 'continue)
       (when-let* ((agent (plist-get state :agent)))
         (agent-workflow-stop-agent agent))
       (when (plist-get state :snapshot)
         (agent-workflow-snapshot-remove (agent-workflow-run-project run) (agent-workflow-run-issue run) job))
       (agent-workflow--job-set run job :status 'done :agent nil :why nil :snapshot nil :back nil
                                :end-commit (and (agent-workflow--job-edits-p run job)
                                                 (let ((dir (agent-workflow--work-directory run)))
                                                   (and (file-directory-p dir)
                                                        (let ((default-directory dir))
                                                          (car (agent-workflow--git-lines "rev-parse" "HEAD")))))))
       (agent-workflow--journal run "job-done" :job job :outcome outcome :commit (plist-get state :commit))
       (agent-workflow--issue-summary run)
       (agent-workflow--changed run)
       (agent-workflow--tick-soon))
      (`(rerun ,other)
       (agent-workflow--rerun-or-ask run job other)))))

(add-hook 'agent-workflow-agent-event-functions #'agent-workflow--agent-event)

(defun agent-workflow--agent-freed (_agent)
  "An agent stops (its job over, its run cancelled or failed, its budget
used up, the watch, pause now...): the runs looked at soon, one waiting for
an agent getting it. In `agent-workflow-agent-stop-functions'."
  (agent-workflow--tick-soon))

(add-hook 'agent-workflow-agent-stop-functions #'agent-workflow--agent-freed)
