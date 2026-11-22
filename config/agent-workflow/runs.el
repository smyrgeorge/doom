;;; $DOOMDIR/config/agent-workflow/runs.el -*- lexical-binding: t; -*-
;; Runs: a workflow working on an issue, its jobs in the order their needs
;; say, Emacs the engine. Loaded from config/agent-workflow.el, after
;; beads.el. No Doom here.
;;
;; You start a run (M-x agent-workflow-run, cmd/agent-workflow run): an
;; issue, open, without a run of its own, with its workflow (yours, its
;; workflow:NAME label's, or the one for its type). A blocked one is queued
;; until its blockers close. Runs on different issues go at once, as the
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

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'json)
(require 'map)

(declare-function agent-shell-insert "agent-shell")
(declare-function agent-shell--prompt-queue-enqueue "agent-shell-prompt-queue")
(declare-function shell-maker-busy "shell-maker")

;; ====== A RUN ======

(cl-defstruct (agent-workflow-run (:constructor agent-workflow-run--make)
                                  (:copier nil))
  project                ; its project's main checkout
  issue                  ; its issue's id
  n                      ; which run of the issue: 1, 2...
  dir                    ; its folder: its journal, state, workflow
  workflow               ; its workflow, as it started (a plist)
  info                   ; its issue as it started (a plist: beads.el)
  state                  ; queued, running, waiting (for you), done, cancelled
  why                    ; what it waits for, in words; nil
  jobs                   ; each job's state: ((NAME . PLIST)...)
  order)                 ; when it was started: the queue's second key

(defvar agent-workflow--runs nil
  "Every run of this Emacs, as they were started.")

(defvar agent-workflow--run-count 0
  "Runs started so far: each one's order.")

(defvar agent-workflow-run-functions nil
  "Called with a run whenever it changes (its state, a job's).")

(defconst agent-workflow--ended '(done cancelled)
  "A run's states once it's over.")

(defun agent-workflow-runs (&optional project)
  "The runs (PROJECT: only its), as they were started."
  (seq-filter (lambda (run) (or (null project) (equal (agent-workflow-run-project run) project)))
              agent-workflow--runs))

(defun agent-workflow-run-of (project issue)
  "ISSUE's run in PROJECT not over yet, or nil."
  (seq-find (lambda (run) (and (equal (agent-workflow-run-issue run) issue)
                               (not (memq (agent-workflow-run-state run) agent-workflow--ended))))
            (agent-workflow-runs project)))

(defun agent-workflow--job (run job)
  "RUN's state of JOB: a plist (:status pending|running|waiting|done|skipped
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
  "How RUN is known: \"doom-a1b · feature\"."
  (format "%s · %s" (agent-workflow-run-issue run) (plist-get (agent-workflow-run-workflow run) :name)))

;; ====== ITS JOURNAL ======

(defun agent-workflow--runs-directory (project)
  "Where PROJECT's runs keep their state."
  (expand-file-name "runs" (expand-file-name agent-workflow-local-directory project)))

(defun agent-workflow--now ()
  "Now, as the journal has it: ISO 8601, UTC."
  (format-time-string "%FT%T%z" nil t))

(defun agent-workflow--journal (run event &rest data)
  "Append EVENT (a string) with DATA (keys and values, as JSON takes them)
to RUN's journal."
  (let ((coding-system-for-write 'utf-8-unix)
        (create-lockfiles nil))
    (write-region (concat (json-serialize (append (list :t (agent-workflow--now) :ev event)
                                                  (agent-workflow--json-ready data)))
                          "\n")
                  nil (expand-file-name "journal.jsonl" (agent-workflow-run-dir run)) t 'silent)))

(defun agent-workflow--json-ready (plist)
  "PLIST with its nil values as JSON's null."
  (cl-loop for (key value) on plist by #'cddr
           append (list key (if (null value) :null value))))

(defun agent-workflow--save-state (run)
  "RUN as it stands written to its state.json (a cache of its journal)."
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
                      :jobs (vconcat
                             (mapcar (lambda (job)
                                       (let ((state (cdr job)))
                                         (agent-workflow--json-ready
                                          (list :name (car job)
                                                :status (symbol-name (plist-get state :status))
                                                :round (or (plist-get state :round) 1)
                                                :outcome (plist-get state :outcome)
                                                :notes (plist-get state :notes)
                                                :session (plist-get state :session)))))
                                     (agent-workflow-run-jobs run))))))
              "\n"))))

(defun agent-workflow--changed (run)
  "RUN changed: its state saved, `agent-workflow-run-functions' told."
  (agent-workflow--save-state run)
  (run-hook-with-args 'agent-workflow-run-functions run))

(defun agent-workflow--set-state (run state &optional why)
  "RUN now in STATE, waiting for WHY (words) if it waits; journaled when it
changes."
  (unless (and (eq (agent-workflow-run-state run) state) (equal (agent-workflow-run-why run) why))
    (setf (agent-workflow-run-state run) state
          (agent-workflow-run-why run) why)
    (agent-workflow--journal run "state" :state (symbol-name state) :why why)
    (agent-workflow--changed run)))

;; ====== ON THE ISSUE ======

(defun agent-workflow--issue-summary (run)
  "RUN's summary written on its issue: its metadata, the label of the job
running (job:NAME), the others' taken off."
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

;; ====== STARTING ONE ======

(defun agent-workflow--fitting (project info)
  "The workflows of PROJECT that fit the issue INFO: its workflow:NAME
label's (that one alone, if there's one), else those whose for: has its
type. Their names."
  (let ((workflows (agent-workflow-workflows project)))
    (if-let* ((label (seq-find (lambda (label) (string-prefix-p "workflow:" label)) (plist-get info :labels))))
        (let ((name (string-remove-prefix "workflow:" label)))
          (if (assoc name workflows)
              (list name)
            (agent-workflow--refuse "%s's label %s: no such workflow (%s)" (plist-get info :id) label
                        (agent-workflow--listed (mapcar #'car workflows)))))
      (mapcar #'car (seq-filter (lambda (workflow) (member (plist-get info :type) (plist-get (cdr workflow) :for)))
                                workflows)))))

(defun agent-workflow--next-run-number (project issue)
  "The next run of ISSUE in PROJECT: 1 more than its runs' folders say."
  (let ((dir (expand-file-name issue (agent-workflow--runs-directory project))))
    (1+ (apply #'max 0 (mapcar #'string-to-number
                               (and (file-directory-p dir) (directory-files dir nil "\\`[0-9]+\\'")))))))

(cl-defun agent-workflow-start-run (project issue &key workflow (by "you"))
  "Start a run on ISSUE of PROJECT with WORKFLOW (a name; default: its
label's, else the one for its type), started BY (you, shell): the run. A
user error, nothing started, if it can't: closed, an epic, a run already,
no workflow or several, an agent-workspace crew there. A blocked issue's
run is queued until its blockers close."
  (let* ((project (file-name-as-directory project))
         (info (agent-workflow-issue project issue))
         (workflows (agent-workflow-workflows project)))
    (cond
     ((equal (plist-get info :status) "closed") (user-error "%s is closed" issue))
     ((equal (plist-get info :type) "epic") (user-error "%s is an epic: its issues are run, not it" issue))
     ((agent-workflow-run-of project issue)
      (user-error "%s has a run already (%s)" issue (agent-workflow-run-name (agent-workflow-run-of project issue))))
     ((agent-workflow-crew-running-p project)
      (user-error "The agent-workspace crew of %s runs: its agents would take the same issues"
                  (file-name-nondirectory (directory-file-name project)))))
    (let* ((name (cond
                  (workflow (if (assoc workflow workflows)
                                workflow
                              (user-error "No workflow %s (%s)" workflow (agent-workflow--listed (mapcar #'car workflows)))))
                  (t (let ((fitting (agent-workflow--fitting project info)))
                       (cond ((null fitting)
                              (user-error "No workflow for a %s like %s (%s): --workflow NAME" (plist-get info :type) issue
                                          (agent-workflow--listed (mapcar #'car workflows))))
                             ((cdr fitting)
                              (user-error "Several workflows fit %s, a %s: %s (--workflow NAME)" issue
                                          (plist-get info :type) (string-join fitting ", ")))
                             (t (car fitting)))))))
           (spec (cdr (assoc name workflows)))
           (n (agent-workflow--next-run-number project issue))
           (dir (file-name-as-directory (expand-file-name (format "%s/%d" issue n) (agent-workflow--runs-directory project))))
           (run (agent-workflow-run--make
                 :project project :issue issue :n n :dir dir :workflow spec :info info :state 'queued
                 :jobs (mapcar (lambda (job) (cons (car job) (list :status 'pending :step 0)))
                               (plist-get spec :jobs))
                 :order (cl-incf agent-workflow--run-count))))
      (make-directory dir t)
      (copy-file (plist-get spec :file) (expand-file-name "workflow.yml" dir) t)
      (agent-workflow--journal run "run-started" :workflow name :by by
                               :main (let ((default-directory project))
                                       (car (agent-workflow--git-lines "rev-parse" "HEAD"))))
      (setq agent-workflow--runs (append agent-workflow--runs (list run)))
      (agent-workflow--bd-write project issue "--status" "in_progress")
      (agent-workflow--issue-summary run)
      (agent-workflow--changed run)
      (agent-workflow--tick-soon)
      run)))

;; ====== THE QUEUE ======

(defvar agent-workflow--tick-timer nil "The next look at the runs, soon.")
(defvar agent-workflow--wait-timer nil "A look at the runs while some wait for something outside.")

(defvar agent-workflow-queue-check)

(defun agent-workflow--tick-soon ()
  "The runs looked at once Emacs is free: what can start, starts."
  (unless (timerp agent-workflow--tick-timer)
    (setq agent-workflow--tick-timer
          (run-at-time 0 nil (lambda ()
                               (setq agent-workflow--tick-timer nil)
                               (agent-workflow-tick))))))

(defun agent-workflow--queue-order (runs)
  "RUNS as their queue has them: the highest priority first (its issue's:
0 first), then the one started first."
  (sort (copy-sequence runs)
        (lambda (a b)
          (let ((pa (plist-get (agent-workflow-run-info a) :priority))
                (pb (plist-get (agent-workflow-run-info b) :priority)))
            (if (/= pa pb) (< pa pb) (< (agent-workflow-run-order a) (agent-workflow-run-order b)))))))

(defun agent-workflow-tick ()
  "Look at every run not over, in the queue's order: what can start,
starts."
  (dolist (run (agent-workflow--queue-order
                (seq-remove (lambda (run) (memq (agent-workflow-run-state run) agent-workflow--ended))
                            agent-workflow--runs)))
    (with-demoted-errors "agent workflow: %S"
      (agent-workflow--advance run)))
  ;; Waiting for blockers: looked at again a while later.
  (let ((outside (seq-some (lambda (run) (and (eq (agent-workflow-run-state run) 'queued)
                                              (agent-workflow-run-why run)))
                           agent-workflow--runs)))
    (cond ((and outside (not (timerp agent-workflow--wait-timer)))
           (setq agent-workflow--wait-timer (run-at-time agent-workflow-queue-check agent-workflow-queue-check
                                                         #'agent-workflow-tick)))
          ((and (not outside) (timerp agent-workflow--wait-timer))
           (cancel-timer agent-workflow--wait-timer)
           (setq agent-workflow--wait-timer nil)))))

(defun agent-workflow--status-of (run status)
  "RUN's jobs whose status is STATUS (a symbol, or a list of them)."
  (let ((statuses (if (listp status) status (list status))))
    (seq-filter (lambda (job) (memq (plist-get (cdr job) :status) statuses)) (agent-workflow-run-jobs run))))

(defun agent-workflow--startable (run)
  "RUN's jobs that can start, in order: pending, their needs done or
skipped."
  (mapcar #'car
          (seq-filter (lambda (job)
                        (and (eq (plist-get (cdr job) :status) 'pending)
                             (seq-every-p (lambda (need)
                                            (memq (plist-get (agent-workflow--job run need) :status) '(done skipped)))
                                          (plist-get (agent-workflow--job-spec run (car job)) :needs))))
                      (agent-workflow-run-jobs run))))

(defun agent-workflow--job-edits-p (run job)
  "Non-nil if JOB of RUN may change the issue's branch: one of its agents'
profiles (its agent steps', its steps' on-fail) lets it edit."
  (let ((profiles (agent-workflow-profiles (agent-workflow-run-project run))))
    (seq-some (lambda (step)
                (seq-some (lambda (name)
                            (and name (agent-workflow-profile-edits-p
                                       (alist-get name profiles nil nil #'equal))))
                          (list (plist-get step :agent) (plist-get step :on-fail))))
              (plist-get (agent-workflow--job-spec run job) :steps))))

(defun agent-workflow--editing (run)
  "The job of RUN holding the issue's branch (one that edits, running or
waiting for you), or nil."
  (car (seq-find (lambda (job) (and (memq (plist-get (cdr job) :status) '(running waiting))
                                    (agent-workflow--job-edits-p run (car job))))
                 (agent-workflow-run-jobs run))))

(defun agent-workflow--needs-agent-p (run job)
  "Non-nil if JOB of RUN's first step is an agent's."
  (eq (plist-get (car (plist-get (agent-workflow--job-spec run job) :steps)) :kind) 'agent))

(defun agent-workflow--refresh (run)
  "RUN's state worked out from its jobs: waiting (for you) if one waits,
saying why; else running if one runs (saying what another waits for);
else queued while none started, waiting for what its first pending job
does."
  (let* ((jobs (agent-workflow-run-jobs run))
         (waiting (seq-find (lambda (job) (eq (plist-get (cdr job) :status) 'waiting)) jobs))
         (pending (seq-find (lambda (job) (and (memq (plist-get (cdr job) :status) '(pending running))
                                               (plist-get (cdr job) :why)))
                            jobs))
         (started (seq-some (lambda (job) (not (eq (plist-get (cdr job) :status) 'pending))) jobs)))
    (cond
     (waiting (agent-workflow--set-state run 'waiting (plist-get (cdr waiting) :why)))
     ((seq-some (lambda (job) (eq (plist-get (cdr job) :status) 'running)) jobs)
      (agent-workflow--set-state run 'running (and pending (plist-get (cdr pending) :why))))
     (pending (agent-workflow--set-state run (if started 'running 'queued) (plist-get (cdr pending) :why))))))

(defun agent-workflow--advance (run)
  "RUN looked at: its blockers (queued), its next job started if none
runs, it's over once every job is done or skipped."
  (catch 'wait
    (when (eq (agent-workflow-run-state run) 'queued)
      (let ((blockers (plist-get (agent-workflow-issue (agent-workflow-run-project run) (agent-workflow-run-issue run))
                                 :blockers)))
        (when blockers
          (agent-workflow--set-state run 'queued (concat "blocked by " (string-join blockers ", ")))
          (throw 'wait nil))))
    ;; A running job's step waiting for an agent: started, if there's one.
    (dolist (job (agent-workflow-run-jobs run))
      (when-let* ((index (plist-get (cdr job) :pool)))
        (when (< (agent-workflow-pool-used) agent-workflow-pool)
          (agent-workflow--job-set run (car job) :pool nil :why nil)
          (agent-workflow--agent-step run (car job) (nth index (plist-get (agent-workflow--job-spec run (car job)) :steps))
                                      index))))
    ;; Every job that can start, starts; one skipped may let others.
    (let ((again t))
      (while again
        (setq again nil)
        (dolist (job (agent-workflow--startable run))
          (cond
           ((not (agent-workflow--if-holds run job))
            (agent-workflow--job-set run job :status 'skipped :why nil)
            (agent-workflow--journal run "job-skipped" :job job :if (plist-get (agent-workflow--job-spec run job) :if))
            (agent-workflow--changed run)
            (setq again t))
           ((and (agent-workflow--job-edits-p run job) (agent-workflow--editing run))
            (agent-workflow--job-set run job :why (format "%s: waiting for %s, which edits the branch" job
                                                          (agent-workflow--editing run))))
           ((and (agent-workflow--needs-agent-p run job) (>= (agent-workflow-pool-used) agent-workflow-pool))
            (agent-workflow--job-set run job :why (format "%s: waiting for an agent: %d of %d work" job
                                                          (agent-workflow-pool-used) agent-workflow-pool)))
           (t (agent-workflow--job-start run job))))))
    (if (seq-every-p (lambda (job) (memq (plist-get (cdr job) :status) '(done skipped))) (agent-workflow-run-jobs run))
        (agent-workflow--run-done run)
      (agent-workflow--refresh run))))

(defun agent-workflow--run-done (run)
  "RUN is over, every job done or skipped: said on its issue; its worktree
removed, if it has nothing not committed (its branch stays)."
  (agent-workflow--set-state run 'done)
  (agent-workflow--journal run "run-done")
  (agent-workflow--issue-summary run)
  (dolist (job (agent-workflow-run-jobs run))
    (agent-workflow-snapshot-remove (agent-workflow-run-project run) (agent-workflow-run-issue run) (car job)))
  (ignore-errors (agent-workflow-worktree-remove (agent-workflow-run-project run) (agent-workflow-run-issue run))))

;; ====== IF ======

(defun agent-workflow--if-holds (run job)
  "Non-nil if JOB of RUN has no if:, or its Lisp holds, evaluated now with
the run's helpers: (issue-id), (issue-type) (a symbol), (issue-labels),
\(issue-priority), (issue-title), (job-outcome \='JOB), (job-status \='JOB).
An error in it: the run waits for you, saying so."
  (let ((form (plist-get (agent-workflow--job-spec run job) :if)))
    (or (null form)
        (let ((info (agent-workflow-run-info run)))
          (condition-case err
              (cl-letf (((symbol-function 'issue-id) (lambda () (plist-get info :id)))
                        ((symbol-function 'issue-type) (lambda () (intern (plist-get info :type))))
                        ((symbol-function 'issue-labels) (lambda () (plist-get info :labels)))
                        ((symbol-function 'issue-priority) (lambda () (plist-get info :priority)))
                        ((symbol-function 'issue-title) (lambda () (plist-get info :title)))
                        ((symbol-function 'job-outcome)
                         (lambda (name) (plist-get (agent-workflow--job run (format "%s" name)) :outcome)))
                        ((symbol-function 'job-status)
                         (lambda (name) (plist-get (agent-workflow--job run (format "%s" name)) :status))))
                (eval (car (read-from-string form)) t))
            (error
             (agent-workflow--wait run job (format "%s: its if failed: %s" job (error-message-string err)))
             (throw 'wait nil)))))))

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
         (where (if edits
                    (let ((worktree (agent-workflow-worktree project issue :type (plist-get info :type)
                                                             :title (plist-get info :title))))
                      (list (car worktree) (cdr worktree)
                            (let ((default-directory (car worktree))) (agent-workflow--git "rev-parse" "HEAD"))))
                  (agent-workflow-snapshot project issue job :type (plist-get info :type)
                                           :title (plist-get info :title)))))
    ;; The branch where this round of it starts: what discarding goes back to.
    (agent-workflow--job-set run job :start-commit
                             (let ((default-directory (car (agent-workflow-worktree project issue
                                                                                    :type (plist-get info :type)
                                                                                    :title (plist-get info :title)))))
                               (agent-workflow--git "rev-parse" "HEAD")))
    (agent-workflow--job-set run job :status 'running :step 0 :why nil :dir (nth 0 where) :commit (nth 2 where)
                             :snapshot (and (not edits) where)
                             :round (or (plist-get (agent-workflow--job run job) :round) 1))
    (agent-workflow--journal run "job-started" :job job :commit (nth 2 where) :edits (if edits t :false)
                             :round (plist-get (agent-workflow--job run job) :round))
    (agent-workflow--refresh run)
    (agent-workflow--issue-summary run)
    (agent-workflow--changed run)
    (agent-workflow--step-start run job (or (plist-get (plist-get (agent-workflow--job run job) :back) :step) 0))))

(defun agent-workflow--step-start (run job index)
  "Step INDEX of JOB of RUN starts."
  (let* ((step (nth index (plist-get (agent-workflow--job-spec run job) :steps)))
         (kind (plist-get step :kind)))
    (agent-workflow--job-set run job :step index :finished nil)
    (agent-workflow--journal run "step-starting" :job job :step index :kind (symbol-name kind))
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
    (append (list (cons "issue.title" (plist-get info :title))
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
    (if (not back)
        prompt
      (format "%s sent the work back to you, %s (round %d)%s.\n\nWhat the branch has now:\n%s\n\nThen, as before:\n\n%s"
              (if (equal (plist-get back :by) "you") "The user" (plist-get back :by))
              job (or (plist-get (agent-workflow--job run job) :round) 1)
              (if (string-empty-p (or (plist-get back :note) "")) ""
                (concat ", with this note: " (plist-get back :note)))
              (agent-workflow--branch-now run job) prompt))))

(defun agent-workflow--branch-now (run job)
  "What JOB of RUN's place has now, in a few lines: its last commits, its
changes not committed."
  (let ((default-directory (or (plist-get (agent-workflow--job run job) :dir)
                               (agent-workflow-worktree-directory (agent-workflow-run-project run)
                                                                  (agent-workflow-run-issue run)))))
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
        (let ((buffer (agent-workflow-agent-buffer held))
              prompt)
          (setf (agent-workflow-agent-values held) values)
          (setq prompt (agent-workflow-fill (agent-workflow--prompt run job step) (agent-workflow--agent-values held)))
          (if (with-current-buffer buffer (shell-maker-busy))
              (with-current-buffer buffer (agent-shell--prompt-queue-enqueue :prompt prompt))
            (agent-shell-insert :text prompt :submit t :no-focus t :shell-buffer buffer))
          (agent-workflow--journal run "step-started" :job job :step index :agent (agent-workflow-agent-name held)))
      (if (>= (agent-workflow-pool-used) agent-workflow-pool)
          ;; A later step's agent, the pool full meanwhile: it waits for one,
          ;; looked at again as an agent stops.
          (progn
            (agent-workflow--job-set run job :pool index
                                     :why (format "%s: waiting for an agent: %d of %d work" job
                                                  (agent-workflow-pool-used) agent-workflow-pool))
            (agent-workflow--refresh run))
        (condition-case err
            (let* ((info (agent-workflow-run-info run))
                   (agent (agent-workflow-start-agent
                           :project (agent-workflow-run-project run) :issue (agent-workflow-run-issue run)
                           :job job :profile (plist-get step :agent)
                           :type (plist-get info :type) :title (plist-get info :title)
                           :values values :outcomes outcomes
                           :prompt (agent-workflow--prompt run job step)
                           :snapshot (plist-get (agent-workflow--job run job) :snapshot)
                           :resume (plist-get (plist-get (agent-workflow--job run job) :back) :session))))
              ;; Its note told: a later step of it isn't sent back.
              (agent-workflow--job-set run job :agent agent :back nil)
              (agent-workflow--journal run "step-started" :job job :step index
                                       :agent (agent-workflow-agent-name agent)
                                       :profile (plist-get step :agent)
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
    (agent-workflow--bd-write (agent-workflow-run-project run) (agent-workflow-run-issue run)
                              "--append-notes" (format "%s (%s): %s" job outcome (if (string-empty-p notes) "-" notes)))
    (agent-workflow--changed run)
    ;; Its turn over already (it said so outside one, or after its hand
    ;; was raised): on at once, once this reply's sent.
    (unless (let ((buffer (agent-workflow-agent-buffer agent)))
              (and (buffer-live-p buffer) (with-current-buffer buffer (shell-maker-busy))))
      (run-at-time 0 nil #'agent-workflow--step-finished run job))
    (list run job outcome)))

(defun agent-workflow--agent-event (agent event)
  "An event of AGENT's session: its turn over, its session gone. In
`agent-workflow-agent-event-functions'."
  (pcase (map-elt event :event)
    ('turn-complete (agent-workflow--turn-over agent))
    ('clean-up
     (when-let* ((found (agent-workflow--agent-run agent)))
       (unless (plist-get (agent-workflow--job (car found) (cdr found)) :finished)
         (agent-workflow--wait (car found) (cdr found) (format "%s: its agent's session ended" (cdr found))))))))

(defun agent-workflow--turn-over (agent)
  "AGENT's turn is over: its step goes on if it said done, else its run
waits for you."
  (when-let* ((found (agent-workflow--agent-run agent)))
    (pcase-let ((`(,run . ,job) found))
      (when (memq (plist-get (agent-workflow--job run job) :status) '(running waiting))
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
      (let ((next (1+ (plist-get state :step))))
        (if (nth next (plist-get (agent-workflow--job-spec run job) :steps))
            (agent-workflow--step-start run job next)
          (agent-workflow--job-end run job))))))

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
       (agent-workflow--job-set run job :status 'done :agent nil :why nil :snapshot nil)
       (agent-workflow--journal run "job-done" :job job :outcome outcome :commit (plist-get state :commit))
       (agent-workflow--issue-summary run)
       (agent-workflow--changed run)
       (agent-workflow--tick-soon))
      (`(rerun ,other)
       (agent-workflow--wait run job (format "%s: %s asks to rerun %s, not done yet" job outcome other))))))

(add-hook 'agent-workflow-agent-event-functions #'agent-workflow--agent-event)

;; ====== GOING BACK ======
;; You send a run back to a job (and a step of it) that has run, with a
;; note, to refine what it did. Nothing is reset: the branch and its
;; commits stay, changes not committed stay in the worktree. The jobs that
;; need it, directly or not, are replaced: a step of theirs running is
;; stopped, their results kept in the journal only, and they run again
;; after it, a round more; the others keep theirs. Its agent's session is
;; resumed (its id kept), told your note and what the branch has now; a
;; fresh one, told the same, if its agent can't resume. Discarding the work
;; since is another thing, asked first: the branch back to the commit the
;; job started from, saying what's lost. Your going back counts against no
;; loop's rounds.

(defun agent-workflow--dependents (run job)
  "The jobs of RUN that need JOB, directly or not."
  (let ((needs (mapcar (lambda (spec) (cons (car spec) (plist-get (cdr spec) :needs)))
                       (plist-get (agent-workflow-run-workflow run) :jobs))))
    (seq-filter (lambda (other) (member job (agent-workflow--before needs other))) (mapcar #'car needs))))

(defun agent-workflow-back-lost (run job)
  "What discarding the work since JOB of RUN started would lose: (COMMITS
. CHANGES), the commits since and the changes not committed, a line each."
  (let* ((commit (plist-get (agent-workflow--job run job) :start-commit))
         (default-directory (agent-workflow-worktree-directory (agent-workflow-run-project run)
                                                                (agent-workflow-run-issue run))))
    (cons (and commit (file-directory-p default-directory)
               (agent-workflow--git-lines "log" "--oneline" (concat commit "..HEAD")))
          (and (file-directory-p default-directory) (agent-workflow--git-lines "status" "--short")))))

(cl-defun agent-workflow-back (run job &key (step 0) note discard (by "you"))
  "Send RUN back to step STEP (from 0) of JOB, with NOTE, BY (you): see
GOING BACK. DISCARD: the branch back to the commit JOB started from, its
changes not committed gone (asked before, by its caller). A user error if
JOB hasn't run, or STEP isn't one."
  (let* ((state (or (agent-workflow--job run job) (user-error "No job %s in %s" job (agent-workflow-run-name run))))
         (steps (plist-get (agent-workflow--job-spec run job) :steps))
         (replaced (cons job (agent-workflow--dependents run job)))
         (project (agent-workflow-run-project run))
         (issue (agent-workflow-run-issue run)))
    (when (memq (plist-get state :status) '(pending skipped))
      (agent-workflow--refuse "%s hasn't run in %s" job (agent-workflow-run-name run)))
    (unless (and (natnump step) (< step (length steps)))
      (user-error "%s has no step %s (%d step%s)" job step (length steps) (if (= (length steps) 1) "" "s")))
    (when (eq (agent-workflow-run-state run) 'cancelled)
      (user-error "%s was cancelled" (agent-workflow-run-name run)))
    (let ((session (or (plist-get state :session)
                       (when-let* ((agent (plist-get state :agent))) (agent-workflow-agent-session agent))))
          (lost (and discard (agent-workflow-back-lost run job))))
      ;; Each job replaced: its agent stopped, its snapshot gone, pending again.
      (dolist (other replaced)
        (let ((other-state (agent-workflow--job run other)))
          (unless (memq (plist-get other-state :status) '(pending skipped))
            (when-let* ((agent (plist-get other-state :agent)))
              (agent-workflow-stop-agent agent))
            (when (plist-get other-state :snapshot)
              (agent-workflow-snapshot-remove project issue other))
            (agent-workflow--job-set run other :status 'pending :agent nil :finished nil :why nil :pool nil
                                     :outcome nil :notes nil :snapshot nil
                                     :round (1+ (or (plist-get other-state :round) 1))))))
      (agent-workflow--job-set run job :back (list :step step :note note :by by :session session))
      (when discard
        (let ((default-directory (agent-workflow-worktree-directory project issue))
              (commit (plist-get state :start-commit)))
          (unless commit (agent-workflow--refuse "%s: the commit it started from isn't known" job))
          (agent-workflow--git "reset" "--hard" commit)
          (agent-workflow--git "clean" "-fd")))
      (agent-workflow--journal run "went-back" :job job :step step :note note :by by
                               :replaced (vconcat replaced) :discarded (if discard t :false)
                               :lost (and lost (vconcat (append (car lost) (cdr lost)))))
      (agent-workflow--bd-write project issue "--append-notes"
                                (format "Sent back to %s by %s%s%s" job by
                                        (if (and note (not (string-empty-p note))) (concat ": " note) "")
                                        (if discard ", the work since discarded" "")))
      (when (memq (agent-workflow-run-state run) agent-workflow--ended)
        (setf (agent-workflow-run-state run) 'running))
      (agent-workflow--refresh run)
      (agent-workflow--changed run)
      (agent-workflow--tick-soon)
      replaced)))

(defun agent-workflow--read-run (project)
  "A run of PROJECT you pick (the only one, not asked)."
  (let ((runs (seq-remove (lambda (run) (eq (agent-workflow-run-state run) 'cancelled)) (agent-workflow-runs project))))
    (pcase runs
      ('nil (user-error "No run in %s" (file-name-nondirectory (directory-file-name project))))
      (`(,run) run)
      (_ (let ((names (mapcar (lambda (run) (cons (format "%s (%s)" (agent-workflow-run-name run)
                                                            (agent-workflow-run-state run))
                                                    run))
                                runs)))
           (cdr (assoc (completing-read "Run: " names nil t) names)))))))

(defun agent-workflow-back-command (run job step note &optional discard)
  "Send RUN back to step STEP of JOB with NOTE (M-x agent-workflow-back).
Interactively the run, the job (one that has run), its step (asked only
when it has several), your note; with \[universal-argument], the work since
discarded, what's lost said and asked first."
  (interactive
   (let* ((project (or (agent-workflow-project) (user-error "Not in a git repository")))
          (run (agent-workflow--read-run project))
          (jobs (mapcar #'car (seq-remove (lambda (job) (memq (plist-get (cdr job) :status) '(pending skipped)))
                                          (agent-workflow-run-jobs run))))
          (job (if jobs (completing-read "Back to the job: " jobs nil t)
                 (user-error "No job of %s has run" (agent-workflow-run-name run))))
          (steps (plist-get (agent-workflow--job-spec run job) :steps))
          (step (if (cdr steps)
                    (let ((names (cl-loop for step in steps for i from 0
                                          collect (cons (format "%d: %s %s" (1+ i) (plist-get step :kind)
                                                                (or (plist-get step :agent) (plist-get step :run)
                                                                    (plist-get step :uses) (plist-get step :elisp)))
                                                        i))))
                      (cdr (assoc (completing-read "Its step: " names nil t) names)))
                  0))
          (note (read-string "Your note: "))
          (discard (and current-prefix-arg
                        (pcase-let ((`(,commits . ,changes) (agent-workflow-back-lost run job)))
                          (yes-or-no-p (format "Discard the work since %s started (%d commit%s, %d change%s not committed)? "
                                               job (length commits) (if (= (length commits) 1) "" "s")
                                               (length changes) (if (= (length changes) 1) "" "s")))))))
     (list run job step note discard)))
  (agent-workflow-back run job :step step :note note :discard discard)
  (message "%s: back to %s%s" (agent-workflow-run-name run) job (if discard ", the work since discarded" "")))

;; ====== YOU ======

(defun agent-workflow--read-issues (project)
  "The issues you pick in PROJECT, several at once (an epic: its open
issues): their ids."
  (let* ((issues (agent-workflow-open-issues project))
         (candidates (mapcar (lambda (issue)
                               (cons (format "%s  %s%s" (nth 0 issue) (nth 1 issue)
                                             (if (equal (nth 2 issue) "epic") "  (epic: its issues)" ""))
                                     issue))
                             issues))
         (picked (completing-read-multiple "Run on: " candidates nil t)))
    (or (seq-mapcat (lambda (choice)
                      (let ((issue (cdr (assoc choice candidates))))
                        (if (equal (nth 2 issue) "epic")
                            (agent-workflow-epic-issues project (car issue))
                          (list (car issue)))))
                    picked)
        (user-error "No issue picked"))))

(defun agent-workflow--read-workflow (project issue)
  "ISSUE's workflow in PROJECT: the one that fits it, asked only when
several do (or none: all of them)."
  (let* ((info (agent-workflow-issue project issue))
         (fitting (ignore-errors (agent-workflow--fitting project info))))
    (if (and fitting (null (cdr fitting)))
        (car fitting)
      (completing-read (format "Workflow for %s (a %s): " issue (plist-get info :type))
                       (or fitting (mapcar #'car (agent-workflow-workflows project))) nil t))))

(defun agent-workflow-run (issues &optional workflow project)
  "Start runs on ISSUES (ids) of PROJECT (default: the current one's), each
with WORKFLOW, else its own: those started and those refused, said.
Interactively, the issues picked, several at once (an epic: its open
issues), then each one's workflow, asked only when several fit. Return
\(STARTED . REFUSED): runs, and (ISSUE . WHY) each."
  (interactive (let ((project (or (agent-workflow-project) (user-error "Not in a git repository"))))
                 (list (agent-workflow--read-issues project) nil project)))
  (let* ((project (or project (agent-workflow-project) (user-error "Not in a git repository")))
         started refused)
    (dolist (issue issues)
      (condition-case err
          (push (agent-workflow-start-run project issue
                                          :workflow (or workflow
                                                        (and (called-interactively-p 'any)
                                                             (agent-workflow--read-workflow project issue)))
                                          :by "you")
                started)
        (user-error (push (cons issue (error-message-string err)) refused))))
    (setq started (nreverse started) refused (nreverse refused))
    (message "%s" (string-join
                   (delq nil (list (and started (concat "Started: " (mapconcat #'agent-workflow-run-name started ", ")))
                                   (and refused (concat "refused: " (mapconcat (lambda (r) (format "%s (%s)" (car r) (cdr r)))
                                                                               refused "; ")))))
                   "; "))
    (cons started refused)))
