;;; $DOOMDIR/config/agent-workflow/watch.el -*- lexical-binding: t; -*-
;; An issue, or its branch, changed by hand while its run goes. Loaded from
;; config/agent-workflow.el, after budget.el. No Doom here.
;;
;; Each run not over is looked at again every `agent-workflow-queue-check'
;; seconds while there's one (and as you ask: `agent-workflow-watch'):
;;
;; - Its issue closed or deferred: its running steps are stopped (their
;;   work kept, their agents' sessions kept), and the run asks: go on (the
;;   issue in progress again), or cancel it.
;; - Blocked by a new dependency: no new job starts until it's unblocked,
;;   saying by what; jobs running finish.
;; - Its type, or its workflow:NAME label, changed: the run keeps its
;;   workflow, and its journal says so.
;; - Its title, description, acceptance or notes edited: the next steps
;;   read them anew.
;; - Its branch: your commits on it are work like any. A job's commits no
;;   longer on it (a reset, a force-push) stop the run, asking: go on as it
;;   is now, or stop. A rebase the run did, or its agent does (a merge's
;;   conflicts), isn't that: its commits are there anew.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar agent-workflow--watch-timer nil "Looks at the runs' issues again, while there are runs.")

(defun agent-workflow--stop-running (run kind why)
  "RUN's running steps stopped, their work and sessions kept: asking you
\(KIND), saying WHY. A job waiting for you already keeps its question."
  (let ((running (mapcar #'car (agent-workflow--status-of run 'running))))
    (dolist (job running)
      (agent-workflow--interrupt run job)
      (agent-workflow--job-set run job :ask (list :kind kind :step (or (plist-get (agent-workflow--job run job) :step) 0)))
      (agent-workflow--wait run job (format "%s: %s" job why)))
    ;; None running: its next job holds the question, not started.
    (unless running
      (when-let* ((next (car (car (agent-workflow--status-of run 'pending)))))
        (agent-workflow--job-set run next :held t :ask (list :kind kind :step 0))
        (agent-workflow--wait run next (format "%s: %s" next why))))))

(defun agent-workflow--commits-gone (run)
  "RUN's jobs whose commits aren't on its branch any more: their names.
None while its branch is being rebased by the run (a job :resolving its
merge's conflicts, a rebase under way): its commits move then, not lost
\(`agent-workflow--rebased' moves the jobs' :end-commit after)."
  (let ((dir (agent-workflow--work-directory run)))
    (when (and (file-directory-p dir)
               (not (seq-some (lambda (job) (plist-get (cdr job) :resolving)) (agent-workflow-run-jobs run)))
               (not (agent-workflow--rebasing-p dir)))
      (let ((default-directory dir))
        (mapcar #'car
                (seq-filter (lambda (job)
                              (when-let* ((commit (plist-get (cdr job) :end-commit)))
                                (not (eql 0 (process-file "git" nil nil nil "merge-base" "--is-ancestor" commit "HEAD")))))
                            (agent-workflow-run-jobs run)))))))

(defun agent-workflow-watch-run (run)
  "RUN's issue and branch looked at again: see the top of this file."
  (unless (or (memq (agent-workflow-run-state run) agent-workflow--ended)
              ;; Asked already for one of these.
              (seq-some (lambda (job) (memq (plist-get (plist-get (cdr job) :ask) :kind) '(closed moved)))
                        (agent-workflow-run-jobs run)))
    (let* ((before (agent-workflow-run-info run))
           ;; No ticket: no issue to look at, its branch only.
           (now (and (agent-workflow-run-ticket-p run)
                     (condition-case nil
                         (agent-workflow-issue (agent-workflow-run-project run) (agent-workflow-run-issue run))
                       (user-error nil)))))
      (when now
        ;; Its text: the next steps read it anew.
        (dolist (key '(:title :description :acceptance :notes))
          (unless (equal (plist-get before key) (plist-get now key))
            (setf (plist-get (agent-workflow-run-info run) key) (plist-get now key))
            (agent-workflow--journal run "issue-changed" :what (substring (symbol-name key) 1))))
        ;; Its type, its workflow label: its workflow kept.
        (let ((label (lambda (info) (seq-find (lambda (l) (string-prefix-p "workflow:" l)) (plist-get info :labels)))))
          (unless (and (equal (plist-get before :type) (plist-get now :type))
                       (equal (funcall label before) (funcall label now)))
            (agent-workflow--journal run "issue-changed" :what "type or workflow label"
                                     :type (plist-get now :type) :label (funcall label now))
            (message "%s: its issue's type or workflow label changed: it keeps its workflow"
                     (agent-workflow-run-name run))
            (setf (plist-get (agent-workflow-run-info run) :type) (plist-get now :type)
                  (plist-get (agent-workflow-run-info run) :labels) (plist-get now :labels))))
        ;; Its blockers.
        (let ((blockers (and (not (eq (agent-workflow-run-state run) 'queued)) (plist-get now :blockers))))
          (unless (equal blockers (agent-workflow-run-blocked run))
            (setf (agent-workflow-run-blocked run) blockers)
            (agent-workflow--journal run "issue-changed" :what "blockers" :blockers (vconcat blockers))
            (agent-workflow--tick-soon)))
        ;; Closed, deferred.
        (when (member (plist-get now :status) '("closed" "deferred"))
          (agent-workflow--journal run "issue-changed" :what "status" :status (plist-get now :status))
          (agent-workflow--stop-running run 'closed (format "its issue was %s by hand: go on (it's in progress again), or cancel the run?"
                                                            (plist-get now :status)))))
      ;; Its branch.
      (when-let* ((gone (agent-workflow--commits-gone run)))
        (agent-workflow--journal run "branch-moved" :jobs (vconcat gone))
        (agent-workflow--stop-running run 'moved (format "the commits of %s aren't on the branch any more (a reset, a force-push?): go on as it is now, or stop?"
                                                         (string-join gone ", "))))
      (agent-workflow--changed run))))

(defun agent-workflow-watch ()
  "Every run not over looked at again (see the top of this file); this
looked at again later while there's one."
  (interactive)
  (let ((active (seq-remove (lambda (run) (memq (agent-workflow-run-state run) agent-workflow--ended))
                            agent-workflow--runs)))
    (dolist (run active)
      (with-demoted-errors "agent workflow: %S" (agent-workflow-watch-run run)))
    (cond ((and active (not (timerp agent-workflow--watch-timer)))
           (setq agent-workflow--watch-timer (run-at-time agent-workflow-queue-check agent-workflow-queue-check
                                                          #'agent-workflow-watch)))
          ((and (not active) (timerp agent-workflow--watch-timer))
           (cancel-timer agent-workflow--watch-timer)
           (setq agent-workflow--watch-timer nil)))))

(defun agent-workflow--watch-soon (run)
  "A run started: its watch started, if it isn't. In
`agent-workflow-run-functions'."
  (when (and (not (timerp agent-workflow--watch-timer))
             (not (memq (agent-workflow-run-state run) agent-workflow--ended)))
    (setq agent-workflow--watch-timer (run-at-time agent-workflow-queue-check agent-workflow-queue-check
                                                   #'agent-workflow-watch))))

(add-hook 'agent-workflow-run-functions #'agent-workflow--watch-soon)
