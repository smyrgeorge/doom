;;; $DOOMDIR/config/agent-workflow/pane.el -*- lexical-binding: t; -*-
;; A run's pane: an Agent UI canvas, ISSUE · WORKFLOW, one per run, drawn by
;; Emacs from the run, its journal and its log (never by an agent).
;; Loaded from config/agent-workflow.el, after log.el. No Doom here.
;;
;; Above its sections, the run: its issue, its state, its time, what it
;; spent of its budget. Then, each under its divider (Agent UI's sections):
;;
;; - Run: its jobs, a checklist, each job's steps under it (status, agent,
;;   round, try, time); at its bottom a box for each job running, live: its
;;   agent at work (what on, its turn's time, its actions as they come,
;;   Show session: at its question if it asks), or its script (its command,
;;   its output's last lines as it comes, Show output).
;; - Needs you, only while it waits for you: what on, as a question you
;;   answer there (an approval: approve, or reject with a note; the loop
;;   guard: go on with notes, accept, stop; retries used up, a step that
;;   broke, its budget used up...; its agent asking in its session: a
;;   permission's own buttons, pressed from there, and Go to it, its session
;;   shown at the question).
;; - Notes, once an agent wrote some: every job's, a line each, each
;;   unfolding to its whole.
;;
;; What an agent shows on its own canvas (its plan, its progress) stays with
;; its session: Show session. Its canvas opens a pane of its own only while
;; it asks you something there (pool.el).
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
(require 'map)
(require 'ansi-color)

(defvar agent-workflow-pane-log-lines)
(defvar agent-ui-answer-function)
(defvar agent-ui-display-function)
(defvar agent-ui--entries)
(declare-function agent-ui--session-name "agent-ui/agent")
(declare-function agent-workflow--uses-merge-p "agent-workflow/dry")
(declare-function agent-workflow-agent-p "agent-workflow/pool")
(declare-function agent-workflow-cancel-asked "agent-workflow/resume")
(declare-function agent-workflow--where-stamp "agent-workflow/runs")
(declare-function agent-workflow-agent-definition "agent-workflow/pool")
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
plists (:job :round :what :outcome :time :text), WHAT what its agent was
at (fixing watch · try 2, its agent step's name), nil if not known.")

(defvar-local agent-workflow--pane-doing nil
  "In a run's pane, from its journal: what each job's agent is at, for its
notes: an alist of a job to WHAT (see `agent-workflow--pane-notes');
its steps' tries, (JOB . INDEX) to the last one started.")

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

(defvar agent-workflow--pane-showing nil
  "Non-nil while a pane is shown on purpose (`agent-workflow-pane').")

(defvar agent-workflow-pane-box-lines 5
  "How many lines a job's live box shows: its agent's last actions, its
script's last lines of output.")

(defvar agent-workflow--pane-activity (make-hash-table :test #'eq :weakness 'key)
  "Each agent's activity, for its live box: a plist, :actions its last tool
calls ((ID KIND TEXT)...), the latest first; :turn when its turn began (a
`float-time'), nil between turns. From its session's events, never polled.")

(defvar agent-workflow--pane-boxes-timer nil
  "The timer drawing the panes' live boxes again, each second, while one
shows a job running.")

(defvar-local agent-workflow--pane-boxes nil
  "In a run's pane: its live boxes shown, an alist of a job to the element
last shown (drawn again only once it changed).")

(defconst agent-workflow--pane-action-marks
  '(("execute" . "⚙") ("read" . "📖") ("search" . "📖") ("fetch" . "📖")
    ("edit" . "✎") ("delete" . "✎") ("move" . "✎"))
  "A tool call's kind (ACP's) as its mark before it; others: •.")

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
  "Whether a question waits in CANVAS (a run's pane, an agent's canvas)."
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
            agent-workflow--pane-doing nil
            agent-workflow--pane-asked nil
            agent-workflow--pane-boxes nil)
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
      ;; What its agent's at: a failed step it fixes (its try), its agent step.
      (pcase event
        ("step-started"
         (when (numberp (plist-get data :try))
           (setf (alist-get (cons job index) agent-workflow--pane-doing nil nil #'equal) (plist-get data :try)))
         (when (plist-get data :agent)
           (setf (alist-get job agent-workflow--pane-doing nil nil #'equal)
                 (or (plist-get data :name) (format "step %d" (1+ (or index 0)))))))
        ("fixing"
         (let ((try (alist-get (cons job index) agent-workflow--pane-doing nil nil #'equal)))
           (setf (alist-get job agent-workflow--pane-doing nil nil #'equal)
                 (concat "fixing " (or (plist-get data :name) (format "step %s" (1+ (or index 0))))
                         (if try (format " · try %d" try) "")))))
        ((or "job-started" "went-back")
         (setf (alist-get job agent-workflow--pane-doing nil t #'equal) nil)))
      ;; An agent's notes, as it ended its step.
      (when-let* (((equal event "step-ended"))
                  (text (plist-get data :notes))
                  ((stringp text))
                  ((not (string-blank-p text))))
        (setq agent-workflow--pane-notes
              (append agent-workflow--pane-notes
                      (list (list :job job :time time :text (string-trim text)
                                  :what (alist-get job agent-workflow--pane-doing nil nil #'equal)
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
        ;; Its on-fail script's start: its box's time from it.
        ("fix-script" (setq times (plist-put times :fix-started time)))
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
  "NOTE's job, its round past 1 said, a fix's what (fixing watch · try 2):
its name in the feed."
  (let ((round (plist-get note :round))
        (what (plist-get note :what)))
    (concat (plist-get note :job) (if (and (numberp round) (> round 1)) (format " · round %d" round) "")
            (if (and what (string-prefix-p "fixing " what)) (concat " · " what) ""))))

(defun agent-workflow--pane-notes-element (&optional open)
  "The pane's agents' notes as a feed (nil before the first): a line each,
its job (its round past 1, a fix's try), its time, its outcome (not done,
nor what its verdict starts with), its verdict
\(`agent-workflow--pane-verdict'); RET on it unfolds it whole, folded until
then (OPEN, the names of those unfolded)."
  (when agent-workflow--pane-notes
    (let ((seen nil))
      (list :id "notes" :type "steps" :close :false :open open
            :steps (mapcar (lambda (note)
                             (let* ((name (agent-workflow--pane-note-name note))
                                    (name (if (member name seen)
                                              (format "%s (%d)" name (1+ (seq-count (lambda (s) (string-prefix-p name s)) seen)))
                                            name))
                                    (outcome (plist-get note :outcome))
                                    (verdict (agent-workflow--pane-verdict (plist-get note :text))))
                               (push name seen)
                               (list :name name :status "done" :body (plist-get note :text)
                                     :detail (concat (format-time-string "%H:%M" (plist-get note :time)) " · "
                                                     ;; Its outcome, unless its verdict says it first.
                                                     (if (and outcome (not (equal outcome "done"))
                                                              (not (string-prefix-p (downcase outcome) (downcase verdict))))
                                                         (concat outcome " · ")
                                                       "")
                                                     verdict))))
                           agent-workflow--pane-notes)))))

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
                               (if (> own 0) (format " · %d commit%s of its" own (if (= own 1) "" "s")) ""))
                             ;; Not committed: yours or its agent's at work,
                             ;; not told apart: counted, not listed as its.
                             (let ((loose (or (plist-get where :uncommitted) 0)))
                               (if (> loose 0) (format " · %d not committed" loose) ""))))
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
worktree, magit; in your checkout, magit alone: its worktree is your
project), changes (its files changed since it started: RET opens
one), commits (its latest, a line each: RET shows one), where-note (its base branch's commits its
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
                         (list :actions (if (plist-get where :checkout)
                                            '((:label "Magit" :prompt "magit" :help "magit on your checkout"))
                                          '((:label "Worktree" :prompt "worktree" :help "open its worktree")
                                            (:label "Magit" :prompt "magit" :help "magit on its worktree")))))))
          (and worktree files
               (list :id "changes" :type "files" :dir worktree :tree (if (> (length files) 12) t :false)
                     :files (mapcar (lambda (file)
                                      (append (list :path (plist-get file :path)
                                                    :status (symbol-name (plist-get file :status)))
                                              (and (plist-get file :added) (list :added (plist-get file :added)))
                                              (and (plist-get file :removed) (list :removed (plist-get file :removed)))
                                              (and (plist-get file :uncommitted) (list :note "not committed"))))
                                    files)))
          ;; A line each (its subject cut), RET or a click opening it.
          (and commits
               (list :id "commits" :type "table" :columns '("" "") :nowrap t
                     :rows (mapcar (lambda (commit) (list (nth 0 commit) (or (nth 1 commit) ""))) commits)
                     ;; Its own (`agent-workflow--pane-answer'): {0} its hash.
                     :row-open '(:prompt "{0}" :help "show this commit")))
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

(defun agent-workflow--pane-now (run)
  "What RUN is at now, in a few words: each running job's step (watch, step
3 of 3), its job's name alone if it has one step; nil if none runs."
  (let ((now (cl-loop for (job . state) in (agent-workflow-run-jobs run)
                      when (eq (plist-get state :status) 'running)
                      collect (let* ((steps (plist-get (agent-workflow--job-spec run job) :steps))
                                     (index (plist-get state :step))
                                     (step (and (numberp index) (nth index steps))))
                                (if (and step (> (length steps) 1))
                                    (format "%s, step %d of %d" (agent-workflow--pane-step-name step)
                                            (1+ index) (length steps))
                                  job)))))
    (and now (string-join now " · "))))

(defun agent-workflow--pane-state (run)
  "RUN's state as its header's first tile: (VALUE DETAIL FACE), its mark
and state, what it waits for or why it ended (else what it's at now), the
colour of its state: running accent (blue, as its graph's running jobs),
needs you warning, done success, failed error, queued and cancelled muted."
  (let* ((state (agent-workflow-run-state run))
         (why (agent-workflow-run-why run))
         ;; A job's next agent step waiting for one: said.
         (pool (seq-some (lambda (job) (and (eq (plist-get (cdr job) :status) 'running)
                                            (plist-get (cdr job) :pool)
                                            (plist-get (cdr job) :why)))
                         (agent-workflow-run-jobs run)))
         (near (and (agent-workflow-run-warned run) "near its budget")))
    (pcase state
      ('waiting (list "◆ needs you" (or why near) "warning"))
      ('queued (list "○ queued" why "muted"))
      ('done (list "✓ done" (and (plist-get (agent-workflow-run-where run) :empty) "no commit") "success"))
      ('cancelled (list "✗ cancelled" why "muted"))
      ('failed (list "✗ failed" why "error"))
      (_ (list "● running" (string-join (delq nil (list (or pool (agent-workflow--pane-now run)) near)) " · ")
               "accent")))))

(defun agent-workflow--pane-figures (run)
  "RUN's header as tiles: its state (what it's at), its time, what it spent
and its tokens (each against its budget, if it has one; tokens only if it
has a budget of them or spent some), its jobs done."
  (let* ((spent (agent-workflow-run-spent-now run))
         (budget (agent-workflow-run-budget run))
         (cost (or (plist-get spent :cost) 0))
         (tokens (or (plist-get spent :tokens) 0))
         (jobs (agent-workflow-run-jobs run)))
    (pcase-let ((`(,value ,detail ,face) (agent-workflow--pane-state run)))
      (delq nil
            (list (append (list :label "State" :value value :good "none")
                          (and detail (not (string-empty-p detail)) (list :change detail))
                          (and face (list :face face)))
                  (append (list :label "Time" :value (agent-workflow--duration-words (plist-get spent :time)) :good "none")
                          (and (plist-get budget :time)
                               (list :change (concat "of " (agent-workflow--duration-words (plist-get budget :time))))))
                  (append (list :label "Cost" :value (agent-workflow--pane-money cost) :good "none")
                          (and (plist-get budget :cost)
                               (list :change (concat "of " (agent-workflow--pane-money (plist-get budget :cost))))))
                  (and (or (plist-get budget :tokens) (> tokens 0))
                       (append (list :label "Tokens" :value (agent-ui-format-compact tokens) :good "none")
                               (and (plist-get budget :tokens)
                                    (list :change (concat "of " (agent-ui-format-compact (plist-get budget :tokens)))))))
                  (list :label "Jobs" :good "none"
                        :value (format "%d / %d" (cl-count-if (lambda (job) (memq (plist-get (cdr job) :status) '(done skipped)))
                                                              jobs)
                                       (length jobs))
                        :change "done"))))))

(defun agent-workflow--pane-header (run)
  "The run, above its sections: its issue's title (a ticket's run; its
name, ISSUE · WORKFLOW, not: its tab and buffer say it), then its
state, time, spending and jobs as tiles (`agent-workflow--pane-figures');
while it isn't over, Cancel under them (asked first:
`agent-workflow-cancel-asked')."
  (append
   ;; At the pane's top: a little space above its tiles.
   (list :id "run" :type "stats" :pad t)
   ;; Its name (ISSUE · WORKFLOW) its tab's, its buffer's: not again. A
   ;; ticket's run, its issue's title, said nowhere else.
   (when-let* (((agent-workflow-run-ticket-p run))
               (title (plist-get (agent-workflow-run-info run) :title))
               ((not (string-blank-p title))))
     (list :title title))
   (list :figures (agent-workflow--pane-figures run))
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
         (who (or (and (plist-get state :fix-script) "its on-fail script")
                  (and agent (agent-workflow-agent-p agent) (agent-workflow-agent-definition agent))
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
header's Cancel (asked first), a job's live box's Show session or Show
output, git's
\(PROMPT worktree, magit: its worktree opened), or a question's answer
\(PROMPT the button's label; a form's, read from its element, KEY's), given
to the run (approved, rejected, confirmed, sent back, cancelled) once the
button's own command is done. An answer that can't be given: said, the
question left as it was."
  (let* ((run agent-workflow--pane-run)
         (pane (current-buffer)))
    (cond ((equal key "git") (agent-workflow--pane-open-worktree run prompt))
          ((equal key "run") (agent-workflow--pane-cancel run))
          ((equal key "commits") (agent-workflow--pane-show-commit run prompt))
          ;; A job's live box: Show session, Show output (PROMPT: what, its job).
          ((string-prefix-p "now-" (agent-ui--key-id key))
           (pcase (split-string prompt " ")
             (`("session" ,job) (agent-workflow--pane-go-to-agent run job))
             (`("output" ,job) (agent-workflow--pane-show-output run job))))
          (t (agent-workflow--pane-answer-question run pane prompt key)))))

(defun agent-workflow--pane-show-commit (run commit)
  "COMMIT (a hash) of RUN shown, from its pane's commits: magit's, else
git show's, read where its work is (its worktree, else its project)."
  (let* ((where (agent-workflow-run-where run))
         (worktree (plist-get where :worktree))
         (default-directory (file-name-as-directory
                             (if (and worktree (file-directory-p worktree))
                                 worktree
                               (agent-workflow-run-project run)))))
    (unless (and (stringp commit) (string-match-p "\\`[0-9a-f]+\\'" commit))
      (user-error "Not a commit: %s" commit))
    (if (fboundp 'magit-show-commit)
        (magit-show-commit commit)
      (let ((buffer (get-buffer-create (format "*git show %s*" commit))))
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (call-process "git" nil t nil "show" commit))
          (goto-char (point-min))
          (diff-mode)
          (view-mode 1))
        (pop-to-buffer buffer)))))

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

;; ====== WHAT EACH JOB RUNS, LIVE ======

(defun agent-workflow--pane-after-jobs ()
  "The current pane's section after which Notes goes: Needs you, else Run."
  (if (agent-ui--find-section "needs-you") "needs-you" "run"))

(defun agent-workflow--pane-box-id (job)
  "The id of JOB's live box: now-JOB, its characters an id's."
  (concat "now-" (replace-regexp-in-string "[^A-Za-z0-9_.-]" "-" job)))

(defun agent-workflow--pane-action-text (tool-call)
  "TOOL-CALL (agent-shell's) as its line says it: its title, else its
description, on one line, its backquotes gone; nil if it has neither."
  (when-let* ((text (seq-find (lambda (text) (and (stringp text) (not (string-blank-p text))))
                              (list (map-elt tool-call :title) (map-elt tool-call :description)))))
    (string-trim (replace-regexp-in-string "[\n\r\t ]+" " " (replace-regexp-in-string "`" "" text)))))

(defun agent-workflow--pane-agent-event (agent event)
  "An event of AGENT's session: its turn begun (its last actions forgotten)
or over, a tool call's (its line, kept where it came, its text as it's
known better); its box drawn again at the next tick. In
`agent-workflow-agent-event-functions'."
  (let ((activity (gethash agent agent-workflow--pane-activity))
        (changed t))
    (pcase (map-elt event :event)
      ('input-submitted
       (setq activity (list :turn (float-time))))
      ((or 'turn-complete 'error)
       (setq activity (plist-put activity :turn nil)))
      ('tool-call-update
       (let* ((data (map-elt event :data))
              (id (map-elt data :tool-call-id))
              (call (map-elt data :tool-call))
              (text (agent-workflow--pane-action-text call))
              (kind (map-elt call :kind))
              (actions (plist-get activity :actions)))
         (if (not text)
             (setq changed nil)
           (if-let* ((action (assoc id actions)))
               (setcdr action (list kind text))
             (setq actions (seq-take (cons (list id kind text) actions) agent-workflow-pane-box-lines)))
           (setq activity (plist-put activity :actions actions))
           (unless (plist-get activity :turn)
             (setq activity (plist-put activity :turn (float-time)))))))
      (_ (setq changed nil)))
    (when changed
      (puthash agent activity agent-workflow--pane-activity))))

(add-hook 'agent-workflow-agent-event-functions #'agent-workflow--pane-agent-event)

(defun agent-workflow--pane-agent-doing (run job state)
  "What JOB of RUN in STATE has its agent at, in a few words: fixing step N
\(name) · try X of Y, resolving its conflicts, its agent step (step N
\(name)); nil if its agent isn't at work (a script step runs, its agent
kept for later)."
  (let* ((steps (plist-get (agent-workflow--job-spec run job) :steps))
         (retry (plist-get state :retry))
         (index (or retry (plist-get state :step) 0))
         (step (nth index steps))
         (name (and step (format "step %d (%s)" (1+ index) (agent-workflow--pane-step-name step)))))
    (cond ((and retry (plist-get state :resolving)) "resolving its conflicts")
          (retry (format "fixing %s · try %d of %d" name
                         (or (alist-get retry (plist-get state :tries)) 1)
                         (1+ (or (plist-get step :retries) 0))))
          ((and step (eq (plist-get step :kind) 'agent)) name))))

(defun agent-workflow--pane-box-of (id title lines none actions)
  "A live box: ID, TITLE, its LINES (texts, or {level, text}) as a log, the
last `agent-workflow-pane-box-lines'; none yet, NONE said, muted (a log of
it was counted as a line of output: 1 line); its ACTIONS."
  (append (list :id id :title title)
          (if lines
              (list :type "log" :show agent-workflow-pane-box-lines :lines lines)
            (list :type "text" :face "muted" :text none))
          (list :actions actions)))

(defun agent-workflow--pane-agent-box (job state)
  "JOB's live box while its agent works (STATE its job's; nil else): its
job, its agent (agent ci), what on, how long its turn's been (or that it
asks you) as its title; its last actions, the latest last, each marked by
its kind; Show session (at its question, if it asks)."
  (when-let* (((not (plist-get state :fix-script)))
              (agent (plist-get state :agent))
              ((agent-workflow-agent-p agent))
              ((not (agent-workflow-agent-stopping agent)))
              ((buffer-live-p (agent-workflow-agent-buffer agent)))
              (doing (agent-workflow--pane-agent-doing agent-workflow--pane-run job state)))
    (let* ((activity (gethash agent agent-workflow--pane-activity))
           (turn (plist-get activity :turn))
           (asks (and (eq (plist-get state :status) 'waiting) (plist-get state :agent-asks))))
      (agent-workflow--pane-box-of
            (agent-workflow--pane-box-id job)
            ;; An agent's, said (its name alone read as part of its job's
            ;; name: a script's box, it looked).
            (string-join (delq nil (list job (concat "agent " (agent-workflow-agent-definition agent)) doing
                                                (cond (asks "asks you")
                                                      (turn (format "its turn %s"
                                                                    (agent-workflow--duration-words
                                                                     (round (- (float-time) turn))))))))
                                " · ")
            ;; Its actions, not output: no level found in their words (a
            ;; command's --log-failed no error).
            (mapcar (lambda (action)
                      (list :level "info"
                            :text (format "%s %s" (or (cdr (assoc (nth 1 action) agent-workflow--pane-action-marks)) "•")
                                          (nth 2 action))))
                    (reverse (plist-get activity :actions)))
            "Nothing done yet in this turn."
            ;; Its own (`agent-workflow--pane-answer'): hovered, what it opens.
            (list (if asks
                      (list :label "Go to it" :prompt (concat "session " job) :help "its session, at its question")
                    (list :label "Show session" :prompt (concat "session " job)
                          :help "its agent-shell session, whole")))))))

(defun agent-workflow--pane-output-lines (process)
  "PROCESS's output so far, its last lines (`agent-workflow-pane-box-lines'):
its colours' codes gone, a line redrawn in place (\\r) its last state."
  (when-let* ((buffer (process-buffer process))
              ((buffer-live-p buffer)))
    (with-current-buffer buffer
      (let* ((start (save-excursion
                      (goto-char (point-max))
                      (forward-line (- (* 2 agent-workflow-pane-box-lines)))
                      (point)))
             (text (ansi-color-filter-apply (buffer-substring-no-properties start (point-max)))))
        (last (seq-remove #'string-blank-p
                          (mapcar (lambda (line) (or (car (last (split-string line "\r" t))) ""))
                                  (split-string text "\n")))
              agent-workflow-pane-box-lines)))))

(defun agent-workflow--pane-script-box (job state)
  "JOB's live box while a script step of its runs (STATE its job's; nil
else): its job, script (else what its step does), its step, its try, its
command and how long it's run as its title; its on-fail script fixing it,
on-fail script, what it fixes, its command. Its output's last lines as it
comes; Show output."
  (when-let* ((process (plist-get state :process))
              ((processp process))
              ((process-live-p process)))
    (let* ((run agent-workflow--pane-run)
           (fixing (plist-get state :fix-script))
           (index (or (plist-get state :step) 0))
           (step (nth index (plist-get (agent-workflow--job-spec run job) :steps)))
           (try (alist-get index (plist-get state :tries)))
           (times (gethash job agent-workflow--pane-times))
           (started (if fixing
                        (plist-get times :fix-started)
                      (plist-get (alist-get index (plist-get times :steps)) :started)))
           (command (lambda (text)
                      (truncate-string-to-width (car (split-string (string-trim (format "%s" text)) "\n"))
                                                60 nil nil "…"))))
      (agent-workflow--pane-box-of
            (agent-workflow--pane-box-id job)
            (string-join
                    (delq nil (if fixing
                                  (list job "on-fail script"
                                        (and step (format "fixing step %d (%s)" (1+ index) (agent-workflow--pane-step-name step)))
                                        (and (numberp try) (format "try %d of %d" try (1+ (or (plist-get step :retries) 0))))
                                        (funcall command (plist-get step :on-fail-run))
                                        (and started (agent-workflow--duration-words (round (- (float-time) started)))))
                                (list job
                                    ;; A script's, said; its command after its step.
                                    (if (eq (plist-get step :kind) 'run) "script" (and step (agent-workflow--pane-step-does step)))
                                    (and step (format "step %d (%s)" (1+ index) (agent-workflow--pane-step-name step)))
                                    (and (numberp try) (> try 1) (format "try %d" try))
                                    (and (eq (plist-get step :kind) 'run) (funcall command (plist-get step :run)))
                                    (and started (agent-workflow--duration-words (round (- (float-time) started)))))))
                    " · ")
            (agent-workflow--pane-output-lines process)
            "No output yet."
            (list (list :label "Show output" :prompt (concat "output " job)
                        :help "its output so far, whole"))))))

(defun agent-workflow--pane-box (job state)
  "JOB's live box (STATE its job's), while it runs: its agent's at work,
else its script's; nil if it runs neither (it waits for a free agent,
for you, or it's over)."
  (and (memq (plist-get state :status) '(running waiting))
       (not (plist-get state :pool))
       (or (agent-workflow--pane-agent-box job state)
           (agent-workflow--pane-script-box job state))))

(defun agent-workflow--pane-show-boxes (run pane)
  "RUN's live boxes in PANE's Run section, a box each job running
\(`agent-workflow--pane-box'), at its bottom (under its jobs, Rounds), each
drawn again only once it changed; a job no longer running, its box gone.
Its old sections of its jobs' agents (a pane drawn before): gone."
  (with-current-buffer pane
    (dolist (section (mapcar #'agent-ui--section-name agent-ui--sections))
      (when (string-prefix-p "job." section)
        (agent-ui-remove-section pane section)))
    (let ((agent-ui-display-function #'ignore)
          (shown agent-workflow--pane-boxes)
          (now nil))
      (dolist (job (agent-workflow-run-jobs run))
        (when-let* ((box (agent-workflow--pane-box (car job) (cdr job))))
          (push (cons (car job) box) now)))
      (setq now (nreverse now))
      ;; Gone: removed.
      (dolist (old shown)
        (unless (assoc (car old) now)
          (when (gethash (agent-ui--key (plist-get (cdr old) :id) "run") agent-ui--entries)
            (agent-ui-remove (plist-get (cdr old) :id) :canvas pane :section "run"))))
      ;; At the Run section's bottom, under Rounds: one above it (Rounds
      ;; came after it), they're all shown again, under it.
      (when-let* ((at (cl-position "run/rounds" agent-ui--order :test #'equal))
                  ((seq-some (lambda (box)
                               (let ((key (agent-ui--key (plist-get (cdr box) :id) "run")))
                                 (and (gethash key agent-ui--entries)
                                      (< (cl-position key agent-ui--order :test #'equal) at))))
                             now)))
        (dolist (box now)
          (when (gethash (agent-ui--key (plist-get (cdr box) :id) "run") agent-ui--entries)
            (agent-ui-remove (plist-get (cdr box) :id) :canvas pane :section "run")))
        (setq shown nil))
      ;; New, or changed: drawn (a new one at the bottom).
      (dolist (box now)
        (unless (equal (cdr (assoc (car box) shown)) (cdr box))
          (agent-ui-show (cdr box) :canvas pane :section "run")))
      (setq agent-workflow--pane-boxes now)
      (when (and now (not (timerp agent-workflow--pane-boxes-timer)))
        (setq agent-workflow--pane-boxes-timer (run-at-time 1 1 #'agent-workflow--pane-boxes-tick))))))

(defun agent-workflow--pane-boxes-tick ()
  "Each second, while a pane shows a job running: its boxes drawn again
\(what changed); stopped once none does."
  (let ((any nil))
    (dolist (run agent-workflow--runs)
      (when-let* ((pane (agent-workflow--pane-live run)))
        (with-demoted-errors "agent workflow's pane: %S"
          (agent-workflow--pane-show-boxes run pane))
        (when (buffer-local-value 'agent-workflow--pane-boxes pane)
          (setq any t))))
    (unless any
      (when (timerp agent-workflow--pane-boxes-timer)
        (cancel-timer agent-workflow--pane-boxes-timer))
      (setq agent-workflow--pane-boxes-timer nil))))

(defun agent-workflow--pane-go-to-agent (run job)
  "JOB of RUN's agent's session shown (its box's Show session), at its
question if it asks you."
  (if-let* ((asks (plist-get (agent-workflow--job run job) :agent-asks))
            ((eq (plist-get (agent-workflow--job run job) :status) 'waiting)))
      (agent-workflow--pane-answer-agent run job (plist-get asks :kind) agent-workflow--pane-go-to-it)
    (agent-workflow--pane-open-session run job)))

(defun agent-workflow--pane-show-output (run job)
  "JOB of RUN's script's output so far shown (its box's Show output), at its end."
  (if-let* ((process (plist-get (agent-workflow--job run job) :process))
            ((processp process))
            (buffer (process-buffer process))
            ((buffer-live-p buffer)))
      (progn
        (pop-to-buffer buffer)
        (goto-char (point-max)))
    (user-error "%s runs no script now" job)))

(defun agent-workflow--pane-agent-stopped (agent)
  "AGENT stops (its job over, sent back, its run cancelled...): what it did
forgotten, its box gone at the next tick. In
`agent-workflow-agent-stop-functions'."
  (remhash agent agent-workflow--pane-activity))

(add-hook 'agent-workflow-agent-stop-functions #'agent-workflow--pane-agent-stopped)

(defun agent-workflow--pane-open-session (run job)
  "JOB of RUN's agent's session shown."
  (let ((agent (plist-get (agent-workflow--job run job) :agent)))
    (if-let* ((buffer (and agent (agent-workflow-agent-buffer agent)))
              ((buffer-live-p buffer)))
        (pop-to-buffer buffer)
      (user-error "%s has no agent working now" job))))

;; ====== DRAWING IT ======

(defun agent-workflow--pane-draw (run &optional made)
  "RUN's pane drawn again from RUN: its header, its jobs and their live
boxes, Needs you, Notes. MADE: just made (not shown while it's drawn)."
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
      (agent-workflow--pane-show-boxes run pane)))

(defun agent-workflow--pane-show-notes (_run pane)
  "PANE's Notes (its agents' verdicts, a feed, each unfolding to its whole):
its section once the first came, after Run and Needs you, before Log;
those you unfolded kept so."
  (let ((open (plist-get (and (gethash "notes/notes" (buffer-local-value 'agent-ui--entries pane))
                              (agent-ui-get "notes" :canvas pane :section "notes"))
                         :open)))
    (when-let* ((notes (agent-workflow--pane-notes-element open)))
      (unless (agent-ui--find-section "notes")
        (agent-ui-section pane "notes" :title "Notes" :after (agent-workflow--pane-after-jobs)))
      (agent-ui-show notes :canvas pane :section "notes"))))

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
