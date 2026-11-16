;;; $DOOMDIR/examples/agent-workspace.el -*- lexical-binding: t; -*-
;; Example: an agent crew (config/agent-workspace.el, docs/agent-workspace.md).
;; M-x +my/example-agent-workspace makes a small compiler project (a git
;; repository in the temp folder, its issues tracked with bd if there's bd)
;; and opens its crew's app with three agents, each in its own worktree, on
;; its issue's branch: ada, a builder, on demo-1; sam, an investigator, on
;; demo-3, its hand raised (it wants to run npm install); ken, a builder, done
;; with demo-6. Its issues are bugs, features and tasks, two of them in an
;; epic. They're stand-in agents (examples/agent-workspace/stand-in.el): they
;; speak ACP as Claude Code does, offline, at no cost. Try: j / k on the
;; bars, a then A to answer sam, #ken in the room, c a new agent, q to leave
;; and the tally to come back, Q to close it (every agent exits). The folder
;; is deleted once it's closed.

;; ====== VARIABLES ======

(defconst +my/example-agent-workspace--stand-in
  (expand-file-name "agent-workspace/stand-in.el" (file-name-directory (or load-file-name buffer-file-name)))
  "The stand-in agent.")

(defconst +my/example-agent-workspace--issues
  ;; id      title                                    type      labels            priority status        assignee blocker  epic
  '(("demo-1" "Lexer: strings with escapes"             "feature" ("build")          1 "in_progress" "ada"    nil      nil)
    ("demo-2" "Parser: recover after a missing brace"   "bug"     ("build")          1 "open"        nil      nil      "demo-7")
    ("demo-3" "Why does the REPL hang on paste?"        "bug"     ("investigation")  2 "in_progress" "sam"    nil      nil)
    ("demo-4" "Review ken's branch"                     "task"    ("review")         2 "open"        nil      nil      nil)
    ("demo-5" "Release 0.3"                             "task"    nil                2 "open"        nil      "demo-2" nil)
    ("demo-6" "Tokens for numbers"                      "feature" ("build")          2 "closed"      "ken"    nil      nil)
    ("demo-7" "Error recovery"                          "epic"    nil                2 "open"        nil      nil      nil)
    ("demo-8" "Errors point at their line"              "feature" ("build")          2 "open"        nil      nil      "demo-7"))
  "The example's issues (see above).")

(defconst +my/example-agent-workspace--files
  '(("README.md" . "# A small compiler\n\nThe example's project.\n")
    ("src/lexer.el" . ";;; lexer.el --- the lexer -*- lexical-binding: t; -*-\n")
    ("src/parser.el" . ";;; parser.el --- the parser -*- lexical-binding: t; -*-\n"))
  "The example's project's files.")

(defvar +my/example-agent-workspace--crew nil
  "The example's agents, as made.")

;; ====== CODE ======

(defun +my/example-agent-workspace--jsonl ()
  "The example's issues as bd imports them: a line of JSON each."
  (mapconcat
   (lambda (issue)
     (seq-let (id title type labels priority status assignee blocker epic) issue
       (json-encode
        `((id . ,id) (title . ,title) (issue_type . ,type) (priority . ,priority) (status . ,status)
          (created_at . "2026-11-02T09:00:00Z") (updated_at . "2026-11-02T09:00:00Z")
          ,@(and (equal status "closed") `((closed_at . ,(format-time-string "%FT%TZ" nil t))))
          ,@(and assignee `((assignee . ,assignee)))
          ,@(and labels `((labels . ,(vconcat labels))))
          ,@(and (or blocker epic)
                 `((dependencies
                    . ,(vconcat (and blocker `(((issue_id . ,id) (depends_on_id . ,blocker) (type . "blocks"))))
                                (and epic `(((issue_id . ,id) (depends_on_id . ,epic) (type . "parent-child"))))))))))))
   +my/example-agent-workspace--issues "\n"))

(defun +my/example-agent-workspace--run (program &rest args)
  "PROGRAM run with ARGS in this folder; an error saying why if it failed."
  (with-temp-buffer
    (unless (eql 0 (apply #'call-process program nil t nil args))
      (error "%s %s: %s" program (string-join args " ") (string-trim (buffer-string))))))

(defun +my/example-agent-workspace--project (dir)
  "The example's project in DIR: its files, committed; its issues (with bd)."
  (let ((default-directory dir)
        (process-environment (append '("GIT_CONFIG_NOSYSTEM=1") process-environment)))
    (pcase-dolist (`(,file . ,text) +my/example-agent-workspace--files)
      (+my/example-write dir file text))
    (+my/example-agent-workspace--run "git" "init" "-q" "-b" "main")
    (+my/example-agent-workspace--run "git" "add" ".")
    (+my/example-agent-workspace--run "git" "-c" "user.name=Example" "-c" "user.email=example@example.com"
                                      "-c" "commit.gpgsign=false" "commit" "-q" "-m" "A small compiler")
    (when (executable-find "bd")
      (let ((issues (make-temp-file "crew-example-" nil ".jsonl" (+my/example-agent-workspace--jsonl))))
        (unwind-protect
            (ignore-errors
              (+my/example-agent-workspace--run "bd" "init" "--quiet" "--skip-agents" "--prefix" "demo")
              (+my/example-agent-workspace--run "bd" "import" issues "--quiet"))
          (delete-file issues))))))

(defun +my/example-agent-workspace--kind ()
  "The stand-in agent, an agent kind of the crew's (agent-shell's mock agent
running it)."
  (require 'agent-shell)
  (require 'agent-shell-mock-agent)
  (setq agent-shell-mock-agent-acp-command
        (list (expand-file-name invocation-name invocation-directory) "--batch" "-Q"
              (concat "--init-directory=" (expand-file-name "agent-workspace-stand-in/" temporary-file-directory))
              "-l" +my/example-agent-workspace--stand-in "-f" "mock-acp-main"))
  (setf (alist-get 'stand-in agent-workspace-kinds) (list :config #'agent-shell-mock-agent-make-agent-config)))

(defun +my/example-agent-workspace-ready ()
  "Non-nil once the example's agents are as it shows them (the screenshots
wait for it): ada working, sam's hand raised, ken done."
  (pcase +my/example-agent-workspace--crew
    (`(,ada ,sam ,ken)
     (and (eq (agent-workspace-agent-state ada) 'working)
          (eq (agent-workspace-agent-state sam) 'hand)
          (memq (agent-workspace-agent-state ken) '(done desk))))))

(defun +my/example-agent-workspace ()
  "Example: an agent crew in its app, three stand-in agents (offline), the
folder deleted once it's closed. See examples/agent-workspace.el."
  (interactive)
  (let* ((dir (file-name-as-directory (file-truename (+my/example-folder "agent-workspace"))))
         (default-directory dir))
    (+my/example-agent-workspace--project dir)
    (+my/example-agent-workspace--kind)
    ;; Your windows left as they are: the crew has its own workspace (or gives
    ;; back the windows it found).
    (setq +my/example-agent-workspace--crew
          (list (agent-workspace-create :role "builder" :name "ada" :kind 'stand-in
                                        :issue "demo-1" :issue-title "Lexer: strings with escapes"
                                        :issue-type "feature")
                (agent-workspace-create :role "investigator" :name "sam" :kind 'stand-in
                                        :issue "demo-3" :issue-title "Why does the REPL hang on paste?"
                                        :issue-type "bug" :prompt "Look into why the REPL hangs on paste")
                (agent-workspace-create :role "builder" :name "ken" :kind 'stand-in
                                        :issue "demo-6" :issue-title "Tokens for numbers"
                                        :issue-type "feature" :prompt "What's left on the lexer?")))
    (let ((app (agent-workspace-open)))
      (agent-workspace-select (car +my/example-agent-workspace--crew))
      (+my/example-delete-when-closed dir (list (agent-workspace--issues-buffer (agent-workspace--app-project app))))
      (message "Crew example: a then A answers sam, #ken in the room, Q closes it")
      app)))

(provide 'example-agent-workspace)
