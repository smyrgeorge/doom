;;; tests/unit/test-agent-workspace-session.el -*- lexical-binding: t; -*-
;; config/agent-workspace/session.el, with core.el: agents' real agent-shell
;; sessions, each in its own worktree of a throwaway git repository, run by a
;; stand-in agent (examples/agent-workspace/stand-in.el, agent-shell's mock agent kind):
;; their states following the events, what you do to one, closing a crew
;; leaving no process.
;; run.sh: slow (~55 s: stand-in sessions).

(require 'agent-shell)
(require 'agent-shell-mock-agent)
(require 'json)

;; Git as git is, not as your ~/.gitconfig has it (hooks, signing...).
(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(+test-load "config/agent-shell" "config/agent-workspace")

;; Nothing about this config's own issues in the stand-in's prompt.
(remove-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context)

(defconst +test-aws--mock (expand-file-name "examples/agent-workspace/stand-in.el" +test-root)
  "The stand-in agent.")

(setq agent-shell-mock-agent-acp-command
      (list (expand-file-name invocation-name invocation-directory)
            "--batch" "-Q" (concat "--init-directory=" (+test-tmp-file "mock-acp-home/"))
            "-l" +test-aws--mock "-f" "mock-acp-main"))

(add-to-list 'agent-workspace-kinds '(mock :config agent-shell-mock-agent-make-agent-config))
;; The stand-in, given Claude Code's options as Claude Code is.
(add-to-list 'agent-workspace-kinds '(mock-claude :config agent-shell-mock-agent-make-agent-config
                                                  :claude-code t))

;; ====== HELPERS ======

(defvar +test-aws--log nil "The stand-in's log file, this test's.")

(defun +test-aws--git (&rest args)
  "Run git with ARGS in `default-directory'; its output."
  (with-temp-buffer
    (unless (eql 0 (apply #'call-process "git" nil t nil args))
      (error "git %S: %s" args (buffer-string)))
    (string-trim (buffer-string))))

(defun +test-aws--project (name &optional beads)
  "A git repository NAME in the temp folder, with a commit (BEADS: and a
.beads/ folder): its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "aws/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (+test-aws--git "init" "-q" "-b" "main")
      (write-region "hello\n" nil (expand-file-name "README" dir))
      (+test-aws--git "add" "README")
      (+test-aws--git "-c" "user.name=Test" "-c" "user.email=test@example.com" "commit" "-q" "-m" "first")
      (when beads (make-directory (expand-file-name ".beads" dir))))
    (file-name-as-directory (file-truename dir))))

(defmacro +test-aws--with-crew (name &rest body)
  "BODY in a new project NAME (`default-directory'), its crew closed after,
the stand-in's log fresh."
  (declare (indent 1))
  `(+test-with-reset
     (let* ((project (+test-aws--project ,name))
            (default-directory project)
            (+test-aws--log (expand-file-name (concat "aws/" ,name ".log") +test-tmp))
            (process-environment (cons (concat "MOCK_ACP_LOG=" +test-aws--log) process-environment)))
       (ignore-errors (delete-file +test-aws--log))
       (unwind-protect (progn ,@body)
         (agent-workspace-close-all)))))

(defun +test-aws--wait (predicate &optional timeout)
  "Wait until PREDICATE returns non-nil, TIMEOUT seconds at most (default 20):
its value, or nil."
  (let ((end (+ (float-time) (or timeout 20)))
        value)
    (while (and (not (setq value (funcall predicate))) (< (float-time) end))
      (accept-process-output nil 0.05))
    value))

(defun +test-aws--state (agent state &optional timeout)
  "Wait for AGENT to be in STATE; non-nil if it got there."
  (+test-aws--wait (lambda () (eq (agent-workspace-agent-state agent) state)) timeout))

(defun +test-aws--create (name &rest args)
  "An agent NAME at the desk: ARGS `agent-workspace-create''s (default: a
builder, the stand-in)."
  (let ((agent (apply #'agent-workspace-create (append args (list :role "builder" :name name :kind 'mock)))))
    (should (+test-aws--state agent 'desk))
    agent))

(defun +test-aws--log-entries ()
  "What the stand-in logged: a plist each."
  (when (file-exists-p +test-aws--log)
    (with-temp-buffer
      (insert-file-contents +test-aws--log)
      (mapcar (lambda (line) (json-parse-string line :object-type 'plist :null-object nil
                                                :false-object nil :array-type 'list))
              (split-string (buffer-string) "\n" t)))))

(defun +test-aws--prompts (name)
  "The prompts the agent NAME got, in order."
  (cl-loop for entry in (+test-aws--log-entries)
           when (and (equal (plist-get entry :agent) name)
                     (equal (plist-get entry :method) "session/prompt"))
           collect (mapconcat (lambda (block) (plist-get block :text))
                              (plist-get (plist-get entry :params) :prompt) "")))

(defun +test-aws--logged (key name)
  "The values of KEY (:start, :child) the agent NAME logged."
  (cl-loop for entry in (+test-aws--log-entries)
           when (and (equal (plist-get entry :agent) name) (plist-get entry key))
           collect (plist-get entry key)))

(defun +test-aws--pid-alive-p (pid)
  "Non-nil if PID runs (not a zombie)."
  (when-let* ((attributes (process-attributes pid)))
    (not (member (alist-get 'state attributes) '("Z" "X")))))

(defun +test-aws--answer (agent option)
  "Answer AGENT's raised hand (a permission) with OPTION, as its buttons do."
  (with-current-buffer (agent-workspace-agent-buffer agent)
    (agent-shell--send-permission-response
     :client (map-elt agent-shell--state :client)
     :request-id (plist-get (agent-workspace-agent-ask agent) :request-id)
     :option-id option
     :state agent-shell--state
     :tool-call-id "t1")))

(defmacro +test-aws--no-questions (&rest body)
  "BODY, failing the test if anything is asked."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest args) (error "Asked: %S" args)))
             ((symbol-function 'yes-or-no-p) (lambda (&rest args) (error "Asked: %S" args))))
     ,@body))

;; ====== STARTING ======

(ert-deftest agent-workspace-session/starts-in-its-worktree ()
  "An agent's session starts in its own worktree, named after it, its buffer
\"ada · builder\", not shown; it wakes up, then waits at the desk."
  (+test-aws--with-crew "start"
    (let ((states nil))
      (let ((agent-workspace-state-change-functions
             (list (lambda (_agent old new) (push (cons old new) states)))))
        (let ((agent (+test-aws--create "ada")))
          (should (equal (reverse states) '((waking . desk))))
          (let ((buffer (agent-workspace-agent-buffer agent))
                (worktree (expand-file-name ".agent-shell/worktrees/builder-ada/" project)))
            (should (equal (buffer-name buffer) "ada · builder"))
            (should-not (get-buffer-window buffer t))
            (should (eq (agent-workspace-buffer-agent buffer) agent))
            (should (equal (agent-workspace-agent-worktree agent) worktree))
            (should (equal (buffer-local-value 'default-directory buffer) worktree))
            (should (equal (agent-workspace-agent-branch agent) "agent/ada"))
            (let ((default-directory worktree))
              (should (equal (+test-aws--git "branch" "--show-current") "agent/ada")))
            ;; The agent runs there.
            (should (equal (plist-get (car (+test-aws--log-entries)) :cwd) worktree))
            (should (equal (agent-workspace-agents) (list agent)))
            (should (eq (agent-workspace-agent "ada") agent))))))))

(ert-deftest agent-workspace-session/its-environment ()
  "Its name for Beads and for us; the project's issues where it has some."
  (+test-with-reset
    (let* ((project (+test-aws--project "environment" t))
           (default-directory project)
           (+test-aws--log (expand-file-name "aws/environment.log" +test-tmp))
           (process-environment (cons (concat "MOCK_ACP_LOG=" +test-aws--log) process-environment)))
      (ignore-errors (delete-file +test-aws--log))
      (unwind-protect
          (progn
            (+test-aws--create "ada")
            (let ((start (car (+test-aws--logged :start "ada"))))
              (should (equal (plist-get start :BEADS_ACTOR) "ada"))
              (should (equal (plist-get start :BEADS_DIR) (expand-file-name ".beads" project)))))
        (agent-workspace-close-all)))))

(ert-deftest agent-workspace-session/a-first-message ()
  ":prompt is its first message, sent once it's ready."
  (+test-aws--with-crew "first-message"
    (let ((agent (agent-workspace-create :role "builder" :name "ada" :kind 'mock :prompt "hello there")))
      (should (+test-aws--state agent 'done))
      (should (equal (+test-aws--prompts "ada") '("hello there"))))))

(ert-deftest agent-workspace-session/an-agent-that-cant-start ()
  "An agent whose agent can't run is stuck, saying why; nothing is left of
its session."
  (+test-aws--with-crew "cant-start"
    (let* ((agent-shell-mock-agent-acp-command '("/nonexistent/agent"))
           (agent (agent-workspace-create :role "builder" :name "ada" :kind 'mock)))
      (should (eq (agent-workspace-agent-state agent) 'stuck))
      (should (agent-workspace-agent-error agent))
      (should-not (agent-workspace-agent-buffer agent))
      (should-not (get-buffer "ada · builder")))))

;; ====== ITS ROLE ======

(defun +test-aws--new-session (name)
  "The session/new the agent NAME's agent got: its params."
  (cl-loop for entry in (+test-aws--log-entries)
           when (and (equal (plist-get entry :agent) name)
                     (equal (plist-get entry :method) "session/new"))
           return (plist-get entry :params)))

(defun +test-aws--mode-set (name)
  "The permission modes the agent NAME's agent was set to."
  (cl-loop for entry in (+test-aws--log-entries)
           when (and (equal (plist-get entry :agent) name)
                     (equal (plist-get entry :method) "session/set_mode"))
           collect (plist-get (plist-get entry :params) :modeId)))

(ert-deftest agent-workspace-session/its-role-s-tools-and-mode-reach-its-agent ()
  "A role's tools and permission mode go to the agent, enforced there: its
denied tools in Claude Code's disallowedTools (claude-agent-acp merges them
into Claude Code's own: they're never offered), its allowed ones in
allowedTools, its mode set before its first prompt; its model too."
  (+test-aws--with-crew "role"
    (let ((sam (+test-aws--create "sam" :role "investigator" :kind 'mock-claude))
          (ada (+test-aws--create "ada" :kind 'mock-claude))
          (linus (+test-aws--create "linus" :model "haiku" :kind 'mock-claude)))
      (let ((options (plist-get (plist-get (plist-get (+test-aws--new-session "sam") :_meta) :claudeCode)
                                :options)))
        (should (equal (plist-get options :disallowedTools) '("Edit" "Write" "NotebookEdit")))
        (should (member "Bash(bd:*)" (plist-get options :allowedTools)))
        (should-not (member "Edit" (plist-get options :allowedTools))))
      (should (equal (+test-aws--mode-set "sam") '("auto")))
      (let ((options (plist-get (plist-get (plist-get (+test-aws--new-session "ada") :_meta) :claudeCode)
                                :options)))
        (should (equal (plist-get options :disallowedTools) '("Bash(git push:*)")))
        (should (member "Edit" (plist-get options :allowedTools))))
      (should (equal (+test-aws--mode-set "ada") '("auto")))
      (should (cl-loop for entry in (+test-aws--log-entries)
                       thereis (and (equal (plist-get entry :agent) "linus")
                                    (equal (plist-get entry :method) "session/set_model")
                                    (equal (plist-get (plist-get entry :params) :modelId) "haiku"))))
      (dolist (agent (list sam ada linus))
        (should (eq (agent-workspace-agent-state agent) 'desk))))))

;; ====== ITS STATES ======

(ert-deftest agent-workspace-session/a-turn-done-until-you-look ()
  "A message makes it work, its time counted from then; its turn over, it's
done until its session is shown; shown when its turn ends, at the desk."
  (+test-aws--with-crew "turn"
    (let ((agent (+test-aws--create "ada")))
      (should (eq (agent-workspace-send agent "hello" :submit t) 'sent))
      (should (+test-aws--wait (lambda () (agent-workspace-agent-since agent))))
      (should (+test-aws--state agent 'done))
      (should-not (agent-workspace-agent-since agent))
      (should (equal (agent-workspace-state-text agent) "done, have a look"))
      (agent-workspace-seen agent)
      (should (eq (agent-workspace-agent-state agent) 'desk))
      ;; Shown as its turn ends: at the desk.
      (switch-to-buffer (agent-workspace-agent-buffer agent))
      (agent-workspace-send agent "again" :submit t)
      (should (+test-aws--state agent 'working))
      (should (+test-aws--wait (lambda () (eq (agent-workspace-agent-state agent) 'desk))))
      (should (equal (+test-aws--prompts "ada") '("hello" "again"))))))

(ert-deftest agent-workspace-session/a-hand-raised ()
  "A permission asked: its hand raised, saying what it wants; answered, back
to work, its time not reset; its turn then over."
  (+test-aws--with-crew "hand"
    (let ((agent (+test-aws--create "ada")))
      (agent-workspace-send agent "permission please" :submit t)
      (should (+test-aws--state agent 'hand))
      (should (equal (agent-workspace-state-text agent) "wants to run npm install"))
      (should (eq (plist-get (agent-workspace-agent-ask agent) :kind) 'permission))
      (let ((since (agent-workspace-agent-since agent)))
        (should since)
        (+test-aws--answer agent "allow")
        (should (+test-aws--state agent 'working))
        (should (equal (agent-workspace-agent-since agent) since))
        (should-not (agent-workspace-agent-ask agent)))
      (should (+test-aws--state agent 'done)))))

(ert-deftest agent-workspace-session/a-question-on-its-canvas ()
  "Its turn ended with a question waiting on its Agent UI canvas: its hand
raised."
  (+test-aws--with-crew "question"
    (let ((agent (+test-aws--create "ada")))
      (run-hook-with-args 'agent-ui-question-waiting-functions
                          (agent-workspace-agent-buffer agent) nil "q1")
      (should (eq (agent-workspace-agent-state agent) 'hand))
      (should (equal (agent-workspace-state-text agent) "asks: a question on its canvas"))
      ;; Another session's question isn't its.
      (agent-workspace-seen agent)
      (with-temp-buffer
        (run-hook-with-args 'agent-ui-question-waiting-functions (current-buffer) nil "q2")))))

(ert-deftest agent-workspace-session/stuck-on-an-error ()
  (+test-aws--with-crew "stuck"
    (let ((agent (+test-aws--create "ada")))
      (agent-workspace-send agent "fail" :submit t)
      (should (+test-aws--state agent 'stuck))
      (should (string-match-p "mock failure" (agent-workspace-agent-error agent)))
      ;; A new message: working again.
      (agent-workspace-send agent "hello" :submit t)
      (should (+test-aws--state agent 'done))
      (should-not (agent-workspace-agent-error agent)))))

(ert-deftest agent-workspace-session/failing-after-it-started ()
  "A failure after agent-shell started its session (a hook of the app's):
the agent stuck, saying why; its session's buffer and process stopped, none
left out of reach (doom-pbk.39)."
  (+test-aws--with-crew "failing-after"
    (let* ((agent-workspace-exit-timeout 1)
           (agent-workspace-session-functions
            (append agent-workspace-session-functions (list (lambda (&rest _) (error "a hook failed")))))
           (agent (agent-workspace-create :role "builder" :name "ada" :kind 'mock)))
      (should (eq (agent-workspace-agent-state agent) 'stuck))
      (should (equal (agent-workspace-agent-error agent) "its session: a hook failed"))
      (should-not (agent-workspace-agent-buffer agent))
      (should-not (get-buffer "ada · builder"))
      (when-let* ((pid (+test-aws--wait (lambda () (plist-get (car (+test-aws--logged :start "ada")) :pid)) 5)))
        (should (+test-aws--wait (lambda () (not (+test-aws--pid-alive-p pid))) 10))))))

(ert-deftest agent-workspace-session/its-process-ending-sends-it-home ()
  "Its agent exiting (a crash): gone home, its session's buffer kept (what
it said); woken, a fresh session."
  (+test-aws--with-crew "exit"
    (let ((agent (+test-aws--create "ada")))
      (agent-workspace-send agent "exit" :submit t)
      (should (+test-aws--state agent 'home))
      (should-not (agent-workspace-live-p agent))
      (should-error (agent-workspace-send agent "hello" :submit t) :type 'user-error)
      (let ((old (agent-workspace-agent-buffer agent)))
        (agent-workspace-wake agent)
        (should (+test-aws--state agent 'desk))
        (should-not (buffer-live-p old))))))

(ert-deftest agent-workspace-session/what-the-app-sent ()
  "A prompt submitted: what the app sent of it (marked as it sent it,
`agent-workspace-send') taken out, each mark once, the rest yours (room.el
says it); a part of it only between blank lines (agent-shell sends what was
queued as one, joined so)."
  (with-temp-buffer
    (setq agent-workspace--sent (list "fix it" "Work on p-1: X"))
    (should-not (agent-workspace--not-sent-by-app (current-buffer) "Work on p-1: X\n"))
    (should (equal agent-workspace--sent '("fix it")))
    ;; Its mark taken: the same again is yours.
    (should (equal (agent-workspace--not-sent-by-app (current-buffer) "Work on p-1: X") "Work on p-1: X"))
    ;; Sent as one with yours.
    (should (equal (agent-workspace--not-sent-by-app (current-buffer) "fix it\n\nand the docs") "and the docs"))
    (should-not agent-workspace--sent)
    ;; Not a part: in a line of yours.
    (setq agent-workspace--sent (list "fix"))
    (should (equal (agent-workspace--not-sent-by-app (current-buffer) "fix the tests") "fix the tests"))
    (should (equal agent-workspace--sent '("fix")))
    (should (equal (agent-workspace--not-sent-by-app (current-buffer) "mine\n\nfix\n\nmore") "mine\n\nmore"))
    (should-not agent-workspace--sent)))

(ert-deftest agent-workspace-session/what-still-waits-isn-t-sent ()
  "A mark whose prompt still waits in agent-shell's queue (the turn it waited
for interrupted, the queue kept) isn't taken by a prompt with its text: that
one is yours. Out of the queue (sent), it's taken."
  (with-temp-buffer
    (let ((queued (copy-sequence "again please")))
      (setq-local agent-shell--state (list (cons :pending-prompts (list queued))))
      (setq agent-workspace--sent (list queued))
      (should (equal (agent-workspace--not-sent-by-app (current-buffer) "again please") "again please"))
      (should (eq (car agent-workspace--sent) queued))
      (setf (alist-get :pending-prompts agent-shell--state) nil)
      (should-not (agent-workspace--not-sent-by-app (current-buffer) "again please"))
      (should-not agent-workspace--sent))))

(ert-deftest agent-workspace-session/a-message-while-it-works-waits ()
  "Sent while it works, a message waits for its turn's end (agent-shell's
queue), then goes."
  (+test-aws--with-crew "queue"
    (let ((agent (+test-aws--create "ada")))
      (agent-workspace-send agent "hold" :submit t)
      (should (+test-aws--state agent 'working))
      (should (+test-aws--wait (lambda () (member "hold" (+test-aws--prompts "ada")))))
      (should (eq (agent-workspace-send agent "next one" :submit t) 'queued))
      ;; Interrupted, agent-shell asks whether to go on with what's queued.
      (cl-letf (((symbol-function 'y-or-n-p) #'ignore))
        (agent-workspace-interrupt agent)
        (should (+test-aws--state agent 'desk)))
      (should (equal (+test-aws--prompts "ada") '("hold")))
      ;; Not interrupted, it goes after the turn.
      (agent-workspace-send agent "slow" :submit t)
      (should (+test-aws--state agent 'working))
      (should (eq (agent-workspace-send agent "after it" :submit t) 'queued))
      (should (+test-aws--state agent 'done))
      ;; Sent after it, with what was still queued (agent-shell merges them).
      (should (+test-aws--wait (lambda () (seq-find (lambda (prompt) (string-match-p "after it" prompt))
                                                    (+test-aws--prompts "ada")))))
      ;; Each one the app's, none left waiting.
      (should (+test-aws--wait (lambda () (null (buffer-local-value 'agent-workspace--sent
                                                                     (agent-workspace-agent-buffer agent)))))))))

;; ====== ITS BRANCHES ======

(ert-deftest agent-workspace-session/a-branch-for-each-piece-of-work ()
  "Its work on branches of its own, made as its turn starts, before its
agent gets the prompt: a prompt at rest, one named from its words; an issue
given while it works, the issue's (TYPE/ID, from the main branch) as its
prompt, queued, starts its turn, the prompt's branch left holding nothing
deleted; given one at the desk, at once. Its bar's branch follows, renamed
by the agent too (at its turn's end)."
  (+test-aws--with-crew "branches"
    (let* ((agent (+test-aws--create "ada"))
           (dir (agent-workspace-agent-worktree agent))
           (head (lambda () (let ((default-directory dir)) (+test-aws--git "branch" "--show-current")))))
      (should (equal (funcall head) "agent/ada"))
      (agent-workspace-send agent "slow, please" :submit t)
      (should (+test-aws--state agent 'working))
      (should (equal (funcall head) "slow-please"))
      (should (equal (agent-workspace-agent-branch agent) "slow-please"))
      ;; An issue while it works: its prompt queued, its branch with it.
      (agent-workspace-give agent "demo-1" "Lexer: strings")
      (should (eq (agent-workspace-send agent (agent-workspace-issue-prompt "demo-1" "Lexer: strings") :submit t)
                  'queued))
      (should (equal (funcall head) "slow-please"))
      (should (+test-aws--wait (lambda () (member "Work on demo-1: Lexer: strings" (+test-aws--prompts "ada")))))
      (should (equal (funcall head) "task/demo-1-strings"))
      (should (equal (agent-workspace-agent-branch agent) "task/demo-1-strings"))
      ;; The stand-in logs a prompt, then runs git to log its branch.
      (should (+test-aws--wait (lambda () (= (length (+test-aws--logged :branch "ada")) 2))))
      (should (equal (+test-aws--logged :branch "ada") '("slow-please" "task/demo-1-strings")))
      (let ((default-directory project))
        (should (equal (+test-aws--git "branch" "--list" "slow-please") "")))
      ;; It names its branch, as it's told; its turn ends: its bar says it.
      (let ((default-directory dir))
        (+test-aws--git "branch" "-m" "task/demo-1-lexer-strings"))
      (agent-workspace-interrupt agent)
      (should (+test-aws--state agent 'desk))
      (should (equal (agent-workspace-agent-branch agent) "task/demo-1-lexer-strings"))
      ;; At the desk: at once.
      (agent-workspace-give agent "demo-2" "Parser" "feature")
      (should (equal (funcall head) "feat/demo-2-parser"))
      (agent-workspace-send agent (agent-workspace-issue-prompt "demo-2" "Parser") :submit t)
      (should (+test-aws--wait (lambda () (= (length (+test-aws--logged :branch "ada")) 3))))
      (should (equal (car (last (+test-aws--logged :branch "ada"))) "feat/demo-2-parser")))))

(ert-deftest agent-workspace-session/a-steer-keeps-its-branch ()
  "An issue given while it works, its prompt steered into the turn instead
(agent-shell's reroute, injected): its worktree stays on the branch of the
turn running, its files there; the issue's branch comes with its next turn
(doom-pbk.34)."
  (+test-aws--with-crew "steer"
    (let* ((agent (+test-aws--create "ada"))
           (dir (agent-workspace-agent-worktree agent))
           (head (lambda () (let ((default-directory dir)) (+test-aws--git "branch" "--show-current")))))
      (agent-workspace-give agent "demo-1" "One")
      (should (equal (funcall head) "task/demo-1"))
      (let ((default-directory dir))
        (write-region "one\n" nil "one.txt")
        (+test-aws--git "add" "one.txt")
        (+test-aws--git "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-m" "one"))
      (agent-workspace-send agent "Work on demo-1: One, hold" :submit t)
      (should (+test-aws--state agent 'working))
      ;; demo-2 given meanwhile, its prompt queued, then steered in.
      (agent-workspace-give agent "demo-2" "Two")
      (should (eq (agent-workspace-send agent (agent-workspace-issue-prompt "demo-2" "Two") :submit t) 'queued))
      (with-current-buffer (agent-workspace-agent-buffer agent)
        (map-put! agent-shell--state :supports-steering t)
        (goto-char (point-max))
        (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
          (call-interactively #'agent-shell-submit-override)))
      (should (+test-aws--wait (lambda () (string-search "[steer] Work on demo-2"
                                                         (with-current-buffer (agent-workspace-agent-buffer agent)
                                                           (buffer-string))))))
      (should (eq (agent-workspace-agent-state agent) 'working))
      (should (equal (funcall head) "task/demo-1"))
      (should (file-exists-p (expand-file-name "one.txt" dir)))
      ;; Its next turn: the issue's branch.
      (agent-workspace-interrupt agent)
      (should (+test-aws--state agent 'desk))
      (agent-workspace-send agent "go on" :submit t)
      (should (+test-aws--wait (lambda () (equal (funcall head) "task/demo-2-two"))))
      (should-not (file-exists-p (expand-file-name "one.txt" dir))))))

;; ====== WHAT YOU DO TO ONE ======

(ert-deftest agent-workspace-session/interrupt ()
  "Interrupted, its turn ends: at the desk (not done)."
  (+test-aws--with-crew "interrupt"
    (let ((agent (+test-aws--create "ada")))
      (agent-workspace-send agent "hold" :submit t)
      (should (+test-aws--wait (lambda () (member "hold" (+test-aws--prompts "ada")))))
      (agent-workspace-interrupt agent)
      (should (+test-aws--state agent 'desk)))))

(ert-deftest agent-workspace-session/kill ()
  "Killed: gone home, its session and process gone, its worktree kept, the
issue you gave it no longer its (given back in bd: test-agent-workspace-loops.el)."
  (+test-aws--with-crew "kill"
    (let* ((agent (+test-aws--create "ada"))
           (buffer (agent-workspace-agent-buffer agent))
           (pid (plist-get (car (+test-aws--logged :start "ada")) :pid)))
      (should (+test-aws--pid-alive-p pid))
      (agent-workspace-give agent "doom-a1b" "A title")
      (+test-aws--no-questions
        (agent-workspace-kill agent))
      (should (eq (agent-workspace-agent-state agent) 'home))
      (should (equal (agent-workspace-state-text agent) "gone home"))
      (should-not (buffer-live-p buffer))
      (should (+test-aws--wait (lambda () (not (+test-aws--pid-alive-p pid))) 10))
      (should (file-directory-p (expand-file-name ".agent-shell/worktrees/builder-ada/" project)))
      (should-not (agent-workspace-agent-issue agent))
      ;; Still in the crew; woken, fresh.
      (should (eq (agent-workspace-agent "ada") agent))
      (agent-workspace-wake agent)
      (should (+test-aws--state agent 'desk)))))

(ert-deftest agent-workspace-session/restart ()
  "Restarted: a fresh session, the old one gone."
  (+test-aws--with-crew "restart"
    (let* ((agent (+test-aws--create "ada"))
           (old (agent-workspace-agent-buffer agent)))
      (agent-workspace-send agent "hello" :submit t)
      (should (+test-aws--state agent 'done))
      (+test-aws--no-questions
        (agent-workspace-restart agent))
      (should-not (buffer-live-p old))
      (should (+test-aws--state agent 'desk))
      (should (buffer-live-p (agent-workspace-agent-buffer agent)))
      (should (equal (buffer-name (agent-workspace-agent-buffer agent)) "ada · builder"))
      ;; Two sessions started.
      (should (= (length (+test-aws--logged :start "ada")) 2)))))

(ert-deftest agent-workspace-session/its-worktrees-folder-deleted ()
  "The whole .agent-shell/ deleted by hand while the crew runs (git still
listing its worktrees, locked): restarted, woken, each agent's worktree is
made anew, on its branch, and its session starts (doom-pbk.33)."
  (+test-aws--with-crew "folder-gone"
    (let* ((ada (+test-aws--create "ada"))
           (ken (+test-aws--create "ken"))
           (dir (agent-workspace-agent-worktree ada)))
      (agent-workspace-sleep ken)
      (delete-directory (expand-file-name ".agent-shell" project) t)
      (+test-aws--no-questions
        (agent-workspace-restart ada))
      (should (+test-aws--state ada 'desk))
      (should (file-directory-p dir))
      (should (equal (agent-workspace-agent-worktree ada) dir))
      (should (equal (let ((default-directory dir)) (+test-aws--git "branch" "--show-current")) "agent/ada"))
      (agent-workspace-wake ken)
      (should (+test-aws--state ken 'desk))
      (should (file-directory-p (agent-workspace-agent-worktree ken)))
      (should (= (length (+test-aws--logged :start "ada")) 2))
      (should (= (length (+test-aws--logged :start "ken")) 2)))))

(ert-deftest agent-workspace-session/sleep-and-wake ()
  "Asleep: its session stopped, in the crew still; nothing sent to it;
woken: a fresh session."
  (+test-aws--with-crew "sleep"
    (let* ((agent (+test-aws--create "ada"))
           (buffer (agent-workspace-agent-buffer agent)))
      (agent-workspace-sleep agent)
      (should (eq (agent-workspace-agent-state agent) 'asleep))
      (should-not (buffer-live-p buffer))
      (should (eq (agent-workspace-agent "ada") agent))
      (should-error (agent-workspace-send agent "hello" :submit t) :type 'user-error)
      (should-error (agent-workspace-interrupt agent) :type 'user-error)
      (agent-workspace-wake agent)
      (should (+test-aws--state agent 'desk))
      (should-error (agent-workspace-wake agent) :type 'user-error))))

(ert-deftest agent-workspace-session/rename ()
  "Renamed: its session, worktree and branch take its new name (its session
started again); not while it works. On the branch of its work (a prompt's),
it stays there; agent/NAME, where it rests, renamed."
  (+test-aws--with-crew "rename"
    (let ((agent (+test-aws--create "ada")))
      (agent-workspace-rename agent "grace")
      (should (equal (agent-workspace-agent-name agent) "grace"))
      (should (+test-aws--state agent 'desk))
      (should (equal (buffer-name (agent-workspace-agent-buffer agent)) "grace · builder"))
      (let ((worktree (expand-file-name ".agent-shell/worktrees/builder-grace/" project)))
        (should (equal (agent-workspace-agent-worktree agent) worktree))
        (should (file-directory-p worktree))
        (should-not (file-exists-p (expand-file-name ".agent-shell/worktrees/builder-ada/" project)))
        (let ((default-directory worktree))
          (should (equal (+test-aws--git "branch" "--show-current") "agent/grace"))))
      (should (+test-aws--logged :start "grace"))
      (agent-workspace-send agent "hold" :submit t)
      (should (+test-aws--state agent 'working))
      (should-error (agent-workspace-rename agent "linus") :type 'user-error)
      ;; Asleep, it stays asleep.
      (agent-workspace-sleep agent)
      (agent-workspace-rename agent "linus")
      (should (eq (agent-workspace-agent-state agent) 'asleep))
      (should (equal (agent-workspace-agent-branch agent) "hold"))
      (let ((default-directory project))
        (should (equal (+test-aws--git "branch" "--list" "agent/linus" "agent/grace") "agent/linus"))))))

(ert-deftest agent-workspace-session/role-changed ()
  "Its role changed: its worktree moved to ROLE-NAME, its branch as it was,
its session started again as its role says; not while it works; asleep, it
stays asleep."
  (+test-aws--with-crew "role"
    (let ((agent (+test-aws--create "ada")))
      (agent-workspace-set-role agent "reviewer")
      (should (equal (agent-workspace-agent-role agent) "reviewer"))
      (should (+test-aws--state agent 'desk))
      (should (equal (buffer-name (agent-workspace-agent-buffer agent)) "ada · reviewer"))
      (let ((worktree (expand-file-name ".agent-shell/worktrees/reviewer-ada/" project)))
        (should (equal (agent-workspace-agent-worktree agent) worktree))
        (should (file-directory-p worktree))
        (should-not (file-exists-p (expand-file-name ".agent-shell/worktrees/builder-ada/" project)))
        (let ((default-directory worktree))
          (should (equal (+test-aws--git "branch" "--show-current") "agent/ada"))))
      (agent-workspace-send agent "hold" :submit t)
      (should (+test-aws--state agent 'working))
      (should-error (agent-workspace-set-role agent "builder") :type 'user-error)
      ;; Asleep, it stays asleep.
      (agent-workspace-sleep agent)
      (agent-workspace-set-role agent "builder")
      (should (eq (agent-workspace-agent-state agent) 'asleep))
      (should (file-directory-p (expand-file-name ".agent-shell/worktrees/builder-ada/" project))))))

(ert-deftest agent-workspace-session/a-name-a-forgotten-agent-left ()
  "Renamed to a name a forgotten agent left (ken, forgotten, his worktree and
branch kept), or given a role whose folder a forgotten one left: refused,
saying why, before anything changes: its name, worktree, branch, session
as they were (doom-pbk.35)."
  (+test-aws--with-crew "left"
    (let* ((ada (+test-aws--create "ada"))
           (ken (+test-aws--create "ken"))
           (session (agent-workspace-agent-buffer ada))
           (dir (agent-workspace-agent-worktree ada)))
      (agent-workspace-forget ken 'keep)
      (should (equal (cadr (should-error (agent-workspace-rename ada "ken") :type 'user-error))
                     "ken is the name of a forgotten agent: its worktree or branch is still there"))
      ;; A reviewer ada's folder, left.
      (make-directory (expand-file-name ".agent-shell/worktrees/reviewer-ada/" project) t)
      (should (equal (cadr (should-error (agent-workspace-set-role ada "reviewer") :type 'user-error))
                     ".agent-shell/worktrees/reviewer-ada is there already"))
      (should (equal (agent-workspace-agent-name ada) "ada"))
      (should (equal (agent-workspace-agent-role ada) "builder"))
      (should (eq (agent-workspace-agent-buffer ada) session))
      (should (buffer-live-p session))
      (should (equal (agent-workspace-agent-worktree ada) dir))
      (should (= (length (+test-aws--logged :start "ada")) 1)))))

(ert-deftest agent-workspace-session/a-rename-failing-midway ()
  "git failing midway through a rename (its branch not renamed): the agent as
it was: its name, its worktree where it was, locked with its name, its
branch, a session started again; said (doom-pbk.35)."
  (+test-aws--with-crew "midway"
    (let* ((ada (+test-aws--create "ada"))
           (dir (agent-workspace-agent-worktree ada))
           (git (symbol-function 'agent-workspace--git)))
      (cl-letf (((symbol-function 'agent-workspace--git)
                 (lambda (&rest args)
                   (if (equal (seq-take args 2) '("branch" "-m"))
                       (error "git branch: fatal: refused")
                     (apply git args)))))
        (should (equal (cadr (should-error (agent-workspace-rename ada "grace") :type 'user-error))
                       "ada isn't renamed: git branch: fatal: refused")))
      (should (equal (agent-workspace-agent-name ada) "ada"))
      (should (equal (agent-workspace-agent-worktree ada) dir))
      (should (file-directory-p dir))
      (should-not (file-exists-p (expand-file-name ".agent-shell/worktrees/builder-grace/" project)))
      (let ((default-directory dir))
        (should (equal (+test-aws--git "branch" "--show-current") "agent/ada")))
      (should (string-prefix-p "agent ada (" (plist-get (agent-workspace--worktree-entry project dir) :locked)))
      (should (+test-aws--state ada 'desk))
      (should (equal (buffer-name (agent-workspace-agent-buffer ada)) "ada · builder"))
      (should (= (length (+test-aws--logged :start "ada")) 2))
      (should-not (+test-aws--logged :start "grace")))))

(ert-deftest agent-workspace-session/forget ()
  "Forgotten: out of the crew, its session stopped; its worktree kept if
you say so, else removed when it holds nothing of its own."
  (+test-aws--with-crew "forget"
    (let ((ada (+test-aws--create "ada"))
          (grace (+test-aws--create "grace"))
          (whats nil))
      (let ((agent-workspace-change-functions (list (lambda (_agent what) (push what whats)))))
        (agent-workspace-forget ada 'keep))
      (should (eq (car whats) 'forgotten))
      (should (equal (agent-workspace-agents) (list grace)))
      (should-not (buffer-live-p (agent-workspace-agent-buffer ada)))
      (should (file-directory-p (expand-file-name ".agent-shell/worktrees/builder-ada/" project)))
      (agent-workspace-forget grace)
      (should-not (agent-workspace-crews))
      (should-not (file-exists-p (expand-file-name ".agent-shell/worktrees/builder-grace/" project))))))

;; ====== CLOSING THE CREW ======

(ert-deftest agent-workspace-session/a-process-s-start-read-twice ()
  "A process is the same while its start, read again, is under a second
from the one noted (Linux: each read works it out anew, 10 ms off now and
then); not later (a pid used again), nor a zombie (doom-pbk.73)."
  (let* ((start (current-time))
         (now start)
         (state "S"))
    (cl-letf (((symbol-function 'process-attributes)
               (lambda (_pid) `((start . ,now) (state . ,state)))))
      (should (agent-workspace--alive-p (cons 42 start)))
      (setq now (time-add start 0.01))
      (should (agent-workspace--alive-p (cons 42 start)))
      (setq now (time-subtract start 0.01))
      (should (agent-workspace--alive-p (cons 42 start)))
      (setq now (time-add start 5))
      (should-not (agent-workspace--alive-p (cons 42 start)))
      (setq now start state "Z")
      (should-not (agent-workspace--alive-p (cons 42 start))))
    (cl-letf (((symbol-function 'process-attributes) #'ignore))
      (should-not (agent-workspace--alive-p (cons 42 start))))))

(ert-deftest agent-workspace-session/close-leaves-no-process ()
  "Closing the crew stops every agent at once, asking nothing, one working,
one with its hand raised, a command started outside the agent's process
group, one that outlives its agent (killed only by the reap after it:
doom-pbk.73); afterwards none of their processes is left. Their worktrees
stay."
  (+test-aws--with-crew "close"
    (let* ((agent-workspace-exit-timeout 1)
           (ada (+test-aws--create "ada"))
           (grace (+test-aws--create "grace"))
           (linus (+test-aws--create "linus")))
      (agent-workspace-send ada "child" :submit t)
      (agent-workspace-send grace "permission" :submit t)
      (agent-workspace-send linus "orphan" :submit t)
      (should (+test-aws--state grace 'hand))
      (should (+test-aws--wait (lambda () (+test-aws--logged :child "ada"))))
      (should (+test-aws--wait (lambda () (+test-aws--logged :orphan "linus"))))
      ;; A message waiting for ada's turn's end: agent-shell would ask.
      (should (eq (agent-workspace-send ada "later" :submit t) 'queued))
      (let ((pids (append (mapcar (lambda (start) (plist-get start :pid))
                                  (append (+test-aws--logged :start "ada")
                                          (+test-aws--logged :start "grace")
                                          (+test-aws--logged :start "linus")))
                          (+test-aws--logged :child "ada")
                          (+test-aws--logged :orphan "linus")))
            (buffers (mapcar #'agent-workspace-agent-buffer (list ada grace linus))))
        (should (= (length pids) 5))
        (should (integerp (car (+test-aws--logged :orphan "linus"))))
        (should (seq-every-p #'+test-aws--pid-alive-p pids))
        (+test-aws--no-questions
          (agent-workspace-close))
        (should-not (agent-workspace-crews))
        (should-not (seq-some #'buffer-live-p buffers))
        (dolist (agent (list ada grace linus))
          (should (eq (agent-workspace-agent-state agent) 'home)))
        (should (+test-aws--wait (lambda () (not (seq-some #'+test-aws--pid-alive-p pids))) 10))
        (dolist (name '("ada" "grace" "linus"))
          (should (file-directory-p (expand-file-name (concat ".agent-shell/worktrees/builder-" name "/")
                                                      project))))))))

(ert-deftest agent-workspace-session/quitting-emacs-asks-nothing-of-the-crew ()
  "Emacs quitting: agent-shell's question about queued prompts leaves the
crew's sessions out (they end with Emacs); kill-emacs-hook closes the crews."
  (+test-aws--with-crew "quit"
    (let ((agent (+test-aws--create "ada")))
      (agent-workspace-send agent "hold" :submit t)
      (should (+test-aws--wait (lambda () (member "hold" (+test-aws--prompts "ada")))))
      (should (eq (agent-workspace-send agent "later" :submit t) 'queued))
      (+test-aws--no-questions
        (should (agent-shell--prompt-queue-confirm-kill-emacs)))
      ;; Its queue is as it was.
      (should (map-elt (buffer-local-value 'agent-shell--state (agent-workspace-agent-buffer agent))
                       :pending-prompts))
      (should (memq #'agent-workspace--quit-h kill-emacs-hook))
      (let ((pid (plist-get (car (+test-aws--logged :start "ada")) :pid)))
        (agent-workspace--quit-h)
        (should-not (agent-workspace-crews))
        (should (+test-aws--wait (lambda () (not (+test-aws--pid-alive-p pid))) 5))))))

(ert-deftest agent-workspace-session/no-timer-while-agents-run ()
  "Agents running, nothing ticks: no timer of the crew's (the app's comes
with it). A stopped session's processes are looked at once, later."
  (+test-aws--with-crew "timers"
    (let ((before (append timer-list timer-idle-list)))
      (+test-aws--create "ada")
      (+test-aws--create "grace")
      ;; Nothing that ticks (a write of crew.json to come is once).
      (should-not (seq-filter (lambda (timer)
                                (and (not (memq timer before))
                                     (timer--repeat-delay timer)
                                     (symbolp (timer--function timer))
                                     (string-prefix-p "agent-workspace" (symbol-name (timer--function timer)))))
                              (append timer-list timer-idle-list)))
      (agent-workspace-close)
      (dolist (timer (append timer-list timer-idle-list))
        (when (and (symbolp (timer--function timer))
                   (string-prefix-p "agent-workspace" (symbol-name (timer--function timer))))
          (should (memq (timer--function timer) '(agent-workspace--reap agent-workspace-crew-save)))
          (should-not (timer--repeat-delay timer)))))))
