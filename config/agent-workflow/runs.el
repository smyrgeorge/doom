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
(declare-function agent-workflow-cancel "agent-workflow/resume")
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
  branch-end)            ; its branch once it's done: (:branch B :deleted t :into MAIN) or (:branch B :why WHY)

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
    :why :tries :user-note :back)
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
\(`agent-workflow-back', a done run) brings it back."
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
        (agent-workflow--bd (agent-workflow-run-project run)
                            (list "close" (agent-workflow-run-issue run) "--reason"
                                  (format "Done in your checkout, on %s"
                                          (or (agent-workflow--checkout-branch (agent-workflow-run-project run))
                                              "a detached HEAD")))))
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
kept, saying why. Journaled, kept in RUN."
  (let* ((project (agent-workflow-run-project run))
         (issue (agent-workflow-run-issue run))
         (default-directory project)
         (branch (agent-workflow--run-branch-made run))
         (into (agent-workflow-main-branch project)))
    (when branch
      (let ((empty nil)
            (why (cond ((eq (plist-get (agent-workflow-run-workflow run) :branch) 'keep)
                        "its workflow keeps it (branch: keep)")
                       ((file-exists-p (expand-file-name ".git" (agent-workflow-worktree-directory project issue)))
                        "its worktree has changes not committed")
                       ((not (eql 0 (process-file "git" nil nil nil "merge-base" "--is-ancestor" branch into)))
                        (format "not merged into %s" into)))))
        (setq empty (agent-workflow--branch-empty-p run branch))
        (unless why
          (condition-case err
              ;; Merged into the main branch, checked: -D, as git's -d would
              ;; look at your checkout's branch instead.
              (agent-workflow--git "branch" "-D" branch)
            (error (setq why (error-message-string err)))))
        (setf (agent-workflow-run-branch-end run)
              (append (if why (list :branch branch :why why) (list :branch branch :deleted t :into into))
                      (and empty (list :empty t))))
        (if why
            (agent-workflow--journal run "branch-kept" :branch branch :why why :empty (if empty t :false))
          (agent-workflow--journal run "branch-deleted" :branch branch :into into :empty (if empty t :false)))))))

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
                           :job job :profile (plist-get step :agent)
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
         (when (memq (plist-get (agent-workflow--job run job) :status) '(running waiting))
           (if (plist-get (agent-workflow--job run job) :finished)
               (agent-workflow--step-finished run job)
             (agent-workflow--wait run job (format "%s: its agent's turn failed: %s" job
                                                   (or (map-elt (map-elt event :data) :message) "an error"))))))))
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
      (cond
       ;; A conflict its agent resolved: the run goes back to its first job
       ;; that edits, its checks and its review run again on it.
       ((and (plist-get state :resolving) (agent-workflow--first-editing run job))
        (agent-workflow--job-set run job :resolving nil :retry nil)
        ;; Its agent's rebase: the jobs' commits there anew (watch.el).
        (agent-workflow--rebased run)
        (agent-workflow-back run (agent-workflow--first-editing run job)
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

;; ====== WHERE ITS WORK IS ======
;; A run's work is on its issue's branch, in its worktree: where it started
;; (your checkout's branch and commit then: its base), what its merge goes
;; into (the main branch), its own commits, those of its base branch the
;; merge takes too (a branch other than the main one), what isn't
;; committed, the snapshots its reading jobs read. Read from git when asked,
;; again a few seconds after.

(defvar agent-workflow--where-cache (make-hash-table :test #'eq :weakness 'key)
  "Each run's `agent-workflow-run-where' and when it was read: (TIME . WHERE).")

(defconst agent-workflow--where-age 3
  "Seconds after which a run's `agent-workflow-run-where' is read again.")

(defun agent-workflow-run-where (run &optional fresh)
  "Where RUN's work is: a plist, :worktree its folder (nil, gone), :branch
its issue's (nil: none yet), :deleted non-nil once its run deleted it
\(merged), :empty non-nil if it got no commit since it started (known), :base where it started (:branch B :commit C;
nil: unknown), :into what its merge goes into, :own its commits, :with
its base branch's the merge takes too, :uncommitted the files changed and
not committed, :merged non-nil once it's merged, :files its files changed
since its base (`agent-workflow--where-files'), :commits its latest
\((SHORT SUBJECT)...), :snapshots its reading jobs' ((JOB DIR COMMIT)...). Read from git if it was more than
`agent-workflow--where-age' seconds ago, or FRESH; nil if git can't say."
  (let ((cached (gethash run agent-workflow--where-cache)))
    (if (and cached (not fresh) (< (- (float-time) (car cached)) agent-workflow--where-age))
        (cdr cached)
      (let ((where (ignore-errors (agent-workflow--where-read run))))
        (puthash run (cons (float-time) where) agent-workflow--where-cache)
        where))))

(defun agent-workflow--where-read (run)
  "Where RUN's work is, read from git (see `agent-workflow-run-where')."
  (if (agent-workflow-run-checkout-p run)
      (agent-workflow--where-checkout run)
    (agent-workflow--where-worktree run)))

(defun agent-workflow--where-checkout (run)
  "Where RUN's work is, in your checkout (runs-in: checkout): its branch,
where it started, its commits since, your changes not committed; :checkout
t, nothing merged or deleted."
  (let* ((project (file-name-as-directory (agent-workflow-run-project run)))
         (default-directory project)
         (branch (agent-workflow--checkout-branch project))
         (base (let ((base (agent-workflow-run-base run))) (and (plist-get base :commit) base)))
         (from (or (plist-get base :commit) "HEAD"))
         (own (string-to-number (or (car (agent-workflow--git-lines "rev-list" "--count" (concat from "..HEAD"))) "0"))))
    (list :checkout t
          :worktree project
          :branch (or branch "HEAD")
          :deleted nil
          :empty (and base (zerop own))
          :base base
          :into branch
          :own own
          :with 0
          :uncommitted (length (agent-workflow--git-lines "status" "--porcelain"))
          :merged nil
          :files (agent-workflow--where-files project from)
          :commits (agent-workflow--where-commits project from "HEAD")
          :snapshots (delq nil (mapcar (lambda (job)
                                         (when-let* (((memq (plist-get (cdr job) :status) '(running waiting)))
                                                     (snapshot (plist-get (cdr job) :snapshot))
                                                     ((file-directory-p (nth 0 snapshot))))
                                           (list (car job) (nth 0 snapshot) (nth 2 snapshot))))
                                       (agent-workflow-run-jobs run))))))

(defun agent-workflow--where-worktree (run)
  "Where RUN's work is, on its own branch (`agent-workflow--where-read')."
  (let* ((project (agent-workflow-run-project run))
         (issue (agent-workflow-run-issue run))
         (default-directory project)
         (dir (agent-workflow-worktree-directory project issue))
         (live (file-exists-p (expand-file-name ".git" dir)))
         (made (or (and live (let ((default-directory dir))
                               (car (agent-workflow--git-lines "branch" "--show-current"))))
                   (agent-workflow--run-branch-made run)))
         (end (agent-workflow-run-branch-end run))
         (deleted (and (not made) (plist-get end :deleted) (plist-get end :branch)))
         (branch (or made deleted))
         (base (let ((base (agent-workflow-run-base run))) (and (plist-get base :commit) base)))
         (into (agent-workflow-main-branch project))
         (count (lambda (range)
                  (string-to-number (or (car (agent-workflow--git-lines "rev-list" "--count" range)) "0"))))
         (own (if made (funcall count (concat (or (plist-get base :commit) into) ".." made)) 0)))
    (list :worktree (and live dir)
          :branch branch
          :deleted (and deleted t)
          ;; No commit since it started (where it started known).
          :empty (if deleted (plist-get end :empty) (and made base (zerop own)))
          :base base
          :into into
          :own own
          :with (if (and base (not (equal (plist-get base :branch) into)))
                    (funcall count (concat into ".." (plist-get base :commit)))
                  0)
          :uncommitted (if live (let ((default-directory dir)) (length (agent-workflow--git-lines "status" "--porcelain")))
                         0)
          :merged (or (and made (> own 0)
                           (eql 0 (process-file "git" nil nil nil "merge-base" "--is-ancestor" made into)))
                      deleted
                      ;; Its own commits unknown (where it started is), its
                      ;; merge done.
                      (seq-some (lambda (job)
                                  (and (eq (plist-get (cdr job) :status) 'done)
                                       (seq-some (lambda (step) (equal (plist-get step :uses) "merge"))
                                                 (plist-get (agent-workflow--job-spec run (car job)) :steps))))
                                (agent-workflow-run-jobs run)))
          :files (and live (agent-workflow--where-files dir (or (plist-get base :commit) into)))
          :commits (and made (agent-workflow--where-commits (if live dir project)
                                                            (or (plist-get base :commit) into) made))
          :snapshots (delq nil (mapcar (lambda (job)
                                         (when-let* (((memq (plist-get (cdr job) :status) '(running waiting)))
                                                     (snapshot (plist-get (cdr job) :snapshot))
                                                     ((file-directory-p (nth 0 snapshot))))
                                           (list (car job) (nth 0 snapshot) (nth 2 snapshot))))
                                       (agent-workflow-run-jobs run))))))

(defconst agent-workflow--where-commits-shown 5
  "A run's latest commits its where has, at most.")

(defun agent-workflow--where-files (dir base)
  "The files changed in the worktree DIR since BASE (a commit, a branch),
committed or not: ((:path P :status added|changed|deleted :added N
:removed N :uncommitted BOOL)...), in their order; a file new and not
tracked yet, added."
  (let* ((default-directory dir)
         (stats (mapcar (lambda (line) (split-string line "\t"))
                        (agent-workflow--git-lines "diff" "--numstat" "--no-renames" base)))
         (statuses (mapcar (lambda (line) (split-string line "\t"))
                           (agent-workflow--git-lines "diff" "--name-status" "--no-renames" base)))
         (untracked (agent-workflow--git-lines "ls-files" "--others" "--exclude-standard"))
         (uncommitted (append (agent-workflow--git-lines "diff" "--name-only" "HEAD") untracked))
         (count (lambda (text) (and text (string-match-p "\\`[0-9]+\\'" text) (string-to-number text)))))
    (append
     (mapcar (lambda (status)
               (let* ((path (nth 1 status))
                      (stat (seq-find (lambda (stat) (equal (nth 2 stat) path)) stats)))
                 (list :path path
                       :status (pcase (car status) ("A" 'added) ("D" 'deleted) (_ 'changed))
                       :added (funcall count (nth 0 stat))
                       :removed (funcall count (nth 1 stat))
                       :uncommitted (and (member path uncommitted) t))))
             statuses)
     (mapcar (lambda (path) (list :path path :status 'added :uncommitted t)) untracked))))

(defun agent-workflow--where-stamp (run)
  "What changes as RUN's place is worked on, read without git: the times
of its git folder's HEAD, index and HEAD's log (a commit, a reset, a
checkout, a file staged), nil if it has none. Equal twice: nothing
committed or staged there in between."
  (let* ((dir (if (agent-workflow-run-checkout-p run)
                  (agent-workflow-run-project run)
                (agent-workflow-worktree-directory (agent-workflow-run-project run) (agent-workflow-run-issue run))))
         (dot (expand-file-name ".git" dir))
         (git (cond ((file-directory-p dot) dot)
                    ((file-readable-p dot)
                     (with-temp-buffer
                       (insert-file-contents dot)
                       (and (re-search-forward "^gitdir: *\\(.+\\)$" nil t)
                            (expand-file-name (match-string 1) dir)))))))
    (when git
      (mapcar (lambda (name) (file-attribute-modification-time (file-attributes (expand-file-name name git))))
              '("HEAD" "index" "logs/HEAD")))))

(defun agent-workflow--where-commits (dir base branch)
  "BRANCH's commits since BASE, read in DIR, the latest first: ((SHORT
SUBJECT)...), `agent-workflow--where-commits-shown' at most."
  (let ((default-directory dir))
    (mapcar (lambda (line) (split-string line "\t"))
            (agent-workflow--git-lines "log" (format "--max-count=%d" agent-workflow--where-commits-shown)
                                       "--format=%h%x09%s" (concat base ".." branch)))))

;; ====== ITS AGENT ASKS ======
;; An agent asking you in its session (agent-shell's permission-request: a
;; tool its profile doesn't allow without asking; its elicitation-request: a
;; question, AskUserQuestion's form) holds its turn until you answer: its
;; job waits for you, saying what it asks, as any wait does (the run's
;; state, status, its pane's Needs you, a notification). Answered, wherever
;; (its session, its pane), the job runs again. Its turn ending, or its
;; session, nothing it asked waits any more.

(defun agent-workflow-agent-asking (run)
  "RUN's job whose agent asks you in its session, and what: (JOB . ASKS),
ASKS (:kind permission|question :what WORDS :why WHY [:request ID]), or nil."
  (seq-some (lambda (job)
              (let* ((state (cdr job))
                     (asks (plist-get state :agent-asks)))
                (and asks (eq (plist-get state :status) 'waiting)
                     (equal (plist-get asks :why) (plist-get state :why))
                     (cons (car job) asks))))
            (agent-workflow-run-jobs run)))

(defun agent-workflow--agent-asks (agent kind what &optional request)
  "AGENT asks you KIND (permission, question) of WHAT (its tool call's
title, the question; nil), REQUEST its question's id (its form in its
session: answered in its pane): its job, running, waits for you."
  (when-let* ((found (agent-workflow--agent-run agent)))
    (pcase-let ((`(,run . ,job) found))
      (when (eq (plist-get (agent-workflow--job run job) :status) 'running)
        (let* ((what (and (stringp what)
                          (let ((line (string-trim (car (split-string (string-trim what) "\n")))))
                            (and (not (string-empty-p line)) line))))
               (why (format "%s: its agent asks %s%s" job
                            (if (eq kind 'permission) "for your permission" "you")
                            (if what (concat ": " what) ""))))
          (agent-workflow--job-set run job :agent-asks (append (list :kind kind :what what :why why)
                                                               (and request (list :request request))))
          (agent-workflow--journal run "asked" :job job :kind "agent" :what what)
          (agent-workflow--wait run job why))))))

(defun agent-workflow--agent-answered (agent)
  "What AGENT asked answered, in its session or its pane: its job runs
again."
  (when-let* ((found (agent-workflow--agent-run agent))
              ((agent-workflow--agent-asks-over agent)))
    (pcase-let ((`(,run . ,job) found))
      (agent-workflow--journal run "answered" :job job :choice "answered its agent" :by "you")
      (agent-workflow--refresh run))))

(defun agent-workflow--agent-asks-over (agent)
  "Nothing AGENT asked waits any more: its job, waiting for it, running
again (its run's state not worked out again). Its run if it asked."
  (when-let* ((found (agent-workflow--agent-run agent)))
    (pcase-let* ((`(,run . ,job) found)
                 (state (agent-workflow--job run job))
                 (asks (plist-get state :agent-asks)))
      (when asks
        (agent-workflow--job-set run job :agent-asks nil)
        (when (and (eq (plist-get state :status) 'waiting)
                   (equal (plist-get state :why) (plist-get asks :why)))
          (agent-workflow--job-set run job :status 'running :why nil))
        run))))

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
         (default-directory (agent-workflow--work-directory run)))
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
    (when (memq (agent-workflow-run-state run) '(cancelled failed))
      (user-error "%s %s" (agent-workflow-run-name run)
                  (if (eq (agent-workflow-run-state run) 'failed) "failed" "was cancelled")))
    (when (and discard (agent-workflow-run-checkout-p run))
      (agent-workflow--refuse "%s works in your checkout: its work isn't discarded there (git reset it yourself)"
                              (agent-workflow-run-name run)))
    (let ((session (or (plist-get state :session)
                       (when-let* ((agent (plist-get state :agent))) (agent-workflow-agent-session agent))))
          (lost (and discard (agent-workflow-back-lost run job))))
      ;; Each job replaced: its agent stopped, its snapshot gone, pending again.
      (dolist (other replaced)
        (let ((other-state (agent-workflow--job run other)))
          (unless (memq (plist-get other-state :status) '(pending skipped))
            (when-let* ((agent (plist-get other-state :agent)))
              (agent-workflow-stop-agent agent))
            (when-let* ((process (plist-get other-state :process)))
              (when (process-live-p process)
                (process-put process 'agent-workflow-stopped t)
                (delete-process process)))
            (when (plist-get other-state :snapshot)
              (agent-workflow-snapshot-remove project issue other))
            (agent-workflow--job-set run other :status 'pending :agent nil :finished nil :why nil :pool nil
                                     :outcome nil :notes nil :snapshot nil :process nil :retry nil
                                     :resolving nil :tries nil :ask nil :back nil
                                     :round (1+ (or (plist-get other-state :round) 1))))))
      (agent-workflow--job-set run job :back (list :step step :note note :by by :session session))
      (when discard
        (let ((default-directory (agent-workflow--work-directory run))
              (commit (plist-get state :start-commit)))
          (unless commit (agent-workflow--refuse "%s: the commit it started from isn't known" job))
          (agent-workflow--git "reset" "--hard" commit)
          (agent-workflow--git "clean" "-fd")
          ;; Commits lost as you chose: not missed later (watch.el).
          (dolist (other (agent-workflow-run-jobs run))
            (agent-workflow--job-set run (car other) :end-commit nil))))
      (agent-workflow--journal run "went-back" :job job :step step :note note :by by
                               :replaced (vconcat replaced) :discarded (if discard t :false)
                               :lost (and lost (vconcat (append (car lost) (cdr lost)))))
      (agent-workflow--run-bd-write run "--append-notes"
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
  (let ((runs (seq-remove (lambda (run) (memq (agent-workflow-run-state run) '(cancelled failed)))
                          (agent-workflow-runs-of project))))
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

;; ====== APPROVAL ======
;; A step with approve: true (a job's: its last step) waits, once it's
;; done, for your OK: the run says so, with what to look at (its outcome and
;; notes, what the branch got since the job started, a script's output), and
;; you're told. Approved, the run goes on. Rejected with a note: an agent
;; step goes back to its agent (in its session, or resumed), then waits for
;; you again; a script's stops the run for you (run it again, skip it, stop).

(defun agent-workflow--needs-approval-p (run job)
  "Non-nil if JOB of RUN's step just done waits for your OK, not given yet."
  (let* ((state (agent-workflow--job run job))
         (index (plist-get state :step))
         (steps (plist-get (agent-workflow--job-spec run job) :steps)))
    (and (or (plist-get (nth index steps) :approve)
             (and (= index (1- (length steps))) (plist-get (agent-workflow--job-spec run job) :approve)))
         (not (eql (plist-get state :approved) index)))))

(defun agent-workflow-to-look-at (run job)
  "What to look at of JOB of RUN's result: a plist (:outcome :notes :diff
:log), :diff what the branch got since the job started (its stat), :log its
last script's output's file."
  (let* ((state (agent-workflow--job run job))
         (start (plist-get state :start-commit))
         (dir (plist-get state :dir))
         (logs (and (file-directory-p (expand-file-name "logs" (agent-workflow-run-dir run)))
                    (directory-files (expand-file-name "logs" (agent-workflow-run-dir run)) t
                                     (concat "\\`" (regexp-quote job) "\\.")))))
    (list :outcome (plist-get state :outcome) :notes (plist-get state :notes)
          :diff (and start dir (file-directory-p dir)
                     (let ((default-directory dir))
                       (string-join (agent-workflow--git-lines "diff" "--stat" start) "\n")))
          :log (car (last logs)))))

(defun agent-workflow--ask-approval (run job)
  "JOB of RUN's result waits for your OK."
  (let ((index (plist-get (agent-workflow--job run job) :step))
        (look (agent-workflow-to-look-at run job)))
    (agent-workflow--job-set run job :ask (list :kind 'approve :step index))
    (agent-workflow--journal run "asked" :job job :step index :kind "approve"
                             :outcome (plist-get look :outcome) :notes (plist-get look :notes)
                             :diff (plist-get look :diff) :log (plist-get look :log))
    (agent-workflow--wait run job (format "%s: its result waits for your OK: approve it, or reject it with a note" job))))

(defun agent-workflow--approval-asked (run)
  "RUN's job whose result waits for your OK, and its question: (JOB . ASK),
or a user error."
  (agent-workflow--refuse-ended run)
  (let ((asking (agent-workflow-asking run)))
    (unless (eq (plist-get (cdr asking) :kind) 'approve)
      (user-error "%s waits for no approval" (agent-workflow-run-name run)))
    asking))

(cl-defun agent-workflow-approve (run &key (by "you"))
  "Approve the result RUN waits for your OK on: the run goes on."
  (pcase-let ((`(,job . ,ask) (agent-workflow--approval-asked run)))
    (agent-workflow--journal run "answered" :job job :choice "approve" :by by)
    (agent-workflow--job-set run job :ask nil :status 'running :why nil :approved (plist-get ask :step) :finished t)
    (agent-workflow--refresh run)
    (agent-workflow--step-finished run job)
    job))

(cl-defun agent-workflow-reject (run note &key (by "you"))
  "Reject the result RUN waits for your OK on, with NOTE: an agent step's
back to its agent (its session, or resumed), asked again once it's done; a
script's stops the run."
  (pcase-let* ((`(,job . ,ask) (agent-workflow--approval-asked run))
               (index (plist-get ask :step))
               (step (nth index (plist-get (agent-workflow--job-spec run job) :steps)))
               (agent (plist-get (agent-workflow--job run job) :agent)))
    (agent-workflow--journal run "answered" :job job :choice "reject" :note note :by by)
    (agent-workflow--run-bd-write run "--append-notes" (format "%s's result rejected by %s: %s" job by note))
    (cond
     ((not (eq (plist-get step :kind) 'agent))
      (agent-workflow--job-set run job :ask (list :kind 'broke :step index :what "its result rejected"))
      (agent-workflow--wait run job (format "%s: its result rejected by you (%s): run it again, skip it, or stop?"
                                            job note)))
     ((and agent (buffer-live-p (agent-workflow-agent-buffer agent)))
      (agent-workflow--job-set run job :ask nil :status 'running :why nil :finished nil :approved nil)
      (agent-workflow--refresh run)
      (agent-workflow-send agent (format "The user rejected your result: %s\n\nChange it, then say done again."
                                         note)))
     (t
      (agent-workflow--job-set run job :ask nil :approved nil)
      (agent-workflow-back run job :step index :note (concat "Your result was rejected: " note) :by by)))
    job))

(defun agent-workflow--read-approval (prompt)
  "A run of the current project waiting for your OK, picked with PROMPT
\(the only one, not asked)."
  (let* ((project (or (agent-workflow-project) (user-error "Not in a git repository")))
         (asking (or (seq-filter (lambda (run) (eq (plist-get (cdr (agent-workflow-asking run)) :kind) 'approve))
                                 (agent-workflow-runs-of project))
                     (user-error "No run waits for your OK"))))
    (if (cdr asking)
        (let ((names (mapcar (lambda (run) (cons (agent-workflow-run-why run) run)) asking)))
          (cdr (assoc (completing-read prompt names nil t) names)))
      (car asking))))

(defun agent-workflow-approve-command (run)
  "Approve the result RUN waits for your OK on (M-x agent-workflow-approve)."
  (interactive (list (agent-workflow--read-approval "Approve: ")))
  (message "%s: %s approved" (agent-workflow-run-name run) (agent-workflow-approve run)))

(defun agent-workflow-reject-command (run note)
  "Reject the result RUN waits for your OK on, with NOTE (M-x
agent-workflow-reject)."
  (interactive (let ((run (agent-workflow--read-approval "Reject: ")))
                 (list run (read-string "Why (the agent's told): "))))
  (message "%s: %s rejected" (agent-workflow-run-name run) (agent-workflow-reject run note)))

;; ====== LOOPS ======
;; An agent's outcome can send the work back: review's changes: rerun build,
;; going back to build (as you do, its notes the note), build and every job
;; after it again. Going back makes cycles, so each back edge's rounds are
;; counted (review>build), and the run's total: past `max-rounds' (the
;; job's, else its workflow's, else `agent-workflow-max-rounds': 10), or
;; past 3 times that in all, or at once when the round sent back changed
;; nothing on the branch (no commit, no change not committed), the run asks
;; you instead. You go on (the count starts again), with a note for the job
;; that sends it back, the one it's sent to, or both; accept it as it is
;; (the run goes on as if it had said continue); or stop it (it waits).
;; Your going back counts for nothing.

(defvar agent-workflow-max-rounds)

(defun agent-workflow--max-rounds (run job)
  "How many times JOB of RUN may send the work back before it asks you."
  (or (plist-get (agent-workflow--job-spec run job) :max-rounds)
      (plist-get (agent-workflow-run-workflow run) :max-rounds)
      agent-workflow-max-rounds))

(defun agent-workflow--changed-nothing-p (run job)
  "Non-nil if JOB of RUN ran again (a round more than its first) and
changed nothing on the branch: no commit since its round started, no
change not committed."
  (let ((state (agent-workflow--job run job)))
    (and (> (or (plist-get state :round) 1) 1)
         (plist-get state :start-commit)
         (let ((default-directory (agent-workflow--work-directory run)))
           (and (file-directory-p default-directory)
                (equal (agent-workflow--git "rev-parse" "HEAD") (plist-get state :start-commit))
                (null (agent-workflow--git-lines "status" "--porcelain")))))))

(defun agent-workflow--rerun-or-ask (run job other)
  "JOB of RUN sends the work back to OTHER (its outcome's rerun): counted,
then done, or asked of you (see LOOPS)."
  (let* ((state (agent-workflow--job run job))
         (edge (format "%s>%s" job other))
         (entry (cdr (assoc edge (agent-workflow-run-edges run))))
         (count (1+ (or (plist-get entry :count) 0)))
         (notes (append (plist-get entry :notes) (list (or (plist-get state :notes) ""))))
         (max (agent-workflow--max-rounds run job))
         (total (1+ (agent-workflow-run-total run)))
         (nothing (agent-workflow--changed-nothing-p run other)))
    (setf (alist-get edge (agent-workflow-run-edges run) nil nil #'equal) (list :count count :notes notes)
          (agent-workflow-run-total run) total)
    (if (or nothing (> count max) (> total (* 3 max)))
        (let ((why (cond (nothing (format "%s: %s's round %d changed nothing on the branch: go on, accept it as it is, or stop?"
                                          job other (or (plist-get (agent-workflow--job run other) :round) 1)))
                         ((> count max) (format "%s: it sent %s back %d times: go on, accept it as it is, or stop?"
                                                job other (1- count)))
                         (t (format "%s: the run was sent back %d times: go on, accept it as it is, or stop?"
                                    job (1- total))))))
          (when-let* ((agent (plist-get state :agent)))
            (agent-workflow-stop-agent agent))
          (agent-workflow--job-set run job :agent nil
                                   :ask (list :edge edge :other other :count (1- count) :notes notes :nothing nothing))
          (agent-workflow--journal run "asked" :job job :edge edge :rounds (1- count) :total (1- total)
                                   :nothing (if nothing t :false) :notes (vconcat notes))
          (agent-workflow--wait run job why))
      (agent-workflow--journal run "rerun" :job job :edge edge :round count :total total)
      (agent-workflow--rerun run job other (plist-get state :notes)))))

(defun agent-workflow--rerun (run job other note &optional yours)
  "OTHER of RUN run again, sent back by JOB with NOTE (and YOURS, your note
for it): going back, the work kept. JOB, if it isn't after OTHER, done."
  (let ((replaced (agent-workflow-back run other :note (if (and yours (not (string-empty-p yours)))
                                                         (format "%s\n\nThe user adds: %s" (or note "") yours)
                                                       note)
                                       :by job)))
    (unless (member job replaced)
      (when-let* ((agent (plist-get (agent-workflow--job run job) :agent)))
        (agent-workflow-stop-agent agent))
      (agent-workflow--job-set run job :status 'done :agent nil :why nil)
      (agent-workflow--journal run "job-done" :job job :outcome (plist-get (agent-workflow--job run job) :outcome))
      (agent-workflow--refresh run)
      (agent-workflow--tick-soon))))

(defun agent-workflow-asking (run)
  "RUN's job asking you (see LOOPS), and what it asks: (JOB . ASK), or nil;
nil once RUN is over (a question left from before its cancel)."
  (unless (memq (agent-workflow-run-state run) agent-workflow--ended)
    (seq-some (lambda (job) (and (plist-get (cdr job) :ask) (cons (car job) (plist-get (cdr job) :ask))))
              (agent-workflow-run-jobs run))))

(defun agent-workflow--refuse-ended (run)
  "A user error if RUN is over: nothing of it is answered."
  (when (memq (agent-workflow-run-state run) agent-workflow--ended)
    (user-error "%s is over (%s): it asks nothing" (agent-workflow-run-name run) (agent-workflow-run-state run))))

(cl-defun agent-workflow-confirm (run choice &key notes more (by "you"))
  "Answer RUN's question with CHOICE. A loop's (see LOOPS): go (on: the
count starts again; NOTES, ((JOB . NOTE)...), for the job that sends it
back and the one it's sent to), accept (it as it is: the run goes on as if
continue), or stop (it waits). A step's whose retries are used up: go (its
tries start again, the agent fixing it told NOTES' note for its job),
skip, stop; a step that broke: go (run it again), skip, stop; a merge
waiting: go (try it again), stop (steps.el); its budget used up: go (MORE,
\(:cost :tokens :time) added to it, its steps continued), stop (budget.el).
A user error if RUN asks nothing (over, it never does), or CHOICE isn't
one of its question's."
  (agent-workflow--refuse-ended run)
  (pcase-let* ((`(,job . ,ask) (or (agent-workflow-asking run)
                                   (when-let* ((agent (agent-workflow-agent-asking run)))
                                     (user-error "%s: %s's agent asks you in its session: answer it there, or in \
the run's pane" (agent-workflow-run-name run) (car agent)))
                                   (user-error "%s asks nothing" (agent-workflow-run-name run))))
               (other (plist-get ask :other))
               (edge (plist-get ask :edge))
               (kind (plist-get ask :kind))
               (allowed (pcase kind ('nil '("go" "accept" "stop")) ((or 'merge 'budget 'moved 'protected) '("go" "stop"))
                          ('closed '("go" "cancel")) ('approve nil)
                          (_ '("go" "skip" "stop")))))
    (when (eq kind 'approve)
      (user-error "%s waits for your OK: approve it, or reject it" (agent-workflow-run-name run)))
    (unless (member choice allowed)
      (user-error "%s: %s, not %s" (agent-workflow-run-name run) (string-join allowed ", ") choice))
    (agent-workflow--journal run "answered" :job job :choice choice :by by
                             :notes (if notes
                                        (vconcat (mapcar (lambda (note) (list :job (car note) :note (cdr note))) notes))
                                      []))
    (when (and kind (not (equal choice "stop")))
      (agent-workflow--job-set run job :ask nil :status 'running :why nil)
      (agent-workflow--refresh run))
    (pcase (and kind choice)
      ('nil)
      ("go"
       (let ((index (plist-get ask :step)))
         (if (eq kind 'retries)
             (let ((tries (plist-get (agent-workflow--job run job) :tries))
                   (mine (cdr (assoc job notes))))
               (setf (alist-get index tries) 0)
               (agent-workflow--job-set run job :tries tries)
               (agent-workflow--fix run job index
                                    (concat (plist-get ask :output)
                                            (if (and mine (not (string-empty-p mine))) (concat "\n\nThe user adds: " mine) ""))
                                    (plist-get ask :what)))
           (if (memq kind '(interrupted budget closed moved))
               (progn
                 (when (eq kind 'budget)
                   (agent-workflow--budget-more run more))
                 (when (eq kind 'closed)
                   (agent-workflow--run-bd-write run "--status" "in_progress"))
                 (when (eq kind 'moved)
                   (dolist (other (agent-workflow-run-jobs run))
                     (agent-workflow--job-set run (car other) :end-commit nil)))
                 (dolist (other (agent-workflow-run-jobs run))
                   (when (and (not (equal (car other) job))
                              (eq (plist-get (plist-get (cdr other) :ask) :kind) kind))
                     (agent-workflow--go-on run (car other) by)))
                 (agent-workflow--job-set run job :ask ask)
                 (agent-workflow--go-on run job by))
             (when (eq kind 'protected)
               (agent-workflow--job-set run job :protected-ok t))
             (agent-workflow--step-start run job index)))))
      ("cancel" (agent-workflow-cancel run :by by))
      ("skip"
       (agent-workflow--journal run "step-skipped" :job job :step (plist-get ask :step))
       ;; Skipped, it needs no OK of yours.
       (agent-workflow--job-set run job :approved (plist-get ask :step))
       (agent-workflow-step-ended run job))
      ("stop"
       (agent-workflow--job-set run job :why (format "%s: stopped by you" job))
       (agent-workflow--refresh run)))
    (pcase (and (not kind) choice)
      ("go"
       (setf (alist-get edge (agent-workflow-run-edges run) nil nil #'equal) nil
             (agent-workflow-run-total run) 0)
       (agent-workflow--job-set run job :ask nil :status 'running :why nil)
       (when-let* ((mine (cdr (assoc job notes))))
         (unless (string-empty-p mine)
           (agent-workflow--job-set run job :user-note mine)))
       (agent-workflow--rerun run job other (plist-get (agent-workflow--job run job) :notes) (cdr (assoc other notes))))
      ("accept"
       (agent-workflow--job-set run job :ask nil :status 'done :why nil)
       (agent-workflow--journal run "job-done" :job job :outcome (plist-get (agent-workflow--job run job) :outcome)
                                :accepted t)
       (agent-workflow--refresh run)
       (agent-workflow--issue-summary run)
       (agent-workflow--changed run)
       (agent-workflow--tick-soon))
      ("stop"
       (agent-workflow--job-set run job :why (format "%s: stopped by you" job))
       (agent-workflow--refresh run)))
    choice))

(defun agent-workflow--go-on (run job by)
  "JOB of RUN, stopped for a question you answered go: continued; one held
before it started, pending again, started as the run goes."
  (if (plist-get (agent-workflow--job run job) :held)
      (progn
        (agent-workflow--job-set run job :held nil :ask nil :status 'pending :why nil)
        (agent-workflow--refresh run)
        (agent-workflow--tick-soon))
    (agent-workflow--continue-job run job by)))

(defun agent-workflow-confirm-command (run choice &optional notes more)
  "Answer RUN's question (M-x agent-workflow-confirm): CHOICE, as the
question allows (go, accept, skip, stop); going on, your notes (empty:
none): for the job that sends it back and the one it's sent to, or for
the agent that fixes a step."
  (interactive
   (let* ((project (or (agent-workflow-project) (user-error "Not in a git repository")))
          (asking (or (seq-filter #'agent-workflow-asking (agent-workflow-runs-of project))
                      (user-error "No run asks you anything")))
          (run (if (cdr asking)
                   (let ((names (mapcar (lambda (run) (cons (agent-workflow-run-name run) run)) asking)))
                     (cdr (assoc (completing-read "Run: " names nil t) names)))
                 (car asking)))
          (ask (agent-workflow-asking run))
          (kind (plist-get (cdr ask) :kind))
          (choice (completing-read (format "%s: " (agent-workflow-run-why run))
                                   (pcase kind ('nil '("go" "accept" "stop")) ((or 'merge 'budget 'moved 'protected) '("go" "stop"))
                                     ('closed '("go" "cancel")) (_ '("go" "skip" "stop")))
                                   nil t))
          (notes (when (equal choice "go")
                   (pcase kind
                     ('nil
                      (delq nil (list (let ((note (read-string (format "Your note for %s (it sends it back): " (car ask)))))
                                        (and (not (string-empty-p note)) (cons (car ask) note)))
                                      (let* ((other (plist-get (cdr ask) :other))
                                             (note (read-string (format "Your note for %s (it's sent back): " other))))
                                        (and (not (string-empty-p note)) (cons other note))))))
                     ('retries
                      (let ((note (read-string "Your note for the agent that fixes it: ")))
                        (and (not (string-empty-p note)) (list (cons (car ask) note))))))))
          (more (when (and (equal choice "go") (eq kind 'budget))
                  (list :cost (let ((n (read-string "Add to its budget, dollars (empty: none): ")))
                                (and (not (string-empty-p n)) (string-to-number n)))
                        :tokens (let ((n (read-string "Tokens (empty: none): ")))
                                  (and (not (string-empty-p n)) (string-to-number n)))
                        :time (let ((n (read-string "Time, as 45m or 1h (empty: none): ")))
                                (and (not (string-empty-p n)) (agent-workflow--duration n)))))))
     (list run choice notes more)))
  (agent-workflow-confirm run choice :notes notes :more more)
  (message "%s: %s" (agent-workflow-run-name run) choice))

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
         (crm-separator (agent-workflow--separator (mapcar #'car candidates))))
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
                    (completing-read-multiple "Run on: " (agent-workflow--issues-table candidates affixes)
                                              nil t))
        (user-error "No issue picked"))))

(defun agent-workflow--read-workflow (project issue)
  "ISSUE's workflow in PROJECT: the one that fits it, asked only when
several do (or none: all of them)."
  (let* ((info (agent-workflow-issue project issue))
         (fitting (ignore-errors (agent-workflow--fitting project info))))
    (if (and fitting (null (cdr fitting)))
        (car fitting)
      (completing-read (format "Workflow for %s (a %s): " issue (plist-get info :type))
                       (or fitting (mapcar #'car (seq-remove (lambda (workflow) (plist-get (cdr workflow) :ticketless))
                                                             (agent-workflow-workflows project))))
                       nil t))))

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
  "A workflow of PROJECT that runs without a ticket, picked (its
description beside it): its name."
  (let* ((workflows (seq-filter (lambda (workflow) (plist-get (cdr workflow) :ticketless))
                                (agent-workflow-workflows project)))
         (completion-extra-properties
          (list :annotation-function
                (lambda (name)
                  (when-let* ((description (plist-get (cdr (assoc name workflows)) :description)))
                    (concat (propertize " " 'display '(space :align-to 24))
                            (propertize description 'face 'completions-annotations)))))))
    (unless workflows
      (user-error "No workflow of %s runs without a ticket (ticket: false); on a ticket: M-x agent-workflow-run-ticket"
                  (file-name-nondirectory (directory-file-name project))))
    (completing-read "Run the workflow: " (mapcar #'car workflows) nil t)))

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
issues), then each one's workflow, asked only when several fit (those that
run without a ticket left out: \[agent-workflow-run]). Return
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
