;;; $DOOMDIR/config/agent-workflow/resume.el -*- lexical-binding: t; -*-
;; A run that stopped goes on from where it was. Loaded from
;; config/agent-workflow.el, after steps.el. No Doom here.
;;
;; A run's state.json holds all it needs to come back (runs.el). Emacs
;; starting, the runs not over of the projects that had some (noted in
;; `agent-workflow-projects-file') are read back, each with the workflow it
;; started with (its workflow.yml); a project's are read back too when you
;; use it before (M-x agent-workflow-run-ticket, continue...). A job that was
;; running is interrupted: it waits for you, as does its run. Continue it
;; (M-x agent-workflow-continue: every run of the project at once; one, with
;; its issue, from the shell): an agent step's session resumed in the same
;; worktree, told it was interrupted and what the branch has now (a fresh
;; one told the same, if it can't be); a script run again from its start.
;; Done steps never run again. Or skip its step, go back to a job, or cancel
;; the run. `agent-workflow-continue-on-start' continues them by itself.
;;
;; A run keeps the workflow it started with; continuing with the current
;; one (C-u, --current) takes the project's now, jobs kept by their names.
;;
;; Pause (M-x agent-workflow-pause): nothing new starts, running steps
;; finish; with C-u, they stop at once, interrupted. M-x
;; agent-workflow-unpause: on again.
;;
;; Cancel (M-x agent-workflow-cancel): its agents stopped, its scripts
;; killed, its jobs running or waiting cancelled, the run over; its issue
;; open again, its branch and worktree kept.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'json)

(defvar agent-workflow-projects-file)
(defvar agent-workflow-continue-on-start)

(defvar agent-workflow--paused nil
  "Non-nil while runs are paused: nothing new starts.")

;; ====== THE PROJECTS WITH RUNS ======

(defun agent-workflow--known-projects ()
  "The projects that had runs, as noted."
  (when (file-readable-p agent-workflow-projects-file)
    (ignore-errors (with-temp-buffer (insert-file-contents agent-workflow-projects-file)
                                     (read (current-buffer))))))

(defvar agent-workflow--noted nil "The projects noted, this Emacs.")

(defun agent-workflow--note-project (run)
  "RUN's project noted as one with runs. In `agent-workflow-run-functions'."
  (let ((project (agent-workflow-run-project run)))
    (unless (member project agent-workflow--noted)
      (push project agent-workflow--noted)
      (let ((known (agent-workflow--known-projects)))
        (unless (member project known)
          (make-directory (file-name-directory agent-workflow-projects-file) t)
          (with-temp-file agent-workflow-projects-file
            (prin1 (cons project known) (current-buffer))))))))

;; ====== READING ONE BACK ======

(defun agent-workflow--job-from-json (object)
  "A job's state as state.json has it (a plist), as the run had it."
  (let ((state nil))
    (dolist (key agent-workflow--saved-job-keys)
      (let ((value (plist-get object key)))
        (setq state
              (plist-put state key
                         (pcase key
                           (:status (and value (intern value)))
                           (:ask (and value (let ((ask (copy-sequence value)))
                                              (setq ask (plist-put ask :kind (and (plist-get ask :kind)
                                                                                  (intern (plist-get ask :kind)))))
                                              ask)))
                           (:tries (cl-loop for (k v) on value by #'cddr
                                            collect (cons (string-to-number (substring (symbol-name k) 1)) v)))
                           (_ value))))))
    state))

(defun agent-workflow--read-run (dir)
  "The run in DIR (a run's folder), read back from its state.json and the
workflow it started with: a run, or nil if it can't be."
  (let ((state-file (expand-file-name "state.json" dir))
        (workflow-file (expand-file-name "workflow.yml" dir)))
    (when (and (file-readable-p state-file) (file-readable-p workflow-file))
      (let* ((saved (with-temp-buffer
                      (insert-file-contents state-file)
                      (json-parse-buffer :object-type 'plist :array-type 'list :null-object nil :false-object nil)))
             (workflow (car (agent-workflow-workflow-read workflow-file 'any (plist-get saved :workflow))))
             (project (file-name-as-directory
                       (expand-file-name "../../../../../" (file-name-as-directory dir)))))
        (when workflow
          (setq workflow (plist-put workflow :file workflow-file))
          (agent-workflow-run--make
           :project project :issue (plist-get saved :issue) :n (plist-get saved :run)
           :dir (file-name-as-directory dir) :workflow workflow
           :info (plist-get saved :info)
           :state (intern (plist-get saved :state)) :why (plist-get saved :why)
           :order (or (plist-get saved :order) (cl-incf agent-workflow--run-count))
           :total (or (plist-get saved :total) 0)
           :spent (let ((spent (plist-get saved :spent)))
                    (append (list :cost (or (plist-get spent :cost) 0) :tokens (or (plist-get spent :tokens) 0))
                            ;; An agent's cost not known: still so.
                            (and (plist-get spent :cost-unknown) (list :cost-unknown t))))
           :active (or (plist-get (plist-get saved :spent) :time) 0)
           :more (plist-get saved :more)
           :warned (plist-get saved :warned)
           :base (plist-get saved :base)
           :branch-end (plist-get saved :branch-end)
           :edges (mapcar (lambda (edge) (cons (plist-get edge :edge)
                                               (list :count (plist-get edge :count) :notes (plist-get edge :notes))))
                          (plist-get saved :edges))
           :jobs (mapcar (lambda (job) (cons (plist-get job :name) (agent-workflow--job-from-json job)))
                         (plist-get saved :jobs))))))))

(defun agent-workflow-restore (project)
  "PROJECT's runs not over read back, those this Emacs hasn't: their jobs
that were running interrupted, waiting for you; the others looked at
\(what can start, starts). Return them."
  (let ((dir (agent-workflow--runs-directory project))
        restored)
    (when (file-directory-p dir)
      (dolist (issue-dir (directory-files dir t "\\`[^.]"))
        (dolist (run-dir (and (file-directory-p issue-dir) (directory-files issue-dir t "\\`[0-9]+\\'")))
          (let ((dir (file-name-as-directory run-dir)))
            (unless (seq-find (lambda (run) (equal (agent-workflow-run-dir run) dir)) agent-workflow--runs)
              (when-let* ((run (ignore-errors (agent-workflow--read-run dir))))
                (unless (memq (agent-workflow-run-state run) agent-workflow--ended)
                  (setf (agent-workflow-run-project run) (file-name-as-directory project))
                  (dolist (job (agent-workflow-run-jobs run))
                    ;; Running, or waiting on its agent's question (that
                    ;; agent gone with Emacs): interrupted.
                    (when (or (eq (plist-get (cdr job) :status) 'running)
                              (and (eq (plist-get (cdr job) :status) 'waiting)
                                   (plist-get (cdr job) :agent-asks)))
                      (agent-workflow--job-set run (car job) :status 'waiting :agent-asks nil
                                               :ask (list :kind 'interrupted :step (or (plist-get (cdr job) :step) 0)
                                                          :reason "Emacs stopped")
                                               :why (format "%s: interrupted (Emacs stopped): continue it, skip its step, or stop?"
                                                            (car job)))))
                  (setq agent-workflow--runs (append agent-workflow--runs (list run)))
                  (agent-workflow--journal run "restored")
                  (agent-workflow--refresh run)
                  (agent-workflow--changed run)
                  (push run restored))))))))
    ;; Those not interrupted (queued, pending jobs left) go on; the
    ;; interrupted ones wait for you (`agent-workflow--advance').
    (when restored (agent-workflow--tick-soon))
    (nreverse restored)))

(defun agent-workflow-restore-all ()
  "Every noted project's runs read back; continued, if
`agent-workflow-continue-on-start' says. In `emacs-startup-hook'."
  (dolist (project (agent-workflow--known-projects))
    (when (file-directory-p project)
      (let ((runs (with-demoted-errors "agent workflow: %S" (agent-workflow-restore project))))
        (when agent-workflow-continue-on-start
          (dolist (run runs)
            (with-demoted-errors "agent workflow: %S" (agent-workflow--continue run))))))))

(defun agent-workflow--ensure-restored (project)
  "PROJECT's runs read back, if they haven't been (before a command uses
them)."
  (unless (seq-some (lambda (run) (equal (agent-workflow-run-project run) project)) agent-workflow--runs)
    (agent-workflow-restore project)))

;; ====== CONTINUING ======

(defun agent-workflow--interrupted (run)
  "RUN's jobs interrupted: their names."
  (mapcar #'car (seq-filter (lambda (job) (eq (plist-get (plist-get (cdr job) :ask) :kind) 'interrupted))
                            (agent-workflow-run-jobs run))))

(defun agent-workflow--with-current-workflow (run)
  "RUN given its project's workflow as it is now (its jobs kept by their
names, new ones pending, gone ones dropped), its copy replaced."
  (let* ((name (plist-get (agent-workflow-run-workflow run) :name))
         (now (or (alist-get name (agent-workflow-workflows (agent-workflow-run-project run)) nil nil #'equal)
                  (user-error "No workflow %s in the project now" name))))
    (copy-file (plist-get now :file) (expand-file-name "workflow.yml" (agent-workflow-run-dir run)) t)
    (setf (agent-workflow-run-workflow run) now
          (agent-workflow-run-jobs run)
          (mapcar (lambda (job) (cons (car job) (or (agent-workflow--job run (car job)) (list :status 'pending :step 0))))
                  (plist-get now :jobs)))
    (agent-workflow--journal run "workflow-changed" :workflow name)))

(cl-defun agent-workflow--continue (run &key current (by "you"))
  "Continue RUN's interrupted jobs: an agent step's session resumed, told
it was interrupted; a script run again. CURRENT: with its project's
workflow as it is now. Return the jobs continued."
  (when current (agent-workflow--with-current-workflow run))
  (let ((jobs (agent-workflow--interrupted run)))
    (dolist (job jobs)
      (agent-workflow--continue-job run job by))
    (agent-workflow--changed run)
    (agent-workflow--tick-soon)
    jobs))

(defun agent-workflow--interrupted-why (ask)
  "Why a job was stopped, its question ASK: words its agent is told."
  (pcase (plist-get ask :kind)
    ('budget "its run's budget was used up, and the user gave it more")
    ('closed "its issue was closed by hand, and opened again")
    ('moved "commits of the branch went missing (a reset, a force-push?)")
    (_ (or (plist-get ask :reason) "Emacs stopped"))))

(defun agent-workflow--continue-job (run job by)
  "JOB of RUN, interrupted, continued BY: its step again, an agent's
session resumed, told so; an agent step its agent was done with already
\(it said so, its turn not over yet when it was stopped: a budget's cost
came at its end), it ends: the job goes on from there, its work not done
again."
  (let* ((state (agent-workflow--job run job))
         (index (plist-get (plist-get state :ask) :step))
         (step (nth index (plist-get (agent-workflow--job-spec run job) :steps))))
    (agent-workflow--journal run "continued" :job job :step index :by by)
    ;; Its own agent step (not a fix of a script's, run afresh).
    (if (and (plist-get state :finished) (eq (plist-get step :kind) 'agent))
        (progn
          (agent-workflow--job-set run job :ask nil :status 'running :why nil)
          (agent-workflow--refresh run)
          (agent-workflow--step-finished run job))
      (agent-workflow--job-set run job :ask nil :status 'running :why nil :finished nil
                               :back (and (eq (plist-get step :kind) 'agent)
                                          (list :step index :by by :session (plist-get state :session)
                                                ;; Why, for its agent.
                                                :interrupted (agent-workflow--interrupted-why
                                                              (plist-get state :ask)))))
      (agent-workflow--refresh run)
      (agent-workflow--step-start run job index))))

(defun agent-workflow--interrupt (run job &optional kind why)
  "JOB of RUN stopped at once: its agent stopped (its session kept), its
script killed; interrupted (paused now), waiting for you. KIND and WHY:
the question it waits on instead (budget, closed...), said so, once."
  (let ((state (agent-workflow--job run job)))
    (when-let* ((agent (plist-get state :agent)))
      (agent-workflow--job-set run job :session (or (agent-workflow-agent-session agent) (plist-get state :session)))
      (agent-workflow-stop-agent agent))
    (when-let* ((process (plist-get state :process)))
      (when (process-live-p process)
        (process-put process 'agent-workflow-stopped t)
        (delete-process process)))
    ;; Its step waiting for an agent: it waits for you now, not for one;
    ;; a fix under way (a failed step's, a merge's conflicts) dropped:
    ;; continued, its step runs afresh, once (skipped, it's skipped).
    (agent-workflow--job-set run job :agent nil :process nil :pool nil :retry nil :resolving nil :fix-script nil
                             :ask (list :kind (or kind 'interrupted) :step (or (plist-get state :step) 0)
                                        :reason (if kind nil "paused")))
    (agent-workflow--journal run "interrupted" :job job :kind (symbol-name (or kind 'interrupted)))
    (agent-workflow--wait run job (if why
                                      (format "%s: %s" job why)
                                    (format "%s: interrupted (paused): continue it, skip its step, or stop?" job)))))

;; ====== CANCELLING ======

(defun agent-workflow--stop-all (run)
  "RUN's agents stopped, its scripts killed, its snapshots gone."
  (dolist (job (agent-workflow-run-jobs run))
    (let ((state (cdr job)))
      (when-let* ((agent (plist-get state :agent))) (agent-workflow-stop-agent agent))
      (when-let* ((process (plist-get state :process)))
        (when (process-live-p process)
          (process-put process 'agent-workflow-stopped t)
          (delete-process process)))
      (when (plist-get state :snapshot)
        (agent-workflow-snapshot-remove (agent-workflow-run-project run) (agent-workflow-run-issue run) (car job)))
      (agent-workflow--job-set run (car job) :agent nil :process nil :snapshot nil :pool nil))))

(defun agent-workflow--cancel-jobs (run &optional except)
  "RUN's jobs running or waiting (but EXCEPT) cancelled, their run over:
their own status, kept in its state.json (no spinner left in its pane or
status); every job's question dropped. Return their names."
  (let ((cancelled nil))
    (dolist (job (agent-workflow-run-jobs run))
      (when (and (memq (plist-get (cdr job) :status) '(running waiting))
                 (not (equal (car job) except)))
        (agent-workflow--job-set run (car job) :status 'cancelled :why nil :finished nil :retry nil :resolving nil
                                 :fix-script nil)
        (push (car job) cancelled)))
    ;; Their questions gone with them: nothing answers them now.
    (dolist (job (agent-workflow-run-jobs run))
      (when (plist-get (cdr job) :ask)
        (agent-workflow--job-set run (car job) :ask nil)))
    (nreverse cancelled)))

(cl-defun agent-workflow--cancel (run &key (by "you"))
  "Cancel RUN: its agents stopped, its scripts killed, its snapshots gone,
its jobs running or waiting cancelled (journaled: :jobs); the run over, its
issue open again; its branch kept, its worktree removed by itself soon
\(`agent-workflow--worktree-removal-soon')."
  (agent-workflow--stop-all run)
  (agent-workflow--journal run "cancelled" :by by :jobs (vconcat (agent-workflow--cancel-jobs run)))
  (agent-workflow--set-state run 'cancelled)
  (agent-workflow--run-bd-write run "--status" "open")
  (agent-workflow--issue-summary run)
  (agent-workflow--worktree-removal-soon run)
  run)

;; ====== ITS WORKTREE, ONCE IT'S OVER ======
;; A run cancelled or failed: its worktree removed by itself
;; `agent-workflow-worktree-removal-delay' seconds after (its pane counting
;; them down, Keep worktree stopping it), if nothing in it would be lost (no
;; change not committed); its branch deleted if it has no commit of its own
;; (as a run done: `agent-workflow--branch-end'), else kept. One with changes
;; not committed keeps it, as does one done with them: M-x
;; agent-workflow-remove-worktree, or its pane's Remove worktree, asked
;; first, saying what goes (those changes lost, said).

(defvar agent-workflow-worktree-removal-delay)

(defvar agent-workflow--worktree-removals (make-hash-table :test #'eq)
  "The runs whose worktree is removed by itself soon: run to (TIMER . WHEN),
WHEN a `float-time'.")

(defun agent-workflow--worktree-clean-p (run)
  "Whether RUN's worktree has nothing removing it would lose: no change not
committed."
  (zerop (or (plist-get (agent-workflow-run-where run t) :uncommitted) 0)))

(defun agent-workflow--worktree-removal-soon (run)
  "RUN just over (cancelled, failed): its worktree removed by itself in
`agent-workflow-worktree-removal-delay' seconds, if it has one and nothing
in it would be lost then; its pane counting down."
  (when (and agent-workflow-worktree-removal-delay
             (agent-workflow--worktree-left-p run)
             (agent-workflow--worktree-clean-p run))
    (agent-workflow-keep-worktree run t)
    (puthash run (cons (run-at-time agent-workflow-worktree-removal-delay nil
                                    #'agent-workflow--worktree-removal-due run)
                       (+ (float-time) agent-workflow-worktree-removal-delay))
             agent-workflow--worktree-removals)
    (agent-workflow--changed run)))

(defun agent-workflow--worktree-removal-due (run)
  "RUN's worktree's time come: removed, if it's still left and nothing in it
would be lost now (a change made meanwhile keeps it)."
  (remhash run agent-workflow--worktree-removals)
  (if (and (agent-workflow--worktree-left-p run) (agent-workflow--worktree-clean-p run))
      (with-demoted-errors "agent workflow: %S"
        (agent-workflow--remove-worktree
         run :by (format "itself, %ds after it ended" agent-workflow-worktree-removal-delay)))
    (agent-workflow--changed run)))

(defun agent-workflow-worktree-removal-time (run)
  "When RUN's worktree is removed by itself (a `float-time'), or nil."
  (cdr (gethash run agent-workflow--worktree-removals)))

(defun agent-workflow-keep-worktree (run &optional quiet)
  "RUN's worktree not removed by itself (its pane's Keep worktree): it
stays, for M-x agent-workflow-remove-worktree. QUIET: nothing said, its
pane not drawn again."
  (when-let* ((removal (gethash run agent-workflow--worktree-removals)))
    (cancel-timer (car removal))
    (remhash run agent-workflow--worktree-removals)
    (unless quiet
      (agent-workflow--journal run "worktree-kept")
      (agent-workflow--changed run)
      (message "%s: its worktree kept" (agent-workflow-run-name run)))))

(defun agent-workflow--newest-run-p (run)
  "Whether RUN is its issue's newest run in its project: the issue's
worktree (one folder, each run on it reusing it) is its."
  (not (seq-some (lambda (other) (and (equal (agent-workflow-run-issue other) (agent-workflow-run-issue run))
                                      (> (agent-workflow-run-n other) (agent-workflow-run-n run))))
                 (agent-workflow-runs-of (agent-workflow-run-project run)))))

(defun agent-workflow--worktree-left-p (run)
  "Whether RUN is over and has a worktree of its own still (not one in your
checkout, nor a newer run's on its issue)."
  (and (memq (agent-workflow-run-state run) agent-workflow--ended)
       (not (agent-workflow-run-checkout-p run))
       (agent-workflow--newest-run-p run)
       (file-exists-p (expand-file-name ".git" (agent-workflow-worktree-directory
                                                (agent-workflow-run-project run) (agent-workflow-run-issue run))))))

(cl-defun agent-workflow--remove-worktree (run &key (by "you"))
  "RUN's worktree removed (its changes not committed lost), its snapshots
too; its branch deleted if it has no commit of its own, else kept
\(`agent-workflow--branch-end'). Journaled; its pane drawn again."
  (unless (agent-workflow--worktree-left-p run)
    (user-error "%s has no worktree left to remove (or isn't over)" (agent-workflow-run-name run)))
  (agent-workflow-keep-worktree run t)
  (let ((project (agent-workflow-run-project run))
        (issue (agent-workflow-run-issue run)))
    (dolist (job (agent-workflow-run-jobs run))
      (ignore-errors (agent-workflow-snapshot-remove project issue (car job))))
    (agent-workflow-worktree-remove project issue t)
    (agent-workflow--journal run "worktree-removed" :by by)
    (agent-workflow--branch-end run)
    (agent-workflow-run-where run t)
    (agent-workflow--save-state run)
    (agent-workflow--changed run)
    run))

(defun agent-workflow--remove-worktree-question (run)
  "What removing RUN's worktree does, asked: its changes not committed
lost, its branch deleted (no commit of its own) or kept."
  (let* ((where (agent-workflow-run-where run t))
         (uncommitted (or (plist-get where :uncommitted) 0))
         (own (or (plist-get where :own) 0)))
    (format "Remove %s's worktree?%s Its branch %s %s. "
            (agent-workflow-run-name run)
            (if (> uncommitted 0)
                (format " Its %d file%s not committed %s lost." uncommitted (if (= uncommitted 1) "" "s")
                        (if (= uncommitted 1) "is" "are"))
              "")
            (plist-get where :branch)
            (if (> own 0)
                (format "is kept (%d commit%s of its own)" own (if (= own 1) "" "s"))
              "is deleted (no commit of its own)"))))

(defun agent-workflow-remove-worktree (run)
  "Remove the worktree a run over kept (M-x agent-workflow-remove-worktree,
its pane's Remove worktree), asked first: its changes not committed lost,
its branch deleted if it has no commit of its own, else kept."
  (interactive (let* ((project (or (agent-workflow-project) (user-error "Not in a git repository")))
                      (runs (progn (agent-workflow--ensure-restored project)
                                   (seq-filter #'agent-workflow--worktree-left-p (agent-workflow-runs-of project))))
                      (names (mapcar (lambda (run) (cons (agent-workflow-run-name run) run)) runs)))
                 (unless runs (user-error "No run over has a worktree left"))
                 (list (cdr (assoc (completing-read "Remove the worktree of: " names nil t) names)))))
  (when (yes-or-no-p (agent-workflow--remove-worktree-question run))
    (agent-workflow--remove-worktree run)
    (message "%s: its worktree removed" (agent-workflow-run-name run))
    t))

;; ====== FAILING ======

(cl-defun agent-workflow-fail (run why &key job step)
  "RUN failed, WHY (words): a step of JOB (STEP, from 0) said it can't go
on (exit 3; an elisp: step's `agent-workflow-abort'). As cancelled: its
agents stopped, its scripts killed, its snapshots gone, its issue open
again, its branch and worktree kept; JOB failed, its other jobs running or
waiting cancelled (journaled: :cancelled), the run over, said as a run
needing you is (`agent-workflow-needs-you-functions')."
  (agent-workflow--stop-all run)
  (when job
    (agent-workflow--job-set run job :status 'failed :why why))
  (agent-workflow--journal run "failed" :job job :step step :why why
                           :cancelled (vconcat (agent-workflow--cancel-jobs run job)))
  (agent-workflow--set-state run 'failed why)
  (agent-workflow--run-bd-write run "--status" "open")
  (agent-workflow--issue-summary run)
  (agent-workflow--worktree-removal-soon run)
  (run-hook-with-args 'agent-workflow-needs-you-functions run (concat "failed: " why))
  run)

;; ====== PAUSING ======

(defun agent-workflow-pause (&optional now)
  "Pause runs: nothing new starts, running steps finish. NOW
\(interactively, \\[universal-argument]): they stop at once, interrupted."
  (interactive "P")
  (setq agent-workflow--paused t)
  (when now
    (dolist (run agent-workflow--runs)
      (dolist (job (agent-workflow-run-jobs run))
        (when (eq (plist-get (cdr job) :status) 'running)
          (agent-workflow--interrupt run (car job))))))
  (message "Agent workflow: paused%s" (if now ", its steps stopped" "")))

(defun agent-workflow-unpause ()
  "Runs on again, as they were before the pause."
  (interactive)
  (setq agent-workflow--paused nil)
  (agent-workflow--tick-soon)
  (message "Agent workflow: on again"))

;; ====== YOU ======

(defun agent-workflow-continue (&optional current)
  "Continue every interrupted run of the current project (M-x
agent-workflow-continue); with \\[universal-argument], with its workflow as
it is now."
  (interactive "P")
  (let* ((project (or (agent-workflow-project) (user-error "Not in a git repository")))
         (runs (progn (agent-workflow--ensure-restored project)
                      (seq-filter #'agent-workflow--interrupted (agent-workflow-runs-of project)))))
    (unless runs (user-error "No run of %s was interrupted" (file-name-nondirectory (directory-file-name project))))
    (dolist (run runs) (agent-workflow--continue run :current current))
    (message "Continued: %s" (mapconcat #'agent-workflow-run-name runs ", "))))

(defun agent-workflow-cancel (run)
  "Cancel RUN (M-x agent-workflow-cancel), asked first."
  (interactive (let* ((project (or (agent-workflow-project) (user-error "Not in a git repository")))
                      (runs (progn (agent-workflow--ensure-restored project)
                                   (seq-remove (lambda (run) (memq (agent-workflow-run-state run) agent-workflow--ended))
                                               (agent-workflow-runs-of project))))
                      (names (mapcar (lambda (run) (cons (agent-workflow-run-name run) run)) runs)))
                 (unless runs (user-error "No run to cancel"))
                 (list (cdr (assoc (completing-read "Cancel the run: " names nil t) names)))))
  (agent-workflow-cancel-asked run))

(cl-defun agent-workflow-cancel-asked (run &key (by "you"))
  "Cancel RUN, BY you, once you said yes to what it stops and keeps (M-x
agent-workflow-cancel, its pane's Cancel). Non-nil if it was."
  (when (yes-or-no-p (format "Cancel %s? Its agents and scripts stop, its issue is open again; %s. "
                             (agent-workflow-run-name run)
                             (if (agent-workflow-run-checkout-p run)
                                 "its commits in your checkout are kept"
                               "its branch and worktree are kept")))
    (agent-workflow--cancel run :by by)
    (message "%s cancelled" (agent-workflow-run-name run))
    t))

(add-hook 'agent-workflow-run-functions #'agent-workflow--note-project)
