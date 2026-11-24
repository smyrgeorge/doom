;;; $DOOMDIR/config/agent-workflow/pane-boxes.el -*- lexical-binding: t; -*-
;; A run's pane's live boxes: what each job running runs, its agent at
;; work or its script, as it goes.
;; Loaded from config/agent-workflow.el, after pane-answer.el. No Doom here.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'map)
(require 'ansi-color)

(defvar agent-shell--state)


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
known better; a new one counted); its box drawn again at the next tick. In
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
             (setq actions (seq-take (cons (list id kind text) actions) agent-workflow-pane-box-lines)
                   activity (plist-put activity :count (1+ (or (plist-get activity :count) 0)))))
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

(defun agent-workflow--pane-model-name (value name description)
  "A model as a box says it: VALUE, its id; NAME and DESCRIPTION, as its
session lists it. Its default: what it is (its description: Opus 5.5),
else \"default model\"; another, its name (Sonnet 5.5), else its id."
  (cond ((equal value "default")
         (if (and description (not (string-blank-p description))) description "default model"))
        ((and name (not (string-blank-p name))) name)
        (t value)))

(defun agent-workflow--pane-agent-model (agent)
  "What AGENT's session runs, as its box says it: its model and its effort
\(Opus 5.5 · high effort), as its session says (its config options, else
its model), what it was asked for until it does (its step's, else its
agent's); nil if neither is known."
  (let* ((buffer (agent-workflow-agent-buffer agent))
         (state (and (buffer-live-p buffer) (buffer-local-boundp 'agent-shell--state buffer)
                     (buffer-local-value 'agent-shell--state buffer)))
         (reported (and state (map-elt state :config-options)))
         ;; An option by its id, else its category (ACP's: model,
         ;; thought_level), as agent-shell finds it.
         (option (lambda (id category)
                   (or (seq-find (lambda (option) (equal (map-elt option :id) id)) reported)
                       (seq-find (lambda (option) (equal (map-elt option :category) category)) reported))))
         ;; What it was asked for: its step's, else its agent's.
         (asked (lambda (key)
                  (or (plist-get (list :model (agent-workflow-agent-model agent)
                                       :effort (agent-workflow-agent-effort agent))
                                 key)
                      (when-let* ((project (agent-workflow-agent-project agent)))
                        (plist-get (alist-get (agent-workflow-agent-definition agent)
                                              (ignore-errors (agent-workflow-agent-definitions project))
                                              nil nil #'equal)
                                   key)))))
         (model (if-let* ((model (funcall option "model" "model")))
                    (let* ((value (map-elt model :current-value))
                           (entry (seq-find (lambda (entry) (equal (map-elt entry :value) value))
                                            (map-elt model :options))))
                      (agent-workflow--pane-model-name value (map-elt entry :name) (map-elt entry :description)))
                  (if-let* ((id (and state (map-nested-elt state '(:session :model-id)))))
                      (let ((entry (seq-find (lambda (entry) (equal (map-elt entry :model-id) id))
                                             (map-nested-elt state '(:session :models)))))
                        (agent-workflow--pane-model-name id (map-elt entry :name) (map-elt entry :description)))
                    (and (not reported) (funcall asked :model)))))
         (effort (if-let* ((effort (funcall option "effort" "thought_level")))
                     (map-elt effort :current-value)
                   (and (not reported) (funcall asked :effort)))))
    (when (or model effort)
      (string-join (delq nil (list model (and effort (concat effort " effort")))) " · "))))

(cl-defun agent-workflow--pane-box-of (id job &key label detail right right-face waiting lines footer empty actions)
  "A live box, Agent UI's activity: ID; JOB in its colour (its Log's, by
its place in its run), what it runs (LABEL), DETAIL muted, RIGHT at its
end (in RIGHT-FACE); ● (◆, yellow, WAITING for you); its LINES under it (a
log's: text, or {text, level, mark, mark-face}), all shown, EMPTY said
while there are none; FOOTER closing them; its ACTIONS. In the pane's
buffer."
  (append (list :id id :type "activity" :owner job :label (or label "")
                :sources (mapcar #'car (agent-workflow-run-jobs agent-workflow--pane-run))
                :show (max 1 (length lines)) :lines lines)
          (if waiting (list :mark "◆" :mark-face "warning") (list :mark "●" :mark-face "accent"))
          (and detail (list :detail detail))
          (and right (list :right right))
          (and right-face (list :right-face right-face))
          (and footer (list :footer footer))
          (and empty (list :empty empty))
          (list :actions actions)))

(defun agent-workflow--pane-agent-box (job state)
  "JOB's live box while its agent works (STATE its job's; nil else): its
agent (agent ci), its model and effort, what on, how long its turn's been
\(or that it asks you, ◆) in its header; its last actions, each marked by its kind, the latest
bright, those before muted; what it asks you after them; how many in its
turn; Show session (at its question, if it asks)."
  (when-let* (((not (plist-get state :fix-script)))
              (agent (plist-get state :agent))
              ((agent-workflow-agent-p agent))
              ((not (agent-workflow-agent-stopping agent)))
              ((buffer-live-p (agent-workflow-agent-buffer agent)))
              (doing (agent-workflow--pane-agent-doing agent-workflow--pane-run job state)))
    (let* ((activity (gethash agent agent-workflow--pane-activity))
           (turn (plist-get activity :turn))
           (asks (and (eq (plist-get state :status) 'waiting) (plist-get state :agent-asks)))
           (actions (reverse (plist-get activity :actions)))
           (count (or (plist-get activity :count) (length actions)))
           (newest (car (last actions))))
      (agent-workflow--pane-box-of
       (agent-workflow--pane-box-id job) job
       ;; An agent's, said (its name alone read as part of its job's: a
       ;; script's box, it looked).
       :label (concat "agent " (agent-workflow-agent-definition agent))
       ;; What it runs on first: its model and effort.
       :detail (string-join (delq nil (list (agent-workflow--pane-agent-model agent) doing)) " · ")
       :waiting (or asks (eq (plist-get state :status) 'waiting))
       :right (cond (asks "asks you")
                    (turn (format "its turn %s" (agent-workflow--duration-words (round (- (float-time) turn))))))
       :right-face (and asks "warning")
       ;; Its actions, the latest last, bright (what it's at), those
       ;; before muted; what it asks you after them. Their words no
       ;; level (a command's --log-failed no error).
       :lines (append (mapcar (lambda (action)
                                (let ((mark (or (cdr (assoc (nth 1 action) agent-workflow--pane-action-marks)) "•")))
                                  (if (and (eq action newest) (not asks))
                                      (list :mark mark :mark-face "accent" :text (nth 2 action))
                                    (list :mark mark :mark-face "muted" :level "debug" :text (nth 2 action)))))
                              actions)
                      (and asks
                           (list (list :mark "?" :mark-face "warning" :level "warning"
                                       :text (concat (if (eq (plist-get asks :kind) 'permission) "may it: " "")
                                                     (or (plist-get asks :what) "its question, in its session"))))))
       :footer (and (or actions asks)
                    (concat (format "%d action%s in this turn" count (if (= count 1) "" "s"))
                            (if asks " · waiting for your answer" "")))
       :empty "Nothing done yet in this turn."
       ;; Its own (`agent-workflow--pane-answer'): hovered, what it opens.
       :actions (list (if asks
                          (list :label "Go to it" :prompt (concat "session " job) :help "its session, at its question")
                        (list :label "Show session" :prompt (concat "session " job)
                              :help "its agent-shell session, whole")))))))

(defvar agent-workflow--pane-output-counts (make-hash-table :test #'eq :weakness 'key)
  "Each script's output counted so far, by its process: (:pos POS :lines N
:errors N :warnings N), POS where it's read up to (its lines read once).")

(defun agent-workflow--pane-output-counts (process)
  "PROCESS's output counted (`agent-workflow--pane-output-counts'): its
lines not blank, its errors and warnings (by their words, as a log finds
them), read on from where it was last; nil without its buffer."
  (when-let* ((buffer (process-buffer process))
              ((buffer-live-p buffer)))
    (with-current-buffer buffer
      (let* ((counts (gethash process agent-workflow--pane-output-counts))
             (counts (if (and counts (<= (plist-get counts :pos) (point-max)))
                         (copy-sequence counts)
                       (list :pos (point-min) :lines 0 :errors 0 :warnings 0)))
             (end (save-excursion (goto-char (point-max)) (skip-chars-backward "^\n") (point))))
        (when (> end (plist-get counts :pos))
          (dolist (line (split-string (ansi-color-filter-apply
                                       (buffer-substring-no-properties (plist-get counts :pos) end))
                                      "\n"))
            (let ((line (or (car (last (split-string line "\r" t))) "")))
              (unless (string-blank-p line)
                (setq counts (plist-put counts :lines (1+ (plist-get counts :lines))))
                (pcase (agent-ui-log--level line)
                  ('error (setq counts (plist-put counts :errors (1+ (plist-get counts :errors)))))
                  ('warning (setq counts (plist-put counts :warnings (1+ (plist-get counts :warnings)))))))))
          (setq counts (plist-put counts :pos end)))
        (puthash process counts agent-workflow--pane-output-counts)))))

(defun agent-workflow--pane-output-footer (process shown)
  "PROCESS's output's counts, its box's footer, SHOWN its lines shown: the
last 5 of 214 lines (5 lines, all), its errors and warnings in their
colours; nil without output."
  (when-let* ((counts (agent-workflow--pane-output-counts process))
              (all (max (plist-get counts :lines) shown))
              ((> all 0)))
    (let ((errors (plist-get counts :errors))
          (warnings (plist-get counts :warnings)))
      (append (list (if (> all shown)
                        (format "the last %d of %d lines" shown all)
                      (format "%d line%s" all (if (= all 1) "" "s"))))
              (and (> errors 0) (list " · " (list :text (format "%d error%s" errors (if (= errors 1) "" "s"))
                                                    :face "error")))
              (and (> warnings 0) (list " · " (list :text (format "%d warning%s" warnings (if (= warnings 1) "" "s"))
                                                      :face "warning")))))))

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
else): its script's name (else its file), its step of all and its try, how
long it's run; its on-fail script fixing it, said, what it fixes and its
try. Its command first, muted, its output's last lines under it as it
comes; how many lines, errors and warnings in all; Show output."
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
           ;; Its first line: the box cuts it to its width.
           (command (lambda (text) (car (split-string (string-trim (format "%s" text)) "\n")))))
      (let ((output (agent-workflow--pane-output-lines process))
            (count (length (plist-get (agent-workflow--job-spec run job) :steps))))
        (agent-workflow--pane-box-of
         (agent-workflow--pane-box-id job) job
         ;; A script's, named (else its file); its on-fail script, said.
         :label (if fixing "on-fail script" (agent-workflow--pane-log-step run (list :job job :step index)))
         :detail (if fixing
                     (string-join (delq nil (list (and step (format "fixing %s" (agent-workflow--pane-log-step
                                                                                 run (list :job job :step index))))
                                                  (and (numberp try)
                                                       (format "try %d of %d" try (1+ (or (plist-get step :retries) 0))))))
                                  " · ")
                   (concat (format "step %d of %d" (1+ index) count)
                           (if (and (numberp try) (> try 1)) (format " · try %d" try) "")))
         :right (and started (agent-workflow--duration-words (round (- (float-time) started))))
         ;; Its command first, muted; its output's last lines under it.
         :lines (append (when-let* ((text (if fixing (plist-get step :on-fail-run) (and (eq (plist-get step :kind) 'run)
                                                                                         (plist-get step :run)))))
                          (list (list :mark "❯" :mark-face "muted" :level "debug" :text (funcall command text))))
                        output)
         :footer (agent-workflow--pane-output-footer process (length output))
         :empty "No output yet."
         :actions (list (list :label "Show output" :prompt (concat "output " job)
                              :help "its output so far, whole")))))))

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
