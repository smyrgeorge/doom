;;; $DOOMDIR/config/agent-workflow/request.el -*- lexical-binding: t; -*-
;; The shell's way in: cmd/agent-workflow. Loaded from
;; config/agent-workflow.el, after check.el. No Doom here.
;;
;; cmd/agent-workflow writes its request in a folder of its own (`request':
;; its operation, then the shell's folder, then its process's id; `payload':
;; JSON) and has Emacs answer it (emacsclient: `agent-workflow-request'), the
;; reply JSON in `reply'.
;;
;;   run {"issues": ["doom-a1b", "doom-c3d"], "workflow": "feature"}
;;        (workflow: optional; an epic's id: its open issues; no issues: the
;;        workflow's own run, one with no ticket) -> {"ok":
;;        true when one started, "started": [{"issue", "workflow", "run",
;;        "state", "why"}...], "refused": [{"issue", "error"}...]}
;;   done {"outcome": "changes", "notes": "..."} (outcome: optional, done)
;;        -> {"ok": true, "issue", "job", "outcome"}: the step of the agent
;;        that ran it ended (runs.el); refused from anywhere else
;;   back {"issue": "doom-a1b", "job": "build", "step": 0, "note": "...",
;;        "discard": false} (step, note, discard: optional) -> {"ok": true,
;;        "issue", "job", "step", "replaced": [jobs], "lost": [lines]}: the
;;        run sent back (runs.el); yours, refused from an agent's session
;;   confirm {"issue": "doom-a1b", "choice": "go", "notes": [{"job":
;;        "review", "note": "..."}...], "more": {"cost": 5, "tokens": N,
;;        "time": "1h"}} (notes, more: optional) -> {"ok": true,
;;        "issue", "job", "choice"}: the run's question answered (runs.el,
;;        LOOPS); yours, refused from an agent's session
;;   approve {"issue": "doom-a1b"}, reject {"issue": "doom-a1b", "note":
;;        "..."} -> {"ok": true, "issue", "job"}: the result the run waits
;;        for your OK on approved, or rejected (runs.el, APPROVAL); yours,
;;        refused from an agent's session
;;   continue {"issue": "doom-a1b", "current": false} (issue: optional,
;;        every interrupted run of the project) -> {"ok": true, "continued":
;;        [{"issue", "jobs"}...]}; cancel {"issue": "doom-a1b"} -> {"ok":
;;        true, "issue"}; pause {"now": false}, unpause {} -> {"ok": true,
;;        "paused"} (resume.el); yours, refused from an agent's session
;;   dry-run {"workflow": "feature", "issue": "doom-a1b", "outcomes":
;;        {"review": ["changes", "approved"]}, "exits": {"build.2": [1,
;;        0]}} (issue, outcomes, exits: optional) -> {"ok": true, "waves":
;;        [[lines]...], "end": {job: status...}, "stopped": why or null,
;;        "branch": what happens to its branch, or null (it stops)}:
;;        nothing run (dry.el); any shell's, an agent's too
;;   logs {"issue": "doom-a1b"} -> {"ok": true, "issue", "workflow",
;;        "run", "state", "why", "log", "journal", "state_file"}: its latest
;;        run, its log.txt made if it's gone (log.el); any shell's
;;   status {"issue": "doom-a1b"} (issue: optional, every run of the project
;;        not over) -> {"ok": true, "runs": [{"issue", "workflow", "run",
;;        "state", "why", "jobs": [{"name", "status", "outcome", "round",
;;        "why"}...], "asking": {"job", "kind"} or null (kind agent: its
;;        agent asks in its session, "question" and "session" too),
;;        "where": {"worktree" (null: gone), "branch", "deleted" (its run
;;        done), "base": {"branch", "commit"} or null, "into", "own",
;;        "with", "uncommitted", "merged", "checkout" (it works in your
;;        checkout: worktree is it)} or null, "spent": {"cost", "tokens", "time"},
;;        "budget": {...} or null, "log"}...]}; any shell's
;;   check {"file": "/abs/feature.yml"} (file: optional) -> {"ok": true
;;        when there's no error (else false, "error": "2 errors"),
;;        "project", "workflows": [names], "profiles": [names], "problems":
;;        [{"level", "file", "line", "message"}...]}: the project's
;;        workflows and profiles, or the one file, read anew (check.el)

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'json)

(declare-function agent-workflow-pause "agent-workflow/resume")
(declare-function agent-workflow-dry-run "agent-workflow/dry")
(declare-function agent-workflow-unpause "agent-workflow/resume")
(declare-function agent-workflow-cancel "agent-workflow/resume")
(declare-function agent-workflow-continue "agent-workflow/resume")
(declare-function agent-workflow--interrupted "agent-workflow/resume")
(declare-function agent-workflow--ensure-restored "agent-workflow/resume")
(defvar agent-workflow--paused)

(defun agent-workflow--request-check (directory payload)
  "Check DIRECTORY's project's workflows and profiles, or PAYLOAD's file:
the reply, a plist."
  (let* ((default-directory (file-name-as-directory directory))
         (project (agent-workflow-project))
         (file (plist-get payload :file))
         (file (and (stringp file) (not (string-empty-p file)) (expand-file-name file)))
         (problems (progn
                     (when (and file (not (file-exists-p file)))
                       (user-error "check: no file %s" (abbreviate-file-name file)))
                     (agent-workflow-check-problems project file))))
    (append
     (let ((errors (seq-count (lambda (p) (eq (car p) 'error)) problems)))
       (if (> errors 0)
           (list :ok :false :error (format "%d error%s" errors (if (= errors 1) "" "s")))
         (list :ok t)))
     (list :project (if project (directory-file-name project) :null)
           :workflows (vconcat (unless file (mapcar #'car (agent-workflow-workflows project))))
           :profiles (vconcat (unless file (mapcar #'car (agent-workflow-profiles project))))
           :problems (vconcat
                      (mapcar (pcase-lambda (`(,level ,_ ,file ,line ,what))
                                (list :level (symbol-name level) :file file :line line :message what))
                              problems))))))

(defun agent-workflow--request-run (directory payload)
  "Start runs on PAYLOAD's issues in DIRECTORY's project, or its workflow's
own run (no issues, a workflow with no ticket): the reply."
  (let* ((default-directory (file-name-as-directory directory))
         (project (or (agent-workflow-project) (user-error "Not in a git repository")))
         (issues (append (plist-get payload :issues) nil))
         (workflow (let ((name (plist-get payload :workflow))) (and (stringp name) (not (string-empty-p name)) name)))
         (refused nil)
         (expanded (seq-mapcat (lambda (issue)
                                 (condition-case err
                                     (if (equal (plist-get (agent-workflow-issue project issue) :type) "epic")
                                         (or (agent-workflow-epic-issues project issue)
                                             (progn (push (cons issue "an epic with no open issue") refused) nil))
                                       (list issue))
                                   (user-error (push (cons issue (error-message-string err)) refused) nil)))
                               issues)))
    (unless (or issues workflow)
      (user-error "run: which issues? agent-workflow run ISSUE..., or a workflow with no ticket: agent-workflow run --workflow NAME"))
    (pcase-let ((`(,started . ,more) (let ((inhibit-message t)
                                           (agent-workflow-from-shell t))
                                       (if issues
                                           (agent-workflow-run-ticket expanded workflow project)
                                         (agent-workflow-run workflow project)))))
      (setq refused (append (nreverse refused) more))
      (list :ok (if started t :false)
            :error (if started :null (format "nothing started: %s"
                                             (mapconcat (lambda (r) (format "%s (%s)" (car r) (cdr r))) refused "; ")))
            :started (vconcat (mapcar #'agent-workflow--run-reply started))
            :refused (vconcat (mapcar (lambda (r) (list :issue (car r) :error (cdr r))) refused))))))

;; ITS LOG, ITS STATE

(defun agent-workflow--run-reply (run)
  "RUN as a reply says it: its issue, workflow, number, state, what it waits
for, its files (log.txt, made if it's gone; its journal; its state.json)."
  (list :issue (agent-workflow-run-issue run)
        :workflow (plist-get (agent-workflow-run-workflow run) :name)
        :run (agent-workflow-run-n run)
        :state (symbol-name (agent-workflow-run-state run))
        :why (or (agent-workflow-run-why run) :null)
        :log (agent-workflow-log-file run)
        :journal (expand-file-name "journal.jsonl" (agent-workflow-run-dir run))
        :state_file (expand-file-name "state.json" (agent-workflow-run-dir run))))

(defun agent-workflow--issue-run (project issue)
  "ISSUE's latest run in PROJECT: this Emacs's, else read from its folder;
a user error if it has none."
  (unless (and (stringp issue) (not (string-empty-p issue)))
    (user-error "which issue?"))
  (or (car (sort (seq-filter (lambda (run) (equal (agent-workflow-run-issue run) issue))
                             (agent-workflow-runs-of project))
                 (lambda (a b) (> (agent-workflow-run-n a) (agent-workflow-run-n b)))))
      (let* ((root (expand-file-name issue (agent-workflow--runs-directory project)))
             (numbers (and (file-directory-p root)
                           (sort (delq nil (mapcar (lambda (dir) (and (string-match-p "\\`[0-9]+\\'" dir)
                                                                      (string-to-number dir)))
                                                   (directory-files root)))
                                 #'>)))
             (dir (and numbers (file-name-as-directory (expand-file-name (number-to-string (car numbers)) root)))))
        (and dir (or (gethash dir agent-workflow--read-runs)
                     (when-let* ((run (agent-workflow--read-run dir)))
                       (puthash dir run agent-workflow--read-runs)))))
      (user-error "%s has no run" issue)))

(defun agent-workflow--where-reply (run)
  "Where RUN's work is (`agent-workflow-run-where'), for status's reply."
  (if-let* ((where (agent-workflow-run-where run)))
      (let ((base (plist-get where :base)))
        (list :worktree (or (plist-get where :worktree) :null)
              :branch (or (plist-get where :branch) :null)
              :deleted (if (plist-get where :deleted) t :false)
              :base (if base (list :branch (or (plist-get base :branch) :null) :commit (plist-get base :commit)) :null)
              :into (plist-get where :into)
              :own (plist-get where :own)
              :with (plist-get where :with)
              :uncommitted (plist-get where :uncommitted)
              :merged (if (plist-get where :merged) t :false)
              :checkout (if (plist-get where :checkout) t :false)))
    :null))

(defun agent-workflow--request-status (directory payload)
  "The reply to status: PAYLOAD's issue's latest run, else DIRECTORY's
project's runs not over."
  (let* ((default-directory (file-name-as-directory directory))
         (project (or (agent-workflow-project) (user-error "Not in a git repository")))
         (issue (plist-get payload :issue)))
    (agent-workflow--ensure-restored project)
    (list :ok t
          :runs (vconcat
                 (mapcar (lambda (run)
                           (let ((asking (agent-workflow-asking run))
                                 (agent-asking (agent-workflow-agent-asking run))
                                 (spent (agent-workflow-run-spent-now run))
                                 (budget (agent-workflow-run-budget run)))
                             (append (agent-workflow--run-reply run)
                                     (list :jobs (vconcat
                                                  (mapcar (lambda (job)
                                                            (let ((state (cdr job)))
                                                              (list :name (car job)
                                                                    :status (symbol-name (plist-get state :status))
                                                                    :outcome (or (plist-get state :outcome) :null)
                                                                    :round (or (plist-get state :round) 0)
                                                                    :why (or (plist-get state :why) :null))))
                                                          (agent-workflow-run-jobs run)))
                                           :asking (cond
                                                    (asking
                                                     (list :job (car asking)
                                                           :kind (let ((kind (plist-get (cdr asking) :kind)))
                                                                   (if kind (symbol-name kind) "loop"))))
                                                    (agent-asking
                                                     (let ((agent (plist-get (agent-workflow--job run (car agent-asking))
                                                                             :agent)))
                                                       (list :job (car agent-asking) :kind "agent"
                                                             :question (or (plist-get (cdr agent-asking) :what) :null)
                                                             :session (or (and agent (agent-workflow-agent-name agent))
                                                                          :null))))
                                                    (t :null))
                                           :where (agent-workflow--where-reply run)
                                           :spent (list :cost (plist-get spent :cost) :tokens (plist-get spent :tokens)
                                                        :time (plist-get spent :time))
                                           :budget (if budget
                                                       (list :cost (or (plist-get budget :cost) :null)
                                                             :tokens (or (plist-get budget :tokens) :null)
                                                             :time (or (plist-get budget :time) :null))
                                                     :null)))))
                         (if (and (stringp issue) (not (string-empty-p issue)))
                             (list (agent-workflow--issue-run project issue))
                           (seq-remove (lambda (run) (memq (agent-workflow-run-state run) agent-workflow--ended))
                                       (agent-workflow-runs-of project))))))))

;; WHO ASKS
;; Not what its shell says (AGENT_WORKFLOW_ISSUE can be unset or changed) but
;; where a request comes from: the script sends its process's id, and the
;; agent whose session's process is one of its ancestors sent it.

(defun agent-workflow--pid-ancestors (pid)
  "PID and its ancestors' ids, itself first (at most 64)."
  (let ((pids nil))
    (while (and (natnump pid) (> pid 1) (not (memq pid pids)) (< (length pids) 64))
      (push pid pids)
      (setq pid (alist-get 'ppid (ignore-errors (process-attributes pid)))))
    (nreverse pids)))

(defun agent-workflow--request-caller (pid)
  "The pool's agent whose session ran the command that sent a request: the
one whose session's process is an ancestor of PID (the script's); nil."
  (when-let* ((ancestors (and pid (agent-workflow--pid-ancestors pid))))
    (seq-find (lambda (agent)
                (when-let* ((process (agent-workflow--session-process (agent-workflow-agent-buffer agent))))
                  (and (process-live-p process) (memq (process-id process) ancestors))))
              agent-workflow--agents)))

(defun agent-workflow--request-done (payload pid)
  "End the step of the agent that sent it (PID, its script's), as PAYLOAD
says: the reply."
  (let ((agent (or (agent-workflow--request-caller pid)
                   (user-error "done: only an agent of a run ends its step, from its own session"))))
    (pcase-let* ((one (let ((one (plist-get payload :one))) (and (stringp one) (not (string-empty-p one)) one)))
                 ;; One argument, a word (an outcome's name, as `done changes'):
                 ;; the outcome, refused if it isn't one of its job's; text
                 ;; with spaces, the notes.
                 (word (and one (string-match-p agent-workflow--name-regexp one)))
                 (`(,run ,job ,outcome)
                  (agent-workflow-done agent
                                       (if word one (plist-get payload :outcome))
                                       (if (and one (not word)) one (plist-get payload :notes)))))
      (list :ok t :issue (agent-workflow-run-issue run) :job job :outcome outcome))))

(defun agent-workflow--request-back (directory payload pid)
  "Send DIRECTORY's project's run on PAYLOAD's issue back, as it says: the
reply. Not from an agent's session."
  (when (agent-workflow--request-caller pid)
    (agent-workflow--refuse "back: yours to do, not an agent's"))
  (let* ((default-directory (file-name-as-directory directory))
         (project (or (agent-workflow-project) (user-error "Not in a git repository")))
         (issue (plist-get payload :issue))
         (_ (agent-workflow--ensure-restored project))
         (run (or (car (last (seq-filter (lambda (run) (equal (agent-workflow-run-issue run) issue))
                                         (agent-workflow-runs-of project))))
                  (user-error "back: %s has no run" issue)))
         (job (plist-get payload :job))
         (step (or (plist-get payload :step) 0))
         (discard (plist-get payload :discard))
         (lost (and discard (agent-workflow-back-lost run job)))
         (replaced (agent-workflow-back run job :step step :note (plist-get payload :note) :discard discard
                                        :by "you")))
    (list :ok t :issue issue :job job :step step :replaced (vconcat replaced)
          :lost (vconcat (append (car lost) (cdr lost))))))

(defun agent-workflow--request-confirm (directory payload pid)
  "Answer the question of DIRECTORY's project's run on PAYLOAD's issue: the
reply. Not from an agent's session."
  (when (agent-workflow--request-caller pid)
    (user-error "confirm: yours to answer, not an agent's"))
  (let* ((default-directory (file-name-as-directory directory))
         (project (or (agent-workflow-project) (user-error "Not in a git repository")))
         (issue (plist-get payload :issue))
         (_ (agent-workflow--ensure-restored project))
         (run (or (agent-workflow-run-of project issue) (user-error "confirm: %s has no run" issue)))
         (job (car (agent-workflow-asking run)))
         (notes (mapcar (lambda (note) (cons (plist-get note :job) (plist-get note :note)))
                        (append (plist-get payload :notes) nil)))
         (more (let ((more (plist-get payload :more)))
                 (and more (list :cost (plist-get more :cost) :tokens (plist-get more :tokens)
                                 :time (and (plist-get more :time) (agent-workflow--duration (plist-get more :time)))))))
         (choice (agent-workflow-confirm run (plist-get payload :choice) :notes notes :more more)))
    (list :ok t :issue issue :job job :choice choice)))

(defun agent-workflow--request-approval (directory payload pid reject)
  "Approve (REJECT: reject, with PAYLOAD's note) the result DIRECTORY's
project's run on PAYLOAD's issue waits for your OK on: the reply. Not from
an agent's session."
  (when (agent-workflow--request-caller pid)
    (agent-workflow--refuse "%s: yours to decide, not an agent's" (if reject "reject" "approve")))
  (let* ((default-directory (file-name-as-directory directory))
         (project (or (agent-workflow-project) (user-error "Not in a git repository")))
         (issue (plist-get payload :issue))
         (_ (agent-workflow--ensure-restored project))
         (run (or (agent-workflow-run-of project issue) (user-error "%s has no run" issue)))
         (job (if reject
                  (agent-workflow-reject run (or (plist-get payload :note) ""))
                (agent-workflow-approve run))))
    (list :ok t :issue issue :job job)))

(defun agent-workflow--request-project (directory pid what)
  "DIRECTORY's project, its runs read back, for WHAT (an operation): a
user error from an agent's session, or outside a repository."
  (when (agent-workflow--request-caller pid)
    (agent-workflow--refuse "%s: yours to do, not an agent's" what))
  (let* ((default-directory (file-name-as-directory directory))
         (project (or (agent-workflow-project) (user-error "Not in a git repository"))))
    (agent-workflow--ensure-restored project)
    project))

(defun agent-workflow--request-continue (directory payload pid)
  "Continue PAYLOAD's issue's run (none: every interrupted run of
DIRECTORY's project): the reply."
  (let* ((project (agent-workflow--request-project directory pid "continue"))
         (issue (plist-get payload :issue))
         (runs (if (and (stringp issue) (not (string-empty-p issue)))
                   (list (or (agent-workflow-run-of project issue) (user-error "%s has no run" issue)))
                 (seq-filter #'agent-workflow--interrupted (agent-workflow-runs-of project)))))
    (unless (seq-some #'agent-workflow--interrupted runs)
      (user-error "continue: no run was interrupted"))
    (list :ok t :continued
          (vconcat (mapcar (lambda (run)
                             (list :issue (agent-workflow-run-issue run)
                                   :jobs (vconcat (agent-workflow-continue run :current (plist-get payload :current)))))
                           runs)))))

(defun agent-workflow--request-dry-run (directory payload)
  "A dry run in DIRECTORY's project, as PAYLOAD says: the reply."
  (let* ((default-directory (file-name-as-directory directory))
         (project (or (agent-workflow-project) (user-error "Not in a git repository")))
         (name (plist-get payload :workflow))
         (spec (or (alist-get name (agent-workflow-workflows project) nil nil #'equal)
                   (user-error "dry-run: no workflow %s" name)))
         (issue (plist-get payload :issue))
         (info (agent-workflow--dry-info project spec (and (stringp issue) (not (string-empty-p issue)) issue)))
         (chosen (lambda (object)
                   (cl-loop for (key value) on object by #'cddr
                            collect (cons (substring (symbol-name key) 1) (append value nil)))))
         (result (agent-workflow-dry-run spec :info info :outcomes (funcall chosen (plist-get payload :outcomes))
                                         :exits (funcall chosen (plist-get payload :exits))
                                         :profiles (agent-workflow-profiles project))))
    (list :ok t
          :waves (vconcat (mapcar #'vconcat (plist-get result :waves)))
          :end (cl-loop for (job . status) in (plist-get result :end)
                        append (list (intern (concat ":" job)) (symbol-name status)))
          :stopped (or (plist-get result :stopped) :null)
          :branch (or (plist-get result :branch) :null))))

(defun agent-workflow-request (dir)
  "Answer cmd/agent-workflow's request in DIR (see the top of this file):
its reply written to DIR/reply. Return t."
  (let* ((lines (split-string (with-temp-buffer
                                (insert-file-contents (expand-file-name "request" dir))
                                (buffer-string))
                              "\n"))
         (op (nth 0 lines))
         (directory (nth 1 lines))
         (pid (and (nth 2 lines) (string-match-p "\\`[0-9]+\\'" (nth 2 lines)) (string-to-number (nth 2 lines))))
         (payload-file (expand-file-name "payload" dir))
         (reply
          (condition-case err
              (let ((payload (when (file-exists-p payload-file)
                               (with-temp-buffer
                                 (let ((coding-system-for-read 'utf-8))
                                   (insert-file-contents payload-file))
                                 (json-parse-buffer :object-type 'plist :null-object nil
                                                    :false-object nil)))))
                (pcase op
                  ("check" (agent-workflow--request-check directory payload))
                  ("dry-run" (agent-workflow--request-dry-run directory payload))
                  ("run" (agent-workflow--request-run directory payload))
                  ("status" (agent-workflow--request-status directory payload))
                  ("logs"
                   (let* ((default-directory (file-name-as-directory directory))
                          (project (or (agent-workflow-project) (user-error "Not in a git repository"))))
                     (agent-workflow--ensure-restored project)
                     (append (list :ok t)
                             (agent-workflow--run-reply (agent-workflow--issue-run project (plist-get payload :issue))))))
                  ("done" (agent-workflow--request-done payload pid))
                  ("back" (agent-workflow--request-back directory payload pid))
                  ("confirm" (agent-workflow--request-confirm directory payload pid))
                  ("approve" (agent-workflow--request-approval directory payload pid nil))
                  ("reject" (agent-workflow--request-approval directory payload pid t))
                  ("continue" (agent-workflow--request-continue directory payload pid))
                  ("cancel"
                   (let* ((project (agent-workflow--request-project directory pid "cancel"))
                          (issue (plist-get payload :issue))
                          (run (or (agent-workflow-run-of project issue) (user-error "%s has no run" issue))))
                     (agent-workflow-cancel run)
                     (list :ok t :issue issue)))
                  ((or "pause" "unpause")
                   (agent-workflow--request-project directory pid op)
                   (let ((inhibit-message t))
                     (if (equal op "pause") (agent-workflow-pause (plist-get payload :now)) (agent-workflow-unpause)))
                   (list :ok t :paused (if agent-workflow--paused t :false)))
                  (_ (list :ok :false :error (format "unknown operation %S; operations: %s" op
                                                     "run, done, back, confirm, approve, reject, continue, cancel, pause, unpause, dry-run, check, logs, status")))))
            (json-parse-error (list :ok :false :error (format "not JSON: %s" (error-message-string err))))
            (error (list :ok :false :error (error-message-string err))))))
    (let ((coding-system-for-write 'utf-8-unix))
      (with-temp-file (expand-file-name "reply" dir)
        (insert (json-serialize reply) "\n")))
    t))
