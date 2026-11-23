;;; $DOOMDIR/config/agent-workflow/back.el -*- lexical-binding: t; -*-
;; Going back: a run sent back to a job and step (by you, or by an agent's
;; outcome: rerun JOB), its loops counted and guarded, and your answer to
;; what a run asks (M-x agent-workflow-back, agent-workflow-confirm).
;; Loaded from config/agent-workflow.el, after where.el. No Doom here.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)


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

(cl-defun agent-workflow--back (run job &key (step 0) note discard (by "you"))
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

(defun agent-workflow--pick-run (project)
  "A run of PROJECT you pick (the only one, not asked). Not resume.el's
`agent-workflow--read-run', which reads a run's folder."
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

(defun agent-workflow-back (run job step note &optional discard)
  "Send RUN back to step STEP of JOB with NOTE (M-x agent-workflow-back).
Interactively the run, the job (one that has run), its step (asked only
when it has several), your note; with \[universal-argument], the work since
discarded, what's lost said and asked first."
  (interactive
   (let* ((project (or (agent-workflow-project) (user-error "Not in a git repository")))
          (run (agent-workflow--pick-run project))
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
  (agent-workflow--back run job :step step :note note :discard discard)
  (message "%s: back to %s%s" (agent-workflow-run-name run) job (if discard ", the work since discarded" "")))

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
then done, or asked of you (see LOOPS). OTHER that hasn't run (skipped by
its if:, not yet): nothing to send back to, JOB waits for you, saying so
\(its step again, or skipped: on as if it said done)."
  (if (memq (plist-get (agent-workflow--job run other) :status) '(pending skipped))
      (let ((outcome (plist-get (agent-workflow--job run job) :outcome))
            (index (plist-get (agent-workflow--job run job) :step)))
        (when-let* ((agent (plist-get (agent-workflow--job run job) :agent)))
          (agent-workflow-stop-agent agent))
        (agent-workflow--job-set run job :agent nil :outcome nil
                                 :ask (list :kind 'broke :step index :what (format "its outcome %s: rerun %s" outcome other)))
        (agent-workflow--journal run "asked" :job job :step index :kind "broke")
        (agent-workflow--wait run job (format "%s: its outcome %s reruns %s, which hasn't run (%s): run its step again, skip it (on as if done), or stop?"
                                              job outcome other (plist-get (agent-workflow--job run other) :status))))
    (agent-workflow--rerun-or-ask-1 run job other)))

(defun agent-workflow--rerun-or-ask-1 (run job other)
  "`agent-workflow--rerun-or-ask''s work, OTHER having run."
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
  (let ((replaced (agent-workflow--back run other :note (if (and yours (not (string-empty-p yours)))
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

(cl-defun agent-workflow--confirm (run choice &key notes more (by "you"))
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
      ("cancel" (agent-workflow--cancel run :by by))
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

(defun agent-workflow-confirm (run choice &optional notes more)
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
  (agent-workflow--confirm run choice :notes notes :more more)
  (message "%s: %s" (agent-workflow-run-name run) choice))
