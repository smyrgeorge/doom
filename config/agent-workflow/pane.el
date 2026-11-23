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
;; - Log: its last events (log.el).
;;
;; What an agent shows on its own canvas (its plan, its progress) stays with
;; its session: Show session. Its canvas opens a pane of its own only while
;; it asks you something there (pool.el).
;;
;; Its parts: this file, the pane and what it shows; pane-answer.el, Needs
;; you and its buttons; pane-boxes.el, the live boxes.
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
(declare-function agent-workflow--where-stamp "agent-workflow/where")
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
header, each nil if it isn't shown, each with a caption (branch, 3
commits, 12 files changed, as a log's counts), in this order: git (its branch,
buttons opening its worktree, magit; in your checkout, magit alone: its
worktree is your project), commits (its latest, a line each: RET shows
one), changes (its files changed since it started: RET opens one), where-note (its base branch's commits its
merge takes too)."
  (let* ((line (agent-workflow--pane-git-line where))
         (worktree (plist-get where :worktree))
         (files (plist-get where :files))
         (commits (plist-get where :commits))
         (base (plist-get where :base))
         (with (or (plist-get where :with) 0)))
    (list (and line
               (append (list :id "git" :type "text" :caption "branch" :text line)
                       (when worktree
                         ;; Its own (`agent-workflow--pane-answer'): hovered, what they open.
                         (list :actions (if (plist-get where :checkout)
                                            '((:label "Magit" :prompt "magit" :help "magit on your checkout"))
                                          '((:label "Worktree" :prompt "worktree" :help "open its worktree")
                                            (:label "Magit" :prompt "magit" :help "magit on its worktree")))))))
          ;; A line each (its subject cut), RET or a click opening it.
          (and commits
               (list :id "commits" :type "table" :columns '("" "") :nowrap t
                     ;; How many, as a log's counts (its own may be more than shown).
                     :caption (let ((all (max (or (plist-get where :own) 0) (length commits))))
                                (if (> all (length commits))
                                    (format "%d commits, the last %d" all (length commits))
                                  (format "%d commit%s" all (if (= all 1) "" "s"))))
                     :rows (mapcar (lambda (commit) (list (nth 0 commit) (or (nth 1 commit) ""))) commits)
                     ;; Its own (`agent-workflow--pane-answer'): {0} its hash.
                     :row-open '(:prompt "{0}" :help "show this commit")))
          ;; Its worktree gone (merged, deleted): its files from its commits,
          ;; opened in your checkout.
          (and files
               (list :id "changes" :type "files"
                     :caption (let ((uncommitted (cl-count-if (lambda (file) (plist-get file :uncommitted)) files)))
                                (concat (format "%d file%s changed" (length files) (if (= (length files) 1) "" "s"))
                                        (if (> uncommitted 0) (format " · %d not committed" uncommitted) "")))
                     :dir (or worktree (and run (file-name-as-directory (agent-workflow-run-project run))))
                     :tree (if (> (length files) 12) t :false)
                     :files (mapcar (lambda (file)
                                      (append (list :path (plist-get file :path)
                                                    :status (symbol-name (plist-get file :status)))
                                              (and (plist-get file :added) (list :added (plist-get file :added)))
                                              (and (plist-get file :removed) (list :removed (plist-get file :removed)))
                                              (and (plist-get file :uncommitted) (list :note "not committed"))))
                                    files)))
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

;; ====== DRAWING IT ======

(defun agent-workflow--pane-draw (run &optional made)
  "RUN's pane drawn again from RUN: its header, its jobs and their live
boxes, Needs you, Notes. MADE: just made (not shown while it's drawn)."
  (when-let* ((pane (agent-workflow--pane-live run)))
    (with-current-buffer pane
      (agent-workflow--pane-draw-in run pane made))))

(defun agent-workflow--pane-show-where (run pane)
  "RUN's git under its header in PANE (`agent-workflow--pane-git'): each
element shown, or removed once it isn't, in their order (one coming after
those after it, its commits after its files: those after it shown again)."
  ;; A pane drawn before: its worktree's row, now git's buttons.
  (when (gethash "where" agent-ui--entries)
    (agent-ui-remove "where" :canvas pane))
  (let* ((ids '("git" "commits" "changes" "where-note"))
         (elements (agent-workflow--pane-git run (agent-workflow-run-where run)))
         ;; The canvas's own: its key its id. Shown, in the order they are.
         (shown (seq-filter (lambda (key) (member key ids)) agent-ui--order))
         (wanted (cl-loop for id in ids for element in elements when element collect id))
         ;; As they'd be: those shown staying in their places, new ones
         ;; after them all.
         (in-order (equal (append (seq-filter (lambda (key) (member key wanted)) shown)
                                  (seq-remove (lambda (id) (member id shown)) wanted))
                          wanted)))
    (cl-loop for id in ids
             for element in elements
             do (cond (element
                       ;; Out of order: those shown after its place again, after it.
                       (when (and (not in-order) (gethash id agent-ui--entries))
                         (agent-ui-remove id :canvas pane))
                       (agent-ui-show element :canvas pane))
                      ((gethash id agent-ui--entries) (agent-ui-remove id :canvas pane))))))

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
