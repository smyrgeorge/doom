;;; $DOOMDIR/config/agent-workflow/budget.el -*- lexical-binding: t; -*-
;; A run's budget: what it may spend, then it asks you. Loaded from
;; config/agent-workflow.el, after resume.el. No Doom here.
;;
;; A workflow's budget: (or `agent-workflow-budget', for one without) caps
;; each of its runs: its cost (dollars, as agent-shell's usage reports have
;; them), its tokens, its time (the run's, while it runs or waits for an
;; agent: not while it waits for you). What it spent is its agents', those
;; gone kept with the run, those working read from their sessions. At 80% of
;; any, it's said, once (in its journal, and as a message). At its budget,
;; its running steps are stopped (their work kept, their agents' sessions
;; kept to resume them) and the run asks you: go on, with more (cost, tokens
;; or time added), its steps continued; or stop.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'map)

(defvar agent-shell--state)
(defvar agent-workflow-budget)

(defvar agent-workflow--budget-timer nil
  "Looks at the runs' time, while one with a time budget runs.")

;; ====== WHAT A RUN SPENT ======

(defun agent-workflow--agent-usage (agent)
  "What AGENT's session spent so far: (:cost N :tokens N)."
  (let ((buffer (agent-workflow-agent-buffer agent)))
    (if (and buffer (buffer-live-p buffer))
        (with-current-buffer buffer
          (let ((usage (and (local-variable-p 'agent-shell--state) (map-elt agent-shell--state :usage))))
            (list :cost (or (map-elt usage :cost-amount) 0) :tokens (or (map-elt usage :total-tokens) 0))))
      (list :cost 0 :tokens 0))))

(defun agent-workflow--agent-gone (agent)
  "AGENT stops: what it spent kept with its run. In
`agent-workflow-agent-stop-functions'."
  (when-let* ((found (agent-workflow--agent-run agent)))
    (let* ((run (car found))
           (usage (agent-workflow--agent-usage agent))
           (spent (agent-workflow-run-spent run)))
      (setf (agent-workflow-run-spent run)
            (list :cost (+ (or (plist-get spent :cost) 0) (plist-get usage :cost))
                  :tokens (+ (or (plist-get spent :tokens) 0) (plist-get usage :tokens)))))))

(defun agent-workflow-run-spent-now (run)
  "What RUN spent so far: (:cost DOLLARS :tokens N :time SECONDS), its
agents gone and working."
  (let ((cost (or (plist-get (agent-workflow-run-spent run) :cost) 0))
        (tokens (or (plist-get (agent-workflow-run-spent run) :tokens) 0)))
    (dolist (job (agent-workflow-run-jobs run))
      (when-let* ((agent (plist-get (cdr job) :agent)))
        (let ((usage (agent-workflow--agent-usage agent)))
          (cl-incf cost (plist-get usage :cost))
          (cl-incf tokens (plist-get usage :tokens)))))
    (list :cost cost :tokens tokens
          :time (round (+ (agent-workflow-run-active run)
                          (if-let* ((since (agent-workflow-run-active-since run))) (- (float-time) since) 0))))))

;; ====== ITS BUDGET ======

(defun agent-workflow-run-budget (run)
  "RUN's budget: its workflow's (else `agent-workflow-budget'), what you
added to it on top: (:cost :tokens :time), each nil without a cap."
  (let ((budget (or (plist-get (agent-workflow-run-workflow run) :budget) agent-workflow-budget))
        (more (agent-workflow-run-more run)))
    (when (or budget more)
      (cl-loop for key in '(:cost :tokens :time)
               append (list key (and (plist-get budget key)
                                     (+ (plist-get budget key) (or (plist-get more key) 0))))))))

(defun agent-workflow--budget-more (run more)
  "MORE (:cost :tokens :time) added to RUN's budget, its warning reset."
  (let ((before (agent-workflow-run-more run)))
    (setf (agent-workflow-run-more run)
          (cl-loop for key in '(:cost :tokens :time)
                   append (list key (+ (or (plist-get before key) 0) (or (plist-get more key) 0))))
          (agent-workflow-run-warned run) nil)
    (agent-workflow--journal run "budget-more" :cost (plist-get more :cost) :tokens (plist-get more :tokens)
                             :time (plist-get more :time))
    (agent-workflow--changed run)))

(defun agent-workflow--budget-words (spent budget)
  "SPENT of BUDGET, as said: \"$12.40 of $15, 2h 10m of 3h\"."
  (string-join
   (delq nil
         (list (and (plist-get budget :cost) (format "$%.2f of $%s" (plist-get spent :cost) (plist-get budget :cost)))
               (and (plist-get budget :tokens) (format "%d of %d tokens" (plist-get spent :tokens) (plist-get budget :tokens)))
               (and (plist-get budget :time) (format "%s of %s" (agent-workflow--duration-words (plist-get spent :time))
                                                     (agent-workflow--duration-words (plist-get budget :time))))))
   ", "))

(defun agent-workflow--duration-words (seconds)
  "SECONDS as said: 2h 10m, 4m 5s, 30s."
  (let ((h (/ seconds 3600)) (m (/ (% seconds 3600) 60)) (s (% seconds 60)))
    (string-join (delq nil (list (and (> h 0) (format "%dh" h)) (and (> m 0) (format "%dm" m))
                                 (and (or (> s 0) (= seconds 0)) (= h 0) (format "%ds" s))))
                 " ")))

(defun agent-workflow--budget-share (run)
  "How much of RUN's budget it spent: the most of its parts, 0 without one."
  (let ((budget (agent-workflow-run-budget run))
        (spent (agent-workflow-run-spent-now run)))
    (apply #'max 0 (delq nil (mapcar (lambda (key)
                                       (when-let* ((limit (plist-get budget key)))
                                         (/ (float (plist-get spent key)) limit)))
                                     '(:cost :tokens :time))))))

(defun agent-workflow-check-budget (run)
  "RUN looked at against its budget: near it (80%), said once; at it, its
running steps stopped and you asked."
  (when (and (agent-workflow-run-budget run) (not (memq (agent-workflow-run-state run) agent-workflow--ended)))
    (let ((share (agent-workflow--budget-share run))
          (words (agent-workflow--budget-words (agent-workflow-run-spent-now run) (agent-workflow-run-budget run))))
      (cond
       ((>= share 1.0)
        (let ((running (mapcar #'car (agent-workflow--status-of run 'running))))
          (when running
            (agent-workflow--journal run "budget-used-up" :spent words)
            (dolist (job running)
              (agent-workflow--interrupt run job)
              (agent-workflow--job-set run job :ask (list :kind 'budget :step (or (plist-get (agent-workflow--job run job) :step) 0)))
              (agent-workflow--wait run job (format "%s: its run's budget is used up (%s): go on with more, or stop?"
                                                    job words))))))
       ((and (>= share 0.8) (not (agent-workflow-run-warned run)))
        (setf (agent-workflow-run-warned run) t)
        (agent-workflow--journal run "budget-near" :spent words)
        (agent-workflow--changed run)
        (message "%s: near its budget (%s)" (agent-workflow-run-name run) words))))))

(defun agent-workflow--check-budgets ()
  "Every run not over looked at against its budget; this looked at again
while one with a time budget runs."
  (let ((timed nil))
    (dolist (run agent-workflow--runs)
      (with-demoted-errors "agent workflow: %S" (agent-workflow-check-budget run))
      (when (and (agent-workflow-run-active-since run) (plist-get (agent-workflow-run-budget run) :time))
        (setq timed t)))
    (cond ((and timed (not (timerp agent-workflow--budget-timer)))
           (setq agent-workflow--budget-timer (run-at-time 30 30 #'agent-workflow--check-budgets)))
          ((and (not timed) (timerp agent-workflow--budget-timer))
           (cancel-timer agent-workflow--budget-timer)
           (setq agent-workflow--budget-timer nil)))))

(defun agent-workflow--budget-event (agent event)
  "An event of AGENT's session: its usage reported, its run looked at
against its budget. In `agent-workflow-agent-event-functions'."
  (when (eq (map-elt event :event) 'usage-update)
    (when-let* ((found (agent-workflow--agent-run agent)))
      (agent-workflow-check-budget (car found)))))

(add-hook 'agent-workflow-agent-event-functions #'agent-workflow--budget-event)
(add-hook 'agent-workflow-agent-stop-functions #'agent-workflow--agent-gone)

(defvar agent-workflow--budget-soon nil "The next look at the budgets, soon.")

(defun agent-workflow--budget-timer-soon (&rest _)
  "The budgets looked at once Emacs is free (a run changed). In
`agent-workflow-run-functions'."
  (unless (timerp agent-workflow--budget-soon)
    (setq agent-workflow--budget-soon
          (run-at-time 0 nil (lambda ()
                               (setq agent-workflow--budget-soon nil)
                               (agent-workflow--check-budgets))))))

(add-hook 'agent-workflow-run-functions #'agent-workflow--budget-timer-soon)
