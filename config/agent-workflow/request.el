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
;;        (workflow: optional; an epic's id: its open issues) -> {"ok":
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
;;        "review", "note": "..."}...]} (notes: optional) -> {"ok": true,
;;        "issue", "job", "choice"}: the run's question answered (runs.el,
;;        LOOPS); yours, refused from an agent's session
;;   approve {"issue": "doom-a1b"}, reject {"issue": "doom-a1b", "note":
;;        "..."} -> {"ok": true, "issue", "job"}: the result the run waits
;;        for your OK on approved, or rejected (runs.el, APPROVAL); yours,
;;        refused from an agent's session
;;   check {"file": "/abs/feature.yml"} (file: optional) -> {"ok": true
;;        when there's no error (else false, "error": "2 errors"),
;;        "project", "workflows": [names], "profiles": [names], "problems":
;;        [{"level", "file", "line", "message"}...]}: the project's
;;        workflows and profiles, or the one file, read anew (check.el)

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'json)

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
  "Start runs on PAYLOAD's issues in DIRECTORY's project: the reply."
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
    (unless issues (user-error "run: which issues? agent-workflow run ISSUE..."))
    (pcase-let ((`(,started . ,more) (let ((inhibit-message t))
                                       (agent-workflow-run expanded workflow project))))
      (setq refused (append (nreverse refused) more))
      (list :ok (if started t :false)
            :error (if started :null (format "nothing started: %s"
                                             (mapconcat (lambda (r) (format "%s (%s)" (car r) (cdr r))) refused "; ")))
            :started (vconcat (mapcar (lambda (run)
                                        (list :issue (agent-workflow-run-issue run)
                                              :workflow (plist-get (agent-workflow-run-workflow run) :name)
                                              :run (agent-workflow-run-n run)
                                              :state (symbol-name (agent-workflow-run-state run))
                                              :why (or (agent-workflow-run-why run) :null)))
                                      started))
            :refused (vconcat (mapcar (lambda (r) (list :issue (car r) :error (cdr r))) refused))))))

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
    (pcase-let ((`(,run ,job ,outcome)
                 (agent-workflow-done agent (plist-get payload :outcome) (plist-get payload :notes))))
      (list :ok t :issue (agent-workflow-run-issue run) :job job :outcome outcome))))

(defun agent-workflow--request-back (directory payload pid)
  "Send DIRECTORY's project's run on PAYLOAD's issue back, as it says: the
reply. Not from an agent's session."
  (when (agent-workflow--request-caller pid)
    (agent-workflow--refuse "back: yours to do, not an agent's"))
  (let* ((default-directory (file-name-as-directory directory))
         (project (or (agent-workflow-project) (user-error "Not in a git repository")))
         (issue (plist-get payload :issue))
         (run (or (car (last (seq-filter (lambda (run) (equal (agent-workflow-run-issue run) issue))
                                         (agent-workflow-runs project))))
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
         (run (or (agent-workflow-run-of project issue) (user-error "confirm: %s has no run" issue)))
         (job (car (agent-workflow-asking run)))
         (notes (mapcar (lambda (note) (cons (plist-get note :job) (plist-get note :note)))
                        (append (plist-get payload :notes) nil)))
         (choice (agent-workflow-confirm run (plist-get payload :choice) :notes notes)))
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
         (run (or (agent-workflow-run-of project issue) (user-error "%s has no run" issue)))
         (job (if reject
                  (agent-workflow-reject run (or (plist-get payload :note) ""))
                (agent-workflow-approve run))))
    (list :ok t :issue issue :job job)))

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
                  ("run" (agent-workflow--request-run directory payload))
                  ("done" (agent-workflow--request-done payload pid))
                  ("back" (agent-workflow--request-back directory payload pid))
                  ("confirm" (agent-workflow--request-confirm directory payload pid))
                  ("approve" (agent-workflow--request-approval directory payload pid nil))
                  ("reject" (agent-workflow--request-approval directory payload pid t))
                  (_ (list :ok :false :error (format "unknown operation %S; operations: run, done, back, confirm, approve, reject, check" op)))))
            (json-parse-error (list :ok :false :error (format "not JSON: %s" (error-message-string err))))
            (error (list :ok :false :error (error-message-string err))))))
    (let ((coding-system-for-write 'utf-8-unix))
      (with-temp-file (expand-file-name "reply" dir)
        (insert (json-serialize reply) "\n")))
    t))
