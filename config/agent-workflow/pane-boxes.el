;;; $DOOMDIR/config/agent-workflow/pane-boxes.el -*- lexical-binding: t; -*-
;; A run's pane's live boxes: what each job running runs, its agent at
;; work or its script, as it goes.
;; Loaded from config/agent-workflow.el, after pane-answer.el. No Doom here.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'map)
(require 'ansi-color)


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
