;;; $DOOMDIR/config/agent-workflow/resume.el -*- lexical-binding: t; -*-
;; A run that stopped goes on from where it was. Loaded from
;; config/agent-workflow.el, after steps.el. No Doom here.
;;
;; A run's state.json holds all it needs to come back (runs.el). Emacs
;; starting, the runs not over of the projects that had some (noted in
;; `agent-workflow-projects-file') are read back, each with the workflow it
;; started with (its workflow.yml); a project's are read back too when you
;; use it before (M-x agent-workflow-run, continue...). A job that was
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
;; killed, the run over; its issue open again, its branch and worktree kept.

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

(defun agent-workflow--from-json-plist (object)
  "OBJECT (a JSON object as a plist) as Lisp, its nested objects too."
  (cl-loop for (key value) on object by #'cddr append (list key value)))

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
                    (list :cost (or (plist-get spent :cost) 0) :tokens (or (plist-get spent :tokens) 0)))
           :active (or (plist-get (plist-get saved :spent) :time) 0)
           :more (plist-get saved :more)
           :warned (plist-get saved :warned)
           :edges (mapcar (lambda (edge) (cons (plist-get edge :edge)
                                               (list :count (plist-get edge :count) :notes (plist-get edge :notes))))
                          (plist-get saved :edges))
           :jobs (mapcar (lambda (job) (cons (plist-get job :name) (agent-workflow--job-from-json job)))
                         (plist-get saved :jobs))))))))

(defun agent-workflow-restore (project)
  "PROJECT's runs not over read back, those this Emacs hasn't: their jobs
that were running interrupted, waiting for you. Return them."
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
                    (when (eq (plist-get (cdr job) :status) 'running)
                      (agent-workflow--job-set run (car job) :status 'waiting
                                               :ask (list :kind 'interrupted :step (or (plist-get (cdr job) :step) 0))
                                               :why (format "%s: interrupted (Emacs stopped): continue it, skip its step, or stop?"
                                                            (car job)))))
                  (setq agent-workflow--runs (append agent-workflow--runs (list run)))
                  (agent-workflow--journal run "restored")
                  (agent-workflow--refresh run)
                  (agent-workflow--changed run)
                  (push run restored))))))))
    (nreverse restored)))

(defun agent-workflow-restore-all ()
  "Every noted project's runs read back; continued, if
`agent-workflow-continue-on-start' says. In `emacs-startup-hook'."
  (dolist (project (agent-workflow--known-projects))
    (when (file-directory-p project)
      (let ((runs (with-demoted-errors "agent workflow: %S" (agent-workflow-restore project))))
        (when agent-workflow-continue-on-start
          (dolist (run runs)
            (with-demoted-errors "agent workflow: %S" (agent-workflow-continue run))))))))

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

(cl-defun agent-workflow-continue (run &key current (by "you"))
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

(defun agent-workflow--continue-job (run job by)
  "JOB of RUN, interrupted, continued BY: its step again, an agent's
session resumed, told so."
  (let* ((state (agent-workflow--job run job))
         (index (plist-get (plist-get state :ask) :step))
         (step (nth index (plist-get (agent-workflow--job-spec run job) :steps))))
    (agent-workflow--journal run "continued" :job job :step index :by by)
    (agent-workflow--job-set run job :ask nil :status 'running :why nil :finished nil
                             :back (and (eq (plist-get step :kind) 'agent)
                                        (list :step index :interrupted t :by by :session (plist-get state :session))))
    (agent-workflow--refresh run)
    (agent-workflow--step-start run job index)))

(defun agent-workflow--interrupt (run job)
  "JOB of RUN stopped at once: its agent stopped (its session kept), its
script killed; interrupted, waiting for you."
  (let ((state (agent-workflow--job run job)))
    (when-let* ((agent (plist-get state :agent)))
      (agent-workflow--job-set run job :session (or (agent-workflow-agent-session agent) (plist-get state :session)))
      (agent-workflow-stop-agent agent))
    (when-let* ((process (plist-get state :process)))
      (when (process-live-p process)
        (process-put process 'agent-workflow-stopped t)
        (delete-process process)))
    (agent-workflow--job-set run job :agent nil :process nil
                             :ask (list :kind 'interrupted :step (or (plist-get state :step) 0)))
    (agent-workflow--journal run "interrupted" :job job)
    (agent-workflow--wait run job (format "%s: interrupted (paused): continue it, skip its step, or stop?" job))))

;; ====== CANCELLING ======

(cl-defun agent-workflow-cancel (run &key (by "you"))
  "Cancel RUN: its agents stopped, its scripts killed, its snapshots gone;
the run over, its issue open again; its branch and worktree kept."
  (dolist (job (agent-workflow-run-jobs run))
    (let ((state (cdr job)))
      (when-let* ((agent (plist-get state :agent))) (agent-workflow-stop-agent agent))
      (when-let* ((process (plist-get state :process)))
        (when (process-live-p process)
          (process-put process 'agent-workflow-stopped t)
          (delete-process process)))
      (when (plist-get state :snapshot)
        (agent-workflow-snapshot-remove (agent-workflow-run-project run) (agent-workflow-run-issue run) (car job)))
      (agent-workflow--job-set run (car job) :agent nil :process nil :snapshot nil)))
  (agent-workflow--journal run "cancelled" :by by)
  (agent-workflow--set-state run 'cancelled)
  (agent-workflow--bd-write (agent-workflow-run-project run) (agent-workflow-run-issue run) "--status" "open")
  (agent-workflow--issue-summary run)
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

(defun agent-workflow-continue-command (&optional current)
  "Continue every interrupted run of the current project (M-x
agent-workflow-continue); with \\[universal-argument], with its workflow as
it is now."
  (interactive "P")
  (let* ((project (or (agent-workflow-project) (user-error "Not in a git repository")))
         (runs (progn (agent-workflow--ensure-restored project)
                      (seq-filter #'agent-workflow--interrupted (agent-workflow-runs project)))))
    (unless runs (user-error "No run of %s was interrupted" (file-name-nondirectory (directory-file-name project))))
    (dolist (run runs) (agent-workflow-continue run :current current))
    (message "Continued: %s" (mapconcat #'agent-workflow-run-name runs ", "))))

(defun agent-workflow-cancel-command (run)
  "Cancel RUN (M-x agent-workflow-cancel), asked first."
  (interactive (let* ((project (or (agent-workflow-project) (user-error "Not in a git repository")))
                      (runs (progn (agent-workflow--ensure-restored project)
                                   (seq-remove (lambda (run) (memq (agent-workflow-run-state run) agent-workflow--ended))
                                               (agent-workflow-runs project))))
                      (names (mapcar (lambda (run) (cons (agent-workflow-run-name run) run)) runs)))
                 (unless runs (user-error "No run to cancel"))
                 (list (cdr (assoc (completing-read "Cancel the run: " names nil t) names)))))
  (when (yes-or-no-p (format "Cancel %s (its agents stopped, its work kept)? " (agent-workflow-run-name run)))
    (agent-workflow-cancel run)
    (message "%s cancelled" (agent-workflow-run-name run))))

(add-hook 'agent-workflow-run-functions #'agent-workflow--note-project)
