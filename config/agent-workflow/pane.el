;;; $DOOMDIR/config/agent-workflow/pane.el -*- lexical-binding: t; -*-
;; A run's pane: an Agent UI canvas, ISSUE · WORKFLOW, one per run, drawn by
;; Emacs from the run, its journal and its log (never by an agent).
;; Loaded from config/agent-workflow.el, after log.el. No Doom here.
;;
;; Above its sections, the run: its issue, its state, its time, what it
;; spent of its budget. Then, each under its divider (Agent UI's sections):
;;
;; - Run: its jobs, a checklist, each job's steps under it (status, agent,
;;   round, try, time).
;; - Needs you, only while it waits for you: what on, as a question you
;;   answer there (an approval: approve, or reject with a note; the loop
;;   guard: go on with notes, accept, stop; retries used up, a step that
;;   broke, its budget used up...; its agent asking in its session: a
;;   permission's own buttons, pressed from there, and Go to it, its session
;;   shown at the question).
;; - A section per job's agent: its agent-shell session's canvas, shown
;;   there (`agent-ui-host'): its plan, its progress, its questions, with no
;;   pane of its own; folded once its job ends (▸ build ✓ 12m). RET on its
;;   divider opens its session.
;; - Log: its last events (log.el).
;;
;; Started from Emacs (M-x agent-workflow-run), its pane opens; from the
;; shell, it's made when you look (M-x agent-workflow-runs, RET), and opens
;; by itself only once you did. A run done: its checklist finished, Agent
;; UI's countdown closes the pane (Keep keeps it); failed, cancelled,
;; waiting: it stays. Closing it stops nothing.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar agent-workflow-pane-log-lines)
(defvar agent-ui-answer-function)
(defvar agent-ui-closes-with)
(defvar agent-ui-display-function)
(defvar agent-ui--entries)
(declare-function agent-ui--session-name "agent-ui/agent")
(declare-function agent-shell-jump-to-latest-permission-button-row "agent-shell")
(declare-function agent-shell-elicitation-jump-to-latest-form "agent-shell-elicitation")
(declare-function +my/agent-shell-permission-buttons "config/agent-shell/permissions")
(declare-function +my/agent-shell-press-permission "config/agent-shell/permissions")

(defvar-local agent-workflow--pane-run nil "In a run's pane: the run.")

(defvar-local agent-workflow--pane-times nil
  "In a run's pane: when its jobs and their steps started and ended, from
its journal: a hash table of a job to (:started T :ended T :steps ((INDEX
:started T :ended T)...)), times in seconds.")

(defvar-local agent-workflow--pane-open nil
  "In a run's pane: non-nil once it may open by itself (started from Emacs,
or you opened it).")

(defvar-local agent-workflow--pane-asked nil
  "In a run's pane: the question its Needs you shows, (JOB KIND WHY).")

(defvar-local agent-workflow--pane-where-shown nil
  "In a run's pane: where its work is, as its header shows it
\(`agent-workflow-run-where').")

(defvar agent-workflow-pane-where-every 15
  "Seconds between looks at where the work of runs not over is (a commit,
files changed), while their panes are open: their headers drawn again if it
changed.")

(defvar agent-workflow--pane-where-timer nil
  "The timer looking at where runs' work is, while a pane of one not over is open.")

(defvar-local agent-workflow--pane-ended nil
  "In a run's pane: its jobs that ended while it showed them: their sections
folded once.")

(defvar agent-workflow--pane-showing nil
  "Non-nil while a pane is shown on purpose (`agent-workflow-pane').")

;; ====== THE PANE ======

(defun agent-workflow--pane-live (run)
  "RUN's pane, if it has one."
  (let ((pane (agent-workflow-run-pane run)))
    (and (buffer-live-p pane) pane)))

(defun agent-workflow--pane-p (buffer)
  "Whether BUFFER is a run's pane."
  (and (buffer-live-p buffer) (buffer-local-value 'agent-workflow--pane-run buffer) t))

(defun agent-workflow--pane-quiet-p (canvas)
  "Whether CANVAS, a run's pane, stays out of the windows: not shown on
purpose, and either not one that opens by itself (see the top of this
file) or nothing in it needs you (its run waits for you, a question waits
in it: only that opens it again, its window closed)."
  (and (agent-workflow--pane-p canvas)
       (not agent-workflow--pane-showing)
       (let ((run (buffer-local-value 'agent-workflow--pane-run canvas)))
         (not (and (buffer-local-value 'agent-workflow--pane-open canvas)
                   (or (eq (agent-workflow-run-state run) 'waiting)
                       (agent-workflow--pane-asks-p canvas)))))))

(defun agent-workflow--pane-asks-p (canvas)
  "Whether a question waits in CANVAS (an agent's, in its section)."
  (and (fboundp 'agent-ui-ask-waiting-p)
       (with-current-buffer canvas
         (seq-some (lambda (key) (agent-ui-ask-waiting-p (agent-ui--entry-element (gethash key agent-ui--entries))))
                   agent-ui--order))))

(defun agent-workflow-pane (run &optional show)
  "RUN's pane: made (drawn from its state, journal and log) if it has none.
SHOW: shown if it's in no window, opening by itself from now on; `select':
its window selected too."
  (let ((pane (or (agent-workflow--pane-live run) (agent-workflow--pane-make run))))
    (when show
      (with-current-buffer pane (setq agent-workflow--pane-open t))
      (unless (get-buffer-window pane t)
        (let ((agent-workflow--pane-showing t))
          (funcall agent-ui-display-function pane)))
      (when-let* (((eq show 'select))
                  (window (get-buffer-window pane t)))
        (select-frame-set-input-focus (window-frame window))
        (select-window window)))
    pane))

(defun agent-workflow--pane-make (run)
  "RUN's pane made, drawn, in no window yet."
  (let* ((agent-ui-display-function #'ignore)
         (pane (agent-ui-canvas (agent-workflow-run-name run))))
    (setf (agent-workflow-run-pane run) pane)
    (with-current-buffer pane
      (setq agent-workflow--pane-run run
            agent-workflow--pane-times (make-hash-table :test #'equal)
            agent-workflow--pane-asked nil
            agent-workflow--pane-ended nil)
      (setq-local agent-ui-answer-function #'agent-workflow--pane-answer
                  agent-ui-closes-with "run/jobs")
      (add-hook 'kill-buffer-hook #'agent-workflow--pane-killed nil t)
      (dolist (event (agent-workflow--journal-events (agent-workflow-run-dir run)))
        (agent-workflow--pane-time (plist-get event :ev) event
                                   (or (ignore-errors (float-time (date-to-time (plist-get event :t))))
                                       (float-time)))))
    (agent-ui-section pane "run" :title "Run")
    (agent-ui-section pane "log" :title "Log")
    (agent-ui-show (list :id "log" :type "log" :show 12 :keep agent-workflow-pane-log-lines
                         :lines (agent-workflow-log-lines run agent-workflow-pane-log-lines))
                   :canvas pane :section "log")
    (agent-workflow--pane-draw run t)
    pane))

(defun agent-workflow--pane-killed ()
  "A run's pane killed (q): its run has none, until you look again."
  (when agent-workflow--pane-run
    (when (eq (agent-workflow-run-pane agent-workflow--pane-run) (current-buffer))
      (setf (agent-workflow-run-pane agent-workflow--pane-run) nil))))

;; ====== WHEN ======

(defun agent-workflow--pane-time (event data time)
  "EVENT of the pane's run, with DATA, at TIME (seconds): its jobs' and
steps' times noted."
  (let* ((job (plist-get data :job))
         (index (plist-get data :step))
         (times (and job (gethash job agent-workflow--pane-times))))
    (cl-flet ((step-set (key)
                (let ((steps (plist-get times :steps)))
                  (setf (alist-get index steps) (plist-put (alist-get index steps) key time))
                  (when (eq key :started)
                    (setf (alist-get index steps) (plist-put (alist-get index steps) :ended nil)))
                  (setq times (plist-put times :steps steps)))))
      (pcase event
        ("job-started" (setq times (list :started time)))
        ("job-done" (setq times (plist-put times :ended time)))
        ("step-started" (when (numberp index) (step-set :started)))
        ((or "step-ended" "script-ended" "step-skipped") (when (numberp index) (step-set :ended))))
      (when job
        (puthash job times agent-workflow--pane-times)))))

(defun agent-workflow--pane-journal (run event data)
  "EVENT of RUN with DATA, in its journal: its pane's times noted. In
`agent-workflow-journal-functions'."
  (when-let* ((pane (agent-workflow--pane-live run)))
    (with-current-buffer pane
      (agent-workflow--pane-time event data (float-time)))))

(add-hook 'agent-workflow-journal-functions #'agent-workflow--pane-journal)

;; ====== WHAT IT SHOWS ======

(defun agent-workflow--pane-where-lines (where)
  "WHERE (`agent-workflow-run-where') in words, the header's lines: its
branch, its commits, what isn't committed; where it started, what it merges
into."
  (when-let* ((branch (plist-get where :branch)))
    (let* ((base (plist-get where :base))
           (into (plist-get where :into))
           (own (or (plist-get where :own) 0))
           (uncommitted (or (plist-get where :uncommitted) 0))
           (merged (plist-get where :merged))
           (said (delq nil (list (pcase own
                                   ;; Merged, where it started unknown: its
                                   ;; commits too.
                                   (0 (and (not merged) "no commit yet"))
                                   (1 "1 commit")
                                   (_ (format "%d commits" own)))
                                 (and (> uncommitted 0)
                                      (format "%d %s not committed" uncommitted (if (= uncommitted 1) "file" "files")))
                                 (and (not (plist-get where :worktree)) "its worktree removed")))))
      (list (concat "⎇ " branch
                    (cond ((plist-get where :deleted) ": deleted, its run done")
                          (said (concat ": " (string-join said ", ")))
                          (t "")))
            (concat (if base
                        (format "from %s at %s · " (or (plist-get base :branch) "a detached HEAD")
                                (substring (plist-get base :commit) 0 (min 7 (length (plist-get base :commit)))))
                      "")
                    (format (if merged "merged into %s" "merges into %s") into))))))

(defun agent-workflow--pane-where (run where)
  "RUN's WHERE (`agent-workflow-run-where') as elements under its header:
its worktree and its reading jobs' snapshots (RET opens one), its base
branch's commits its merge takes too, said. Their ids, all of them: where,
where-note, nil each one not shown."
  (let* ((project (agent-workflow-run-project run))
         (worktree (plist-get where :worktree))
         (base (plist-get where :base))
         (with (or (plist-get where :with) 0))
         (files (append (when worktree
                          (list (list :path (file-relative-name worktree project) :note "its worktree")))
                        (mapcar (lambda (snapshot)
                                  (list :path (file-relative-name (nth 1 snapshot) project)
                                        :note (format "%s's snapshot, at %s" (nth 0 snapshot)
                                                      (substring (or (nth 2 snapshot) "") 0
                                                                 (min 7 (length (or (nth 2 snapshot) "")))))))
                                (plist-get where :snapshots)))))
    (list (and files (list :id "where" :type "files" :dir project :files files))
          (and (> with 0) (not (plist-get where :merged))
               (list :id "where-note" :type "text" :face "warning"
                     :text (format "Started from %s, not %s: its %d %s not in %s %s merged too."
                                   (plist-get base :branch) (plist-get where :into) with
                                   (if (= with 1) "commit" "commits") (plist-get where :into)
                                   (if (= with 1) "is" "are")))))))

(defun agent-workflow--pane-header (run)
  "The run, above its sections: its issue, its state, its time, its budget,
where its work is."
  (let* ((info (agent-workflow-run-info run))
         (state (agent-workflow-run-state run))
         (spent (agent-workflow-run-spent-now run))
         (budget (agent-workflow-run-budget run))
         (time (agent-workflow--duration-words (plist-get spent :time))))
    (list :id "run" :type "text"
          :title (format "%s: %s" (agent-workflow-run-issue run) (or (plist-get info :title) ""))
          :face (pcase state ('waiting "warning") ('cancelled "muted") ('done "success") (_ "plain"))
          :text (string-join
                 (append
                  (delq nil
                        (list (format "%s · %s · %s"
                                      (plist-get (agent-workflow-run-workflow run) :name)
                                      (pcase state
                                        ('waiting "waits for you")
                                        ('queued (concat "queued" (if (agent-workflow-run-why run)
                                                                      (concat ": " (agent-workflow-run-why run))
                                                                    "")))
                                        (_ (symbol-name state)))
                                      time)
                              (cond (budget (concat "spent " (agent-workflow--budget-words spent budget)
                                                    (if (agent-workflow-run-warned run) " · near its budget" "")))
                                    ((> (plist-get spent :cost) 0)
                                     (format "spent $%.2f, %s tokens" (plist-get spent :cost)
                                             (agent-ui-format-compact (plist-get spent :tokens)))))))
                  (agent-workflow--pane-where-lines (agent-workflow-run-where run)))
                 "\n"))))

(defun agent-workflow--pane-step-name (step)
  "STEP of a job (a plist), as its checklist names it."
  (pcase (plist-get step :kind)
    ('agent (format "agent: %s" (plist-get step :agent)))
    ('run (format "run: %s" (truncate-string-to-width
                             (car (split-string (string-trim (format "%s" (plist-get step :run))) "\n"))
                             40 nil nil "…")))
    ('elisp "elisp")
    ('uses (format "uses: %s" (plist-get step :uses)))
    (_ "a step")))

(defun agent-workflow--pane-status (status)
  "A job's STATUS as a checklist's."
  (pcase status
    ('running "running") ('done "done") ('skipped "skipped") (_ "pending")))

(defun agent-workflow--pane-timed (item times status)
  "ITEM, a checklist's step, with its TIMES (:started :ended) for STATUS
\(its checklist's): its start while it runs, how long it took once done."
  (let ((started (plist-get times :started))
        (ended (plist-get times :ended)))
    (cond ((and started (equal status "running")) (append item (list :started started)))
          ((and started ended (equal status "done")) (append item (list :seconds (max 0 (- ended started)))))
          (t item))))

(defun agent-workflow--pane-job (run job state)
  "JOB of RUN in STATE as a step of its checklist, its steps under it."
  (let* ((spec (agent-workflow--job-spec run job))
         (steps (plist-get spec :steps))
         (status (plist-get state :status))
         (index (or (plist-get state :step) 0))
         (times (gethash job agent-workflow--pane-times))
         (agent (seq-find (lambda (step) (eq (plist-get step :kind) 'agent)) steps))
         (tries (alist-get index (plist-get state :tries)))
         (outcome (plist-get state :outcome))
         (detail (string-join
                  (delq nil (list (and agent (format "agent %s" (plist-get agent :agent)))
                                  (and (numberp (plist-get state :round)) (> (plist-get state :round) 1)
                                       (format "round %d" (plist-get state :round)))
                                  (and (numberp tries) (> tries 0) (memq status '(running waiting))
                                       (format "try %d" (1+ tries)))
                                  (and (eq status 'done) outcome (not (equal outcome "done")) outcome)
                                  (and (eq status 'waiting) "◆ needs you")
                                  (and (eq status 'pending) (plist-get state :why)
                                       (format "waits: %s" (plist-get state :why)))))
                  " · "))
         (mapped (agent-workflow--pane-status status))
         (item (list :name job :status mapped)))
    (unless (string-empty-p detail)
      (setq item (append item (list :detail detail))))
    (setq item (agent-workflow--pane-timed item times mapped))
    (if (not (cdr steps))
        item
      (append item
              (list :steps
                    (cl-loop for step in steps for i from 0
                             collect (let ((sub (cond ((memq status '(done skipped)) (if (eq status 'done) "done" "skipped"))
                                                      ((memq status '(running waiting))
                                                       (cond ((< i index) "done")
                                                             ((= i index) (if (eq status 'running) "running" "pending"))
                                                             (t "pending")))
                                                      (t "pending"))))
                                       (agent-workflow--pane-timed
                                        (list :name (agent-workflow--pane-step-name step) :status sub)
                                        (alist-get i (plist-get times :steps)) sub))))))))

(defun agent-workflow--pane-jobs (run over)
  "RUN's checklist: its jobs. OVER: the run over already when its pane was
made (not closed by its countdown: you looked at it)."
  (list :id "jobs" :type "steps" :close (if over :false t)
        :steps (mapcar (lambda (job) (agent-workflow--pane-job run (car job) (cdr job)))
                       (agent-workflow-run-jobs run))))

;; ====== NEEDS YOU ======

(defun agent-workflow--pane-question (run job ask why)
  "What RUN asks you of JOB (ASK, its question: nil, a wait with none), WHY
in words: Agent UI elements, the question first (its id ask), what to look
at with it."
  (let ((kind (plist-get ask :kind)))
    (cond
     ((and ask (null kind))
      ;; The loop guard: what now, a note for each.
      (let ((other (plist-get ask :other)))
        (list (list :id "ask" :type "form" :title "The loop guard" :question why
                    :fields (list (list :name "choice" :label "What now" :type "select" :required t
                                        :options '("go on" "accept it as it is" "stop") :value "go on")
                                  (list :name "note-job" :label (format "Note for %s (it sends it back)" job))
                                  (list :name "note-other" :label (format "Note for %s (it's sent back)" other))))
              (when-let* ((notes (append (plist-get ask :notes) nil)))
                (list :id "rounds" :type "text" :with "ask" :face "muted"
                      :text (mapconcat (lambda (note) (format "· %s" note)) notes "\n"))))))
     ((eq kind 'budget)
      (list (list :id "ask" :type "form" :title "Its budget" :question why
                  :fields '((:name "choice" :label "What now" :type "select" :required t
                                   :options ("go on, with more" "stop") :value "go on, with more")
                            (:name "cost" :label "More dollars" :type "number" :min 0)
                            (:name "tokens" :label "More tokens" :type "integer" :min 0)
                            (:name "time" :label "More time (45m, 1h)")))))
     (t
      (let ((options (pcase kind
                       ('approve '("Approve" "Reject"))
                       ((or 'retries 'broke 'interrupted) '("Go on" "Skip its step" "Stop"))
                       ((or 'merge 'moved 'protected) '("Go on" "Stop"))
                       ('closed '("Go on (the issue in progress again)" "Cancel the run"))
                       (_ '("Run its step again" "Cancel the run")))))
        (cons (list :id "ask" :type "choice" :question why :options options
                    :note (if (memq kind '(approve retries)) t (if ask :false t)))
              (when (eq kind 'approve)
                (let ((look (agent-workflow-to-look-at run job)))
                  (list (list :id "look" :type "text" :with "ask"
                              :text (string-join
                                     (delq nil (list (format "Outcome: %s" (or (plist-get look :outcome) "done"))
                                                     (and (plist-get look :notes) (concat "Notes: " (plist-get look :notes)))
                                                     (and (plist-get look :diff) (not (string-empty-p (plist-get look :diff)))
                                                          (concat "Its changes:\n" (plist-get look :diff)))
                                                     (and (plist-get look :log) (concat "Its script's output: "
                                                                                       (abbreviate-file-name (plist-get look :log))))))
                                     "\n")))))))))))

(defconst agent-workflow--pane-go-to-it "Go to it (its session, at the question)"
  "The option of an agent's question in Needs you showing its session.")

(defun agent-workflow--pane-agent-question (run job asks why)
  "What JOB of RUN's agent asks you in its session (ASKS, as
`agent-workflow-agent-asking' has it), WHY in words: a choice, a
permission's options agent-shell's own buttons, and Go to it."
  (let* ((agent (plist-get (agent-workflow--job run job) :agent))
         (buffer (and agent (agent-workflow-agent-buffer agent)))
         (buttons (and (eq (plist-get asks :kind) 'permission)
                       (buffer-live-p buffer)
                       (fboundp '+my/agent-shell-permission-buttons)
                       (mapcar #'car (+my/agent-shell-permission-buttons buffer)))))
    (list (list :id "ask" :type "choice" :question why :note :false
                :options (append buttons (list agent-workflow--pane-go-to-it))))))

(defun agent-workflow--pane-answer-agent (run job kind picked)
  "JOB of RUN's agent's question (KIND: permission, question) answered in
its pane with PICKED: a permission's button pressed, or its session shown
at the question (asked again here: it still is)."
  (let* ((agent (plist-get (agent-workflow--job run job) :agent))
         (buffer (and agent (agent-workflow-agent-buffer agent))))
    (unless (buffer-live-p buffer)
      (user-error "%s has no agent working now" job))
    (if (equal picked agent-workflow--pane-go-to-it)
        (progn
          (agent-workflow--pane-open-session run job)
          (with-current-buffer buffer
            (ignore-errors
              (if (eq kind 'permission)
                  (agent-shell-jump-to-latest-permission-button-row)
                (agent-shell-elicitation-jump-to-latest-form))))
          (agent-workflow--pane-changed run))
      (unless (and (fboundp '+my/agent-shell-press-permission)
                   (+my/agent-shell-press-permission buffer picked))
        (user-error "%s's agent no longer asks that" job)))))

(defun agent-workflow--pane-needs (run pane)
  "RUN's Needs you, in PANE: shown while it waits for you (its question,
shown again only when it's another), gone once it doesn't."
  (with-current-buffer pane
    (let* ((waiting (eq (agent-workflow-run-state run) 'waiting))
           (asking (agent-workflow-asking run))
           (agent-asking (and (not asking) (agent-workflow-agent-asking run)))
           (job (or (car asking)
                    (car agent-asking)
                    (car (seq-find (lambda (job) (eq (plist-get (cdr job) :status) 'waiting))
                                   (agent-workflow-run-jobs run)))))
           (ask (cdr asking))
           (why (or (and job (plist-get (agent-workflow--job run job) :why)) (agent-workflow-run-why run)))
           (asked (and waiting job (list job (cond (ask (or (plist-get ask :kind) 'guard))
                                                   (agent-asking 'agent))
                                         why))))
      (cond
       ((not asked)
        (when (agent-ui--find-section "needs-you")
          (agent-ui-remove-section pane "needs-you"))
        (setq agent-workflow--pane-asked nil))
       ((not (equal asked agent-workflow--pane-asked))
        (if (agent-ui--find-section "needs-you")
            (agent-ui-clear :canvas pane :section "needs-you")
          (agent-ui-section pane "needs-you" :title "Needs you" :state 'needs-you :after "run"))
        (agent-ui-section pane "needs-you" :note job)
        (setq agent-workflow--pane-asked asked)
        (dolist (element (if agent-asking
                             (agent-workflow--pane-agent-question run job (cdr agent-asking) why)
                           (agent-workflow--pane-question run job ask why)))
          (agent-ui-show element :canvas pane :section "needs-you")))))))

(defun agent-workflow--pane-answer (_prompt _submit key)
  "A question of a run's pane answered (`agent-ui-answer-function'): its
answer, read from its element (KEY's), given to the run (approved,
rejected, confirmed, sent back, cancelled) once the answer's own command is
done (it marks its question answered first). An answer that can't be
given: said, the question left as it was."
  (let* ((run agent-workflow--pane-run)
         (pane (current-buffer))
         (element (agent-ui-get key :canvas pane))
         (asked agent-workflow--pane-asked)
         (job (car asked))
         (kind (nth 1 asked))
         (by "you, in its pane")
         (give (agent-workflow--pane-answer-action run job kind element by)))
    (unless (and run asked (equal (agent-ui--key-section key) "needs-you"))
      (user-error "This run asks nothing here"))
    ;; Answered: the next question shown, even if it's the same again.
    (setq agent-workflow--pane-asked nil)
    (run-at-time 0 nil (lambda ()
                         (condition-case err
                             (funcall give)
                           (error (message "%s: %s" (agent-workflow-run-name run) (error-message-string err))
                                  (when (buffer-live-p pane)
                                    (agent-workflow--pane-changed run))))))))

(defun agent-workflow--pane-answer-action (run job kind element by)
  "What answering RUN's question on JOB (KIND: its :ask's, `guard' for the
loop guard's, `agent' for its agent's, nil for a wait with no question) with
ELEMENT (the question,
answered) does: a function of no argument, BY you. A user error if the
answer can't be given (nothing chosen, a rejection without a note)."
  (if (equal (plist-get element :type) "form")
      (let* ((values (plist-get element :values))
             (choice (plist-get values :choice))
             (text (lambda (key) (let ((value (plist-get values key)))
                                   (and (stringp value) (not (string-blank-p value)) (string-trim value))))))
        (if (eq kind 'budget)
            (let ((more (list :cost (let ((n (plist-get values :cost))) (and (numberp n) n))
                              :tokens (let ((n (plist-get values :tokens))) (and (numberp n) n))
                              :time (let ((time (funcall text :time)))
                                      (and time (agent-workflow--duration time))))))
              (if (equal choice "stop")
                  (lambda () (agent-workflow-confirm run "stop" :by by))
                (lambda () (agent-workflow-confirm run "go" :by by :more more))))
          (let* ((other (plist-get (cdr (agent-workflow-asking run)) :other))
                 (notes (delq nil (list (and (funcall text :note-job) (cons job (funcall text :note-job)))
                                        (and (funcall text :note-other) (cons other (funcall text :note-other))))))
                 (choice (pcase choice ("accept it as it is" "accept") ("stop" "stop") (_ "go"))))
            (lambda () (agent-workflow-confirm run choice :by by :notes notes)))))
    (let* ((picked (car (plist-get element :selected)))
           (note (let ((note (plist-get element :note-text)))
                   (and (stringp note) (not (string-blank-p note)) (string-trim note)))))
      (unless picked
        (user-error "Choose one first"))
      (pcase kind
        ('agent
         (let ((asks (plist-get (agent-workflow--job run job) :agent-asks)))
           (lambda () (agent-workflow--pane-answer-agent run job (plist-get asks :kind) picked))))
        ('approve
         (if (equal picked "Approve")
             (lambda () (agent-workflow-approve run :by by))
           (unless note (user-error "Say why in a note: the agent's told it"))
           (lambda () (agent-workflow-reject run note :by by))))
        ('nil
         (if (string-prefix-p "Cancel" picked)
             (lambda () (agent-workflow-cancel run :by by))
           (lambda () (agent-workflow-back run job :step (or (plist-get (agent-workflow--job run job) :step) 0)
                                           :note note :by by))))
        (_
         (let ((choice (cond ((string-prefix-p "Go on" picked) "go")
                             ((string-prefix-p "Skip" picked) "skip")
                             ((string-prefix-p "Cancel" picked) "cancel")
                             (t "stop"))))
           (lambda () (agent-workflow-confirm run choice :by by :notes (and note (list (cons job note)))))))))))

;; ====== ITS AGENTS ======

(defun agent-workflow--pane-section (job)
  "The section of JOB's agent: job.JOB (a job's name has no dot)."
  (concat "job." job))

(defun agent-workflow--pane-agents (run pane)
  "RUN's jobs' agents in PANE: a section each, its session's canvas shown
there; a job over, its section folded once, its mark done."
  (with-current-buffer pane
    (dolist (job (agent-workflow-run-jobs run))
      (let* ((name (car job))
             (state (cdr job))
             (status (plist-get state :status))
             (agent (plist-get state :agent))
             (section (agent-workflow--pane-section name))
             (times (gethash name agent-workflow--pane-times))
             (started (plist-get times :started))
             (note (and started (agent-workflow--duration-words
                                 (round (- (or (and (memq status '(done skipped)) (plist-get times :ended))
                                               (float-time))
                                           started)))))
             (mark (pcase status ('running 'running) ('waiting 'needs-you) ('done 'done) ('skipped 'done) (_ 'waiting))))
        (when (and agent (not (agent-ui--find-section section)))
          (agent-ui-section pane section :title name :state mark :note note
                            :after (or (car (last (seq-filter (lambda (s) (string-prefix-p "job." s))
                                                              (mapcar #'agent-ui--section-name agent-ui--sections))))
                                       (and (agent-ui--find-section "needs-you") "needs-you")
                                       "run")
                            :open (lambda () (agent-workflow--pane-open-session run name))))
        (when (agent-ui--find-section section)
          (agent-ui-section pane section :state mark :note note)
          ;; Its session's canvas, shown here.
          (when-let* ((buffer (and agent (agent-workflow-agent-buffer agent)))
                      ((buffer-live-p buffer))
                      ((fboundp 'agent-ui--session-name))
                      (canvas (agent-ui--session-name buffer))
                      ((not (equal (agent-ui--section-hosts (agent-ui--find-section section)) canvas))))
            (agent-ui-host canvas pane section))
          ;; Over: folded, once; running again (sent back), unfolded.
          (cond ((and (memq status '(done skipped)) (not (member name agent-workflow--pane-ended)))
                 (push name agent-workflow--pane-ended)
                 (agent-ui-section pane section :folded t))
                ((and (eq status 'running) (member name agent-workflow--pane-ended))
                 (setq agent-workflow--pane-ended (delete name agent-workflow--pane-ended))
                 (agent-ui-section pane section :folded nil))))))))

(defun agent-workflow--pane-open-session (run job)
  "JOB of RUN's agent's session shown (RET on its section's divider)."
  (let ((agent (plist-get (agent-workflow--job run job) :agent)))
    (if-let* ((buffer (and agent (agent-workflow-agent-buffer agent)))
              ((buffer-live-p buffer)))
        (pop-to-buffer buffer)
      (user-error "%s has no agent working now" job))))

;; ====== DRAWING IT ======

(defun agent-workflow--pane-draw (run &optional made)
  "RUN's pane drawn again from RUN: its header, its jobs, Needs you, its
agents' sections. MADE: just made (the run over already: not closed by its
countdown)."
  (when-let* ((pane (agent-workflow--pane-live run)))
    (with-current-buffer pane
      (agent-workflow--pane-draw-in run pane made))))

(defun agent-workflow--pane-show-where (run pane)
  "RUN's where under its header in PANE (`agent-workflow--pane-where'):
each element shown, or removed once it isn't."
  (cl-loop for id in '("where" "where-note")
           for element in (agent-workflow--pane-where run (agent-workflow-run-where run))
           do (cond (element (agent-ui-show element :canvas pane))
                    ;; The canvas's own: its key its id.
                    ((gethash id agent-ui--entries) (agent-ui-remove id :canvas pane)))))

(defun agent-workflow--pane-where-tick ()
  "Where the work of each run not over with a pane is looked at again: its
pane drawn again if it changed (a commit, files changed between its run's
events). Stopped once there's none."
  (let ((any nil))
    (dolist (run agent-workflow--runs)
      (when-let* (((not (memq (agent-workflow-run-state run) agent-workflow--ended)))
                  (pane (agent-workflow--pane-live run)))
        (setq any t)
        (with-demoted-errors "agent workflow's pane: %S"
          (unless (equal (agent-workflow-run-where run) (buffer-local-value 'agent-workflow--pane-where-shown pane))
            (agent-workflow--pane-draw run)))))
    (unless any
      (when (timerp agent-workflow--pane-where-timer)
        (cancel-timer agent-workflow--pane-where-timer))
      (setq agent-workflow--pane-where-timer nil))))

(defun agent-workflow--pane-draw-in (run pane made)
  "RUN's PANE drawn again, PANE's buffer current (see
`agent-workflow--pane-draw')."
  (let ((agent-ui-display-function (if made #'ignore agent-ui-display-function)))
      (setq agent-workflow--pane-where-shown (agent-workflow-run-where run))
      (agent-ui-show (agent-workflow--pane-header run) :canvas pane)
      (agent-workflow--pane-show-where run pane)
      (unless (or (memq (agent-workflow-run-state run) agent-workflow--ended)
                  (timerp agent-workflow--pane-where-timer))
        (setq agent-workflow--pane-where-timer
              (run-at-time agent-workflow-pane-where-every agent-workflow-pane-where-every
                           #'agent-workflow--pane-where-tick)))
      (agent-ui-show (agent-workflow--pane-jobs run (and made (memq (agent-workflow-run-state run) agent-workflow--ended)))
                     :canvas pane :section "run")
      (agent-ui-section pane "run" :state (pcase (agent-workflow-run-state run)
                                            ('running 'running) ('waiting 'needs-you) ('queued 'waiting)
                                            ('done 'done) ('cancelled 'failed)))
      (agent-workflow--pane-needs run pane)
      (agent-workflow--pane-agents run pane)))

(defun agent-workflow--pane-changed (run)
  "RUN changed: its pane drawn again, if it has one. In
`agent-workflow-run-functions'."
  (when (agent-workflow--pane-live run)
    (with-demoted-errors "agent workflow's pane: %S"
      (agent-workflow--pane-draw run))))

(add-hook 'agent-workflow-run-functions #'agent-workflow--pane-changed)

(defun agent-workflow--pane-log (run line)
  "LINE in RUN's log: its pane's Log shows it. In
`agent-workflow-log-functions'."
  (when-let* ((pane (agent-workflow--pane-live run)))
    (with-demoted-errors "agent workflow's pane: %S"
      (agent-ui-append "log" (list :lines (list line)) :canvas pane :section "log"))))

(add-hook 'agent-workflow-log-functions #'agent-workflow--pane-log)

(defun agent-workflow--pane-started (run shell)
  "RUN started: its pane opened, unless from the SHELL. In
`agent-workflow-started-functions'."
  (unless (or shell (not (fboundp 'agent-ui-canvas)))
    (agent-workflow-pane run t)))

(add-hook 'agent-workflow-started-functions #'agent-workflow--pane-started)
