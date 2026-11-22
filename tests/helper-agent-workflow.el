;;; tests/helper-agent-workflow.el -*- lexical-binding: t; -*-
;; What the agent workflow's run tests share (test-agent-workflow-runs.el,
;; test-agent-workflow-steps.el): a throwaway Beads project with profiles and
;; a workflow, runs in it with stand-in agents, their jobs, prompts and
;; journal read back. Loaded by each test file using it, after tests/helper.el
;; and config/agent-workflow.el, the stand-in set as the mock agent.

;; ====== HELPERS ======

(defconst +test-awr--profile "---\ndescription: does a job\n---\nDo it.\n")

(defconst +test-awr--feature "description: build, then review
for: [feature]
jobs:
  build:
    agent: build
    prompt: 'Build {issue}: {issue.title}'
  docs:
    needs: build
    if: (eq (issue-type) 'bug)
    agent: build
  review:
    needs: build
    agent: review
    prompt: 'Review {issue}. The builder said: {jobs.build.notes}'
    outcomes:
      approved: continue
      changes: rerun build
")

(defun +test-awr--project (name)
  "A Beads project NAME (prefix demo) with the profiles build and review
and the workflow feature: its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awr/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (+test-bd-init "--quiet" "--skip-agents" "--prefix" "demo")
      (+test-git-user)
      (dolist (file '(("profiles/build.md" . nil) ("profiles/review.md" . nil)))
        (make-directory (expand-file-name ".agent-workflow/profiles" dir) t)
        (write-region +test-awr--profile nil (expand-file-name (concat ".agent-workflow/" (car file)) dir)))
      (make-directory (expand-file-name ".agent-workflow/workflows" dir) t)
      (write-region +test-awr--feature nil (expand-file-name ".agent-workflow/workflows/feature.yml" dir)))
    (file-name-as-directory (file-truename dir))))

(defmacro +test-awr (name &rest body)
  "BODY in a new Beads project NAME (`project', `default-directory'): no
starters, no runs or agents before or after; skipped without bd."
  (declare (indent 1))
  `(progn
     (skip-unless (executable-find "bd"))
     (let* ((project (+test-awr--project ,name))
            (default-directory project)
            (log (expand-file-name (concat "awr/" ,name ".log") +test-tmp))
            (agent-workflow-starters-directory (+test-tmp-file "awr/no-starters/"))
            (agent-workflow--profiles-cache (make-hash-table :test #'equal))
            (agent-workflow--workflows-cache (make-hash-table :test #'equal))
            (agent-workflow-kind 'mock)
            (agent-workflow--runs nil)
            (process-environment (cons (concat "MOCK_ACP_LOG=" (expand-file-name (concat "awr/" ,name ".log") +test-tmp))
                                       process-environment)))
       (ignore-errors (delete-file log))
       (unwind-protect (progn ,@body)
         (mapc #'agent-workflow-stop-agent agent-workflow--agents)
         (when (timerp agent-workflow--wait-timer) (cancel-timer agent-workflow--wait-timer))
         (setq agent-workflow--wait-timer nil)))))

(defun +test-awr--issue (project title &rest args)
  "An issue of PROJECT: TITLE, a feature unless ARGS say (bd create's). Its id."
  (let ((default-directory project))
    (with-temp-buffer
      (unless (eql 0 (apply #'call-process "bd" nil (list t nil) nil "create" "--title" title "--json"
                            (or args '("--type" "feature"))))
        (error "bd create: %s" (buffer-string)))
      (alist-get 'id (json-parse-string (buffer-string) :object-type 'alist)))))

(defun +test-awr--bd (project &rest args)
  "bd ARGS in PROJECT, its JSON."
  (let ((default-directory project))
    (with-temp-buffer
      (unless (eql 0 (apply #'call-process "bd" nil (list t nil) nil (append args '("--json"))))
        (error "bd %S: %s" args (buffer-string)))
      (json-parse-string (buffer-string) :object-type 'alist :array-type 'list :null-object nil :false-object nil))))

(defun +test-awr--shown (project id)
  "Issue ID of PROJECT as bd shows it."
  (let ((found (+test-awr--bd project "show" id)))
    (if (consp (caar found)) (car found) found)))

(defun +test-awr--wait (predicate &optional timeout)
  "Wait until PREDICATE returns non-nil, TIMEOUT seconds at most (default
20): its value, or nil."
  (let ((end (+ (float-time) (or timeout 20)))
        value)
    (while (and (not (setq value (funcall predicate))) (< (float-time) end))
      (accept-process-output nil 0.05))
    value))

(defun +test-awr--prompts (name)
  "The prompts the stand-ins of the test NAME got, in order."
  (let ((log (expand-file-name (concat "awr/" name ".log") +test-tmp)))
    (when (file-exists-p log)
      (with-temp-buffer
        (insert-file-contents log)
        (cl-loop for line in (split-string (buffer-string) "\n" t)
                 for entry = (json-parse-string line :object-type 'plist :null-object nil :false-object nil
                                                :array-type 'list)
                 when (equal (plist-get entry :method) "session/prompt")
                 collect (mapconcat (lambda (block) (or (plist-get block :text) ""))
                                    (plist-get (plist-get entry :params) :prompt) ""))))))

(defun +test-awr--job (run job)
  "JOB's status in RUN."
  (plist-get (agent-workflow--job run job) :status))

(defun +test-awr--agent (run job)
  "The agent JOB of RUN holds, once it has one."
  (+test-awr--wait (lambda () (plist-get (agent-workflow--job run job) :agent))))

(defun +test-awr--journal (run)
  "RUN's journal: its events' names, in order."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "journal.jsonl" (agent-workflow-run-dir run)))
    (mapcar (lambda (line) (plist-get (json-parse-string line :object-type 'plist) :ev))
            (split-string (buffer-string) "\n" t))))

(defun +test-awr--finish (run job &optional outcome notes)
  "JOB of RUN's agent, its turn over, says it's done (OUTCOME, NOTES)."
  (let ((agent (+test-awr--agent run job)))
    (should (+test-awr--wait (lambda () (eq (+test-awr--job run job) 'waiting))))
    (agent-workflow-done agent outcome (or notes "done"))
    (should (+test-awr--wait (lambda () (eq (+test-awr--job run job) 'done))))))

(defun +test-awr--commit (dir file message)
  "A commit in DIR adding FILE, with MESSAGE, as an agent would make."
  (let ((default-directory dir))
    (write-region (concat message "\n") nil file)
    (call-process "git" nil nil nil "add" file)
    (call-process "git" nil nil nil "-c" "user.name=Agent" "-c" "user.email=agent@example.com"
                  "commit" "-q" "-m" message)))

