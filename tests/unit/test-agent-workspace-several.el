;;; tests/unit/test-agent-workspace-several.el -*- lexical-binding: t; -*-
;; Several crews of one project (doom-pbk.164), config/agent-workspace/: a
;; crew's key, its files, its agents' names (an ada in two crews, told apart
;; by their handles: ada, ada@test), two crews open at once and each opened
;; again, SPC o w asking which, and cmd/agent-workspace's --crew. Their
;; loops, bd telling two adas apart: test-agent-workspace-loops.el.

(require 'agent-shell)
(require 'persp-mode)
(require 'json)
(require 'server)

;; Git as git is, not as your ~/.gitconfig has it (hooks, signing...).
(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(+test-load "config/agent-shell" "config/agent-ui" "config/tiling" "config/agent-workspace")
(remove-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context)
(setq agent-workspace-minimap nil)

(defconst +test-aw2-script (expand-file-name "cmd/agent-workspace" +test-root))

;; ====== HELPERS ======

(defun +test-aw2--git (&rest args)
  "git ARGS in `default-directory': its output, trimmed."
  (with-temp-buffer
    (unless (eql 0 (apply #'call-process "git" nil t nil args))
      (error "git %S: %s" args (buffer-string)))
    (string-trim (buffer-string))))

(defun +test-aw2--project (name)
  "A git repository NAME in the temp folder, with a commit: its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "aw2/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (+test-aw2--git "init" "-q" "-b" "main")
      (+test-git-user)
      (write-region "hello\n" nil "README")
      (+test-aw2--git "add" "README")
      (+test-aw2--git "commit" "-q" "-m" "first"))
    (file-name-as-directory (file-truename dir))))

(defmacro +test-aw2 (name &rest body)
  "BODY in a new project NAME (`project'; `test', its crew test's key), no
app or crew before or after; agents' sessions plain buffers (`started':
the handles of those started, latest first), at the desk; bd not run."
  (declare (indent 1))
  `(+test-with-reset
     (let* ((project (+test-aw2--project ,name))
            (test (agent-workspace-crew-key project "test"))
            (default-directory project)
            (agent-workspace--crews (make-hash-table :test #'equal))
            (agent-workspace--apps (make-hash-table :test #'equal))
            (agent-workspace--opened nil)
            (agent-workspace-loop nil)
            (started nil))
       (ignore test started)
       (set-frame-size (selected-frame) 220 40)
       (cl-letf (((symbol-function 'agent-workspace--start)
                  (lambda (agent)
                    (push (agent-workspace-agent-handle agent) started)
                    (let ((buffer (get-buffer-create (agent-workspace-buffer-name agent))))
                      (with-current-buffer buffer (setq agent-workspace--agent agent))
                      (setf (agent-workspace-agent-buffer agent) buffer
                            (agent-workspace-agent-state agent) 'desk)
                      (agent-workspace--changed agent 'session)
                      buffer)))
                 ((symbol-function 'agent-workspace--stop)
                  (lambda (agent state &rest _)
                    (when (buffer-live-p (agent-workspace-agent-buffer agent))
                      (kill-buffer (agent-workspace-agent-buffer agent)))
                    (setf (agent-workspace-agent-buffer agent) nil
                          (agent-workspace-agent-state agent) state)
                    nil))
                 ((symbol-function 'agent-workspace--issues-refresh) #'ignore)
                 ;; crew.json written at once (no wait).
                 ((symbol-function 'run-at-time)
                  (let ((run-at-time (symbol-function 'run-at-time)))
                    (lambda (time repeat fn &rest args)
                      (if (eq fn #'agent-workspace-crew-save)
                          (progn (apply fn args) nil)
                        (apply run-at-time time repeat fn args))))))
         (unwind-protect (progn ,@body)
           (dolist (key (hash-table-keys agent-workspace--apps))
             (agent-workspace--close-app key))
           (agent-workspace-close-all)
           (set-frame-parameter nil 'agent-workspace nil))))))

(defmacro +test-aw2--persp (&rest body)
  "BODY with persp-mode on, in its workspace \"main\"; off after."
  (declare (indent 0))
  `(let ((persp-auto-save-opt 0)
         (persp-auto-resume-time -1)
         (persp-save-dir (file-name-as-directory (+test-tmp-file "persp")))
         (persp-kill-foreign-buffer-behaviour 'kill))
     (persp-mode 1)
     (persp-add-new "main")
     (persp-frame-switch "main")
     (unwind-protect (progn ,@body)
       (persp-mode -1))))

(defun +test-aw2--file (project name)
  "PROJECT's file NAME in .agent-shell/agent-workspace/, its text, or nil."
  (let ((file (expand-file-name (concat ".agent-shell/agent-workspace/" name) project)))
    (and (file-exists-p file) (with-temp-buffer (insert-file-contents file) (buffer-string)))))

(defun +test-aw2--names (project)
  "The names of PROJECT's crew's agents, in order."
  (mapcar #'agent-workspace-agent-name (agent-workspace-agents project)))

;; ====== ITS KEY, ITS FILES ======

(ert-deftest agent-workspace-several/a-crew-s-key-and-files ()
  "A crew's key: the project's root for its default crew, ROOT#NAME for a
named one (not a folder: its folder taken from it); a named crew's files
its name before theirs, the default crew's as before; an agent's handle,
NAME@CREW in a named crew, NAME in the default one, read back."
  (let* ((root "/src/doom/")
         (test (agent-workspace-crew-key root "test"))
         (in (lambda (file) (concat root ".agent-shell/agent-workspace/" file))))
    (should (equal (agent-workspace-crew-key root) root))
    (should (equal (agent-workspace-crew-key "/src/doom" "") root))
    (should (equal test "/src/doom/#test"))
    (should (equal (agent-workspace-dir test) root))
    (should (equal (agent-workspace-dir root) root))
    (should (equal (agent-workspace-crew-name test) "test"))
    (should-not (agent-workspace-crew-name root))
    (should (equal (agent-workspace--root test) test))
    (should (equal (agent-workspace-crew-label root) "doom"))
    (should (equal (agent-workspace-crew-label test) "doom · test"))
    ;; Its files.
    (should (equal (agent-workspace--crew-path root) (funcall in "crew.json")))
    (should (equal (agent-workspace--crew-path test) (funcall in "test.crew.json")))
    (should (equal (agent-workspace--room-file root) (funcall in "room.jsonl")))
    (should (equal (agent-workspace--room-file test) (funcall in "test.room.jsonl")))
    (should (equal (agent-workspace--inbox-path root) (funcall in "inbox.jsonl")))
    (should (equal (agent-workspace--inbox-path test) (funcall in "test.inbox.jsonl")))
    (should (equal (agent-workspace--messages-path root) (funcall in "messages.json")))
    (should (equal (agent-workspace--messages-path test) (funcall in "test.messages.json")))
    (should (equal (agent-workspace--crew-lock-file root) (funcall in "crew.lock")))
    (should (equal (agent-workspace--crew-lock-file test) (funcall in "test.crew.lock")))
    ;; Its agents' handles.
    (should (equal (agent-workspace-handle "ada" root) "ada"))
    (should (equal (agent-workspace-handle "ada" test) "ada@test"))
    (should (equal (agent-workspace-handle-parts "ada@test" root) (cons test "ada")))
    (should (equal (agent-workspace-handle-parts "ada" test) (cons root "ada")))))

;; ====== ONE NAME IN TWO CREWS ======

(ert-deftest agent-workspace-several/an-ada-in-each-crew ()
  "An ada in the default crew and one in the test crew, both scribes: two
agents, each its own worktree (scribe-ada, scribe-ada@test), branch at
rest (agent/ada, agent/ada@test), buffer, name for bd and its shell, {name}
and lock; a file of each one's worktree is its; a second ada in one crew
refused. One renamed: its worktree and branch moved, the other's as they
were."
  (+test-aw2 "two-adas"
    (let ((ada (agent-workspace-create :role "scribe" :name "ada"))
          (her (agent-workspace-create :role "scribe" :name "ada" :project test))
          (worktrees (expand-file-name ".agent-shell/worktrees/" project)))
      (should-not (eq ada her))
      (should (equal (+test-aw2--names project) '("ada")))
      (should (equal (+test-aw2--names test) '("ada")))
      (should (equal (agent-workspace-agent-worktree ada) (expand-file-name "scribe-ada/" worktrees)))
      (should (equal (agent-workspace-agent-worktree her) (expand-file-name "scribe-ada@test/" worktrees)))
      (should (equal (agent-workspace-agent-branch ada) "agent/ada"))
      (should (equal (agent-workspace-agent-branch her) "agent/ada@test"))
      (should (equal (sort (split-string (+test-aw2--git "branch" "--list" "agent/*" "--format=%(refname:short)"))
                           #'string<)
                     '("agent/ada" "agent/ada@test")))
      (should (equal (buffer-name (agent-workspace-agent-buffer ada)) "ada · scribe"))
      (should (equal (buffer-name (agent-workspace-agent-buffer her)) "ada · scribe · test"))
      (should (member "BEADS_ACTOR=ada" (agent-workspace--environment ada)))
      (should (member "BEADS_ACTOR=ada@test" (agent-workspace--environment her)))
      (should (member "AGENT_WORKSPACE_AGENT=ada@test" (agent-workspace--environment her)))
      (should (equal (agent-workspace--placeholder her "name") "ada@test"))
      (should (equal (agent-workspace--placeholder her "main") (directory-file-name project)))
      (should (equal (agent-workspace-worktree-reason her)
                     (format "agent ada@test (scribe), crew of %s · test"
                             (file-name-nondirectory (directory-file-name project)))))
      ;; A file of each one's worktree: its.
      (let ((mine (expand-file-name "README" (agent-workspace-agent-worktree ada)))
            (hers (expand-file-name "README" (agent-workspace-agent-worktree her))))
        (should (equal (agent-workspace-worktree-of hers) (list test "ada")))
        (should (equal (agent-workspace-worktree-of mine) (list project "ada")))
        (should (eq (agent-workspace-file-agent hers) her))
        (should (eq (agent-workspace-file-agent mine) ada)))
      ;; One ada a crew.
      (should-error (agent-workspace-create :role "builder" :name "ada" :project test) :type 'user-error)
      (should-not (equal (agent-workspace-pool-name test "builder") "ada"))
      ;; Hers renamed: hers moved, his as it was.
      (agent-workspace-rename her "ana")
      (should (equal (agent-workspace-agent-worktree her) (expand-file-name "scribe-ana@test/" worktrees)))
      (should (file-directory-p (expand-file-name "scribe-ana@test/" worktrees)))
      (should (equal (agent-workspace-agent-branch her) "agent/ana@test"))
      (should (equal (agent-workspace-agent-worktree ada) (expand-file-name "scribe-ada/" worktrees)))
      (should (equal (sort (split-string (+test-aw2--git "branch" "--list" "agent/*" "--format=%(refname:short)"))
                           #'string<)
                     '("agent/ada" "agent/ana@test"))))))

;; ====== TWO CREWS OPEN AT ONCE ======

(ert-deftest agent-workspace-several/two-crews-open-at-once ()
  "The default crew and the test crew of one project, open at once: each its
own workspace (crew · NAME, crew · NAME · test), app, agents, room, saved
crew and lock; Q closes the test crew alone; opened again, it's as it was
\(its agents from test.crew.json), the default crew's untouched."
  (+test-aw2 "open-two"
    (+test-aw2--persp
      (let ((folder (file-name-nondirectory (directory-file-name project))))
        (agent-workspace-open nil project)
        (agent-workspace-create :role "scribe" :name "ada")
        (agent-workspace-open nil test)
        (agent-workspace-create :role "scribe" :name "ada" :project test)
        (agent-workspace-create :role "builder" :name "bob" :project test)
        (should (agent-workspace--app project))
        (should (agent-workspace--app test))
        (should (equal (safe-persp-name (get-current-persp)) (concat "crew · " folder " · test")))
        (should (equal (frame-parameter nil 'agent-workspace) test))
        (should (equal (agent-workspace-workspace-name project) (concat "crew · " folder)))
        (should (equal (+test-aw2--names project) '("ada")))
        (should (equal (+test-aw2--names test) '("ada" "bob")))
        ;; Each its own room.
        (agent-workspace-room-post test :kind 'note :text "said in test")
        (agent-workspace-room-post project :kind 'note :text "said in default")
        (should (string-search "said in test" (+test-aw2--file project "test.room.jsonl")))
        (should-not (string-search "said in default" (+test-aw2--file project "test.room.jsonl")))
        (should (string-search "said in default" (+test-aw2--file project "room.jsonl")))
        (should-not (string-search "said in test" (+test-aw2--file project "room.jsonl")))
        ;; Each its own saved crew and lock.
        (agent-workspace-crew-save project)
        (agent-workspace-crew-save test)
        (should (string-search "\"bob\"" (+test-aw2--file project "test.crew.json")))
        (should-not (string-search "\"bob\"" (+test-aw2--file project "crew.json")))
        (should (string-prefix-p (number-to-string (emacs-pid)) (+test-aw2--file project "crew.lock")))
        (should (string-prefix-p (number-to-string (emacs-pid)) (+test-aw2--file project "test.crew.lock")))
        (should (equal (agent-workspace-saved-crews project) (list project test)))
        ;; Q in the test crew: it alone closes.
        (agent-workspace-quit)
        (should-not (agent-workspace--app test))
        (should-not (agent-workspace-agents test))
        (should-not (+test-aw2--file project "test.crew.lock"))
        (should (agent-workspace--app project))
        (should (equal (+test-aw2--names project) '("ada")))
        (should (string-search "\"bob\"" (+test-aw2--file project "test.crew.json")))
        ;; Opened again: as it was (in crew.json's order: its roles').
        (setq started nil)
        (agent-workspace-open nil test)
        (should (equal (sort (+test-aw2--names test) #'string<) '("ada" "bob")))
        (should (equal (sort started #'string<) '("ada@test" "bob@test")))
        (should (equal (safe-persp-name (get-current-persp)) (concat "crew · " folder " · test")))
        (should (equal (+test-aw2--names project) '("ada")))))))

;; ====== SPC o w ASKS ======

(defmacro +test-aw2--asked (answers &rest body)
  "BODY with the minibuffer answering ANSWERS in turn (`read-string' and
`completing-read' alike); `asked': what each was offered, latest first
\(a prompt and, for a choice, its choices and annotations)."
  (declare (indent 1))
  `(let ((answers ,answers)
         (asked nil))
     (cl-letf (((symbol-function 'read-string)
                (lambda (prompt &rest _) (push (list prompt) asked) (pop answers)))
               ((symbol-function 'completing-read)
                (lambda (prompt collection &rest _)
                  (let ((choices (all-completions "" collection)))
                    (push (list prompt choices
                                (mapcar (lambda (choice)
                                          (when-let* ((note (plist-get completion-extra-properties
                                                                       :annotation-function))
                                                      (text (funcall note choice)))
                                            (string-trim text)))
                                        choices))
                          asked))
                  (pop answers)))
               ((symbol-function 'sit-for) #'ignore))
       ,@body)))

(ert-deftest agent-workspace-several/spc-o-w-asks-which ()
  "SPC o w: a project with no crew asks a new crew's name, empty its default
crew; a name not one asked again. With crews saved or running: each
offered (the default as default, the one opened last first, an open one
marked), or a new one, whose name is then asked."
  (+test-aw2 "asks"
    ;; None: a name, empty the default crew.
    (+test-aw2--asked '("")
      (call-interactively #'agent-workspace-open)
      (should (equal (caar asked) "New crew's name (empty: the default crew): "))
      (should (agent-workspace--app project)))
    (agent-workspace-create :role "scribe" :name "ada")
    (agent-workspace-crew-save project)
    ;; Saved and open: offered, or a new one; a wrong name asked again.
    (+test-aw2--asked '("+ a new crew" "Not a Name" "default" "test")
      (call-interactively #'agent-workspace-open)
      (let ((offered (car (last asked))))
        (should (equal (cadr offered) '("default" "+ a new crew")))
        (should (equal (caddr offered) '("open" nil))))
      (should (= (length asked) 4))
      (should (agent-workspace--app test)))
    (agent-workspace-create :role "scribe" :name "ada" :project test)
    (agent-workspace-crew-save test)
    ;; Both: the test crew, opened last, first; the default one picked.
    (+test-aw2--asked '("default")
      (call-interactively #'agent-workspace-open)
      (should (equal (cadr (car asked)) '("test" "default" "+ a new crew")))
      (should (equal (frame-parameter nil 'agent-workspace) project)))
    ;; Closed, the test crew is still offered: saved.
    (agent-workspace--close-app test)
    (+test-aw2--asked '("test")
      (call-interactively #'agent-workspace-open)
      (should (equal (cadr (car asked)) '("default" "test" "+ a new crew")))
      (should (equal (caddr (car asked)) '("open" "saved" nil)))
      (should (equal (+test-aw2--names test) '("ada"))))))

;; ====== cmd/agent-workspace --crew ======

(defmacro +test-aw2--with-server (&rest body)
  "BODY with this Emacs a server only the script talks to (EMACS_SOCKET_NAME)."
  (declare (indent 0))
  `(let* ((server-socket-dir (make-temp-file "/tmp/aw2-" t))
          (server-name "test")
          (process-environment
           (cons (concat "EMACS_SOCKET_NAME=" (expand-file-name server-name server-socket-dir))
                 process-environment)))
     (unwind-protect
         (progn (server-start nil t) ,@body)
       (server-force-delete)
       (delete-directory server-socket-dir t))))

(defun +test-aw2--run (&rest args)
  "Run cmd/agent-workspace with ARGS: its reply, parsed (null :null, false
:false). Asynchronously: this Emacs, its server, answers it meanwhile."
  (let* ((output (generate-new-buffer " *aw2-run*"))
         (process (make-process :name "aw2" :buffer output :command (cons +test-aw2-script args)
                                :connection-type 'pipe :noquery t :sentinel #'+test-process-sentinel
                                :stderr (get-buffer-create " *aw2-stderr*"))))
    (with-timeout (30 (delete-process process) (ert-fail "cmd/agent-workspace didn't end"))
      (while (not (+test-process-ended-p process))
        (accept-process-output nil 0.02)))
    (prog1 (json-parse-string (with-current-buffer output (buffer-string)) :object-type 'plist :array-type 'list)
      (kill-buffer output))))

(ert-deftest agent-workspace-several/the-script-s-crew ()
  "cmd/agent-workspace acts on the default crew; --crew NAME (anywhere among
its arguments), on that one; from a named crew's agent's shell
\(AGENT_WORKSPACE_AGENT, its handle), on its crew. An agent's request
naming another crew than its own: refused. A name that isn't one:
refused."
  (+test-aw2 "script"
    (agent-workspace-create :role "builder" :name "ada")
    (let ((her (agent-workspace-create :role "builder" :name "ada" :project test)))
      (agent-workspace-create :role "builder" :name "bob" :project test)
      (+test-aw2--with-server
        (let ((names (lambda (reply) (mapcar (lambda (agent) (plist-get agent :name)) (plist-get reply :agents)))))
          (let ((reply (+test-aw2--run "status")))
            (should (eq (plist-get reply :crew) :null))
            (should (equal (funcall names reply) '("ada"))))
          (let ((reply (+test-aw2--run "status" "--crew" "test")))
            (should (equal (plist-get reply :crew) "test"))
            (should (equal (plist-get reply :project) (directory-file-name project)))
            (should (equal (funcall names reply) '("ada" "bob"))))
          (should (equal (funcall names (+test-aw2--run "--crew=default" "status")) '("ada")))
          ;; Its own crew's bob only.
          (should (plist-get (+test-aw2--run "sleep" "bob" "--crew" "test") :ok))
          (should (eq (agent-workspace-agent-state (agent-workspace-agent "bob" test)) 'asleep))
          (should (string-prefix-p "No agent bob in this crew" (plist-get (+test-aw2--run "wake" "bob") :error)))
          (should (string-prefix-p "Not a crew's name: Test" (plist-get (+test-aw2--run "status" "--crew" "Test") :error)))
          ;; Her shell's word: her crew.
          (let ((process-environment (cons "AGENT_WORKSPACE_AGENT=ada@test" process-environment)))
            (should (equal (funcall names (+test-aw2--run "status")) '("ada" "bob")))))
        ;; Her session's own request: her crew, no other.
        (let ((agent-workspace--request-from her))
          (should (equal (agent-workspace--request-project project) test))
          (should (equal (agent-workspace--request-project project '(:crew "test")) test))
          (should (string-search "its own crew"
                                 (cadr (should-error (agent-workspace--request-project project '(:crew "default"))
                                                     :type 'user-error)))))))))
