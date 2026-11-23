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
;; Started from Emacs (M-x agent-workflow-run-ticket, agent-workflow-run),
;; its pane opens; from the shell, it's made when you look (M-x
;; agent-workflow-runs, RET), and opens
;; by itself only once you did. Done, failed, cancelled, waiting: it stays,
;; until you close it (q); nothing counts down to close it (what it showed
;; went with it). Closing it stops nothing.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar agent-workflow-pane-log-lines)
(defvar agent-ui-answer-function)
(defvar agent-ui-display-function)
(defvar agent-ui--entries)
(declare-function agent-ui--session-name "agent-ui/agent")
(declare-function agent-workflow--uses-merge-p "agent-workflow/dry")
(declare-function agent-workflow-agent-p "agent-workflow/pool")
(declare-function agent-workflow-cancel-asked "agent-workflow/resume")
(declare-function agent-workflow--where-stamp "agent-workflow/runs")
(declare-function agent-workflow-agent-profile "agent-workflow/pool")
(declare-function agent-shell-jump-to-latest-permission-button-row "agent-shell")
(declare-function agent-shell-elicitation-jump-to-latest-form "agent-shell-elicitation")
(declare-function agent-shell-elicitation--get "agent-shell-elicitation")
(declare-function agent-shell-elicitation--set-values "agent-shell-elicitation")
(declare-function agent-shell-elicitation--clearing "agent-shell-elicitation")
(declare-function agent-shell-elicitation--submit "agent-shell-elicitation")
(defvar agent-shell--state)
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

(defvar-local agent-workflow--pane-rounds nil
  "In a run's pane: its jobs' rounds, from its journal, the first first:
plists (:job :round :start :end :outcome), END nil while it runs.")

(defvar-local agent-workflow--pane-notes nil
  "In a run's pane: its agents' notes, from its journal, in order:
plists (:job :round :outcome :time :text).")

(defvar-local agent-workflow--pane-asked nil
  "In a run's pane: the question its Needs you shows, (JOB KIND WHY).")

(defvar-local agent-workflow--pane-where-shown nil
  "In a run's pane: where its work is, as its header shows it
\(`agent-workflow-run-where').")

(defvar-local agent-workflow--pane-where-stamp nil
  "In a run's pane: its place's stamp as last looked at
\(`agent-workflow--where-stamp'), while its run waits for you.")

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

(defun agent-workflow--pane-name (run)
  "RUN's pane's name, its own: its name (ISSUE · WORKFLOW), its number
after it past its issue's first run (ISSUE · WORKFLOW · run 2): two runs of
an issue never share a pane (one drawing over the other, its buttons
answering the other)."
  (if (and (agent-workflow-run-ticket-p run) (> (or (agent-workflow-run-n run) 1) 1))
      (format "%s · run %d" (agent-workflow-run-name run) (agent-workflow-run-n run))
    (agent-workflow-run-name run)))

(defun agent-workflow--pane-make (run)
  "RUN's pane made, drawn, in no window yet."
  (let* ((agent-ui-display-function #'ignore)
         (pane (agent-ui-canvas (agent-workflow--pane-name run)))
         (lines nil))
    (setf (agent-workflow-run-pane run) pane)
    (with-current-buffer pane
      (setq agent-workflow--pane-run run
            agent-workflow--pane-times (make-hash-table :test #'equal)
            agent-workflow--pane-rounds nil
            agent-workflow--pane-notes nil
            agent-workflow--pane-asked nil
            agent-workflow--pane-ended nil)
      (setq-local agent-ui-answer-function #'agent-workflow--pane-answer
                  ;; An agent's elements finished (its plan done) stay: no
                  ;; countdown closing them (one giving its own :close, it).
                  agent-ui-close-finished nil)
      (add-hook 'kill-buffer-hook #'agent-workflow--pane-killed nil t)
      ;; Its times, rounds and Log's lines, event by event (a job done: how
      ;; long its round took, its round's start then).
      (dolist (event (agent-workflow--journal-events (agent-workflow-run-dir run)))
        (let ((time (or (ignore-errors (date-to-time (plist-get event :t))) (current-time))))
          (agent-workflow--pane-time (plist-get event :ev) event (float-time time))
          (when-let* ((line (agent-workflow--pane-log-line run (plist-get event :ev) event time)))
            (push line lines)))))
    (agent-ui-section pane "run" :title "Run")
    (agent-ui-section pane "log" :title "Log")
    (agent-ui-show (list :id "log" :type "log" :show 12 :keep agent-workflow-pane-log-lines
                         :lines (last (nreverse lines) agent-workflow-pane-log-lines))
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
      (agent-workflow--pane-round event data time)
      ;; An agent's notes, as it ended its step.
      (when-let* (((equal event "step-ended"))
                  (text (plist-get data :notes))
                  ((stringp text))
                  ((not (string-blank-p text))))
        (setq agent-workflow--pane-notes
              (append agent-workflow--pane-notes
                      (list (list :job job :time time :text (string-trim text)
                                  :outcome (plist-get data :outcome)
                                  :round (plist-get (car (last (seq-filter (lambda (round) (equal (plist-get round :job) job))
                                                                           agent-workflow--pane-rounds)))
                                                    :round))))))
      (pcase event
        ("job-started" (setq times (list :started time)))
        ("job-done" (setq times (plist-put times :ended time)))
        ;; Sent back: the jobs replaced not started (their sections' time
        ;; counting from their next start, not the last).
        ("went-back"
         (dolist (name (append (plist-get data :replaced) nil))
           (unless (equal name job)
             (remhash name agent-workflow--pane-times))))
        ;; Its run over: when its jobs running stopped (their section's time).
        ((or "cancelled" "failed")
         (dolist (name (append (plist-get data :jobs) (plist-get data :cancelled) nil))
           (when-let* ((times (gethash name agent-workflow--pane-times)))
             (puthash name (plist-put times :cancelled time) agent-workflow--pane-times))))
        ("step-started" (when (numberp index) (step-set :started)))
        ((or "step-ended" "script-ended" "step-skipped") (when (numberp index) (step-set :ended))))
      (when job
        (puthash job times agent-workflow--pane-times)))))

(defun agent-workflow--pane-journal (run event data)
  "EVENT of RUN with DATA, in its journal: its pane's times noted, its line
in its Log. In `agent-workflow-journal-functions'."
  (when-let* ((pane (agent-workflow--pane-live run)))
    (with-current-buffer pane
      (agent-workflow--pane-time event data (float-time))
      (when-let* ((line (agent-workflow--pane-log-line run event data (current-time))))
        (with-demoted-errors "agent workflow's pane: %S"
          (agent-ui-append "log" (list :lines (list line)) :canvas pane :section "log"))))))

;; THE LOG: the run's journal as log.el says it (log.txt, the shell's), but
;; shorter, in its own pane: no issue on each line, its time HH:MM, its job's
;; name in a column; a job's agent step starting and ending left out (its
;; job's start and end say it), a job done saying how long it took; a wait
;; saying what for (not how to answer from the shell), a warning; what went
;; wrong, an error.

(defconst agent-workflow--pane-log-errors
  '("cancelled" "failed" "budget-used-up" "interrupted" "branch-moved")
  "The events a run's pane's Log says as errors.")

(defconst agent-workflow--pane-log-warnings
  '("waiting" "budget-near" "branch-kept")
  "The events a run's pane's Log says as warnings.")

(defun agent-workflow--pane-log-line (run event data time)
  "EVENT of RUN with DATA at TIME (a Lisp time) as a line of its pane's Log
\(see above): text, or (:level LEVEL :text TEXT); nil if it says nothing
there. In the pane's buffer: a job's times its `agent-workflow--pane-times'."
  (let* ((job (if (equal event "rerun")
                  ;; Sent back: the job it's sent to, by the one sending it.
                  (or (cadr (split-string (or (plist-get data :edge) "") ">")) (plist-get data :job))
                (plist-get data :job)))
         (step (plist-get data :step))
         (spec (and job (agent-workflow--job-spec run job)))
         (kind (and (numberp step) (plist-get (nth step (plist-get spec :steps)) :kind)))
         (what (cond
                ;; Its job's start and end say it.
                ((and (member event '("step-started" "step-ended")) (eq kind 'agent)) nil)
                ((equal event "waiting")
                 (concat "waits for you: "
                         (let ((why (or (plist-get data :why) "")))
                           (if (and job (string-prefix-p (concat job ": ") why))
                               (substring why (+ (length job) 2))
                             why))))
                ((equal event "job-done")
                 (let* ((times (and job (gethash job agent-workflow--pane-times)))
                        (started (plist-get times :started))
                        (ended (or (plist-get times :ended) (float-time time))))
                   (concat (agent-workflow--log-what (agent-workflow-run-issue run) event data 'none)
                           (if started
                               (format " (%s)" (agent-workflow--duration-words (round (max 0 (- ended started)))))
                             ""))))
                (t (agent-workflow--log-what (agent-workflow-run-issue run) event data 'none))))
         (width (apply #'max 1 (mapcar (lambda (job) (length (car job))) (agent-workflow-run-jobs run)))))
    (when what
      (let ((text (format "%s  %s  %s" (format-time-string "%H:%M" time)
                          (string-pad (or job "·") width)
                          (replace-regexp-in-string "[\n\r]+" " " what))))
        (cond ((member event agent-workflow--pane-log-errors) (list :level "error" :text text))
              ((member event agent-workflow--pane-log-warnings) (list :level "warn" :text text))
              (t text))))))

(add-hook 'agent-workflow-journal-functions #'agent-workflow--pane-journal)

(defun agent-workflow--pane-round (event data time)
  "EVENT of the pane's run, with DATA, at TIME (seconds): its jobs' rounds
noted (`agent-workflow--pane-rounds'). A round started again before its
end (sent back, replaced): replaced; the run over, cancelled: every round
running ended."
  (let ((job (plist-get data :job)))
    (cl-flet ((close (round outcome)
                (unless (plist-get round :end)
                  (plist-put round :end time)
                  (plist-put round :outcome outcome))))
      (pcase event
        ("job-started"
         (dolist (round agent-workflow--pane-rounds)
           (when (equal (plist-get round :job) job) (close round "replaced")))
         (setq agent-workflow--pane-rounds
               (append agent-workflow--pane-rounds
                       (list (list :job job :round (or (plist-get data :round) 1) :start time :end nil)))))
        ("job-done"
         (when-let* ((round (seq-find (lambda (round) (and (equal (plist-get round :job) job)
                                                           (not (plist-get round :end))))
                                      agent-workflow--pane-rounds)))
           (close round (or (plist-get data :outcome) "done"))))
        ;; Its step ended, saying an outcome: kept on its round, said if
        ;; it's closed by its sending the work back.
        ("step-ended"
         (when-let* ((outcome (plist-get data :outcome))
                     (round (seq-find (lambda (round) (and (equal (plist-get round :job) job)
                                                           (not (plist-get round :end))))
                                      agent-workflow--pane-rounds)))
           (plist-put round :said outcome)))
        ;; Sent back: each job replaced its round closed, the one sending it
        ;; back with its outcome (review → changes), the others replaced.
        ("went-back"
         (let ((by (plist-get data :by)))
           (dolist (name (append (plist-get data :replaced) nil))
             (dolist (round agent-workflow--pane-rounds)
               (when (equal (plist-get round :job) name)
                 (close round (or (and (equal name by) (plist-get round :said)) "replaced")))))))
        ((or "run-done" "cancelled" "failed")
         (dolist (round agent-workflow--pane-rounds)
           (close round (if (equal event "run-done") "done" event))))))))

(defun agent-workflow--pane-rounds-element ()
  "The pane's rounds as a timeline (nil before the first): a bar each, its
round past 1 and an outcome other than done said; one running growing;
one ended done (its outcome in its name), replaced or cancelled grey."
  (when agent-workflow--pane-rounds
    (cl-flet ((stamp (time) (format-time-string "%FT%TZ" time t)))
      (list :id "rounds" :type "timeline" :title "Rounds"
            :tasks (mapcar (lambda (round)
                             (let ((outcome (plist-get round :outcome))
                                   (number (plist-get round :round)))
                               (append
                                (list :name (concat (plist-get round :job)
                                                    (if (and (numberp number) (> number 1))
                                                        (format " · round %d" number)
                                                      "")
                                                    (if (and outcome (not (equal outcome "done")))
                                                        (concat " → " outcome)
                                                      ""))
                                      :start (stamp (plist-get round :start))
                                      ;; Ended: done, whatever its outcome (approved,
                                      ;; changes: said in its name); not a failure.
                                      :status (cond ((null (plist-get round :end)) "running")
                                                    ((member outcome '("replaced" "cancelled")) "queued")
                                                    ((equal outcome "failed") "failed")
                                                    (t "done")))
                                (and (plist-get round :end) (list :end (stamp (plist-get round :end)))))))
                           agent-workflow--pane-rounds)))))

(defun agent-workflow--pane-verdict (text)
  "TEXT's verdict, the line a note is in the feed: its first line (its
bold, a list's dash dropped), else its first sentence, 80 characters at
most."
  (let* ((line (string-trim (replace-regexp-in-string
                             "\\*\\*\\|`" "" (replace-regexp-in-string "\\`[-*] " ""
                                                                     (car (split-string (string-trim text) "\n"))))))
         (line (if (and (> (length line) 80)
                        (string-match "\\`\\(.+?[.!?]\\)\\(?:\\s-\\|\\'\\)" line))
                   (match-string 1 line)
                 line)))
    (truncate-string-to-width line 80 nil nil "…")))

(defun agent-workflow--pane-note-name (note)
  "NOTE's job, its round past 1 said: its name in the feed."
  (let ((round (plist-get note :round)))
    (concat (plist-get note :job) (if (and (numberp round) (> round 1)) (format " · round %d" round) ""))))

(defun agent-workflow--pane-notes-element ()
  "The pane's agents' notes as a feed (nil before the first): a line each,
its job (its round past 1), its time, its outcome (not done, nor what its
verdict starts with), its verdict (`agent-workflow--pane-verdict'); its
whole in its agent's section."
  (when agent-workflow--pane-notes
    (let ((seen nil))
      (list :id "notes" :type "steps" :close :false
            :steps (mapcar (lambda (note)
                             (let* ((name (agent-workflow--pane-note-name note))
                                    (name (if (member name seen)
                                              (format "%s (%d)" name (1+ (seq-count (lambda (s) (string-prefix-p name s)) seen)))
                                            name))
                                    (outcome (plist-get note :outcome))
                                    (verdict (agent-workflow--pane-verdict (plist-get note :text))))
                               (push name seen)
                               (list :name name :status "done"
                                     :detail (concat (format-time-string "%H:%M" (plist-get note :time)) " · "
                                                     ;; Its outcome, unless its verdict says it first.
                                                     (if (and outcome (not (equal outcome "done"))
                                                              (not (string-prefix-p (downcase outcome) (downcase verdict))))
                                                         (concat outcome " · ")
                                                       "")
                                                     verdict))))
                           agent-workflow--pane-notes)))))

(defun agent-workflow--pane-job-notes-element (job)
  "JOB's notes, whole (Markdown), for its agent's section; several rounds',
each under its round, outcome and time. Nil if it has none."
  (when-let* ((notes (seq-filter (lambda (note) (equal (plist-get note :job) job)) agent-workflow--pane-notes)))
    (list :id "agent-notes" :type "markdown" :title "Its notes"
          :markdown (if (cdr notes)
                        (mapconcat (lambda (note)
                                     (format "**Round %s** · %s · %s\n\n%s"
                                             (or (plist-get note :round) 1) (or (plist-get note :outcome) "done")
                                             (format-time-string "%H:%M" (plist-get note :time)) (plist-get note :text)))
                                   notes "\n\n")
                      (plist-get (car notes) :text)))))

;; ====== WHAT IT SHOWS ======

(defun agent-workflow--pane-short (commit)
  "COMMIT (a hash) shortened, as git shows it."
  (substring commit 0 (min 7 (length commit))))

(defun agent-workflow--pane-git-line (where)
  "WHERE (`agent-workflow-run-where')'s branch, in a line: ⎇ BRANCH, where
it started → what it merges into (merged, deleted once it is); nil if it
has none yet."
  (when-let* ((branch (plist-get where :branch)))
    (let ((base (plist-get where :base))
          (into (plist-get where :into)))
      (concat "⎇ " branch "   "
              (cond ((plist-get where :checkout)
                     ;; Your checkout: no branch of its own, nothing merged.
                     (concat "your checkout"
                             (if base (format ", from %s" (agent-workflow--pane-short (plist-get base :commit))) "")
                             (let ((own (or (plist-get where :own) 0)))
                               (if (> own 0) (format " · %d commit%s since" own (if (= own 1) "" "s")) ""))))
                    ((and (plist-get where :deleted) (plist-get where :empty)) "no commit · deleted")
                    ((plist-get where :deleted) (format "deleted, merged into %s" into))
                    ((plist-get where :merged) (format "merged into %s" into))
                    (base (format "%s@%s → %s" (or (plist-get base :branch) "HEAD")
                                  (agent-workflow--pane-short (plist-get base :commit)) into))
                    (t (format "→ %s" into)))
              (if (or (plist-get where :worktree) (plist-get where :deleted) (plist-get where :checkout))
                  ""
                " · its worktree removed")
              (mapconcat (lambda (snapshot)
                           (format "\n%s reads its snapshot at %s" (nth 0 snapshot)
                                   (agent-workflow--pane-short (or (nth 2 snapshot) ""))))
                         (plist-get where :snapshots) "")))))

(defun agent-workflow--pane-git (run where)
  "RUN's WHERE (`agent-workflow-run-where') as the elements under its
header, each nil if it isn't shown: git (its branch, buttons opening its
worktree, magit), changes (its files changed since it started: RET opens
one), commits (its latest), where-note (its base branch's commits its
merge takes too)."
  (let* ((line (agent-workflow--pane-git-line where))
         (worktree (plist-get where :worktree))
         (files (plist-get where :files))
         (commits (plist-get where :commits))
         (base (plist-get where :base))
         (with (or (plist-get where :with) 0)))
    (ignore run)
    (list (and line
               (append (list :id "git" :type "text" :text line)
                       (when worktree
                         ;; Its own (`agent-workflow--pane-answer'): hovered, what they open.
                         (list :actions '((:label "Worktree" :prompt "worktree" :help "open its worktree")
                                          (:label "Magit" :prompt "magit" :help "magit on its worktree"))))))
          (and worktree files
               (list :id "changes" :type "files" :dir worktree :tree (if (> (length files) 12) t :false)
                     :files (mapcar (lambda (file)
                                      (append (list :path (plist-get file :path)
                                                    :status (symbol-name (plist-get file :status)))
                                              (and (plist-get file :added) (list :added (plist-get file :added)))
                                              (and (plist-get file :removed) (list :removed (plist-get file :removed)))
                                              (and (plist-get file :uncommitted) (list :note "not committed"))))
                                    files)))
          (and commits
               (list :id "commits" :type "text" :face "muted"
                     :text (mapconcat (lambda (commit) (format "%s  %s" (nth 0 commit) (nth 1 commit)))
                                      commits "\n")))
          (and (> with 0) (not (plist-get where :merged))
               (list :id "where-note" :type "text" :face "warning"
                     :text (format "Started from %s, not %s: its %d %s not in %s %s merged too."
                                   (plist-get base :branch) (plist-get where :into) with
                                   (if (= with 1) "commit" "commits") (plist-get where :into)
                                   (if (= with 1) "is" "are")))))))

(defun agent-workflow--pane-money (dollars)
  "DOLLARS as the header says them: $15, $1.24."
  (if (and (numberp dollars) (= dollars (truncate dollars)))
      (format "$%d" (truncate dollars))
    (format "$%.2f" (or dollars 0))))

(defun agent-workflow--pane-state-line (run)
  "RUN's state in a line: its mark and state, its time, what it spent, its
tokens, each against its budget if it has one."
  (let* ((state (agent-workflow-run-state run))
         (spent (agent-workflow-run-spent-now run))
         (budget (agent-workflow-run-budget run))
         (cost (or (plist-get spent :cost) 0))
         (tokens (or (plist-get spent :tokens) 0)))
    (string-join
     (delq nil
           (list (pcase state
                   ('waiting "◆ needs you")
                   ('queued (concat "○ queued" (if (agent-workflow-run-why run)
                                                   (concat ": " (agent-workflow-run-why run))
                                                 "")))
                   ('done (if (plist-get (agent-workflow-run-where run) :empty) "✓ done · no commit" "✓ done"))
                   ('cancelled "✗ cancelled")
                   ('failed (concat "✗ failed" (if (agent-workflow-run-why run)
                                                   (concat ": " (agent-workflow-run-why run))
                                                 "")))
                   (_ (concat "● running"
                              ;; A job's next agent step waiting for one: said.
                              (if-let* ((job (seq-find (lambda (job) (and (eq (plist-get (cdr job) :status) 'running)
                                                                          (plist-get (cdr job) :pool)))
                                                       (agent-workflow-run-jobs run)))
                                        (why (plist-get (cdr job) :why)))
                                  (concat ": " why)
                                ""))))
                 (concat (agent-workflow--duration-words (plist-get spent :time))
                         (if (plist-get budget :time)
                             (concat " of " (agent-workflow--duration-words (plist-get budget :time)))
                           ""))
                 (cond ((plist-get budget :cost)
                        (format "%s of %s" (agent-workflow--pane-money cost)
                                (agent-workflow--pane-money (plist-get budget :cost))))
                       ((> cost 0) (agent-workflow--pane-money cost)))
                 (cond ((plist-get budget :tokens)
                        (format "%s of %s tokens" (agent-ui-format-compact tokens)
                                (agent-ui-format-compact (plist-get budget :tokens))))
                       ((> tokens 0) (format "%s tokens" (agent-ui-format-compact tokens))))
                 (and (agent-workflow-run-warned run) "near its budget")))
     " · ")))

(defun agent-workflow--pane-header (run)
  "The run, above its sections: its issue (no ticket: its name), then its
state in a line; while it isn't over, Cancel under it (asked first:
`agent-workflow-cancel-asked')."
  (append
   (list :id "run" :type "text"
         :title (if (agent-workflow-run-ticket-p run)
                    (format "%s: %s" (agent-workflow-run-issue run)
                            (or (plist-get (agent-workflow-run-info run) :title) ""))
                  (agent-workflow-run-name run))
         :face (pcase (agent-workflow-run-state run)
                 ('waiting "warning") ('cancelled "muted") ('failed "error") ('done "success") (_ "plain"))
         :text (agent-workflow--pane-state-line run))
   ;; Its own (`agent-workflow--pane-answer'); over, none.
   (unless (memq (agent-workflow-run-state run) agent-workflow--ended)
     (list :actions '((:label "Cancel" :prompt "cancel" :help "cancel the run (asked first)"))))))

(defun agent-workflow--pane-step-name (step)
  "STEP of a job (a plist), as its checklist names it: its name, else what
it does (`agent-workflow--pane-step-does')."
  (or (plist-get step :name) (agent-workflow--pane-step-does step)))

(defun agent-workflow--pane-step-does (step)
  "What STEP of a job (a plist) does, in a few words."
  (pcase (plist-get step :kind)
    ('agent (format "agent: %s" (plist-get step :agent)))
    ('run (format "run: %s" (truncate-string-to-width
                             (car (split-string (string-trim (format "%s" (plist-get step :run))) "\n"))
                             40 nil nil "…")))
    ('elisp "elisp")
    ('uses (format "uses: %s" (plist-get step :uses)))
    (_ "a step")))

(defun agent-workflow--pane-status (status)
  "A job's STATUS as a checklist's: waiting for you, ◆; cancelled (its run
over), as skipped (–, grey: no spinner), its detail saying it."
  (pcase status
    ('running "running") ('waiting "waiting") ('done "done") ((or 'skipped 'cancelled) "skipped") ('failed "failed")
    (_ "pending")))

(defun agent-workflow--pane-timed (item times status)
  "ITEM, a checklist's step, with its TIMES (:started :ended) for STATUS
\(its checklist's): its start while it runs, how long it took once done."
  (let ((started (plist-get times :started))
        (ended (plist-get times :ended)))
    (cond ((and started (member status '("running" "waiting"))) (append item (list :started started)))
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
         ;; Its next agent step waiting for a free one: not running (no
         ;; spinner, not timed), saying why.
         (pooled (and (eq status 'running) (plist-get state :pool)))
         ;; A step that failed, its agent fixing it: who, and its try.
         (fixing (and (memq status '(running waiting)) (plist-get state :retry)
                      (agent-workflow--pane-fixing run job state)))
         (detail (string-join
                  (delq nil (list (and (eq status 'skipped) (plist-get spec :if)
                                       (format "its if: %s" (string-trim (plist-get spec :if))))
                                  (and agent (not (eq status 'skipped)) (format "agent %s" (plist-get agent :agent)))
                                  (and (numberp (plist-get state :round)) (> (plist-get state :round) 1)
                                       (format "round %d" (plist-get state :round)))
                                  ;; One step: its fixing said on its job's line; several, fixing
                                  ;; there, who and its try on its step's.
                                  (and fixing (if (cdr steps) "fixing" fixing))
                                  ;; Its tries count the one running: a second, said.
                                  (and (not fixing) (numberp tries) (> tries 1) (memq status '(running waiting))
                                       (format "try %d" tries))
                                  (and (eq status 'done) outcome (not (equal outcome "done")) outcome)
                                  ;; What it left on the branch.
                                  (and (eq status 'done)
                                       (if (agent-workflow--uses-merge-p spec)
                                           (if (plist-get (agent-workflow-run-where run) :empty) "nothing to merge" "merged")
                                         (and (agent-workflow--job-edits-p run job)
                                              (plist-get state :start-commit)
                                              (equal (plist-get state :start-commit) (plist-get state :end-commit))
                                              "no commit")))
                                  (and (eq status 'waiting) "needs you")
                                  (and (eq status 'cancelled) "cancelled")
                                  (and (or (eq status 'pending) pooled) (plist-get state :why)
                                       (format "waits: %s" (plist-get state :why)))))
                  " · "))
         (mapped (if pooled "pending" (agent-workflow--pane-status status)))
         (item (list :name job :status mapped)))
    (unless (string-empty-p detail)
      (setq item (append item (list :detail detail))))
    (setq item (agent-workflow--pane-timed item times mapped))
    (if (not (cdr steps))
        item
      (append item
              (list :steps
                    (cl-loop for step in steps for i from 0
                             collect (let* ((fixed (and fixing (= i index)))
                                            (sub (cond ((memq status '(done skipped)) (if (eq status 'done) "done" "skipped"))
                                                       ;; Being fixed: it failed.
                                                       (fixed "failed")
                                                       ((memq status '(running waiting failed))
                                                        (cond ((< i index) "done")
                                                              ((and (= i index) pooled) "pending")
                                                              ((= i index) (symbol-name status))
                                                              (t "pending")))
                                                       ;; Its run cancelled: those it didn't end, grey.
                                                       ((eq status 'cancelled) (if (< i index) "done" "skipped"))
                                                       (t "pending")))
                                            (does (and (plist-get step :name) (agent-workflow--pane-step-does step))))
                                       (agent-workflow--pane-timed
                                        (append (list :name (agent-workflow--pane-step-name step) :status sub)
                                                ;; Named: what it does after it; being fixed, who fixes
                                                ;; it and its try.
                                                (and (or does fixed)
                                                     (list :detail (string-join (delq nil (list does (and fixed fixing)))
                                                                                " · "))))
                                        (alist-get i (plist-get times :steps)) sub))))))))

(defun agent-workflow--pane-fixing (run job state)
  "JOB of RUN in STATE, its step :retry failed and its agent fixing it: who
fixes it and its try, as its step's detail says them (ci fixing it · try 1
of 6: its try that failed, of all it may have)."
  (let* ((index (plist-get state :retry))
         (step (nth index (plist-get (agent-workflow--job-spec run job) :steps)))
         (agent (plist-get state :agent))
         (who (or (and agent (agent-workflow-agent-p agent) (agent-workflow-agent-profile agent))
                  (plist-get step :on-fail)
                  "its agent"))
         (tries (or (alist-get index (plist-get state :tries)) 1)))
    (if (plist-get state :resolving)
        ;; A merge's conflicts: its retries not counted.
        (format "%s resolving its conflicts" who)
      (format "%s fixing it · try %d of %d" who tries (1+ (or (plist-get step :retries) 0))))))

(defun agent-workflow--pane-graph (run)
  "RUN's jobs as a graph: each a node, marked and coloured by its state (its
round past 1 said), an arrow from each job to those needing it."
  (let ((specs (plist-get (agent-workflow-run-workflow run) :jobs)))
    (list :id "graph" :type "graph"
          :nodes (mapcar (lambda (job)
                           (let* ((state (cdr job))
                                  (status (plist-get state :status))
                                  (round (plist-get state :round)))
                             (append
                              (list :id (car job)
                                    :label (concat (car job) " "
                                                   (pcase status
                                                     ('done "✓") ('running "●") ('waiting "◆")
                                                     ('skipped "–") ('failed "✗") ('cancelled "⊘") (_ "○"))
                                                   (if (and (numberp round) (> round 1)) (format " r%d" round) "")))
                              (pcase status
                                ('done '(:status "ok")) ('running '(:status "active"))
                                ('waiting '(:status "warning")) ('failed '(:status "error"))))))
                         (agent-workflow-run-jobs run))
          :edges (cl-loop for (job . spec) in specs
                          append (mapcar (lambda (need) (list need job)) (plist-get spec :needs))))))

(defun agent-workflow--pane-jobs (run)
  "RUN's checklist: its jobs. Finished, it stays (its pane with it)."
  (list :id "jobs" :type "steps" :close :false
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
      ;; A line, its answers buttons; one ending in … asks its note.
      (let ((options (pcase kind
                       ('approve '("Approve" "Reject…"))
                       ('retries '("Go on" "Go on, with a note…" "Skip its step" "Stop"))
                       ((or 'broke 'interrupted) '("Go on" "Skip its step" "Stop"))
                       ((or 'merge 'moved 'protected) '("Go on" "Stop"))
                       ('closed '("Go on (the issue in progress again)" "Cancel the run"))
                       (_ '("Run its step again" "Run it again, with a note…" "Cancel the run")))))
        (cons (agent-workflow--pane-ask-line why options)
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

(defconst agent-workflow--pane-go-to-it "Go to it"
  "The option of an agent's question in Needs you showing its session.")

(defun agent-workflow--pane-ask-line (text options)
  "Needs you's question: TEXT in a line, ◆ before it, OPTIONS its buttons
\(each its label, as its answer)."
  (list :id "ask" :type "text" :face "warning" :text (concat "◆ " text)
        :actions (mapcar (lambda (option) (list :label option :prompt option)) options)))

;; AN AGENT'S QUESTION, ANSWERED HERE: its form in its session (agent-shell's
;; elicitation: AskUserQuestion's), as Agent UI's own: one question with
;; options a choice (several, a multi-select; a note, its free answer), more
;; a form (selects, text, numbers, yes or no); answered as its form's Submit
;; does (agent-shell's own: its required answers checked). One it can't draw
;; (a multi-select among others): Go to it. Go to it, always too.

(defun agent-workflow--pane-elicitation (run job asks)
  "The form JOB of RUN's agent asks (ASKS: its :request) in its session,
still waiting: (BUFFER STATE ELICITATION), or nil."
  (when-let* ((request (plist-get asks :request))
              (agent (plist-get (agent-workflow--job run job) :agent))
              (buffer (agent-workflow-agent-buffer agent))
              ((buffer-live-p buffer))
              ((fboundp 'agent-shell-elicitation--get))
              (state (buffer-local-value 'agent-shell--state buffer))
              (elicitation (agent-shell-elicitation--get state request))
              ((eq (map-elt elicitation :status) 'pending)))
    (list buffer state elicitation)))

(defun agent-workflow--pane-elicitation-fields (elicitation)
  "ELICITATION's fields asked (a free answer's own folded into its select's)."
  (seq-remove (lambda (field) (map-elt field :folded-into)) (map-elt elicitation :fields)))

(defun agent-workflow--pane-option-label (option)
  "An elicitation's OPTION as its label: its title, else its value."
  (format "%s" (or (map-elt option :title) (map-elt option :value))))

(defun agent-workflow--pane-elicitation-question (run job asks)
  "JOB of RUN's agent's form (ASKS) as Agent UI's question (see above), or
nil if it can't be drawn."
  (when-let* ((found (agent-workflow--pane-elicitation run job asks))
              (elicitation (nth 2 found))
              (fields (agent-workflow--pane-elicitation-fields elicitation)))
    (let* ((message (or (map-elt elicitation :message) (plist-get asks :what)))
           (question (concat job " asks: " (or message "its question")))
           (actions (list (list :label agent-workflow--pane-go-to-it :prompt agent-workflow--pane-go-to-it)))
           (one (car fields)))
      (cond
       ((and (null (cdr fields)) (memq (map-elt one :type) '(single-select multi-select)))
        (list :id "ask" :type "choice" :title (map-elt one :title)
              :question (if (and (map-elt one :description) (not message))
                            (concat job " asks: " (map-elt one :description))
                          question)
              :options (mapcar (lambda (option)
                                 (append (list :label (agent-workflow--pane-option-label option))
                                         (and (map-elt option :description)
                                              (list :detail (map-elt option :description)))))
                               (map-elt one :options))
              :multiple (if (eq (map-elt one :type) 'multi-select) t :false)
              :note (if (map-elt one :custom-key) t :false)
              :actions actions))
       ((seq-every-p (lambda (field) (memq (map-elt field :type) '(single-select boolean string number integer)))
                     fields)
        (list :id "ask" :type "form" :question question
              :fields (mapcar (lambda (field)
                                (append (list :name (map-elt field :key)
                                              :label (or (map-elt field :title) (map-elt field :description)
                                                         (map-elt field :key))
                                              :type (pcase (map-elt field :type)
                                                      ('single-select "select") ('boolean "boolean")
                                                      ('number "number") ('integer "integer") (_ "text")))
                                        (and (eq (map-elt field :type) 'single-select)
                                             (list :options (mapcar #'agent-workflow--pane-option-label
                                                                    (map-elt field :options))))
                                        (and (map-elt field :required) (list :required t))))
                              fields)
              :actions actions))))))

(defun agent-workflow--pane-elicitation-answer (elicitation element)
  "ELEMENT's answer (a choice's, a form's: see above) as ELICITATION's
values, ((KEY . VALUE)...); a user error if it gives none."
  (let ((fields (agent-workflow--pane-elicitation-fields elicitation)))
    (cl-flet ((value-of (field label)
                (if-let* ((option (seq-find (lambda (option)
                                              (equal (agent-workflow--pane-option-label option) label))
                                            (map-elt field :options))))
                    (map-elt option :value)
                  label)))
      (if (equal (plist-get element :type) "choice")
          (let* ((field (car fields))
                 (selected (plist-get element :selected))
                 (note (let ((note (plist-get element :note-text)))
                         (and (stringp note) (not (string-blank-p note)) (string-trim note)))))
            (cond ((and note (map-elt field :custom-key)) (list (cons (map-elt field :custom-key) note)))
                  (selected
                   (let ((values (mapcar (lambda (label) (value-of field label)) selected)))
                     (list (cons (map-elt field :key)
                                 (if (eq (map-elt field :type) 'multi-select) values (car values))))))
                  (t (user-error "Choose one first"))))
        (let ((values (plist-get element :values)))
          (or (delq nil
                    (mapcar (lambda (field)
                              (let ((value (plist-get values (intern (concat ":" (map-elt field :key))))))
                                (unless (or (null value) (equal value ""))
                                  (cons (map-elt field :key)
                                        (pcase (map-elt field :type)
                                          ('single-select (value-of field value))
                                          ('boolean (if (memq value '(nil :false)) :false t))
                                          (_ value))))))
                            fields))
              (user-error "Answer it first")))))))

(defun agent-workflow--pane-answer-elicitation (run job asks answer)
  "JOB of RUN's agent's form (ASKS) answered with ANSWER (its values), as
its Submit does (agent-shell's: its required answers checked)."
  (pcase-let ((`(,buffer ,state ,elicitation) (or (agent-workflow--pane-elicitation run job asks)
                                                  (user-error "%s's agent no longer asks that" job))))
    (ignore elicitation)
    (with-current-buffer buffer
      (let ((id (plist-get asks :request)))
        (pcase-dolist (`(,key . ,value) answer)
          (agent-shell-elicitation--set-values
           state id (agent-shell-elicitation--clearing (agent-shell-elicitation--get state id) key value)))
        (agent-shell-elicitation--submit :state state :id id)))))

(defun agent-workflow--pane-agent-answer-action (run job element pressed)
  "What answering JOB of RUN's agent's question with ELEMENT (PRESSED: the
label of its button pressed, or its answer) does: a function of no
argument (see `agent-workflow--pane-answer-action')."
  (let ((asks (plist-get (agent-workflow--job run job) :agent-asks)))
    (if (and (member (plist-get element :type) '("choice" "form"))
             (not (equal pressed agent-workflow--pane-go-to-it)))
        (let* ((found (or (agent-workflow--pane-elicitation run job asks)
                          (user-error "%s's agent no longer asks that" job)))
               (answer (agent-workflow--pane-elicitation-answer (nth 2 found) element)))
          (lambda () (agent-workflow--pane-answer-elicitation run job asks answer)))
      (lambda () (agent-workflow--pane-answer-agent run job (plist-get asks :kind) pressed)))))

(defun agent-workflow--pane-agent-question (run job asks why)
  "What JOB of RUN's agent asks you in its session (ASKS, as
`agent-workflow-agent-asking' has it), WHY in words: its form as Agent
UI's own (see above); else a line, a permission's options agent-shell's
own buttons, and Go to it."
  (ignore why)
  (if-let* ((question (agent-workflow--pane-elicitation-question run job asks)))
      (list question)
    (let* ((agent (plist-get (agent-workflow--job run job) :agent))
           (buffer (and agent (agent-workflow-agent-buffer agent)))
           (what (plist-get asks :what))
           (buttons (and (eq (plist-get asks :kind) 'permission)
                         (buffer-live-p buffer)
                         (fboundp '+my/agent-shell-permission-buttons)
                         (mapcar #'car (+my/agent-shell-permission-buttons buffer)))))
      (list (agent-workflow--pane-ask-line
             (concat job (if (eq (plist-get asks :kind) 'permission) " asks for your permission" " asks you")
                     (if what (concat ": " what) ""))
             (append buttons (list agent-workflow--pane-go-to-it)))))))

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

(defun agent-workflow--pane-answer (prompt _submit key)
  "A button of a run's pane pressed (`agent-ui-answer-function'): its
header's Cancel (asked first), git's
\(PROMPT worktree, magit: its worktree opened), or a question's answer
\(PROMPT the button's label; a form's, read from its element, KEY's), given
to the run (approved, rejected, confirmed, sent back, cancelled) once the
button's own command is done. An answer that can't be given: said, the
question left as it was."
  (let* ((run agent-workflow--pane-run)
         (pane (current-buffer)))
    (cond ((equal key "git") (agent-workflow--pane-open-worktree run prompt))
          ((equal key "run") (agent-workflow--pane-cancel run))
          (t (agent-workflow--pane-answer-question run pane prompt key)))))

(defun agent-workflow--pane-cancel (run)
  "RUN cancelled from its pane's Cancel, asked first; over already: said."
  (when (memq (agent-workflow-run-state run) agent-workflow--ended)
    (user-error "%s is over already" (agent-workflow-run-name run)))
  (agent-workflow-cancel-asked run :by "you, in its pane"))

(defun agent-workflow--pane-open-worktree (run how)
  "RUN's worktree opened, HOW: worktree (dired), magit (its status)."
  (let ((dir (plist-get (agent-workflow-run-where run) :worktree)))
    (unless (and dir (file-directory-p dir))
      (user-error "%s has no worktree now" (agent-workflow-run-name run)))
    (if (and (equal how "magit") (fboundp 'magit-status))
        (magit-status dir)
      (pop-to-buffer (dired-noselect dir)))))

(defun agent-workflow--pane-answer-question (run pane prompt key)
  "RUN's question in PANE answered with PROMPT, its button pressed on KEY's
element (see `agent-workflow--pane-answer')."
  (let* ((asked agent-workflow--pane-asked)
         (job (car asked))
         (kind (nth 1 asked))
         (by "you, in its pane")
         (give (progn
                 (unless (and run asked (equal (agent-ui--key-section key) "needs-you"))
                   (user-error "This run asks nothing here"))
                 (agent-workflow--pane-answer-action run job kind (agent-ui-get key :canvas pane) by prompt))))
    ;; Answered: the next question shown, even if it's the same again.
    (setq agent-workflow--pane-asked nil)
    (run-at-time 0 nil (lambda ()
                         (condition-case err
                             (funcall give)
                           (error (message "%s: %s" (agent-workflow-run-name run) (error-message-string err))
                                  (when (buffer-live-p pane)
                                    (agent-workflow--pane-changed run))))))))

(defun agent-workflow--pane-answer-action (run job kind element by &optional pressed)
  "What answering RUN's question on JOB (KIND: its :ask's, `guard' for the
loop guard's, `agent' for its agent's, nil for a wait with no question) with
ELEMENT (the question, answered; a line's: the label of the button
PRESSED, one ending in … asking its note) does: a function of no argument,
BY you. A user error if the answer can't be given (nothing chosen, a
rejection without a note)."
  (cond
   ((eq kind 'agent) (agent-workflow--pane-agent-answer-action run job element pressed))
   ((equal (plist-get element :type) "form")
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
          (lambda () (agent-workflow-confirm run choice :by by :notes notes))))))
   (t
    (let* ((line (equal (plist-get element :type) "text"))
           (picked (if line pressed (car (plist-get element :selected))))
           (note (let ((note (if (and line picked (string-suffix-p "…" picked))
                                 (read-string (if (eq kind 'approve)
                                                  (format "Why (%s's agent is told it): " job)
                                                (format "Your note for %s: " job)))
                               (plist-get element :note-text))))
                   (and (stringp note) (not (string-blank-p note)) (string-trim note)))))
      (unless picked
        (user-error "Choose one first"))
      (when (and line (string-suffix-p "…" picked) (not note))
        (user-error "No note: nothing answered"))
      (pcase kind
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
           (lambda () (agent-workflow-confirm run choice :by by :notes (and note (list (cons job note))))))))))))

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
                                 (round (- (or (and (memq status '(done skipped cancelled))
                                                    (or (plist-get times :ended) (plist-get times :cancelled)))
                                               (float-time))
                                           started)))))
             (mark (pcase status ('running 'running) ('waiting 'needs-you) ('done 'done) ('skipped 'done)
                          ('cancelled 'failed) (_ 'waiting))))
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
          (cond ((and (memq status '(done skipped cancelled)) (not (member name agent-workflow--pane-ended)))
                 (push name agent-workflow--pane-ended)
                 (agent-ui-section pane section :folded t))
                ((and (eq status 'running) (member name agent-workflow--pane-ended))
                 (setq agent-workflow--pane-ended (delete name agent-workflow--pane-ended))
                 (agent-ui-section pane section :folded nil))))))))

(defvar agent-ui--hosts)
(defvar agent-ui-session)

(defun agent-workflow--pane-agent-stopped (agent)
  "AGENT stops (its job over, sent back, its run cancelled...): what its
session's canvas showed in its run's pane kept there, its section's own
\(folded once its job's done), not gone with its session. In
`agent-workflow-agent-stop-functions'."
  (when-let* ((buffer (agent-workflow-agent-buffer agent))
              ((buffer-live-p buffer))
              ((fboundp 'agent-ui-unhost))
              (name (buffer-local-value 'agent-ui-session buffer))
              ((assoc name agent-ui--hosts)))
    (agent-ui-unhost name t)))

(add-hook 'agent-workflow-agent-stop-functions #'agent-workflow--pane-agent-stopped)

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
agents' sections. MADE: just made (not shown while it's drawn)."
  (when-let* ((pane (agent-workflow--pane-live run)))
    (with-current-buffer pane
      (agent-workflow--pane-draw-in run pane made))))

(defun agent-workflow--pane-show-where (run pane)
  "RUN's git under its header in PANE (`agent-workflow--pane-git'): each
element shown, or removed once it isn't."
  ;; A pane drawn before: its worktree's row, now git's buttons.
  (when (gethash "where" agent-ui--entries)
    (agent-ui-remove "where" :canvas pane))
  (cl-loop for id in '("git" "changes" "commits" "where-note")
           for element in (agent-workflow--pane-git run (agent-workflow-run-where run))
           do (cond (element (agent-ui-show element :canvas pane))
                    ;; The canvas's own: its key its id.
                    ((gethash id agent-ui--entries) (agent-ui-remove id :canvas pane)))))

(defun agent-workflow--pane-where-tick ()
  "Where the work of each run not over with a pane is looked at again: its
pane drawn again if it changed (a commit, files changed between its run's
events), else its header (its time, what it spent). Stopped once there's
none."
  (let ((any nil))
    (dolist (run agent-workflow--runs)
      (when-let* (((not (memq (agent-workflow-run-state run) agent-workflow--ended)))
                  (pane (agent-workflow--pane-live run)))
        (setq any t)
        (with-demoted-errors "agent workflow's pane: %S"
          (if (or
               ;; Waiting for you, nothing committed or staged since it was
               ;; last read: git not asked again (no agent at work on it).
               (and (eq (agent-workflow-run-state run) 'waiting)
                    (let ((stamp (agent-workflow--where-stamp run)))
                      (prog1 (and stamp (equal stamp (buffer-local-value 'agent-workflow--pane-where-stamp pane)))
                        (with-current-buffer pane (setq agent-workflow--pane-where-stamp stamp)))))
               (equal (agent-workflow-run-where run) (buffer-local-value 'agent-workflow--pane-where-shown pane)))
              ;; Its header's time and spending, moving on.
              (let ((agent-ui-display-function #'ignore))
                (agent-ui-show (agent-workflow--pane-header run) :canvas pane))
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
      (agent-ui-show (agent-workflow--pane-graph run) :canvas pane :section "run")
      (agent-ui-show (agent-workflow--pane-jobs run)
                     :canvas pane :section "run")
      (if-let* ((rounds (agent-workflow--pane-rounds-element)))
          (agent-ui-show rounds :canvas pane :section "run")
        (when (gethash "run/rounds" agent-ui--entries)
          (agent-ui-remove "rounds" :canvas pane :section "run")))
      (agent-ui-section pane "run" :state (pcase (agent-workflow-run-state run)
                                            ('running 'running) ('waiting 'needs-you) ('queued 'waiting)
                                            ('done 'done) ((or 'cancelled 'failed) 'failed)))
      (agent-workflow--pane-needs run pane)
      (agent-workflow--pane-show-notes run pane)
      (agent-workflow--pane-agents run pane)))

(defun agent-workflow--pane-show-notes (run pane)
  "RUN's PANE's Notes (its agents' verdicts, a feed): its section once the
first came, after Run and Needs you, before its agents'; each agent's notes
whole in its own section, made (folded) if its agent's gone already (a
pane drawn again from its journal)."
  (when-let* ((notes (agent-workflow--pane-notes-element)))
    (unless (agent-ui--find-section "notes")
      (agent-ui-section pane "notes" :title "Notes" :after (if (agent-ui--find-section "needs-you") "needs-you" "run")))
    (agent-ui-show notes :canvas pane :section "notes")
    (dolist (job (delete-dups (mapcar (lambda (note) (plist-get note :job)) agent-workflow--pane-notes)))
      (when-let* ((section (agent-workflow--pane-section job))
                  (element (agent-workflow--pane-job-notes-element job)))
        (unless (agent-ui--find-section section)
          (let ((status (plist-get (agent-workflow--job run job) :status)))
            (agent-ui-section pane section :title job
                              :state (pcase status ('running 'running) ('waiting 'needs-you) ('done 'done)
                                       ('skipped 'done) ('cancelled 'failed) (_ 'waiting))
                              :folded (memq status '(done skipped cancelled))
                              :after (or (car (last (seq-filter (lambda (s) (string-prefix-p "job." s))
                                                                (mapcar #'agent-ui--section-name agent-ui--sections))))
                                         "notes")
                              :open (lambda () (agent-workflow--pane-open-session run job)))
            (when (memq status '(done skipped cancelled))
              (push job agent-workflow--pane-ended))))
        (with-demoted-errors "agent workflow's pane: %S"
          (agent-ui-show element :canvas pane :section section))))))

(defun agent-workflow--pane-changed (run)
  "RUN changed: its pane drawn again, if it has one. In
`agent-workflow-run-functions'."
  (when (agent-workflow--pane-live run)
    (with-demoted-errors "agent workflow's pane: %S"
      (agent-workflow--pane-draw run))))

(add-hook 'agent-workflow-run-functions #'agent-workflow--pane-changed)


(defun agent-workflow--pane-started (run shell)
  "RUN started: its pane opened, unless from the SHELL. In
`agent-workflow-started-functions'."
  (unless (or shell (not (fboundp 'agent-ui-canvas)))
    (agent-workflow-pane run t)))

(add-hook 'agent-workflow-started-functions #'agent-workflow--pane-started)
