;;; tests/unit/test-agent-workflow-pool.el -*- lexical-binding: t; -*-
;; config/agent-workflow/pool.el and worktree.el: the pool's agents, real
;; agent-shell sessions run by a stand-in agent
;; (examples/agent-workspace/stand-in.el, agent-shell's mock agent kind), each
;; a job's, with no role or name, started with its step's agent in its
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
(remove-hook '+my/agent-shell-context-functions #'+my/agent-shell-beads-context)

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
folder and an agent build of its own: its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awp/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (+test-awp--git "init" "-q" "-b" "main")
      (write-region "hello\n" nil (expand-file-name "README" dir))
      (+test-awp--git "add" "README")
      (+test-awp--git "-c" "user.name=Test" "-c" "user.email=test@example.com" "commit" "-q" "-m" "first")
      (make-directory (expand-file-name ".beads" dir))
      (make-directory (expand-file-name ".agent-workflow/agents" dir) t)
      (write-region "---
description: builds an issue with its tests
tools: Read, Bash(git -C {worktree} commit:*)
deny: Bash(git push:*)
model: sonnet
mode: acceptEdits
---
Build {issue} on {branch}, in {project}.
" nil (expand-file-name ".agent-workflow/agents/build.md" dir)))
    (file-name-as-directory (file-truename dir))))

(defmacro +test-awp--with-project (name &rest body)
  "BODY in a new project NAME (`project', `default-directory'), no starters,
every agent stopped after, the stand-in's log fresh."
  (declare (indent 1))
  `(let* ((project (+test-awp--project ,name))
          (default-directory project)
          (agent-workflow-starters-directory (+test-tmp-file "awp/no-starters/"))
          (agent-workflow--definitions-cache (make-hash-table :test #'equal))
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
  "An agent for JOB of ISSUE in PROJECT, with the agent build: ARGS more
of `agent-workflow-start-agent''s."
  (apply #'agent-workflow-start-agent
         (append args (list :project project :issue issue :job job :definition "build"))))

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

(defmacro +test-awp--counting (function &rest body)
  "BODY with FUNCTION's calls counted in `calls'."
  (declare (indent 1))
  `(let ((calls 0) (real (symbol-function ,function)))
     (cl-letf (((symbol-function ,function) (lambda (&rest args) (cl-incf calls) (apply real args))))
       ,@body)))

(ert-deftest agent-workflow-pool/a-worktree-listed-once ()
  "Made, reused or removed: git's worktrees listed once each, not again
for its lock and its branch (doom-8y4: git called again and again)."
  (+test-awp--with-project "listed"
    (+test-awp--counting 'agent-workflow--worktrees
      (should (equal (cdr (agent-workflow-worktree project "demo-1" :type "feature" :title "A pool"))
                     "feat/demo-1-pool"))
      (should (= calls 1))
      (should (plist-get (agent-workflow--worktree-entry project (agent-workflow-worktree-directory project "demo-1"))
                         :locked))
      (setq calls 0)
      (should (equal (cdr (agent-workflow-worktree project "demo-1")) "feat/demo-1-pool"))
      (should (= calls 1))
      (setq calls 0)
      (agent-workflow-worktree-remove project "demo-1")
      (should (= calls 1))
      (should-not (file-exists-p (agent-workflow-worktree-directory project "demo-1"))))))

(ert-deftest agent-workflow-pool/a-snapshot ()
  "Detached at its worktree's commit, made without listing git's
worktrees; its folder removed by hand (git still noting it): made again
over it; one there: replaced, nothing of it kept."
  (+test-awp--with-project "snapshot"
    (let* ((from (agent-workflow-worktree project "demo-1" :type "feature" :title "A pool"))
           (dir (agent-workflow-snapshot-directory project "demo-1" "review"))
           (head (let ((default-directory (car from))) (+test-awp--git "rev-parse" "HEAD"))))
      (+test-awp--counting 'agent-workflow--worktrees
        (should (equal (agent-workflow-snapshot project "demo-1" "review" :from from)
                       (list dir "feat/demo-1-pool" head)))
        (should (equal (let ((default-directory dir)) (+test-awp--git "rev-parse" "HEAD")) head))
        (delete-directory dir t)
        (should (string-match-p "demo-1@review" (+test-awp--git "worktree" "list")))
        (agent-workflow-snapshot project "demo-1" "review" :from from)
        (should (file-exists-p (expand-file-name "README" dir)))
        (write-region "scratch\n" nil (expand-file-name "scratch.txt" dir))
        (agent-workflow-snapshot project "demo-1" "review" :from from)
        (should (file-exists-p (expand-file-name "README" dir)))
        (should-not (file-exists-p (expand-file-name "scratch.txt" dir)))
        (should (= calls 0)))
      (agent-workflow-snapshot-remove project "demo-1" "review")
      (should-not (file-exists-p dir))
      (should-not (string-match-p "demo-1@review" (+test-awp--git "worktree" "list"))))))

(ert-deftest agent-workflow-pool/the-main-branch-read-once-a-turn ()
  "Read from git once a turn (doom-8y4: two git calls each time a job's
script, agent or pane asked); a change made meanwhile seen the next turn."
  (+test-awp--with-project "main-branch"
    (+test-awp--counting 'agent-workflow--main-branch-read
      (should (equal (agent-workflow-main-branch project) "main"))
      (should (equal (agent-workflow-main-branch (directory-file-name project)) "main"))
      (should (= calls 1))
      (+test-awp--git "branch" "-m" "main" "master")
      (should (equal (agent-workflow-main-branch project) "main"))
      (+test-sleep 0.01)
      (should (equal (agent-workflow-main-branch project) "master"))
      (should (= calls 2)))))

(ert-deftest agent-workflow-pool/no-worktree-without-a-commit ()
  (let ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "awp-empty-") t))))
    (let ((default-directory dir))
      (+test-awp--git "init" "-q")
      (should-error (agent-workflow-worktree dir "demo-1") :type 'user-error))))

;; ====== AN AGENT ======

(ert-deftest agent-workflow-pool/an-agent ()
  "A job's agent: its session named by its issue and job, in the issue's
worktree, its bd as ISSUE/JOB, its agent's model, mode and tools (their
variables filled in, shell-quoted), told its job, how it ends it and its
agent's instructions; its first message sent."
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
        ;; Its session: its agent's tools, filled in.
        (let* ((new (car (+test-awp--wait
                          (lambda () (+test-awp--logged (lambda (e) (equal (plist-get e :method) "session/new")))))))
               (options (plist-get (plist-get (plist-get (plist-get new :params) :_meta) :claudeCode) :options)))
          ;; Ending its step needs no permission.
          (should (equal (plist-get options :allowedTools)
                         (list "Read" (format "Bash(git -C %s commit:*)" (shell-quote-argument (directory-file-name worktree)))
                               (format "Bash(%s done:*)" (expand-file-name "cmd/agent-workflow" +test-root)))))
          ;; What runs it, never changed by it.
          ;; What runs it, never changed by it: the project's, yours (in
          ;; .agent-shell/), where it works and in the main checkout.
          (let ((denied (plist-get options :disallowedTools))
                (main (concat "/" (file-name-as-directory (expand-file-name project)))))
            (should (equal (car denied) "Bash(git push:*)"))
            (dolist (tool '("Edit" "Write" "NotebookEdit"))
              (dolist (pattern '(".agent-workflow/**" ".agent-shell/agent-workflow/workflows/**"
                                 ".agent-shell/agent-workflow/agents/**"))
                (should (member (format "%s(%s)" tool pattern) denied))
                (should (member (format "%s(%s%s)" tool main pattern) denied))))
            (should (string-prefix-p "Edit(//" (seq-find (lambda (rule) (string-search main rule)) denied)))))
        ;; Its first message, its variables filled in.
        (should (+test-awp--wait
                 (lambda () (+test-awp--logged (lambda (e) (and (equal (plist-get e :method) "session/prompt")
                                                                (string-match-p "Build demo-1: A pool"
                                                                                (format "%S" (plist-get e :params))))))))))
      ;; Its model and mode, the agent's.
      (let ((config (agent-workflow--config agent)))
        (should (equal (funcall (alist-get :default-model-id config)) "sonnet"))
        (should (equal (funcall (alist-get :default-session-mode-id config)) "acceptEdits"))
        (should (equal (alist-get :buffer-name config) "demo-1 · build")))
      ;; What it's told.
      (let ((told (let ((agent-workflow--starting agent)) (agent-workflow-agent-context))))
        (should (string-match-p "you do the job build of the run on the issue demo-1" told))
        (should (string-match-p "known as \"demo-1 · build\"" told))
        (should (string-match-p (regexp-quote "cmd/agent-workflow done OUTCOME \"notes\": the outcome (one of done, approved, changes)") told))
        (should (string-match-p "Never switch, make or rename branches, push, or change, relabel or close the issue" told))
        (should (string-match-p "run as demo-1/build (BEADS_ACTOR)" told))
        (should (string-suffix-p "Build demo-1 on feat/demo-1-pool, in agent." told)))
      (should-not (agent-workflow-agent-context)))))

(ert-deftest agent-workflow-pool/told-whatever-its-agent ()
  "What its session is told (every session's, then its job's): to an agent
taking a system prompt from Emacs (the stand-in, as Claude Code's adapter),
as it; to one taking none, before its first message, once."
  (+test-awp--with-project "told"
    (+test-awp--start project "demo-1" "build" :prompt "Build it")
    (let* ((new (car (+test-awp--wait
                      (lambda () (+test-awp--logged (lambda (e) (equal (plist-get e :method) "session/new")))))))
           (system (plist-get (plist-get new :params) :systemPrompt))
           (text (plist-get (car (plist-get system :content)) :text))
           (prompt (car (+test-awp--wait
                         (lambda () (+test-awp--logged (lambda (e) (equal (plist-get e :method) "session/prompt"))))))))
      (should (equal (plist-get system :mode) "append"))
      (should (string-prefix-p "You are running inside Emacs" text))
      (should (string-match-p "you do the job build of the run on the issue demo-1" text))
      ;; Its first message, its own alone.
      (should (equal (mapcar (lambda (block) (plist-get block :text)) (plist-get (plist-get prompt :params) :prompt))
                     '("Build it")))))
  (+test-awp--with-project "told-first"
    (let ((process-environment (cons "MOCK_ACP_NO_SYSTEM_PROMPT=1" process-environment)))
      (let ((agent (+test-awp--start project "demo-1" "build" :prompt "Build it")))
        (let* ((new (car (+test-awp--wait
                          (lambda () (+test-awp--logged (lambda (e) (equal (plist-get e :method) "session/new")))))))
               (prompt (car (+test-awp--wait
                             (lambda () (+test-awp--logged (lambda (e) (equal (plist-get e :method) "session/prompt")))))))
               (blocks (mapcar (lambda (block) (plist-get block :text)) (plist-get (plist-get prompt :params) :prompt))))
          (should-not (plist-get (plist-get new :params) :systemPrompt))
          (should (= (length blocks) 2))
          (should (string-match-p "<system-prompt>\nYou are running inside Emacs" (car blocks)))
          (should (string-match-p "you do the job build of the run on the issue demo-1" (car blocks)))
          (should (equal (cadr blocks) "Build it")))
        ;; Its next message, its own alone.
        (+test-awp--wait (lambda () (not (with-current-buffer (agent-workflow-agent-buffer agent) (shell-maker-busy)))) 5)
        (agent-workflow-send agent "Again")
        (let ((again (car (last (+test-awp--wait
                                 (lambda () (let ((prompts (+test-awp--logged
                                                            (lambda (e) (equal (plist-get e :method) "session/prompt")))))
                                              (and (= (length prompts) 2) prompts))))))))
          (should (equal (mapcar (lambda (block) (plist-get block :text)) (plist-get (plist-get again :params) :prompt))
                         '("Again"))))))))

(ert-deftest agent-workflow-pool/a-step-s-model-and-effort ()
  "Its model and effort: its agent's, or its step's over them; its effort
set once its model is, as a config option (claude-agent-acp's effort)."
  (+test-awp--with-project "effort"
    ;; Its agent's: sonnet, no effort.
    (let ((agent (+test-awp--start project "demo-1" "build")))
      (should-not (alist-get :default-config-options (agent-workflow--config agent))))
    ;; Its step's, over them.
    (let* ((agent (+test-awp--start project "demo-2" "build" :model "opus" :effort "high"))
           (config (agent-workflow--config agent)))
      (should (equal (funcall (alist-get :default-model-id config)) "opus"))
      ;; By ACP's category for it (Claude Code's effort; another's own).
      (should (equal (funcall (alist-get :default-config-options config)) '(("thought_level" . "high"))))
      (should (equal (plist-get (agent-workflow-definition-filled agent) :effort) "high"))
      ;; Its session: its model set, then its effort.
      (let* ((set (car (+test-awp--wait
                        (lambda () (+test-awp--logged
                                    (lambda (e) (equal (plist-get e :method) "session/set_config_option")))))))
             (entries (+test-awp--log-entries))
             (model (seq-find (lambda (e) (and (equal (plist-get e :method) "session/set_model")
                                               (equal (plist-get (plist-get e :params) :modelId) "opus")))
                              entries)))
        (should (equal (plist-get (plist-get set :params) :configId) "effort"))
        (should (equal (plist-get (plist-get set :params) :value) "high"))
        (should model)
        (should (< (seq-position entries model) (seq-position entries set)))))))

(ert-deftest agent-workflow-pool/its-kind ()
  "Its kind: its step's, else its agent file's, else `agent-workflow-kind';
its session started with that kind's config, Claude Code's options only for
Claude Code."
  (+test-awp--with-project "kind"
    (let ((agent-workflow-kinds (append agent-workflow-kinds
                                        '((other :config agent-shell-mock-agent-make-agent-config)))))
      ;; The default: Claude Code's (the stand-in as it).
      (let ((agent (+test-awp--start project "demo-1" "build")))
        (should (eq (plist-get (agent-workflow-definition-filled agent) :kind) 'mock))
        (should (alist-get 'claudeCode (alist-get :session-meta (agent-workflow--config agent)))))
      ;; Its step's, another kind: no Claude Code options.
      (let ((agent (+test-awp--start project "demo-2" "build" :kind 'other)))
        (should (eq (plist-get (agent-workflow-definition-filled agent) :kind) 'other))
        (should-not (alist-get 'claudeCode (alist-get :session-meta (agent-workflow--config agent)))))
      ;; One that isn't: an error, nothing started.
      (should-error (+test-awp--start project "demo-3" "build" :kind 'nothing)))))

(ert-deftest agent-workflow-pool/a-cost-not-reported-is-unknown ()
  "An agent other than Claude Code whose session reported no cost (agent-shell
starts it at 0.0, no currency): its cost unknown; one reported: known. Claude
Code's: known (doom-38o.73)."
  (+test-awp--with-project "cost"
    (let ((agent-workflow-kinds (append agent-workflow-kinds
                                        '((other :config agent-shell-mock-agent-make-agent-config)))))
      (let ((other (+test-awp--start project "demo-1" "build" :kind 'other)))
        (should (plist-get (agent-workflow--agent-usage other) :unknown))
        (with-current-buffer (agent-workflow-agent-buffer other)
          (let ((usage (copy-alist (map-elt agent-shell--state :usage))))
            (setf (alist-get :cost-amount usage) 0.5
                  (alist-get :cost-currency usage) "USD")
            (map-put! agent-shell--state :usage usage)))
        (should-not (plist-get (agent-workflow--agent-usage other) :unknown))
        (should (equal (plist-get (agent-workflow--agent-usage other) :cost) 0.5)))
      (should-not (plist-get (agent-workflow--agent-usage (+test-awp--start project "demo-2" "build")) :unknown)))))

(ert-deftest agent-workflow-pool/another-kind-s-rules ()
  "An agent other than Claude Code: its tools, ending its step, its deny and
what runs it answer its permission requests (Claude Code's: in its
options, none here): done allowed, a denied command or an edit of
.agent-workflow/ refused, there or in the main checkout."
  (+test-awp--with-project "rules"
    (let ((agent-workflow-kinds (append agent-workflow-kinds
                                        '((other :config agent-shell-mock-agent-make-agent-config)))))
      (let* ((claude (+test-awp--start project "demo-1" "build"))
             (other (+test-awp--start project "demo-2" "build" :kind 'other))
             (rules (buffer-local-value '+my/agent-shell-permission-rules (agent-workflow-agent-buffer other)))
             (dir (agent-workflow-agent-worktree other))
             (verdict (lambda (kind &rest more)
                        (+my/agent-shell-permission-by-rules
                         rules (append (list (cons :kind kind))
                                       (cl-loop for (key value) on more by #'cddr collect (cons key value)))
                         dir))))
        (should-not (buffer-local-value '+my/agent-shell-permission-rules (agent-workflow-agent-buffer claude)))
        (should (member (format "Bash(%s done:*)" agent-workflow-command) (plist-get rules :tools)))
        (should (eq (funcall verdict "execute" :raw-input `((command . ,(concat agent-workflow-command " done approved \"ok\""))))
                    'allow))
        (should (eq (funcall verdict "execute" :raw-input '((command . "git push origin"))) 'reject))
        (should (eq (funcall verdict "read") 'allow))
        (should (eq (funcall verdict "edit" :raw-input `((file_path . ,(expand-file-name ".agent-workflow/workflows/x.yml" dir))))
                    'reject))
        (should (eq (funcall verdict "edit" :raw-input `((file_path . ,(expand-file-name ".agent-workflow/scripts/a.sh" project))))
                    'reject))
        ;; Its own files: not decided here (asked, or its mode's).
        (should-not (funcall verdict "edit" :raw-input `((file_path . ,(expand-file-name "src/a.el" dir)))))))))

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
alive), nor with an agent that isn't one; nothing made."
  (+test-awp--with-project "refused"
    (should (equal (cadr (should-error (+test-awp--start project "demo-1" "build" :definition "nobody") :type 'user-error))
                   "No agent nobody: build"))
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

(ert-deftest agent-workflow-pool/an-agent-s-canvas-opens-only-asking ()
  "An agent of the pool's canvas opens no pane (it stays with its session),
unless it asks you something there; any other canvas as before."
  (let* ((opened nil)
         (agent-workflow--canvas-fallback (lambda (canvas) (push canvas opened)))
         (asks nil))
    (cl-letf (((symbol-function 'agent-workflow--canvas-agent) (lambda (canvas) (equal canvas "agent's")))
              ((symbol-function 'agent-workflow--pane-asks-p) (lambda (_canvas) asks))
              ((symbol-function 'agent-workflow--pane-quiet-p) #'ignore))
      (agent-workflow--display-canvas "agent's")
      (should-not opened)
      (setq asks t)
      (agent-workflow--display-canvas "agent's")
      (should (equal opened '("agent's")))
      (setq asks nil)
      (agent-workflow--display-canvas "another")
      (should (equal opened '("another" "agent's"))))))
