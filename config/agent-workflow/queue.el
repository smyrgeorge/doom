;;; $DOOMDIR/config/agent-workflow/queue.el -*- lexical-binding: t; -*-
;; Starting a run, the queue (which runs go, as the pool and their limits
;; allow) and the commands that start them. Loaded from
;; config/agent-workflow.el, after runs.el. No Doom here.
;;
;; The commands: M-x agent-workflow-run-ticket, agent-workflow-run, their
;; issues picked as the issue list shows them. A run itself: runs.el.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)


;; ====== STARTING ONE ======

(defun agent-workflow--fitting (project info)
  "The workflows of PROJECT that fit the issue INFO: its workflow:NAME
label's (that one alone, if there's one), else those whose for: has its
type. Their names."
  (let ((workflows (agent-workflow-workflows project)))
    (if-let* ((label (seq-find (lambda (label) (string-prefix-p "workflow:" label)) (plist-get info :labels))))
        (let ((name (string-remove-prefix "workflow:" label)))
          (cond ((not (assoc name workflows))
                 (agent-workflow--refuse "%s's label %s: no such workflow (%s)" (plist-get info :id) label
                                         (agent-workflow--listed (mapcar #'car workflows))))
                ((plist-get (cdr (assoc name workflows)) :ticketless)
                 (agent-workflow--refuse "%s's label %s: %s runs without a ticket (M-x agent-workflow-run)"
                                         (plist-get info :id) label name))
                (t (list name))))
      (mapcar #'car (seq-filter (lambda (workflow) (and (not (plist-get (cdr workflow) :ticketless))
                                                        (member (plist-get info :type) (plist-get (cdr workflow) :for))))
                                workflows)))))

(defun agent-workflow--next-run-number (project issue)
  "The next run of ISSUE in PROJECT: 1 more than its runs' folders say."
  (let ((dir (expand-file-name issue (agent-workflow--runs-directory project))))
    (1+ (apply #'max 0 (mapcar #'string-to-number
                               (and (file-directory-p dir) (directory-files dir nil "\\`[0-9]+\\'")))))))

(cl-defun agent-workflow-start-run (project issue &key workflow (by "you") ask)
  "Start a run on ISSUE of PROJECT with WORKFLOW (a name; default: its
label's, else the one for its type), started BY (you, shell): the run. A
user error, nothing started, if it can't: closed, an epic, a run already,
no workflow or several, an agent-workspace crew there, a project's
workflow you don't trust (ASK: you're asked, trust.el). A blocked issue's
run is queued until its blockers close."
  (let* ((project (file-name-as-directory project))
         (workflows (agent-workflow-workflows project))
         (_ (when (and workflow (plist-get (cdr (assoc workflow workflows)) :ticketless))
              (user-error "%s runs without a ticket: M-x agent-workflow-run, or agent-workflow run --workflow %s"
                          workflow workflow)))
         (info (agent-workflow-issue project issue)))
    (cond
     ((equal (plist-get info :status) "closed") (user-error "%s is closed" issue))
     ((equal (plist-get info :type) "epic") (user-error "%s is an epic: its issues are run, not it" issue))
     ((agent-workflow-run-of project issue)
      (user-error "%s has a run already (%s)" issue (agent-workflow-run-name (agent-workflow-run-of project issue))))
     ((and workflow (plist-get (cdr (assoc workflow workflows)) :checkout) (agent-workflow--checkout-run project))
      (user-error "%s works in your checkout already: one run there at a time"
                  (agent-workflow-run-name (agent-workflow--checkout-run project))))
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
           (spec (cdr (assoc name workflows))))
      (when (and (plist-get spec :checkout) (agent-workflow--checkout-run project))
        (user-error "%s works in your checkout already: one run there at a time"
                    (agent-workflow-run-name (agent-workflow--checkout-run project))))
      (agent-workflow--check-trust project spec ask)
      (agent-workflow--new-run project issue spec info by))))

(defun agent-workflow--new-run (project id spec info by)
  "A new run of PROJECT on ID (an issue's id; a workflow's own run: its
name) with the workflow SPEC, INFO its issue (a plist), started BY: made,
journaled, queued. Its issue in progress, if it's on one."
  ;; An older run's worktree removal waiting: not this one's, which
  ;; reuses its folder.
  (dolist (old (agent-workflow-runs-of project))
    (when (and (equal (agent-workflow-run-issue old) id) (agent-workflow-worktree-removal-time old))
      (agent-workflow-keep-worktree old t)
      (agent-workflow--changed old)))
  (let* ((n (agent-workflow--next-run-number project id))
         (dir (file-name-as-directory (expand-file-name (format "%s/%d" id n) (agent-workflow--runs-directory project))))
         (run (agent-workflow-run--make
               :project project :issue id :n n :dir dir :workflow spec :info info :state 'queued
               :jobs (mapcar (lambda (job) (cons (car job) (list :status 'pending :step 0)))
                             (plist-get spec :jobs))
               :order (cl-incf agent-workflow--run-count))))
    ;; Its folder out of git first: in your checkout, its files aren't
    ;; changes of yours.
    (agent-workflow--keep-out-of-git project)
    (make-directory dir t)
    (copy-file (plist-get spec :file) (expand-file-name "workflow.yml" dir) t)
    (agent-workflow--journal run "run-started" :workflow (plist-get spec :name) :by by
                             :ticket (if (agent-workflow-run-ticket-p run) t :false)
                             :main (let ((default-directory project))
                                     (car (agent-workflow--git-lines "rev-parse" "HEAD"))))
    (setq agent-workflow--runs (append agent-workflow--runs (list run)))
    (agent-workflow--run-bd-write run "--status" "in_progress")
    (agent-workflow--issue-summary run)
    (agent-workflow--changed run)
    (agent-workflow--tick-soon)
    run))

(defun agent-workflow--workflow-info (spec)
  "What a run of SPEC (a workflow with no ticket) has for its issue: its
name for an id, its description for a title; no type, no labels."
  (list :id (plist-get spec :name) :title (or (plist-get spec :description) (plist-get spec :name))
        :description "" :acceptance "" :notes "" :type nil :priority 2 :status "open" :labels nil :blockers nil))

(cl-defun agent-workflow-start-workflow-run (project workflow &key (by "you") ask)
  "Start a run of WORKFLOW (a name) in PROJECT, on no ticket (its ticket:
false), started BY (you, shell): the run. Its workflow's name stands for an
issue's id (its folder, worktree, log), its branch run/NAME-N made from your
checkout's HEAD; no Beads. A user error, nothing started, if it can't: no
such workflow, one on tickets, a run of it already, its last run's worktree
left with changes not committed, an agent-workspace crew there, a project's
workflow you don't trust (ASK: you're asked, trust.el)."
  (let* ((project (file-name-as-directory project))
         (workflows (agent-workflow-workflows project))
         (spec (or (cdr (assoc workflow workflows))
                   (user-error "No workflow %s (%s)" workflow (agent-workflow--listed (mapcar #'car workflows))))))
    (cond
     ((not (plist-get spec :ticketless))
      (user-error "%s runs on a ticket: M-x agent-workflow-run-ticket, or agent-workflow run ISSUE --workflow %s"
                  workflow workflow))
     ((agent-workflow-run-of project workflow)
      (user-error "%s has a run already (%s)" workflow (agent-workflow-run-name (agent-workflow-run-of project workflow))))
     ((and (plist-get spec :checkout) (agent-workflow--checkout-run project))
      (user-error "%s works in your checkout already: one run there at a time"
                  (agent-workflow-run-name (agent-workflow--checkout-run project))))
     ((agent-workflow-crew-running-p project)
      (user-error "The agent-workspace crew of %s runs: its agents would take the same issues"
                  (file-name-nondirectory (directory-file-name project)))))
    (agent-workflow--check-trust project spec ask)
    (unless (plist-get spec :checkout)
      (agent-workflow--fresh-worktree project workflow))
    (agent-workflow--new-run project workflow spec (agent-workflow--workflow-info spec) by)))

(defun agent-workflow--checkout-run (project)
  "PROJECT's run not over that works in your checkout, or nil."
  (seq-find (lambda (run) (and (agent-workflow-run-checkout-p run)
                               (not (memq (agent-workflow-run-state run) agent-workflow--ended))))
            (agent-workflow-runs-of (file-name-as-directory project))))

(defun agent-workflow--fresh-worktree (project workflow)
  "WORKFLOW's last run's worktree in PROJECT (one cancelled, failed, or
done with changes not committed) removed, its branch kept: a new run's is
made anew, on its own branch. A user error if it has changes not
committed: nothing lost."
  (let ((dir (agent-workflow-worktree-directory project workflow)))
    (when (file-exists-p (expand-file-name ".git" dir))
      (when (let ((default-directory dir)) (agent-workflow--git-lines "status" "--porcelain"))
        (user-error "%s's last run left changes not committed in %s: commit them or remove it first"
                    workflow (abbreviate-file-name (directory-file-name dir))))
      (agent-workflow-worktree-remove project workflow))))

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
agents (its agent steps', its steps' on-fail) lets it edit."
  (let ((definitions (agent-workflow-agent-definitions (agent-workflow-run-project run))))
    (seq-some (lambda (step)
                (seq-some (lambda (name)
                            (and name (agent-workflow-definition-edits-p
                                       (alist-get name definitions nil nil #'equal))))
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
    (when (memq (agent-workflow-run-state run) agent-workflow--ended)
      (throw 'wait nil))
    (when (and (eq (agent-workflow-run-state run) 'queued) (agent-workflow-run-ticket-p run))
      (let ((blockers (plist-get (agent-workflow-issue (agent-workflow-run-project run) (agent-workflow-run-issue run))
                                 :blockers)))
        (when blockers
          (agent-workflow--set-state run 'queued (concat "blocked by " (string-join blockers ", ")))
          (throw 'wait nil))))
    ;; A job interrupted (Emacs stopped, paused now): nothing new starts
    ;; until it's continued (resume.el).
    (when (agent-workflow--interrupted run)
      (throw 'wait nil))
    ;; Blocked since it started (watch.el): nothing new starts.
    (when-let* ((blockers (agent-workflow-run-blocked run)))
      (dolist (job (agent-workflow--startable run))
        (agent-workflow--job-set run job :why (format "%s: waiting: its issue is blocked by %s" job
                                                      (string-join blockers ", "))))
      (agent-workflow--refresh run)
      (throw 'wait nil))
    ;; Paused: nothing new starts.
    (when agent-workflow--paused
      (dolist (job (agent-workflow--startable run))
        (agent-workflow--job-set run job :why (format "%s: waiting: runs are paused" job)))
      (agent-workflow--refresh run)
      (throw 'wait nil))
    ;; A running job's step waiting for an agent: started, if there's one.
    (dolist (job (agent-workflow-run-jobs run))
      (when-let* ((index (plist-get (cdr job) :pool))
                  ;; Still running (not interrupted, cancelled meanwhile).
                  ((eq (plist-get (cdr job) :status) 'running)))
        (unless (agent-workflow--no-agent run (car job))
          (agent-workflow--job-set run (car job) :pool nil :why nil)
          (if (consp index)
              ;; An agent to fix its step: (:fix INDEX OUTPUT WHAT).
              (apply #'agent-workflow--fix run (car job) (cdr index))
            (agent-workflow--agent-step run (car job) (nth index (plist-get (agent-workflow--job-spec run (car job)) :steps))
                                        index)))))
    ;; Every job that can start, starts; one skipped may let others.
    (let ((again t))
      (while again
        (setq again nil)
        (dolist (job (agent-workflow--startable run))
          ;; Over meanwhile (a job before failed as it started: an elisp
          ;; step's abort): nothing more starts.
          (when (memq (agent-workflow-run-state run) agent-workflow--ended)
            (throw 'wait nil))
          (cond
           ((not (agent-workflow--if-holds run job))
            (agent-workflow--job-set run job :status 'skipped :why nil)
            (agent-workflow--journal run "job-skipped" :job job :if (plist-get (agent-workflow--job-spec run job) :if))
            (agent-workflow--changed run)
            (setq again t))
           ((and (agent-workflow--job-edits-p run job) (agent-workflow--editing run))
            (agent-workflow--job-set run job :why (format "%s: waiting for %s, which edits the branch" job
                                                          (agent-workflow--editing run))))
           ;; In your checkout: never over changes of yours (its agent
           ;; would commit them).
           ((and (agent-workflow-run-checkout-p run) (agent-workflow--job-edits-p run job)
                 (agent-workflow--checkout-dirty-p (agent-workflow-run-project run)))
            (agent-workflow--job-set run job :why (format "%s: waiting: your checkout has changes not committed (commit or stash them)" job)))
           ((and (agent-workflow--needs-agent-p run job) (>= (agent-workflow-pool-used) agent-workflow-pool))
            (agent-workflow--job-set run job :why (format "%s: waiting for an agent: %d of %d work" job
                                                          (agent-workflow-pool-used) agent-workflow-pool)))
           ((agent-workflow--over-limit run job)
            (agent-workflow--job-set run job :why (format "%s: waiting: %s" job (agent-workflow--over-limit run job))))
           (t (agent-workflow--job-start run job))))))
    (if (seq-every-p (lambda (job) (memq (plist-get (cdr job) :status) '(done skipped))) (agent-workflow-run-jobs run))
        (agent-workflow--run-done run)
      (agent-workflow--refresh run))))

(defun agent-workflow--run-done (run)
  "RUN is over, every job done or skipped: its worktree removed, if it has
nothing not committed; its branch deleted or kept (`agent-workflow--branch-end');
said on its issue."
  ;; Its snapshots and worktree removed, its branch deleted or kept, first:
  ;; run done is its log's last line.
  (dolist (job (agent-workflow-run-jobs run))
    (agent-workflow-snapshot-remove (agent-workflow-run-project run) (agent-workflow-run-issue run) (car job)))
  (if (agent-workflow-run-checkout-p run)
      ;; In your checkout: its work is there; its issue, if it has one, done.
      (when (agent-workflow-run-ticket-p run)
        (agent-workflow--bd-close (agent-workflow-run-project run) (agent-workflow-run-issue run)
                                  (format "Done in your checkout, on %s"
                                          (or (agent-workflow--checkout-branch (agent-workflow-run-project run))
                                              "a detached HEAD"))))
    (ignore-errors (agent-workflow-worktree-remove (agent-workflow-run-project run) (agent-workflow-run-issue run)))
    (agent-workflow--branch-end run))
  ;; Where it is now (its worktree gone, merged, its branch deleted), said.
  (agent-workflow-run-where run t)
  (agent-workflow--set-state run 'done)
  (agent-workflow--journal run "run-done")
  (agent-workflow--issue-summary run))

(defun agent-workflow--branch-empty-p (run branch)
  "Whether BRANCH, RUN's issue's, got no commit since RUN's base (where it
started); nil if that's unknown."
  (when-let* ((base (plist-get (agent-workflow-run-base run) :commit)))
    (let ((default-directory (agent-workflow-run-project run)))
      (equal (car (agent-workflow--git-lines "rev-list" "--count" (concat base ".." branch))) "0"))))

(defun agent-workflow--branch-end (run)
  "RUN done, its worktree removed: its issue's branch deleted if its
workflow says so (branch: delete, the default) and its work is in the main
branch (never a commit lost: your checkout may be on another branch); else
kept, saying why. Journaled, kept in RUN, its last commit too (:head: its
files and commits read from it once it's gone)."
  (let* ((project (agent-workflow-run-project run))
         (issue (agent-workflow-run-issue run))
         (default-directory project)
         (branch (agent-workflow--run-branch-made run))
         (into (agent-workflow-main-branch project)))
    (when branch
      (let ((empty nil)
            (head nil)
            (why (cond ((eq (plist-get (agent-workflow-run-workflow run) :branch) 'keep)
                        "its workflow keeps it (branch: keep)")
                       ((file-exists-p (expand-file-name ".git" (agent-workflow-worktree-directory project issue)))
                        "its worktree has changes not committed")
                       ((not (eql 0 (process-file "git" nil nil nil "merge-base" "--is-ancestor" branch into)))
                        (format "not merged into %s" into)))))
        (setq empty (agent-workflow--branch-empty-p run branch))
        (setq head (car (agent-workflow--git-lines "rev-parse" "--verify" "--quiet" (concat branch "^{commit}"))))
        (unless why
          (condition-case err
              ;; Merged into the main branch, checked: -D, as git's -d would
              ;; look at your checkout's branch instead.
              (agent-workflow--git "branch" "-D" branch)
            (error (setq why (error-message-string err)))))
        (setf (agent-workflow-run-branch-end run)
              (append (if why (list :branch branch :why why) (list :branch branch :deleted t :into into))
                      (and head (list :head head))
                      (and empty (list :empty t))))
        (if why
            (agent-workflow--journal run "branch-kept" :branch branch :why why :empty (if empty t :false))
          (agent-workflow--journal run "branch-deleted" :branch branch :into into :head head
                                   :empty (if empty t :false)))))))

;; ====== LIMITS ======
;; Under the pool's size: a workflow's concurrency, how many of the pool's
;; agents work on its runs at once (every project's); a job's, how many of it
;; run at once across its workflow's runs (merge: 1), scripts too.

(defun agent-workflow--working-for (workflow)
  "How many of the pool's agents work on runs of WORKFLOW (a name)."
  (seq-count (lambda (agent)
               (when-let* ((found (agent-workflow--agent-run agent)))
                 (equal (plist-get (agent-workflow-run-workflow (car found)) :name) workflow)))
             (seq-filter (lambda (agent) (buffer-live-p (agent-workflow-agent-buffer agent))) agent-workflow--agents)))

(defun agent-workflow--running-of (workflow job)
  "How many runs of WORKFLOW (a name) have their JOB running, or waiting
for you."
  (seq-count (lambda (run)
               (and (equal (plist-get (agent-workflow-run-workflow run) :name) workflow)
                    (memq (plist-get (agent-workflow--job run job) :status) '(running waiting))))
             agent-workflow--runs))

(defun agent-workflow--no-agent (run job)
  "Why an agent can't start now for JOB of RUN, a step past its first (a
later agent step, an on-fail agent), in words; nil if it can: the pool
full, or RUN's workflow at its concurrency (its agents at once)."
  (let* ((workflow (agent-workflow-run-workflow run))
         (name (plist-get workflow :name))
         (limit (plist-get workflow :concurrency)))
    (cond
     ((>= (agent-workflow-pool-used) agent-workflow-pool)
      (format "%s: waiting for an agent: %d of %d work" job (agent-workflow-pool-used) agent-workflow-pool))
     ((and limit (>= (agent-workflow--working-for name) limit))
      (format "%s: waiting: %s at its limit, %d of %d agents" job name (agent-workflow--working-for name) limit)))))

(defun agent-workflow--over-limit (run job)
  "Why JOB of RUN can't start for its limits, in words; nil if it can: its
job's concurrency reached, or (it needs an agent) its workflow's. An agent
started past its first step: `agent-workflow--no-agent'."
  (let* ((workflow (agent-workflow-run-workflow run))
         (name (plist-get workflow :name))
         (job-limit (plist-get (agent-workflow--job-spec run job) :concurrency))
         (limit (plist-get workflow :concurrency)))
    (cond
     ((and job-limit (>= (agent-workflow--running-of name job) job-limit))
      (format "%s at its limit, %d of %d" job (agent-workflow--running-of name job) job-limit))
     ((and limit (agent-workflow--needs-agent-p run job) (>= (agent-workflow--working-for name) limit))
      (format "%s at its limit, %d of %d agents" name (agent-workflow--working-for name) limit)))))

;; ====== YOU ======

;; The issues offered as the issue list draws them (config/beads/look.el, when
;; it's loaded): a status icon, a priority badge and a type icon before the id
;; and title, the labels as tags after. Several picked at once: separated by a
;; comma, else, a title having one (which would cut it in two: never a match,
;; RET only filling the prompt), by the first of ; | & no title has.
(defconst agent-workflow--separators '("," ";" "|" "&")
  "What may separate several issues picked: the first that's in no title.")

(defvar +my/beads--statuses)

(defun agent-workflow--separator (candidates)
  "`crm-separator' for CANDIDATES (strings): the first of
`agent-workflow--separators' none of them has."
  (let ((separator (or (seq-find (lambda (separator)
                                   (not (seq-some (lambda (candidate) (string-search separator candidate))
                                                  candidates)))
                                 agent-workflow--separators)
                       "‖")))
    (propertize (concat "[ \t]*" (regexp-quote separator) "[ \t]*")
                'separator separator
                'description (if (equal separator ",") "comma-separated list"
                               (format "list separated by %s" separator)))))

(defun agent-workflow--issue-affixes (issue statuses)
  "ISSUE's (PREFIX . SUFFIX) in the picker (see above), ISSUE as
`agent-workflow-open-issues' has it, STATUSES the open issues' (a table,
id -> status: those blocking it)."
  (let* ((info (or (nth 3 issue)
                   `((id . ,(nth 0 issue)) (title . ,(nth 1 issue)) (issue_type . ,(nth 2 issue)))))
         (looks (fboundp '+my/beads-format-status))
         (labels (alist-get 'labels info))
         (epic (and (equal (nth 2 issue) "epic") (propertize "  (epic: its issues)" 'face 'shadow))))
    (cons (if looks
              ;; The statuses' faces: beads.el's, in the theme's colours once
              ;; loaded (config/beads/theme.el); the list may not have been
              ;; opened yet.
              (let ((+my/beads--statuses statuses))
                (require 'beads-faces nil t)
                (concat (string-pad (+my/beads-format-status info) 2)
                        (+my/beads-format-priority info) " "
                        (+my/beads-format-type info) " "))
            "")
          (concat epic
                  (when labels
                    (concat "  " (mapconcat (lambda (label)
                                              (if looks (+my/beads--label-tag label)
                                                (propertize label 'face 'shadow)))
                                            labels " ")))))))

(defun agent-workflow--issues-table (candidates affixes)
  "A completion table of CANDIDATES (an alist) in bd's order, each with its
AFFIXES (a table, candidate -> (PREFIX . SUFFIX))."
  (lambda (string predicate action)
    (if (eq action 'metadata)
        `(metadata (display-sort-function . identity)
                   (cycle-sort-function . identity)
                   (affixation-function
                    . ,(lambda (names)
                         (mapcar (lambda (name)
                                   (let ((affix (gethash name affixes)))
                                     (list name (or (car affix) "") (or (cdr affix) ""))))
                                 names))))
      (complete-with-action action candidates string predicate))))

(defun agent-workflow--read-issues (project)
  "The issues you pick in PROJECT, several at once (an epic: its open
issues): their ids."
  (let* ((issues (agent-workflow-open-issues project))
         (width (seq-reduce (lambda (width issue) (max width (string-width (car issue)))) issues 0))
         (statuses (make-hash-table :test #'equal))
         (affixes (make-hash-table :test #'equal))
         (candidates (mapcar (lambda (issue)
                               (cons (concat (string-pad (nth 0 issue) width) "  " (nth 1 issue)) issue))
                             issues))
         (separator (agent-workflow--separator (mapcar #'car candidates))))
    (dolist (issue issues)
      (puthash (nth 0 issue) (or (alist-get 'status (nth 3 issue)) "open") statuses))
    (dolist (candidate candidates)
      (puthash (car candidate) (agent-workflow--issue-affixes (cdr candidate) statuses) affixes))
    ;; The prefixes as wide as the widest: the ids in a column (a type is a
    ;; word in a terminal, an icon in a graphic frame).
    (let ((widest (seq-max (cons 0 (mapcar (lambda (affix) (string-width (car affix)))
                                           (hash-table-values affixes))))))
      (maphash (lambda (name affix)
                 (puthash name (cons (concat (car affix) (make-string (- widest (string-width (car affix))) ?\s))
                                     (cdr affix))
                          affixes))
               affixes))
    (or (seq-mapcat (lambda (choice)
                      (let ((issue (cdr (assoc choice candidates))))
                        (if (equal (nth 2 issue) "epic")
                            (agent-workflow-epic-issues project (car issue))
                          (list (car issue)))))
                    ;; crm loaded first: its `crm-separator' bound as its own
                    ;; (crm isn't loaded as Emacs starts, config/emacs/libraries.el).
                    (progn (require 'crm)
                           (dlet ((crm-separator separator))
                             (completing-read-multiple "Run on: " (agent-workflow--issues-table candidates affixes)
                                                       nil t))))
        (user-error "No issue picked"))))

(defconst agent-workflow--picker-gap 2
  "The columns between two of the workflow picker's.")

(defun agent-workflow--fit-text (text width)
  "TEXT cut to WIDTH columns, … where cut."
  (if (<= (string-width text) width) text (truncate-string-to-width text width nil nil "…")))

(defun agent-workflow--workflow-group-title (origin)
  "The workflow picker's divider for workflows of ORIGIN."
  (pcase origin
    ('local (format "local · %s/workflows/" agent-workflow-local-directory))
    ('project (format "project · %s/workflows/" agent-workflow-directory))
    (_ "starters")))

(defun agent-workflow--workflow-rows (project info width)
  "The workflow picker's rows for the issue INFO of PROJECT, WIDTH columns
at most (`agent-workflow--rows'): every workflow taking a ticket, those
that fit it first in each group (its workflow:NAME label's, or those whose
for: has its type): ● fits, ○ doesn't, dimmed; the types each is for (its
label's, said)."
  (let* ((label (seq-find (lambda (label) (string-prefix-p "workflow:" label)) (plist-get info :labels)))
         (labelled (and label (string-remove-prefix "workflow:" label)))
         (type (plist-get info :type)))
    (agent-workflow--rows
     (seq-remove (lambda (workflow) (plist-get (cdr workflow) :ticketless))
                 (agent-workflow-workflows project))
     width
     (lambda (workflow)
       (if labelled
           (equal (car workflow) labelled)
         (and (member type (plist-get (cdr workflow) :for)) t)))
     (lambda (workflow)
       (cond ((and labelled (equal (car workflow) labelled)) (concat "its " label))
             ((plist-get (cdr workflow) :for)
              (concat "for " (string-join (plist-get (cdr workflow) :for) ", ")))
             (t ""))))))

(defun agent-workflow--rows (workflows width &optional fits for)
  "The rows of a workflow picker for WORKFLOWS ((NAME . SPEC)...), WIDTH
columns at most: ((NAME PREFIX SUFFIX ORIGIN FITS)...), grouped by where
they come from (yours, the project's, the starters), each a row of columns
as the agent workspace's role picker has them: a mark, its name, its
description, its jobs, FOR's text (a function of a workflow: the tickets
it's for). FITS (a function of a workflow): those it fits first in each
group, marked ● (FOR's text in green), the others ○, dimmed; nil: each
marked ▶, none dimmed. Columns that don't fit the width dropped from the
right (its jobs first), its description cut with …."
  (let* ((fits* (or fits #'always))
         (origins '(local project starter))
         (sorted (seq-mapcat (lambda (origin)
                               (let ((these (seq-filter (lambda (workflow)
                                                          (eq (or (plist-get (cdr workflow) :origin) 'starter) origin))
                                                        workflows)))
                                 (append (seq-filter fits* these) (seq-remove fits* these))))
                             origins))
         (cells (mapcar (lambda (workflow)
                          (let ((spec (cdr workflow)))
                            (list :name (car workflow)
                                  :fits (and (funcall fits* workflow) t)
                                  :description (or (plist-get spec :description) "")
                                  :jobs (mapconcat #'car (plist-get spec :jobs) " · ")
                                  :for (or (and for (funcall for workflow)) ""))))
                        sorted))
         (gap agent-workflow--picker-gap)
         (widest (lambda (key) (apply #'max 0 (mapcar (lambda (cell) (string-width (plist-get cell key))) cells))))
         (names (funcall widest :name))
         (shown (seq-filter (lambda (key) (> (funcall widest key) 0)) '(:for :jobs)))
         (cap (lambda (key) (if (eq key :jobs) 32 40)))
         (room (lambda (keys) (apply #'+ (mapcar (lambda (key) (+ gap (min (funcall cap key) (funcall widest key)))) keys))))
         (description-room (lambda (keys) (- width 2 names gap (funcall room keys)))))
    ;; Its jobs dropped first, then the types, while the description can't
    ;; have 20 columns.
    (while (and shown (< (funcall description-room shown) (min 20 (funcall widest :description))))
      (setq shown (remq (if (memq :jobs shown) :jobs :for) shown)))
    (let ((described (max 0 (min (funcall widest :description) (funcall description-room shown)))))
      (mapcar
       (lambda (cell)
         (let* ((fit (plist-get cell :fits))
                (pad (lambda (text w) (concat text (make-string (max 0 (- w (string-width text))) ?\s))))
                (parts (append (and (> described 3)
                                    (list (funcall pad (agent-workflow--fit-text (plist-get cell :description) described)
                                                   described)))
                               (mapcar (lambda (key)
                                         (let ((w (min (funcall cap key) (funcall widest key))))
                                           (funcall pad (agent-workflow--fit-text (plist-get cell key) w) w)))
                                       (reverse shown))))
                (suffix (string-trim-right
                         (concat (make-string (- names (string-width (plist-get cell :name))) ?\s)
                                 (mapconcat (lambda (part) (concat (make-string gap ?\s) part)) parts "")))))
           (cond ((not fits))
                 (fit
                  (when-let* ((at (and (memq :for shown) (string-search (plist-get cell :for) suffix))))
                    (add-face-text-property at (+ at (length (plist-get cell :for))) 'success t suffix)))
                 (t (add-face-text-property 0 (length suffix) 'shadow t suffix)))
           (list (plist-get cell :name)
                 (cond ((not fits) (propertize "▶ " 'face 'font-lock-keyword-face))
                       (fit (propertize "● " 'face 'success))
                       (t (propertize "○ " 'face 'shadow)))
                 suffix
                 (or (plist-get (cdr (assoc (plist-get cell :name) workflows)) :origin) 'starter)
                 fit)))
       cells))))

(defun agent-workflow--read-in-place (prompt names default)
  "One of NAMES read in the minibuffer with PROMPT (a match required),
DEFAULT selected where it is: vertico moves a default to the top, out of
its group, so there it's given none and DEFAULT is selected once vertico
has listed them. An empty answer is DEFAULT."
  (let* ((vertico (bound-and-true-p vertico-mode))
         (answer
          (minibuffer-with-setup-hook
              (lambda ()
                (when (and vertico default (fboundp 'vertico--goto))
                  (letrec ((select (lambda ()
                                     (remove-hook 'post-command-hook select t)
                                     (when-let* ((index (and (local-variable-p 'vertico--input)
                                                             (seq-position (bound-and-true-p vertico--candidates)
                                                                           default))))
                                       (vertico--goto index)
                                       (vertico--exhibit)))))
                    (add-hook 'post-command-hook select 90 t))))
            (completing-read prompt names nil t nil nil (unless vertico default)))))
    (if (string-empty-p answer) (or default answer) answer)))

(defun agent-workflow--read-from-rows (prompt rows &optional default)
  "A workflow read with PROMPT from ROWS (a function of a width: its rows,
`agent-workflow--rows'), each its row of columns, grouped, in their order,
DEFAULT selected where it is (default: the first): its name. An error if
there are none."
  (let* ((cache nil)
         (row-list (lambda ()
                     (let ((width (1- (window-body-width (or (active-minibuffer-window) (minibuffer-window))))))
                       (unless (eq (car cache) width)
                         (setq cache (cons width (funcall rows width))))
                       (cdr cache))))
         (names (mapcar #'car (funcall row-list)))
         (completion-extra-properties
          (list :affixation-function
                (lambda (candidates)
                  (let ((now (funcall row-list)))
                    (mapcar (lambda (name)
                              (if-let* ((row (assoc name now)))
                                  (list (if (nth 4 row) name (propertize name 'face 'shadow)) (nth 1 row) (nth 2 row))
                                (list name "" "")))
                            candidates)))
                :group-function
                (lambda (name transform)
                  (if transform
                      name
                    (when-let* ((row (assoc name (funcall row-list))))
                      (agent-workflow--workflow-group-title (nth 3 row)))))
                :display-sort-function #'identity
                :cycle-sort-function #'identity)))
    (unless names
      (user-error "No workflow to pick"))
    (agent-workflow--read-in-place prompt names (or default (car names)))))

(defun agent-workflow--read-workflow (project issue)
  "ISSUE's workflow in PROJECT, always asked: every workflow taking a ticket
\(yours, the project's, the starters), grouped, a row of columns each
\(`agent-workflow--workflow-rows'), those that fit it first, the first of
them selected."
  (let* ((info (agent-workflow-issue project issue))
         (rows (lambda (width) (agent-workflow--workflow-rows project info width)))
         (all (funcall rows 120)))
    (unless all
      (user-error "No workflow takes a ticket (M-x agent-workflow-run runs those that don't)"))
    (agent-workflow--read-from-rows
     (format "Workflow for %s (a %s%s): " issue (or (plist-get info :type) "task")
             (if-let* ((title (plist-get info :title))) (concat ": " (agent-workflow--fit-text title 40)) ""))
     rows
     (car (or (seq-find (lambda (row) (nth 4 row)) all) (car all))))))

(defun agent-workflow--started (started refused)
  "STARTED runs said to `agent-workflow-started-functions', and with those
REFUSED ((ID . WHY)...) in the echo area."
  (dolist (run started)
    (run-hook-with-args 'agent-workflow-started-functions run agent-workflow-from-shell))
  (message "%s" (string-join
                 (delq nil (list (and started (concat "Started: " (mapconcat #'agent-workflow-run-name started ", ")))
                                 (and refused (concat "refused: " (mapconcat (lambda (r) (format "%s (%s)" (car r) (cdr r)))
                                                                             refused "; ")))))
                 "; ")))

(defun agent-workflow--read-ticketless (project)
  "A workflow of PROJECT that runs without a ticket, picked from its rows
\(`agent-workflow--rows': its name, its description, its jobs), grouped by
where it comes from: its name."
  (let ((workflows (seq-filter (lambda (workflow) (plist-get (cdr workflow) :ticketless))
                               (agent-workflow-workflows project))))
    (unless workflows
      (user-error "No workflow of %s runs without a ticket (ticket: false); on a ticket: M-x agent-workflow-run-ticket"
                  (file-name-nondirectory (directory-file-name project))))
    (agent-workflow--read-from-rows "Run the workflow: "
                                    (lambda (width) (agent-workflow--rows workflows width)))))

(defun agent-workflow-run (workflow &optional project)
  "Start a run of WORKFLOW (a name) of PROJECT (default: the current
one's), on no ticket: a workflow that says ticket: false (see
`agent-workflow-start-workflow-run'). Interactively, picked among them.
Return (STARTED . REFUSED), as `agent-workflow-run-ticket' does. On a
ticket: \[agent-workflow-run-ticket]."
  (interactive (let ((project (or (agent-workflow-project) (user-error "Not in a git repository"))))
                 (list (agent-workflow--read-ticketless project) project)))
  (let ((project (or project (agent-workflow-project) (user-error "Not in a git repository")))
        started refused)
    (agent-workflow--ensure-restored project)
    (condition-case err
        (push (agent-workflow-start-workflow-run project workflow :by "you" :ask (called-interactively-p 'any))
              started)
      (user-error (push (cons workflow (error-message-string err)) refused)))
    (agent-workflow--started started refused)
    (cons started refused)))

(defun agent-workflow-run-ticket (issues &optional workflow project)
  "Start runs on ISSUES (ids) of PROJECT (default: the current one's), each
with WORKFLOW, else its own: those started and those refused, said.
Interactively, the issues picked, several at once (an epic: its open
issues), then each one's workflow, always asked: every workflow that takes
a ticket, yours, the project's and the starters, those that fit it first
\(those that run without a ticket left out: \[agent-workflow-run]). Return
\(STARTED . REFUSED): runs, and (ISSUE . WHY) each."
  (interactive (let ((project (or (agent-workflow-project) (user-error "Not in a git repository"))))
                 (list (agent-workflow--read-issues project) nil project)))
  (let* ((project (or project (agent-workflow-project) (user-error "Not in a git repository")))
         started refused)
    (agent-workflow--ensure-restored project)
    (dolist (issue issues)
      (condition-case err
          (push (agent-workflow-start-run project issue
                                          :workflow (or workflow
                                                        (and (called-interactively-p 'any)
                                                             (agent-workflow--read-workflow project issue)))
                                          :by "you" :ask (called-interactively-p 'any))
                started)
        (user-error (push (cons issue (error-message-string err)) refused))))
    (setq started (nreverse started) refused (nreverse refused))
    (agent-workflow--started started refused)
    (cons started refused)))
