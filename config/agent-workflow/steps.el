;;; $DOOMDIR/config/agent-workflow/steps.el -*- lexical-binding: t; -*-
;; The steps that aren't an agent's: run (a script), elisp (Lisp in your
;; Emacs) and uses (a built-in: merge). Loaded from config/agent-workflow.el,
;; after runs.el. No Doom here.
;;
;; A run: step is GitHub Actions' run: its text a script, run by its shell
;; (bash by default; python, node, any interpreter), in the job's place (the
;; issue's worktree, or a reading job's snapshot), with ISSUE, BRANCH, MAIN,
;; MAIN_BRANCH, WORKTREE, JOB, ROUND and TRY in its environment, within its
;; timeout (`agent-workflow-script-timeout' if it has none). One line naming
;; a file of .agent-workflow/ runs your checkout's copy of it, never the
;; branch's: an agent can't change the check it's run against. Its output is
;; kept in the run's logs/ and journaled (its last lines).
;;
;;   exit 0     the next step
;;   exit 1     the work is wrong: its output goes to the job's agent (or,
;;              the job having none, one with the step's on-fail profile),
;;              which fixes it and says done; the step runs again (from
;;              its retry-from step: those between run again too), up to
;;              its retries (0 by default, its own tries counted); used
;;              up, the run asks you: go on (with a note for the agent),
;;              skip the step, or stop
;;   exit 3     it can't go on: the run failed (its agents stopped, its
;;              issue open again, its branch and worktree kept; resume.el)
;;   other, or a timeout: the script broke; no agent is sent, the run asks
;;              you: go (run it again), skip it, or stop
;;
;; An elisp: step runs in your Emacs, the run's helpers bound as in if:
;; (issue-id)...: returning is exit 0; signalling `agent-workflow-fail' (its
;; message the output) exit 1; `agent-workflow-abort' exit 3 (the run
;; failed); any other error, it broke. Quick: it blocks
;; Emacs.
;;
;; uses: merge, safe. It merges the issue's branch into the main branch
;; (`agent-workflow-main-branch': origin's HEAD, else main, else master),
;; never pushing:
;; 1. Merged already: done (it's safe to run twice). Changing
;;    .agent-workflow/ (what runs the workflows): it waits for your go.
;; 2. Tried first in a worktree of its own, detached at the main branch: a
;;    conflict, the branch is rebased onto it, if that goes cleanly, and
;;    tried again; else the on-fail agent rebases it, resolving the
;;    conflicts (its retries not counted), and the run goes back to its
;;    first job that edits (its checks, its review, run again on what was
;;    resolved).
;; 3. Its suite (with: {suite: make test}) run there, on the merge: exit 1
;;    as a script's (to the on-fail agent), else it broke.
;; 4. Into the main branch: where it's checked out in your checkout, there,
;;    only if none of the files it changes has a change of yours, else it
;;    waits for you, naming them (go: try again); checked out in another
;;    worktree, it waits for you; where it isn't, the branch is moved to the
;;    merge, no tree touched.
;; 5. The issue closed (a workflow's own run: there's none).

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(define-error 'agent-workflow-fail "The step failed")
(define-error 'agent-workflow-abort "The run failed")

(defvar agent-workflow-script-timeout)

;; ====== THE AGENT THAT FIXES ======

(defun agent-workflow--fix (run job index output what)
  "Step INDEX of JOB of RUN failed (WHAT, in words; OUTPUT its output): the
job's agent told, else one with the step's on-fail profile started, to fix
it and say done; the step then runs again. No agent to send: the run
waits for you. Its pane redrawn either way (who fixes it, or the wait)."
  (agent-workflow--fix-1 run job index output what)
  (agent-workflow--changed run))

(defun agent-workflow--fix-1 (run job index output what)
  "`agent-workflow--fix''s work, its pane not redrawn."
  (let* ((step (nth index (plist-get (agent-workflow--job-spec run job) :steps)))
         (state (agent-workflow--job run job))
         (held (plist-get state :agent))
         (from (agent-workflow--retry-from run job index))
         (message (format "%s (try %d of %d). Its output:\n\n%s\n\nFix it, commit, then say done again: %s."
                          what (agent-workflow--tries run job index) (1+ (or (plist-get step :retries) 0))
                          (agent-workflow--tail output 60)
                          (if (= from index)
                              "the step runs again"
                            (format "its job runs again from its step %d%s, then this one"
                                    (1+ from) (agent-workflow--step-called run job from)))))
         (profile (plist-get step :on-fail)))
    (agent-workflow--job-set run job :retry index :finished nil)
    (cond
     ((and held (buffer-live-p (agent-workflow-agent-buffer held)))
      (agent-workflow-send held message)
      (agent-workflow--journal run "fixing" :job job :step index :agent (agent-workflow-agent-name held)))
     ((not profile)
      (agent-workflow--job-set run job :retry nil)
      (agent-workflow--wait run job (format "%s: %s, and no agent fixes it (on-fail: a profile)" job what)))
     ((agent-workflow--no-agent run job)
      ;; The pool full, its workflow at its limit: it waits for an agent,
      ;; looked at again as one stops (runs.el's --advance).
      (agent-workflow--job-set run job :retry nil :pool (list :fix index output what)
                               :why (agent-workflow--no-agent run job))
      (agent-workflow--refresh run))
     (t
      (condition-case err
          (let* ((info (agent-workflow-run-info run))
                 (snapshot (plist-get state :snapshot))
                 (agent (agent-workflow-start-agent
                         :project (agent-workflow-run-project run) :issue (agent-workflow-run-issue run)
                         :job job :profile profile :type (plist-get info :type) :title (plist-get info :title)
                         :branch (agent-workflow--run-branch run)
                         :place (and (agent-workflow-run-checkout-p run) (agent-workflow--run-worktree run))
                         :values (append (agent-workflow--job-values run job) (agent-workflow--run-values run))
                         :prompt message :snapshot snapshot)))
            (agent-workflow--job-set run job :agent agent)
            (agent-workflow--journal run "fixing" :job job :step index :agent (agent-workflow-agent-name agent)
                                     :profile profile))
        (error (agent-workflow--job-set run job :retry nil)
               (agent-workflow--wait run job (format "%s: %s, and its agent didn't start: %s" job what
                                                     (error-message-string err)))))))))

(defun agent-workflow--step-called (run job index)
  "Step INDEX of JOB of RUN's name, as \" (NAME)\"; none: \"\"."
  (if-let* ((name (plist-get (nth index (plist-get (agent-workflow--job-spec run job) :steps)) :name)))
      (format " (%s)" name)
    ""))

(defun agent-workflow--step-named (step)
  "STEP's name, as \", NAME\"; none: \"\"."
  (if-let* ((name (plist-get step :name))) (concat ", " name) ""))

(defun agent-workflow--tries (run job index)
  "How many times step INDEX of JOB of RUN has run, this round."
  (or (alist-get index (plist-get (agent-workflow--job run job) :tries)) 0))

(defun agent-workflow--tail (text lines)
  "TEXT's last LINES lines."
  (let ((all (split-string (string-trim-right (or text "")) "\n")))
    (string-join (last all lines) "\n")))

(defun agent-workflow--failed (run job index output what)
  "Step INDEX of JOB of RUN failed, the work wrong (exit 1): fixed and run
again, while its retries last; used up, the run asks you."
  (let ((step (nth index (plist-get (agent-workflow--job-spec run job) :steps))))
    (if (> (agent-workflow--tries run job index) (or (plist-get step :retries) 0))
        (progn
          (agent-workflow--job-set run job :ask (list :kind 'retries :step index :output output :what what))
          (agent-workflow--journal run "asked" :job job :step index :kind "retries")
          (agent-workflow--wait run job (format "%s: %s, its retries used up: go on, skip it, or stop?" job what)))
      (agent-workflow--fix run job index output what))))

(defun agent-workflow--broke (run job index why)
  "Step INDEX of JOB of RUN broke (WHY): no agent sent, the run asks you."
  (agent-workflow--job-set run job :ask (list :kind 'broke :step index :what why))
  (agent-workflow--journal run "asked" :job job :step index :kind "broke")
  (agent-workflow--wait run job (format "%s: %s: run it again, skip it, or stop?" job why)))

(defun agent-workflow--count-try (run job index)
  "Step INDEX of JOB of RUN runs once more: its tries counted."
  (let ((tries (plist-get (agent-workflow--job run job) :tries)))
    (setf (alist-get index tries) (1+ (or (alist-get index tries) 0)))
    (agent-workflow--job-set run job :tries tries)))

;; ====== A SCRIPT ======

(defun agent-workflow--script-environment (run job)
  "A script's environment for JOB of RUN (\"NAME=VALUE\"...)."
  (let* ((project (agent-workflow-run-project run))
         (state (agent-workflow--job run job))
         (beads (expand-file-name ".beads" project)))
    (append (list (concat "ISSUE=" (agent-workflow-run-issue run))
                  (concat "BRANCH=" (or (nth 1 (plist-get state :snapshot))
                                        (let ((default-directory (agent-workflow--work-directory run)))
                                          (or (car (agent-workflow--git-lines "branch" "--show-current")) ""))))
                  (concat "MAIN=" (directory-file-name project))
                  (concat "MAIN_BRANCH=" (agent-workflow-main-branch project))
                  (concat "WORKTREE=" (directory-file-name (plist-get state :dir)))
                  (concat "JOB=" job)
                  (format "ROUND=%d" (or (plist-get state :round) 1))
                  (format "TRY=%d" (max 1 (agent-workflow--tries run job (plist-get state :step))))
                  (concat "BEADS_ACTOR=" (agent-workflow-run-issue run) "/" job))
            (when (file-directory-p beads) (list (concat "BEADS_DIR=" beads))))))

(defun agent-workflow--script-command (run text shell)
  "How RUN runs the script TEXT with SHELL (nil: bash): a command line, its
script written to a file of the run's. One line naming a file of
.agent-workflow/: your checkout's."
  (let* ((project (agent-workflow-run-project run))
         (text (string-trim text))
         (text (if (and (not shell) (not (string-match-p "\n" text))
                        (string-match "\\`\\(?:\\./\\)?\\(\\.agent-workflow/[^ \t]+\\)" text)
                        (file-regular-p (expand-file-name (match-string 1 text) project)))
                   (concat (shell-quote-argument (expand-file-name (match-string 1 text) project))
                           (substring text (match-end 0)))
                 text))
         (file (make-temp-file (expand-file-name "script-" (agent-workflow-run-dir run)) nil
                               (if shell (concat "." (file-name-nondirectory (car (split-string shell)))) ".sh")
                               (concat text "\n"))))
    (append (split-string-and-unquote (or shell "bash")) (list file))))

(defun agent-workflow--log-file (run job index)
  "Where the output of step INDEX of JOB of RUN goes, this round and try."
  (let ((state (agent-workflow--job run job)))
    (expand-file-name (format "logs/%s.r%d.t%d.%d.log" job (or (plist-get state :round) 1)
                              (agent-workflow--tries run job index) (1+ index))
                      (agent-workflow-run-dir run))))

(cl-defun agent-workflow--spawn (run job index command &key on-exit timeout directory)
  "Run COMMAND (a list) for step INDEX of JOB of RUN in DIRECTORY (default:
the job's place), its output logged; ON-EXIT called with its exit status
\(timeout when it ran out of TIMEOUT seconds) and its output."
  (let* ((log (agent-workflow--log-file run job index))
         (buffer (generate-new-buffer " *agent-workflow script*"))
         (default-directory (file-name-as-directory (or directory (plist-get (agent-workflow--job run job) :dir))))
         (process-environment (append (agent-workflow--script-environment run job) process-environment))
         (timed-out nil)
         (process nil)
         (timer nil))
    (make-directory (file-name-directory log) t)
    (setq process
          (make-process
           :name "agent-workflow-script" :buffer buffer :command command :connection-type 'pipe :noquery t
           ;; Its errors in its output, without a word of the pipe's own.
           :stderr (make-pipe-process :name "agent-workflow-script errors" :buffer buffer :noquery t
                                      :sentinel #'ignore)
           :sentinel (lambda (process _event)
                       (unless (process-live-p process)
                         (when timer (cancel-timer timer))
                         (let ((output (with-current-buffer buffer (buffer-string)))
                               (status (if timed-out 'timeout (process-exit-status process))))
                           (kill-buffer buffer)
                           (let ((coding-system-for-write 'utf-8-unix))
                             (write-region output nil log nil 'silent))
                           (agent-workflow--job-set run job :process nil)
                           (unless (process-get process 'agent-workflow-stopped)
                             (agent-workflow--journal run "script-ended" :job job :step index
                                                      :exit (if (eq status 'timeout) "timeout" status)
                                                      :log (file-relative-name log (agent-workflow-run-dir run))
                                                      :tail (agent-workflow--tail output 20))
                             ;; Out of the sentinel: what follows may send an
                             ;; agent a message, which agent-shell can't from
                             ;; inside one.
                             (run-at-time 0 nil on-exit status output)))))))
    (agent-workflow--job-set run job :process process)
    (when timeout
      (setq timer (run-at-time timeout nil (lambda ()
                                             (when (process-live-p process)
                                               (setq timed-out t)
                                               (interrupt-process process)
                                               (run-at-time 2 nil (lambda () (when (process-live-p process)
                                                                               (kill-process process)))))))))
    process))

(defun agent-workflow--step-done-or-failed (run job index status output what)
  "Step INDEX of JOB of RUN ended with STATUS (its exit, or timeout),
OUTPUT: on to the next, fixed, or asked (see the top of this file)."
  (pcase status
    (0 (agent-workflow-step-ended run job))
    (1 (agent-workflow--failed run job index output (format "%s returned 1" what)))
    (3 (agent-workflow-fail run (format "%s: %s: %s" job what
                                        (or (car (last (split-string (string-trim (or output "")) "\n" t)))
                                            "it returned 3"))
                            :job job :step index))
    ('timeout (agent-workflow--broke run job index (format "%s ran out of time" what)))
    (_ (agent-workflow--broke run job index (format "%s broke (it returned %s)" what status)))))

(defun agent-workflow--run-step (run job step index)
  "The run: step STEP (INDEX of JOB of RUN): its script, as the top of
this file says."
  (agent-workflow--count-try run job index)
  (let ((what (format "its step %d%s (%s)" (1+ index) (agent-workflow--step-named step)
                      (agent-workflow--short (plist-get step :run)))))
    (agent-workflow--journal run "step-started" :job job :step index :kind "run"
                             :try (agent-workflow--tries run job index))
    (agent-workflow--spawn run job index (agent-workflow--script-command run (plist-get step :run) (plist-get step :shell))
                           :timeout (or (plist-get step :timeout) agent-workflow-script-timeout)
                           :on-exit (lambda (status output)
                                      (agent-workflow--step-done-or-failed run job index status output what)))))

(defun agent-workflow--short (text)
  "TEXT on one line, at most 40 characters."
  (let ((line (car (split-string (string-trim (or text "")) "\n"))))
    (if (> (length line) 40) (concat (substring line 0 39) "…") line)))

;; ====== LISP ======

(defun agent-workflow--elisp-step (run job step index)
  "The elisp: step STEP (INDEX of JOB of RUN): its Lisp, evaluated in your
Emacs with the run's helpers, in the job's place."
  (agent-workflow--count-try run job index)
  (agent-workflow--journal run "step-started" :job job :step index :kind "elisp"
                           :try (agent-workflow--tries run job index))
  (let ((what (format "its step %d%s (elisp)" (1+ index) (agent-workflow--step-named step)))
        (default-directory (file-name-as-directory (plist-get (agent-workflow--job run job) :dir)))
        (outcome nil))
    (setq outcome
          (condition-case err
              (progn
                (agent-workflow--with-helpers run
                  (let ((text (plist-get step :elisp)) (start 0))
                    (while (not (string-blank-p (substring text start)))
                      (let ((read (read-from-string text start)))
                        (setq start (cdr read))
                        (eval (car read) t)))))
                (list 0 ""))
            (agent-workflow-fail (list 1 (error-message-string err)))
            (agent-workflow-abort (list 3 (error-message-string err)))
            (error (list 2 (error-message-string err)))))
    (agent-workflow--journal run "script-ended" :job job :step index :exit (car outcome) :tail (cadr outcome))
    (agent-workflow--step-done-or-failed run job index (car outcome) (cadr outcome) what)))

;; ====== MERGE ======

(defun agent-workflow--merge-worktree (run)
  "Where RUN's merge is tried: a worktree of its own."
  (agent-workflow-snapshot-directory (agent-workflow-run-project run) (agent-workflow-run-issue run) "merge-try"))

(defun agent-workflow--merge-step (run job step index)
  "The uses: merge step STEP (INDEX of JOB of RUN): see the top of this
file."
  (agent-workflow--count-try run job index)
  (agent-workflow--journal run "step-started" :job job :step index :kind "merge"
                           :try (agent-workflow--tries run job index))
  (condition-case err
      (let* ((project (agent-workflow-run-project run))
             (issue (agent-workflow-run-issue run))
             (worktree (agent-workflow-worktree-directory project issue))
             (branch (let ((default-directory worktree)) (agent-workflow--git "branch" "--show-current")))
             (main (agent-workflow-main-branch project))
             (try (agent-workflow--merge-worktree run)))
        (cond
         ((let ((default-directory project))
            (eql 0 (process-file "git" nil nil nil "merge-base" "--is-ancestor" branch main)))
          (agent-workflow--merged run job index branch main t))
         ;; What runs the workflows changed by the branch: merged only once
         ;; you say so (trust.el).
         ((and (not (plist-get (agent-workflow--job run job) :protected-ok))
               (let ((default-directory project))
                 (seq-filter (lambda (file) (string-prefix-p ".agent-workflow/" file))
                             (agent-workflow--git-lines "diff" "--name-only" (concat main "..." branch)))))
          (let ((files (let ((default-directory project))
                         (seq-filter (lambda (file) (string-prefix-p ".agent-workflow/" file))
                                     (agent-workflow--git-lines "diff" "--name-only" (concat main "..." branch))))))
            (agent-workflow--job-set run job :ask (list :kind 'protected :step index))
            (agent-workflow--journal run "asked" :job job :step index :kind "protected" :files (vconcat files))
            (agent-workflow--wait run job (format "%s: its branch changes what runs the workflows (%s): merge it \
anyway (go), or stop?" job (string-join files ", ")))))
         (t
          (let ((default-directory project))
            (agent-workflow-snapshot-remove project issue "merge-try")
            (agent-workflow--git "worktree" "add" "--detach" (directory-file-name try) main))
          (if (let ((default-directory try))
                (eql 0 (process-file "git" nil nil nil "-c" "user.name=agent workflow"
                                     "-c" "user.email=agent-workflow@localhost"
                                     "merge" "--no-ff" "--no-edit" "-m" (format "Merge %s (%s)" branch issue) branch)))
              (agent-workflow--merge-suite run job step index branch main try)
            (let ((default-directory try)) (process-file "git" nil nil nil "merge" "--abort"))
            (agent-workflow-snapshot-remove project issue "merge-try")
            (agent-workflow--merge-conflict run job index branch main)))))
    (error (agent-workflow--broke run job index (format "its merge: %s" (error-message-string err))))))

(defun agent-workflow--merge-suite (run job step index branch main try)
  "The merge of BRANCH into MAIN tried in TRY: STEP's suite run there, then
it's merged for real."
  (let ((merged (let ((default-directory try)) (agent-workflow--git "rev-parse" "HEAD")))
        (done (lambda () (agent-workflow-snapshot-remove (agent-workflow-run-project run)
                                                         (agent-workflow-run-issue run) "merge-try"))))
    (if-let* ((suite (plist-get (plist-get step :with) :suite)))
        (agent-workflow--spawn
         run job index (agent-workflow--script-command run suite nil) :directory try
         :timeout (or (plist-get step :timeout) agent-workflow-script-timeout)
         :on-exit (lambda (status output)
                    (funcall done)
                    (if (eql status 0)
                        (agent-workflow--merge-into run job index branch main merged)
                      (agent-workflow--step-done-or-failed run job index status output
                                                           (format "its suite (%s), on the merge"
                                                                   (agent-workflow--short suite))))))
      (funcall done)
      (agent-workflow--merge-into run job index branch main merged))))

(defun agent-workflow--merge-into (run job index branch main merged)
  "BRANCH merged into MAIN for real (MERGED: the merge as tried), if MAIN
is still where it was tried (else tried again on it): where MAIN is
checked out in your checkout, fast-forwarded there to MERGED, if no file
it changes has a change of yours; where it's checked out elsewhere, it
waits for you; where it isn't, its ref moved to MERGED."
  (condition-case err
      (let* ((project (agent-workflow-run-project run))
             (default-directory project)
             (where (seq-find (lambda (worktree) (equal (plist-get worktree :branch) main))
                              (agent-workflow--worktrees project)))
             ;; Where the merge was tried: its first parent.
             (base (agent-workflow--git "rev-parse" (concat merged "^1"))))
        (cond
         ;; Main moved since the merge was tried (another run merged, your
         ;; commits while its suite ran): tried again on it, never merged
         ;; blind nor overwritten.
         ((let ((now (agent-workflow--git "rev-parse" (concat "refs/heads/" main))))
            (unless (equal base now)
              (agent-workflow--journal run "main-moved" :job job :step index :into main :from base :to now)
              t))
          (agent-workflow--merge-step run job (nth index (plist-get (agent-workflow--job-spec run job) :steps)) index))
         ((null where)
          ;; Its ref moved to the merge, only from where it was tried.
          (agent-workflow--git "update-ref" "-m" (format "agent workflow: merge %s" branch)
                               (concat "refs/heads/" main) merged base)
          (agent-workflow--merged run job index branch main nil))
         ((not (equal (file-truename (plist-get where :dir)) (file-truename project)))
          (agent-workflow--job-set run job :ask (list :kind 'merge :step index))
          (agent-workflow--wait run job (format "%s: its merge waits: %s is checked out in %s, not your checkout: \
merge it there, or check it out here, then go" job main (abbreviate-file-name (plist-get where :dir)))))
         (t
          (let* ((changed (agent-workflow--git-lines "diff" "--name-only" (concat main "..." branch)))
                 (yours (mapcar (lambda (line) (car (last (split-string (substring line 3) " -> "))))
                                (agent-workflow--git-lines "status" "--porcelain")))
                 (both (seq-filter (lambda (file) (member file changed)) yours)))
            (if both
                (progn
                  (agent-workflow--job-set run job :ask (list :kind 'merge :step index))
                  (agent-workflow--journal run "asked" :job job :step index :kind "merge" :files (vconcat both))
                  (agent-workflow--wait run job (format "%s: its merge waits: your checkout has changes in %s: \
commit or stash them, then go" job (string-join both ", "))))
              ;; The merge as tried (and its suite passed on), fast-forwarded
              ;; to: main is its first parent. Failing, never left mid-merge.
              (condition-case err
                  (agent-workflow--git "merge" "--ff-only" merged)
                (error (when (file-exists-p (expand-file-name (agent-workflow--git "rev-parse" "--git-path" "MERGE_HEAD")))
                         (process-file "git" nil nil nil "merge" "--abort"))
                       (signal (car err) (cdr err))))
              (agent-workflow--merged run job index branch main nil))))))
    (error (agent-workflow--broke run job index (format "its merge: %s" (error-message-string err))))))

(defun agent-workflow--rebasing-p (dir)
  "Non-nil if a rebase is under way in DIR (a worktree): its conflicts
being resolved."
  (let ((default-directory dir))
    (seq-some (lambda (name)
                (file-exists-p (expand-file-name (agent-workflow--git "rev-parse" "--git-path" name) dir)))
              '("rebase-merge" "rebase-apply"))))

(defun agent-workflow--rebased (run)
  "RUN's branch rebased by the run (onto the main branch, its conflicts
resolved): its jobs' commits are there anew, under other names; their
:end-commit moved to the branch as it is now, for the watch (watch.el)."
  (let ((head (let ((default-directory (agent-workflow--work-directory run)))
                (agent-workflow--git "rev-parse" "HEAD"))))
    (dolist (job (agent-workflow-run-jobs run))
      (when (plist-get (cdr job) :end-commit)
        (agent-workflow--job-set run (car job) :end-commit head)))))

(defun agent-workflow--merge-conflict (run job index branch main)
  "BRANCH conflicts with MAIN: rebased onto it if that goes cleanly (and
the merge tried again), else the on-fail agent rebases it, resolving. Its
own rebase that failed aborted; never one under way (its agent's)."
  (let* ((default-directory (agent-workflow--work-directory run))
         (clean (and (not (agent-workflow--rebasing-p default-directory))
                     (null (agent-workflow--git-lines "status" "--porcelain")))))
    (if (and clean
             (eql 0 (process-file "git" nil nil nil "-c" "user.name=agent workflow"
                                  "-c" "user.email=agent-workflow@localhost" "rebase" main)))
        (progn
          (agent-workflow--journal run "rebased" :job job :step index :onto main)
          (agent-workflow--rebased run)
          (agent-workflow--merge-step run job (nth index (plist-get (agent-workflow--job-spec run job) :steps)) index))
      (when clean
        (process-file "git" nil nil nil "rebase" "--abort"))
      (agent-workflow--job-set run job :resolving t)
      (agent-workflow--fix
       run job index
       (format "Merging %s into %s conflicts. Rebase it onto %s here (git rebase %s), resolving the conflicts, \
and commit." branch main main main)
       "its merge conflicts"))))

(defun agent-workflow--merged (run job index branch main already)
  "BRANCH is merged into MAIN (ALREADY: it was; with no commit since its run
started, nothing to merge): the issue closed (a run with no ticket: none),
the step over."
  (let ((empty (and already (agent-workflow--branch-empty-p run branch))))
    (agent-workflow--journal run "merged" :job job :step index :branch branch :into main
                             :already (if already t :false) :empty (if empty t :false))
    (when (agent-workflow-run-ticket-p run)
      (agent-workflow--bd (agent-workflow-run-project run)
                          (list "close" (agent-workflow-run-issue run) "--reason"
                                (if empty
                                    (format "Nothing to merge: %s has no commit" branch)
                                  (format "Merged %s into %s" branch main))))))
  (agent-workflow-step-ended run job))

(setq agent-workflow-step-functions
      (list (cons 'run #'agent-workflow--run-step)
            (cons 'elisp #'agent-workflow--elisp-step)
            (cons 'uses (lambda (run job step index)
                          (pcase (plist-get step :uses)
                            ("merge" (agent-workflow--merge-step run job step index)))))))
