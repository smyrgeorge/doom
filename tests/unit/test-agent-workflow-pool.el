;;; tests/unit/test-agent-workflow-pool.el -*- lexical-binding: t; -*-
;; config/agent-workflow/pool.el and worktree.el: the pool's agents, real
;; agent-shell sessions run by a stand-in agent
;; (examples/agent-workspace/stand-in.el, agent-shell's mock agent kind), each
;; a job's, with no role or name, started with its step's profile in its
;; issue's worktree; the pool's size; refused where an agent-workspace crew
;; runs; an agent's canvas opening no pane; stopped, leaving no process.
;; run.sh: slow (stand-in sessions)

(require 'agent-shell)
(require 'agent-shell-mock-agent)
(require 'json)

;; Git as git is, not as your ~/.gitconfig has it (hooks, signing...).
(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(+test-load "config/agent-shell" "config/agent-workflow")

;; Nothing about this config's own issues in the stand-in's prompt.
(remove-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context)

(setq agent-shell-mock-agent-acp-command
      (list (expand-file-name invocation-name invocation-directory)
            "--batch" "-Q" (concat "--init-directory=" (+test-tmp-file "mock-acp-home/"))
            "-l" (expand-file-name "examples/agent-workspace/stand-in.el" +test-root) "-f" "mock-acp-main"))

;; The stand-in, given Claude Code's options as Claude Code is.
(add-to-list 'agent-workflow-kinds '(mock :config agent-shell-mock-agent-make-agent-config :claude-code t))

;; ====== HELPERS ======

(defvar +test-awp--log nil "The stand-in's log file, this test's.")

(defun +test-awp--git (&rest args)
  "Run git with ARGS in `default-directory'; its output."
  (with-temp-buffer
    (unless (eql 0 (apply #'call-process "git" nil t nil args))
      (error "git %S: %s" args (buffer-string)))
    (string-trim (buffer-string))))

(defun +test-awp--project (name)
  "A git repository NAME in the temp folder, with a commit, a .beads/
folder and a profile build of its own: its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awp/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (+test-awp--git "init" "-q" "-b" "main")
      (write-region "hello\n" nil (expand-file-name "README" dir))
      (+test-awp--git "add" "README")
      (+test-awp--git "-c" "user.name=Test" "-c" "user.email=test@example.com" "commit" "-q" "-m" "first")
      (make-directory (expand-file-name ".beads" dir))
      (make-directory (expand-file-name ".agent-workflow/profiles" dir) t)
      (write-region "---
description: builds an issue with its tests
tools: Read, Bash(git -C {worktree} commit:*)
deny: Bash(git push:*)
model: sonnet
mode: acceptEdits
---
Build {issue} on {branch}, in {project}.
" nil (expand-file-name ".agent-workflow/profiles/build.md" dir)))
    (file-name-as-directory (file-truename dir))))

(defmacro +test-awp--with-project (name &rest body)
  "BODY in a new project NAME (`project', `default-directory'), no starters,
every agent stopped after, the stand-in's log fresh."
  (declare (indent 1))
  `(let* ((project (+test-awp--project ,name))
          (default-directory project)
          (agent-workflow-starters-directory (+test-tmp-file "awp/no-starters/"))
          (agent-workflow--profiles-cache (make-hash-table :test #'equal))
          (agent-workflow--workflows-cache (make-hash-table :test #'equal))
          (agent-workflow-kind 'mock)
          (+test-awp--log (expand-file-name (concat "awp/" ,name ".log") +test-tmp))
          (process-environment (cons (concat "MOCK_ACP_LOG=" +test-awp--log) process-environment)))
     (ignore-errors (delete-file +test-awp--log))
     (unwind-protect (progn ,@body)
       (mapc #'agent-workflow-stop-agent agent-workflow--agents))))

(defun +test-awp--wait (predicate &optional timeout)
  "Wait until PREDICATE returns non-nil, TIMEOUT seconds at most (default 20):
its value, or nil."
  (let ((end (+ (float-time) (or timeout 20)))
        value)
    (while (and (not (setq value (funcall predicate))) (< (float-time) end))
      (accept-process-output nil 0.05))
    value))

(defun +test-awp--log-entries ()
  "What the stand-in logged: a plist each."
  (when (file-exists-p +test-awp--log)
    (with-temp-buffer
      (insert-file-contents +test-awp--log)
      (mapcar (lambda (line) (json-parse-string line :object-type 'plist :null-object nil
                                                :false-object nil :array-type 'list))
              (split-string (buffer-string) "\n" t)))))

(defun +test-awp--logged (predicate)
  "The stand-in's entries PREDICATE holds for."
  (seq-filter predicate (+test-awp--log-entries)))

(defun +test-awp--start (project issue job &rest args)
  "An agent for JOB of ISSUE in PROJECT, with the profile build: ARGS more
of `agent-workflow-start-agent''s."
  (apply #'agent-workflow-start-agent
         (append args (list :project project :issue issue :job job :profile "build"))))

;; ====== THE WORKTREE ======

(ert-deftest agent-workflow-pool/an-issue-s-branch ()
  "TYPE/ID-WORDS: fix/ for a bug, feat/ for a feature, task/ for none, four
words, small ones out."
  (should (equal (agent-workflow-issue-branch "doom-a1b" "bug" "Lexer: escapes in strings are not read")
                 "fix/doom-a1b-escapes-strings-read"))
  (should (equal (agent-workflow-issue-branch "doom-a1b.3" "feature" "Agent workflow: a pool of agents")
                 "feat/doom-a1b.3-pool-agents"))
  (should (equal (agent-workflow-issue-branch "doom-x" nil nil) "task/doom-x"))
  (should (equal (agent-workflow-issue-branch "doom-x" "chore" "Café's menu") "chore/doom-x-cafes-menu")))

(ert-deftest agent-workflow-pool/an-issue-s-worktree ()
  "Made the first time on the issue's branch from your checkout's HEAD,
locked with the issue as its reason, out of git; reused after; removed
with its branch kept."
  (+test-awp--with-project "worktree"
    (pcase-let ((`(,dir . ,branch) (agent-workflow-worktree project "demo-1" :type "feature" :title "A pool")))
      (should (equal dir (expand-file-name ".agent-shell/agent-workflow/worktrees/demo-1/" project)))
      (should (equal branch "feat/demo-1-pool"))
      (should (file-exists-p (expand-file-name "README" dir)))
      (let ((entry (agent-workflow--worktree-entry project dir)))
        (should (equal (plist-get entry :branch) "feat/demo-1-pool"))
        (should (equal (plist-get entry :locked) "agent workflow: demo-1, in worktree")))
      ;; Out of git: the project's status doesn't see it.
      (should-not (string-match-p "agent-shell" (+test-awp--git "status" "--porcelain")))
      ;; Reused: its work kept; its title changed since, its branch too.
      (write-region "work\n" nil (expand-file-name "work.txt" dir))
      (should (equal (agent-workflow-worktree project "demo-1" :type "feature" :title "Renamed")
                     (cons dir "feat/demo-1-pool")))
      (should (file-exists-p (expand-file-name "work.txt" dir)))
      ;; Changes not committed: git refuses to remove it.
      (should-error (agent-workflow-worktree-remove project "demo-1") :type 'user-error)
      (delete-file (expand-file-name "work.txt" dir))
      (agent-workflow-worktree-remove project "demo-1")
      (should-not (file-exists-p dir))
      (should (member "feat/demo-1-pool" (split-string (+test-awp--git "branch" "--format=%(refname:short)") "\n")))
      ;; Its branch there: taken again.
      (should (equal (cdr (agent-workflow-worktree project "demo-1" :type "bug" :title "Other"))
                     "feat/demo-1-pool")))))

(ert-deftest agent-workflow-pool/no-worktree-without-a-commit ()
  (let ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "awp-empty-") t))))
    (let ((default-directory dir))
      (+test-awp--git "init" "-q")
      (should-error (agent-workflow-worktree dir "demo-1") :type 'user-error))))

;; ====== AN AGENT ======

(ert-deftest agent-workflow-pool/an-agent ()
  "A job's agent: its session named by its issue and job, in the issue's
worktree, its bd as ISSUE/JOB, its profile's model, mode and tools (their
variables filled in, shell-quoted), told its job, how it ends it and its
profile's instructions; its first message sent."
  (+test-awp--with-project "agent"
    (let ((agent (+test-awp--start project "demo-1" "build" :type "feature" :title "A pool"
                                   :outcomes '("approved" "changes")
                                   :values '(("issue.title" . "A pool"))
                                   :prompt "Build demo-1: {issue.title}")))
      (should (equal (agent-workflow-agent-name agent) "demo-1 · build"))
      (should (equal (buffer-name (agent-workflow-agent-buffer agent)) "demo-1 · build"))
      (should (eq (agent-workflow-buffer-agent (agent-workflow-agent-buffer agent)) agent))
      (should (equal (agent-workflow-agents project) (list agent)))
      (should (= (agent-workflow-pool-used) 1))
      (let ((worktree (expand-file-name ".agent-shell/agent-workflow/worktrees/demo-1/" project)))
        (should (equal (agent-workflow-agent-worktree agent) worktree))
        (should (equal (agent-workflow-agent-branch agent) "feat/demo-1-pool"))
        ;; Its process: in the worktree, as ISSUE/JOB, on the project's issues.
        (let ((start (car (+test-awp--wait (lambda () (+test-awp--logged (lambda (e) (plist-get e :start))))))))
          (should start)
          (should (equal (plist-get start :cwd) worktree))
          (should (equal (plist-get (plist-get start :start) :BEADS_ACTOR) "demo-1/build"))
          (should (equal (plist-get (plist-get start :start) :BEADS_DIR) (expand-file-name ".beads" project))))
        ;; Its session: its profile's tools, filled in.
        (let* ((new (car (+test-awp--wait
                          (lambda () (+test-awp--logged (lambda (e) (equal (plist-get e :method) "session/new")))))))
               (options (plist-get (plist-get (plist-get (plist-get new :params) :_meta) :claudeCode) :options)))
          (should (equal (plist-get options :allowedTools)
                         (list "Read" (format "Bash(git -C %s commit:*)" (shell-quote-argument (directory-file-name worktree))))))
          (should (equal (plist-get options :disallowedTools) '("Bash(git push:*)"))))
        ;; Its first message, its variables filled in.
        (should (+test-awp--wait
                 (lambda () (+test-awp--logged (lambda (e) (and (equal (plist-get e :method) "session/prompt")
                                                                (string-match-p "Build demo-1: A pool"
                                                                                (format "%S" (plist-get e :params))))))))))
      ;; Its model and mode, the profile's.
      (let ((config (agent-workflow--config agent)))
        (should (equal (funcall (alist-get :default-model-id config)) "sonnet"))
        (should (equal (funcall (alist-get :default-session-mode-id config)) "acceptEdits"))
        (should (equal (alist-get :buffer-name config) "demo-1 · build")))
      ;; What it's told.
      (let ((told (let ((agent-workflow--starting agent)) (agent-workflow-agent-context))))
        (should (string-match-p "you do the job build of the run on the issue demo-1" told))
        (should (string-match-p "known as \"demo-1 · build\"" told))
        (should (string-match-p (regexp-quote "cmd/agent-workflow done OUTCOME \"notes\": the outcome (one of done, approved, changes)") told))
        (should (string-match-p "never switch, make or rename branches, push, or change, relabel or close the issue" told))
        (should (string-match-p "run as demo-1/build (BEADS_ACTOR)" told))
        (should (string-suffix-p "Build demo-1 on feat/demo-1-pool, in agent." told)))
      (should-not (agent-workflow-agent-context)))))

(ert-deftest agent-workflow-pool/the-pool-is-full ()
  "As many agents at once as the pool says, in every project; one stopped
makes room."
  (+test-awp--with-project "full"
    (let* ((agent-workflow-pool 2)
           (one (+test-awp--start project "demo-1" "build"))
           (two (+test-awp--start project "demo-2" "build")))
      (should (= (agent-workflow-pool-used) 2))
      (should (equal (cadr (should-error (+test-awp--start project "demo-3" "build") :type 'user-error))
                     "The pool is full: 2 of 2 agents work (agent-workflow-pool)"))
      (agent-workflow-stop-agent one)
      (should (= (agent-workflow-pool-used) 1))
      (should (+test-awp--start project "demo-3" "build"))
      (ignore two))))

(ert-deftest agent-workflow-pool/refused ()
  "No agent where an agent-workspace crew runs (its lock held by an Emacs
alive), nor with a profile that isn't one; nothing made."
  (+test-awp--with-project "refused"
    (should (equal (cadr (should-error (+test-awp--start project "demo-1" "build" :profile "nobody") :type 'user-error))
                   "No profile nobody: build"))
    (let ((lock (expand-file-name ".agent-shell/agent-workspace/crew.lock" project)))
      (make-directory (file-name-directory lock) t)
      (write-region (format "%d here\n" (emacs-pid)) nil lock)
      (should (agent-workflow-crew-running-p project))
      (should (equal (cadr (should-error (+test-awp--start project "demo-1" "build") :type 'user-error))
                     "The agent-workspace crew of refused runs: its agents would take the same issues"))
      ;; A lock left by an Emacs gone.
      (write-region "999999 gone\n" nil lock)
      (should-not (agent-workflow-crew-running-p project)))
    (should-not (agent-workflow-agents project))
    (should-not (file-exists-p (expand-file-name ".agent-shell/agent-workflow/worktrees/demo-1" project)))))

(ert-deftest agent-workflow-pool/stopped-leaving-no-process ()
  "Stopped: its buffer gone without a question, its process ended, its
session's id kept; out of the pool."
  (+test-awp--with-project "stopped"
    (let* ((agent (+test-awp--start project "demo-1" "build" :prompt "hold"))
           (buffer (agent-workflow-agent-buffer agent))
           (pid (+test-awp--wait (lambda () (plist-get (plist-get (car (+test-awp--logged (lambda (e) (plist-get e :start)))) :start) :pid)))))
      (should pid)
      (should (+test-awp--wait (lambda () (agent-workflow-agent-session agent))))
      (agent-workflow-stop-agent agent)
      (should-not (buffer-live-p buffer))
      (should-not (agent-workflow-agent-buffer agent))
      (should (agent-workflow-agent-session-id agent))
      (should-not (agent-workflow-agents project))
      (should (+test-awp--wait (lambda () (let ((attributes (process-attributes pid)))
                                            (or (null attributes)
                                                (member (alist-get 'state attributes) '("Z" "X"))))))))))

(ert-deftest agent-workflow-pool/its-canvas-opens-no-pane ()
  "An agent's canvas isn't shown (kept for its ticket's pane); any other
canvas as before."
  (+test-awp--with-project "canvas"
    (let* ((agent (+test-awp--start project "demo-1" "build"))
           (shown nil)
           (agent-workflow--canvas-fallback (lambda (canvas) (push canvas shown)))
           (ours (generate-new-buffer " canvas ours"))
           (other (generate-new-buffer " canvas other")))
      (unwind-protect
          (progn
            (with-current-buffer ours (setq-local agent-ui--session-buffer (agent-workflow-agent-buffer agent)))
            (with-current-buffer other (setq-local agent-ui--session-buffer (generate-new-buffer " a session")))
            (agent-workflow--display-canvas ours)
            (agent-workflow--display-canvas other)
            (should (equal shown (list other))))
        (kill-buffer ours)
        (kill-buffer other)))))
