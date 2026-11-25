;;; $DOOMDIR/config/agent-workflow/answers.el -*- lexical-binding: t; -*-
;; What a run waits for your answer on: its agent asking in its session,
;; a step's result to approve (M-x agent-workflow-approve,
;; agent-workflow-reject). Your answer to its other questions: back.el.
;; Loaded from config/agent-workflow.el, after back.el. No Doom here.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)


;; ====== ITS AGENT ASKS ======
;; An agent asking you in its session (agent-shell's permission-request: a
;; tool its agent doesn't allow without asking; its elicitation-request: a
;; question, its form: Claude Code's AskUserQuestion's) holds its turn until you answer: its
;; job waits for you, saying what it asks, as any wait does (the run's
;; state, status, its pane's Needs you, a notification). Answered, wherever
;; (its session, its pane), the job runs again. Its turn ending, or its
;; session, nothing it asked waits any more.

(defun agent-workflow-agent-asking (run)
  "RUN's job whose agent asks you in its session, and what: (JOB . ASKS),
ASKS (:kind permission|question :what WORDS :why WHY [:request ID]), or nil."
  (seq-some (lambda (job)
              (let* ((state (cdr job))
                     (asks (plist-get state :agent-asks)))
                (and asks (eq (plist-get state :status) 'waiting)
                     (equal (plist-get asks :why) (plist-get state :why))
                     (cons (car job) asks))))
            (agent-workflow-run-jobs run)))

(defun agent-workflow--agent-asks (agent kind what &optional request)
  "AGENT asks you KIND (permission, question) of WHAT (its tool call's
title, the question; nil), REQUEST its question's id (its form in its
session: answered in its pane): its job, running, waits for you."
  (when-let* ((found (agent-workflow--agent-run agent)))
    (pcase-let ((`(,run . ,job) found))
      (when (eq (plist-get (agent-workflow--job run job) :status) 'running)
        (let* ((what (and (stringp what)
                          (let ((line (string-trim (car (split-string (string-trim what) "\n")))))
                            (and (not (string-empty-p line)) line))))
               (why (format "%s: its agent asks %s%s" job
                            (if (eq kind 'permission) "for your permission" "you")
                            (if what (concat ": " what) ""))))
          (agent-workflow--job-set run job :agent-asks (append (list :kind kind :what what :why why)
                                                               (and request (list :request request))))
          (agent-workflow--journal run "asked" :job job :kind "agent" :what what)
          (agent-workflow--wait run job why))))))

(defun agent-workflow--agent-answered (agent)
  "What AGENT asked answered, in its session or its pane: its job runs
again."
  (when-let* ((found (agent-workflow--agent-run agent))
              ((agent-workflow--agent-asks-over agent)))
    (pcase-let ((`(,run . ,job) found))
      (agent-workflow--journal run "answered" :job job :choice "answered its agent" :by "you")
      (agent-workflow--refresh run))))

(defun agent-workflow--agent-asks-over (agent)
  "Nothing AGENT asked waits any more: its job, waiting for it, running
again (its run's state not worked out again). Its run if it asked."
  (when-let* ((found (agent-workflow--agent-run agent)))
    (pcase-let* ((`(,run . ,job) found)
                 (state (agent-workflow--job run job))
                 (asks (plist-get state :agent-asks)))
      (when asks
        (agent-workflow--job-set run job :agent-asks nil)
        (when (and (eq (plist-get state :status) 'waiting)
                   (equal (plist-get state :why) (plist-get asks :why)))
          (agent-workflow--job-set run job :status 'running :why nil))
        run))))

;; ====== APPROVAL ======
;; A step with approve: true (a job's: its last step) waits, once it's
;; done, for your OK: the run says so, with what to look at (its outcome and
;; notes, what the branch got since the job started, a script's output), and
;; you're told. Approved, the run goes on. Rejected with a note: an agent
;; step goes back to its agent (in its session, or resumed), then waits for
;; you again; a script's stops the run for you (run it again, skip it, stop).

(defun agent-workflow--needs-approval-p (run job)
  "Non-nil if JOB of RUN's step just done waits for your OK, not given yet."
  (let* ((state (agent-workflow--job run job))
         (index (plist-get state :step))
         (steps (plist-get (agent-workflow--job-spec run job) :steps)))
    (and (or (plist-get (nth index steps) :approve)
             (and (= index (1- (length steps))) (plist-get (agent-workflow--job-spec run job) :approve)))
         (not (eql (plist-get state :approved) index)))))

(defun agent-workflow-to-look-at (run job)
  "What to look at of JOB of RUN's result: a plist (:outcome :notes :diff
:log), :diff what the branch got since the job started (its stat), :log its
last script's output's file."
  (let* ((state (agent-workflow--job run job))
         (start (plist-get state :start-commit))
         (dir (plist-get state :dir))
         (logs (and (file-directory-p (expand-file-name "logs" (agent-workflow-run-dir run)))
                    (directory-files (expand-file-name "logs" (agent-workflow-run-dir run)) t
                                     (concat "\\`" (regexp-quote job) "\\.")))))
    (list :outcome (plist-get state :outcome) :notes (plist-get state :notes)
          :diff (and start dir (file-directory-p dir)
                     (let ((default-directory dir))
                       (string-join (agent-workflow--git-lines "diff" "--stat" start) "\n")))
          :log (car (last logs)))))

(defun agent-workflow--ask-approval (run job)
  "JOB of RUN's result waits for your OK."
  (let ((index (plist-get (agent-workflow--job run job) :step))
        (look (agent-workflow-to-look-at run job)))
    (agent-workflow--job-set run job :ask (list :kind 'approve :step index))
    (agent-workflow--journal run "asked" :job job :step index :kind "approve"
                             :outcome (plist-get look :outcome) :notes (plist-get look :notes)
                             :diff (plist-get look :diff) :log (plist-get look :log))
    (agent-workflow--wait run job (format "%s: its result waits for your OK: approve it, or reject it with a note" job))))

(defun agent-workflow--approval-asked (run)
  "RUN's job whose result waits for your OK, and its question: (JOB . ASK),
or a user error."
  (agent-workflow--refuse-ended run)
  (let ((asking (agent-workflow-asking run)))
    (unless (eq (plist-get (cdr asking) :kind) 'approve)
      (user-error "%s waits for no approval" (agent-workflow-run-name run)))
    asking))

(cl-defun agent-workflow--approve (run &key (by "you"))
  "Approve the result RUN waits for your OK on: the run goes on."
  (pcase-let ((`(,job . ,ask) (agent-workflow--approval-asked run)))
    (agent-workflow--journal run "answered" :job job :choice "approve" :by by)
    (agent-workflow--job-set run job :ask nil :status 'running :why nil :approved (plist-get ask :step) :finished t)
    (agent-workflow--refresh run)
    (agent-workflow--step-finished run job)
    job))

(cl-defun agent-workflow--reject (run note &key (by "you"))
  "Reject the result RUN waits for your OK on, with NOTE: an agent step's
back to its agent (its session, or resumed), asked again once it's done; a
script's stops the run."
  (pcase-let* ((`(,job . ,ask) (agent-workflow--approval-asked run))
               (index (plist-get ask :step))
               (step (nth index (plist-get (agent-workflow--job-spec run job) :steps)))
               (agent (plist-get (agent-workflow--job run job) :agent)))
    (agent-workflow--journal run "answered" :job job :choice "reject" :note note :by by)
    (agent-workflow--run-bd-write run "--append-notes" (format "%s's result rejected by %s: %s" job by note))
    (cond
     ((not (eq (plist-get step :kind) 'agent))
      (agent-workflow--job-set run job :ask (list :kind 'broke :step index :what "its result rejected"))
      (agent-workflow--wait run job (format "%s: its result rejected by you (%s): run it again, skip it, or stop?"
                                            job note)))
     ((and agent (buffer-live-p (agent-workflow-agent-buffer agent)))
      (agent-workflow--job-set run job :ask nil :status 'running :why nil :finished nil :approved nil)
      (agent-workflow--refresh run)
      (agent-workflow-send agent (format "The user rejected your result: %s\n\nChange it, then say done again."
                                         note)))
     (t
      (agent-workflow--job-set run job :ask nil :approved nil)
      (agent-workflow--back run job :step index :note (concat "Your result was rejected: " note) :by by)))
    job))

(defun agent-workflow--read-approval (prompt)
  "A run of the current project waiting for your OK, picked with PROMPT
\(the only one, not asked)."
  (let* ((project (or (agent-workflow-project) (user-error "Not in a git repository")))
         (asking (or (seq-filter (lambda (run) (eq (plist-get (cdr (agent-workflow-asking run)) :kind) 'approve))
                                 (agent-workflow-runs-of project))
                     (user-error "No run waits for your OK"))))
    (if (cdr asking)
        (let ((names (mapcar (lambda (run) (cons (agent-workflow-run-why run) run)) asking)))
          (cdr (assoc (completing-read prompt names nil t) names)))
      (car asking))))

(defun agent-workflow-approve (run)
  "Approve the result RUN waits for your OK on (M-x agent-workflow-approve)."
  (interactive (list (agent-workflow--read-approval "Approve: ")))
  (message "%s: %s approved" (agent-workflow-run-name run) (agent-workflow--approve run)))

(defun agent-workflow-reject (run note)
  "Reject the result RUN waits for your OK on, with NOTE (M-x
agent-workflow-reject)."
  (interactive (let ((run (agent-workflow--read-approval "Reject: ")))
                 (list run (read-string "Why (the agent's told): "))))
  (message "%s: %s rejected" (agent-workflow-run-name run) (agent-workflow--reject run note)))
