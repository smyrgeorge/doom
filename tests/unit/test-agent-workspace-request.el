;;; tests/unit/test-agent-workspace-request.el -*- lexical-binding: t; -*-
;; config/agent-workspace/request.el's status, give, wake, sleep and loop,
;; with cmd/agent-workspace: the crew seen and run from the shell, as its
;; keys do (t, Z, L), said in the room by who did it; from an agent's shell
;; only if its role leads. Status read from agents as records; the actions on
;; stand-in agents (examples/agent-workspace/stand-in.el) in throwaway git
;; repositories, bd tracking their issues where an issue is given or a loop
;; turned on (skipped without bd).
;; run.sh: slow (stand-in sessions, bd)

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(require 'server)
(require 'agent-shell)
(require 'agent-shell-mock-agent)
(require 'json)
(+test-load "config/agent-shell" "config/agent-ui" "config/agent-workspace")
(remove-hook '+my/agent-shell-context-functions #'+my/agent-shell-beads-context)

(setq agent-shell-mock-agent-acp-command
      (list (expand-file-name invocation-name invocation-directory)
            "--batch" "-Q" (concat "--init-directory=" (+test-tmp-file "mock-acp-home/"))
            "-l" (expand-file-name "examples/agent-workspace/stand-in.el" +test-root) "-f" "mock-acp-main"))
;; The stand-in's modes: Claude Code's, as it lists them; it starts in auto.
(add-to-list 'agent-workspace-kinds `(mock :config agent-shell-mock-agent-make-agent-config :modes ,agent-workspace-modes :mode "auto"))

(defconst +test-awq-script (expand-file-name "cmd/agent-workspace" +test-root))

;; ====== HELPERS ======

(defvar +test-awq--log nil "The stand-ins' log, this test's.")

(defun +test-awq--project (name &optional beads)
  "A git repository NAME in the temp folder, with a commit (BEADS: its
issues tracked by bd): its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awq/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (if beads
          (+test-bd-init "--quiet" "--skip-agents" "--prefix" "demo")
        (call-process "git" nil nil nil "init" "-q" "-b" "main")
        (+test-git-user)
        (write-region "hello\n" nil "README")
        (call-process "git" nil nil nil "add" "README")
        (call-process "git" nil nil nil "commit" "-q" "-m" "first")))
    (file-name-as-directory (file-truename dir))))

(defmacro +test-awq (name beads agents &rest body)
  "BODY in a new project NAME (`project'; BEADS: its issues tracked by bd,
skipped without it) whose AGENTS ((NAME ROLE)...), stand-ins, are at the
desk, their loop off, each bound to its name; no crew, inbox or app
before or after."
  (declare (indent 3))
  `(progn
     ,@(when beads '((skip-unless (executable-find "bd"))))
     (+test-with-reset
       (let* ((project (+test-awq--project ,name ,beads))
              (default-directory project)
              (+test-awq--log (expand-file-name (concat "awq/" ,name ".log") +test-tmp))
              (process-environment (cons (concat "MOCK_ACP_LOG=" +test-awq--log) process-environment))
              (agent-workspace--crews (make-hash-table :test #'equal))
              (agent-workspace--apps (make-hash-table :test #'equal))
              (agent-workspace--roles-cache (make-hash-table :test #'equal))
              (agent-workspace--inboxes (make-hash-table :test #'equal))
              (agent-workspace--inbox-sent (make-hash-table :test #'equal))
              ;; Its agents start with their loop off, each test turning it
              ;; on as it says: a new one looping from the start has its
              ;; own tests (test-agent-workspace-loops.el).
              (agent-workspace-loop nil)
              (agent-workspace-loop-retry 0.2)
              (agent-workspace-loop-check nil))
         (ignore-errors (delete-file +test-awq--log))
         (cl-letf (((symbol-function 'agent-workspace--issues-refresh) #'ignore))
           (unwind-protect
               (let ,(mapcar (lambda (agent)
                               `(,(intern (car agent))
                                 (agent-workspace-create :role ,(cadr agent) :name ,(car agent) :kind 'mock)))
                             agents)
                 (should (+test-wait-for (lambda () (seq-every-p (lambda (agent)
                                                                   (eq (agent-workspace-agent-state agent) 'desk))
                                                                 (agent-workspace-agents project)))
                                         20))
                 ,@body)
             (when (agent-workspace--app project) (agent-workspace--close-app project))
             (agent-workspace-close-all)))))))

(defun +test-awq--request (op &optional payload)
  "OP's reply (parsed: null :null, false :false) as cmd/agent-workspace gets
it, PAYLOAD its JSON, from `default-directory'."
  (let ((dir (make-temp-file (+test-tmp-file "awq-request-") t)))
    (with-temp-file (expand-file-name "request" dir)
      (insert op "\n" default-directory "\n"))
    (when payload
      (with-temp-file (expand-file-name "payload" dir) (insert payload)))
    (should (eq (agent-workspace-request dir) t))
    (with-temp-buffer
      (insert-file-contents (expand-file-name "reply" dir))
      (json-parse-buffer :object-type 'plist :array-type 'list))))

(defun +test-awq--error (op payload)
  "OP's error as its reply says it, refused."
  (let ((reply (+test-awq--request op payload)))
    (should (eq (plist-get reply :ok) :false))
    (plist-get reply :error)))

(defun +test-awq--room (project)
  "What PROJECT's room said, kept: (AGENT KIND TO TEXT) each, in order."
  (let ((file (expand-file-name ".agent-shell/agent-workspace/room.jsonl" project)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (cl-loop for line in (split-string (buffer-string) "\n" t)
                 for entry = (json-parse-string line :object-type 'plist :null-object nil)
                 collect (list (plist-get entry :agent) (plist-get entry :kind)
                               (plist-get entry :to) (plist-get entry :text)))))))

(defun +test-awq--said (project)
  "What PROJECT's room said someone did to an agent: (AGENT KIND TO TEXT)
each, a note or an issue with a :to."
  (seq-filter (lambda (entry) (and (member (nth 1 entry) '("note" "issue")) (nth 2 entry)))
              (+test-awq--room project)))

(defun +test-awq--issue (project title &rest args)
  "An issue of PROJECT: TITLE, a task unless ARGS say (bd create's). Its id."
  (let ((default-directory project))
    (with-temp-buffer
      (unless (eql 0 (apply #'call-process "bd" nil (list t nil) nil "create" "--title" title "--json"
                            (or args '("--type" "task" "--labels" "build"))))
        (error "bd create: %s" (buffer-string)))
      (alist-get 'id (json-parse-string (buffer-string) :object-type 'alist)))))

(defun +test-awq--bd-issue (project id)
  "Issue ID of PROJECT as bd shows it: an alist."
  (let ((default-directory project))
    (car (json-parse-string (with-output-to-string
                              (with-current-buffer standard-output
                                (call-process "bd" nil (list t nil) nil "show" id "--json")))
                            :object-type 'alist :array-type 'list))))

(defun +test-awq--prompts (name)
  "The prompts the stand-in NAME got, in order."
  (cl-loop for entry in (+test-json-lines +test-awq--log)
           when (and (equal (plist-get entry :agent) name)
                     (equal (plist-get entry :method) "session/prompt"))
           collect (mapconcat (lambda (block) (plist-get block :text))
                              (plist-get (plist-get entry :params) :prompt) "")))

;; ====== STATUS ======

(defmacro +test-awq--records (&rest body)
  "BODY in a new project (`project'), its crew records with no session,
nothing waiting for them: ada, a builder working on demo-1 (a loop of
hers), changed files; linus, a reviewer, his hand raised, one of her files
changed; sam, a builder asleep."
  (declare (indent 0))
  `(+test-with-reset
     (let* ((project (+test-awq--project "status"))
            (default-directory project)
            (agent-workspace--crews (make-hash-table :test #'equal))
            (agent-workspace--apps (make-hash-table :test #'equal))
            (agent-workspace--roles-cache (make-hash-table :test #'equal))
            (agent-workspace--inboxes (make-hash-table :test #'equal))
            (agent-workspace--inbox-sent (make-hash-table :test #'equal))
            (agent-workspace--offered (make-hash-table :test #'equal))
            (agent-workspace--talk (make-hash-table :test #'equal))
            (agent-workspace-outside-events t)
            (agent-workspace-agents-talk t)
            (agent-workspace-talk 'ask)
            (worktrees (expand-file-name ".agent-shell/worktrees/" project))
            (ada (agent-workspace--make-agent
                  :name "ada" :role "builder" :colour "blue" :project project :state 'working
                  :since (- (float-time) 330) :issue "demo-1" :issue-title "the lexer" :loop t
                  :branch "task/demo-1-the-lexer" :worktree (expand-file-name "builder-ada/" worktrees)))
            (linus (agent-workspace--make-agent
                    :name "linus" :role "reviewer" :colour "green" :project project :state 'hand
                    :since (- (float-time) 40) :branch "agent/linus"
                    :worktree (expand-file-name "reviewer-linus/" worktrees)
                    :ask '(:kind permission :title "npm install" :tool-kind "execute" :key "k1")))
            (sam (agent-workspace--make-agent
                  :name "sam" :role "builder" :colour "yellow" :project project :state 'asleep
                  :branch "agent/sam" :worktree (expand-file-name "builder-sam/" worktrees))))
       (puthash project (list sam linus ada) agent-workspace--crews)
       (agent-workspace--add-changed ada '("src/lexer.el" "README"))
       (agent-workspace--add-changed linus '("src/lexer.el"))
       (ignore ada linus sam)
       ,@body)))

(ert-deftest agent-workspace-request/status ()
  "status: each agent of the crew in the stage's order: its state and its
words as its bar says them, its turn's time, loop, issue, branch, worktree,
changed files, its raised hand, the events waiting for it; then the files
two agents changed (the minimap's ⚠), the room's offers still standing (not
one whose issue isn't ready any more, nor one for another role now) and the
talk setting. From an agent's shell too, any role's."
  (+test-awq--records
    (agent-workspace-inbox-add project "linus" "the build broke" :from "ci")
    (agent-workspace-inbox-add project "linus" "again" :from "ci")
    (agent-workspace--talk-set project 'on)
    (puthash project '((("demo-4" "builder" nil) . "ada")
                       (("demo-3" "reviewer" nil) . "linus")
                       (("demo-2" "reviewer" nil) . "linus")
                       (("demo-2" "builder" nil) . "sam"))
             agent-workspace--offered)
    (cl-letf (((symbol-function 'agent-workspace--issues-data)
               (lambda (_project)
                 (list :ready (list (list :id "demo-2" :title "review the lexer" :role "reviewer")
                                    (list :id "demo-4" :title "the parser" :role "reviewer"))))))
      (let ((reply (+test-awq--request "status" "{}")))
        (should (equal (plist-get reply :ok) t))
        (should (equal (plist-get reply :project) (directory-file-name project)))
        (should (equal (plist-get reply :agents)
                       (list (list :name "sam" :role "builder" :state "asleep" :words "asleep" :time :null
                                   :loop :false :issue :null :issue_title :null :branch "agent/sam"
                                   :worktree (expand-file-name ".agent-shell/worktrees/builder-sam" project)
                                   :changed nil :asking :null :events 0)
                             (list :name "ada" :role "builder" :state "working" :words "building demo-1"
                                   :time "5m" :loop t :issue "demo-1" :issue_title "the lexer"
                                   :branch "task/demo-1-the-lexer"
                                   :worktree (expand-file-name ".agent-shell/worktrees/builder-ada" project)
                                   :changed '("src/lexer.el" "README") :asking :null :events 0)
                             (list :name "linus" :role "reviewer" :state "hand" :words "wants to run npm install"
                                   :time "40s" :loop :false :issue :null :issue_title :null :branch "agent/linus"
                                   :worktree (expand-file-name ".agent-shell/worktrees/reviewer-linus" project)
                                   :changed '("src/lexer.el")
                                   :asking '(:kind "permission" :title "npm install" :words "wants to run npm install")
                                   :events 2))))
        (should (equal (plist-get reply :conflicts) '((:file "src/lexer.el" :agents ("linus" "ada")))))
        (should (equal (plist-get reply :offers)
                       '((:issue "demo-2" :title "review the lexer" :to "linus" :role "reviewer"))))
        (should (equal (plist-get reply :talk) "on"))
        ;; From an agent's shell: the same.
        (should (equal (+test-awq--request "status" "{\"agent\":\"ada\"}") reply))))
    ;; Agents not allowed to talk: off, whatever the crew's switch says.
    (let ((agent-workspace-agents-talk nil))
      (should (equal (plist-get (+test-awq--request "status" "{}") :talk) "off")))
    ;; Stuck: its error in its words, as on its bar.
    (let ((sam (agent-workspace-agent "sam" project)))
      (setf (agent-workspace-agent-state sam) 'stuck
            (agent-workspace-agent-error sam) "its session: No agent here\nmore"))
    (should (equal (plist-get (car (plist-get (+test-awq--request "status" "{}") :agents)) :words)
                   "stuck: its session: No agent here")))
  ;; No crew there.
  (let ((default-directory (file-name-as-directory (make-temp-file (+test-tmp-file "awq-nogit-") t))))
    (should (string-prefix-p "No crew here: not a git repository" (+test-awq--error "status" "{}")))))

(ert-deftest agent-workspace-request/no-branch-is-null ()
  "An agent with no branch checked out (a rebase, a commit): its branch
null in an action's reply, not {} (doom-pbk.183)."
  (let ((agent (agent-workspace--make-agent :name "ada" :role "builder" :state 'desk
                                            :worktree "/p/.agent-shell/worktrees/ada/" :branch nil)))
    (should (equal (json-serialize (agent-workspace--request-agent agent))
                   "{\"name\":\"ada\",\"role\":\"builder\",\"worktree\":\"/p/.agent-shell/worktrees/ada\",\"branch\":null,\"state\":\"desk\"}"))))

(ert-deftest agent-workspace-request/status-of-an-empty-crew ()
  "status where a crew could be, but none's running: no agents, nothing
conflicting or offered."
  (+test-with-reset
    (let* ((project (+test-awq--project "empty"))
           (default-directory project)
           (agent-workspace--crews (make-hash-table :test #'equal))
           (agent-workspace--talk (make-hash-table :test #'equal))
           (agent-workspace-agents-talk t)
           (agent-workspace-talk 'ask))
      (should (equal (+test-awq--request "status")
                     (list :ok t :project (directory-file-name project) :agents nil :conflicts nil
                           :offers nil :talk "ask"))))))

;; ====== GIVE ======

(ert-deftest agent-workspace-request/give ()
  "give ISSUE --to NAME, as t does: claimed in bd as the agent, its prompt
sent now (free) or after its turn (working); said in the room as the
shell's. Refused, nothing given nor said: an agent not in the crew, one
asleep, an issue bd doesn't know, closed, an epic, or another agent's."
  (+test-awq "give" t (("ada" "builder") ("ken" "builder"))
    (let ((one (+test-awq--issue project "the lexer"))
          (two (+test-awq--issue project "the parser"))
          (epic (+test-awq--issue project "the compiler" "--type" "epic"))
          (closed (+test-awq--issue project "the docs")))
      (let ((default-directory project))
        (call-process "bd" nil nil nil "close" closed))
      ;; Free: sent now.
      (let ((reply (+test-awq--request "give" (format "{\"issue\":%S,\"to\":\"ada\",\"agent\":\"\"}" one))))
        (should (equal (plist-get reply :ok) t))
        (should (equal (plist-get reply :name) "ada"))
        (should (equal (plist-get reply :issue) one))
        (should (equal (plist-get reply :prompt) "sent"))
        (should (string-prefix-p (format "task/%s-" one) (plist-get reply :branch))))
      (should (equal (agent-workspace-agent-issue ada) one))
      (should (+test-wait-for (lambda () (member (format "Work on %s: the lexer" one) (+test-awq--prompts "ada"))) 20))
      (should (equal (alist-get 'assignee (+test-awq--bd-issue project one)) "ada"))
      (should (equal (alist-get 'status (+test-awq--bd-issue project one)) "in_progress"))
      (should (+test-wait-for (lambda () (eq (agent-workspace-agent-state ada) 'working)) 20))
      ;; Working: after its turn.
      (should (equal (plist-get (+test-awq--request "give" (format "{\"issue\":%S,\"to\":\"ada\"}" two)) :prompt)
                     "queued"))
      (should (equal (+test-awq--said project)
                     `(("shell" "issue" "ada" ,(format "gave %s to ada" one))
                       ("shell" "issue" "ada" ,(format "gave %s to ada" two)))))
      ;; Refused, saying why.
      (agent-workspace-sleep ken)
      (dolist (case `(((:issue ,one :to "nobody") "No agent nobody in this crew; agents: ada, ken")
                      ((:issue ,one :to "ken") ,(format "%s not given to ken: ken is asleep" one))
                      ((:issue ,one) "give: to whom? give ISSUE --to NAME")
                      ((:to "ada") "give: which issue? give ISSUE --to NAME")))
        (should (equal (+test-awq--error "give" (json-serialize (car case))) (cadr case))))
      (agent-workspace-wake ken)
      (should (+test-wait-for (lambda () (eq (agent-workspace-agent-state ken) 'desk)) 20))
      (dolist (case `((,one ,(format "%s not given to ken: issue already claimed by ada" one))
                      ("demo-zzz" "No issue demo-zzz here")
                      (,epic ,(format "%s is an epic: give one of its issues" epic))
                      (,closed ,(format "%s is closed" closed))))
        (should (equal (+test-awq--error "give" (json-serialize (list :issue (car case) :to "ken")))
                       (cadr case))))
      (should-not (agent-workspace-agent-issue ken))
      (should-not (+test-awq--prompts "ken"))
      (should (= (length (+test-awq--said project)) 2)))))

(ert-deftest agent-workspace-request/give-without-beads ()
  "give in a project whose issues bd doesn't track: refused, saying so."
  (+test-awq "give-no-beads" nil (("ada" "builder"))
    (should (equal (+test-awq--error "give" "{\"issue\":\"demo-1\",\"to\":\"ada\"}")
                   "give-no-beads doesn't track its issues with Beads: no issue to give"))
    (should-not (agent-workspace-agent-issue ada))))

;; ====== WAKE, SLEEP ======

(ert-deftest agent-workspace-request/wake-and-sleep ()
  "sleep NAME, wake NAME, as Z does: its session stopped, then a fresh one;
each said in the room as the shell's. Refused: one asleep put to sleep,
one awake woken, one not in the crew, none named."
  (+test-awq "wake-sleep" nil (("ada" "builder"))
    (let ((reply (+test-awq--request "sleep" "{\"name\":\"ada\",\"agent\":\"\"}")))
      (should (equal (plist-get reply :ok) t))
      (should (equal (plist-get reply :name) "ada"))
      (should (equal (plist-get reply :state) "asleep")))
    (should (eq (agent-workspace-agent-state ada) 'asleep))
    (should-not (agent-workspace-live-p ada))
    (should (equal (+test-awq--error "sleep" "{\"name\":\"ada\"}") "ada is asleep"))
    (should (equal (plist-get (+test-awq--request "wake" "{\"name\":\"ada\"}") :state) "waking"))
    (should (+test-wait-for (lambda () (eq (agent-workspace-agent-state ada) 'desk)) 20))
    (should (equal (+test-awq--error "wake" "{\"name\":\"ada\"}") "ada is awake"))
    (should (equal (+test-awq--said project)
                   '(("shell" "note" "ada" "put ada to sleep")
                     ("shell" "note" "ada" "woke ada"))))
    (dolist (case '(("wake" "{\"name\":\"bob\"}" "No agent bob in this crew; agents: ada")
                    ("sleep" "{}" "sleep: whom? sleep NAME")
                    ("wake" "{\"name\":\"\"}" "wake: whom? wake NAME")))
      (should (equal (+test-awq--error (nth 0 case) (nth 1 case)) (nth 2 case))))
    ;; Gone home: woken, not put to sleep.
    (agent-workspace-kill ada)
    (should (equal (+test-awq--error "sleep" "{\"name\":\"ada\"}") "ada is gone home"))
    (should (equal (plist-get (+test-awq--request "wake" "{\"name\":\"ada\"}") :ok) t))
    (should (+test-wait-for (lambda () (eq (agent-workspace-agent-state ada) 'desk)) 20))))

;; ====== LOOP ======

(ert-deftest agent-workspace-request/loop ()
  "loop NAME on|off, as L does: on, it naps with nothing ready; off, it's
at the desk. Said in the room as the shell's only when it changed. Refused:
a role with no labels, on or off not said."
  (+test-awq "loop" t (("ada" "builder") ("max" "scribe"))
    (let ((reply (+test-awq--request "loop" "{\"name\":\"ada\",\"on\":true}")))
      (should (equal (plist-get reply :ok) t))
      (should (equal (plist-get reply :loop) t)))
    (should (agent-workspace-agent-loop ada))
    (should (+test-wait-for (lambda () (eq (agent-workspace-agent-state ada) 'nap)) 20))
    (should (equal (plist-get (+test-awq--request "loop" "{\"name\":\"ada\",\"on\":true}") :loop) t))
    (should (equal (plist-get (+test-awq--request "loop" "{\"name\":\"ada\",\"on\":false}") :loop) :false))
    (should-not (agent-workspace-agent-loop ada))
    (should (eq (agent-workspace-agent-state ada) 'desk))
    (should (equal (plist-get (+test-awq--request "loop" "{\"name\":\"ada\",\"on\":false}") :loop) :false))
    (should (equal (+test-awq--said project)
                   '(("shell" "note" "ada" "turned ada's loop on")
                     ("shell" "note" "ada" "turned ada's loop off"))))
    (dolist (case `(("{\"name\":\"max\",\"on\":true}"
                     ,(format-message "max's role, scribe, has no labels: no issue is its to take"))
                    ("{\"name\":\"ada\"}" "loop: on or off? loop NAME on|off")
                    ("{\"on\":true}" "loop: whose? loop NAME on|off")))
      (should (equal (+test-awq--error "loop" (car case)) (cadr case))))
    (should-not (agent-workspace-agent-loop max))))

;; ====== ONLY A LEAD ======

(ert-deftest agent-workspace-request/only-a-lead-runs-the-crew ()
  "From an agent's shell, give, wake, sleep and loop only if its role leads
\(leads: true): another's refused, saying so, nothing done; its status
still answered. A lead's done, said in the room as its; not putting itself
to sleep."
  (+test-awq "lead" nil (("max" "lead") ("ada" "builder"))
    (should (plist-get (agent-workspace-role max) :leads))
    (should-not (plist-get (agent-workspace-role ada) :leads))
    (dolist (case '(("give" "{\"issue\":\"demo-1\",\"to\":\"max\",\"agent\":\"ada\"}")
                    ("wake" "{\"name\":\"max\",\"agent\":\"ada\"}")
                    ("sleep" "{\"name\":\"max\",\"agent\":\"ada\"}")
                    ("loop" "{\"name\":\"ada\",\"on\":true,\"agent\":\"ada\"}")))
      (should (equal (+test-awq--error (car case) (cadr case))
                     "only a lead runs the crew: ada's role, builder, doesn't lead")))
    (should (equal (+test-awq--error "sleep" "{\"name\":\"ada\",\"agent\":\"ghost\"}")
                   "only a lead runs the crew: ghost isn't in it"))
    ;; Another project's max (the same name) asking from this one's
    ;; folder: not its lead (doom-pbk.180).
    (let ((agent-workspace--request-from
           (agent-workspace--make-agent :name "max" :role "lead" :project "/another/project/")))
      (should (equal (cadr (should-error (agent-workspace--request-actor project nil) :type 'user-error))
                     "only a lead runs the crew: max isn't in it")))
    (let ((agent-workspace--request-from max))
      (should (equal (agent-workspace--request-actor project nil) "max")))
    (should (eq (plist-get (+test-awq--request "status" "{\"agent\":\"ada\"}") :ok) t))
    (should (agent-workspace-live-p max))
    (should-not (agent-workspace-agent-loop ada))
    (should-not (+test-awq--said project))
    ;; The lead's.
    (should (eq (plist-get (+test-awq--request "sleep" "{\"name\":\"ada\",\"agent\":\"max\"}") :ok) t))
    (should (eq (agent-workspace-agent-state ada) 'asleep))
    (should (eq (plist-get (+test-awq--request "wake" "{\"name\":\"ada\",\"agent\":\"max\"}") :ok) t))
    (should (+test-wait-for (lambda () (eq (agent-workspace-agent-state ada) 'desk)) 20))
    (should (equal (+test-awq--error "sleep" "{\"name\":\"max\",\"agent\":\"max\"}")
                   "max can't put itself to sleep: its session would end with this command"))
    (should (agent-workspace-live-p max))
    (should (equal (+test-awq--said project)
                   '(("max" "note" "ada" "put ada to sleep")
                     ("max" "note" "ada" "woke ada"))))))

(ert-deftest agent-workspace-request/a-lead-finds-why-and-acts ()
  "The starter lead, asked why linus takes no review: status shows him
asleep, his loop off. On the user's word it turns his loop on and wakes
him, the room saying so as the lead's; woken, he loops (nothing to
review: he naps). Its own loop refused: the lead has no labels."
  (+test-awq "lead-acts" t (("max" "lead") ("linus" "reviewer"))
    (agent-workspace-sleep linus)
    (let ((seen (seq-find (lambda (agent) (equal (plist-get agent :name) "linus"))
                          (plist-get (+test-awq--request "status" "{\"agent\":\"max\"}") :agents))))
      (should (equal (plist-get seen :state) "asleep"))
      (should (eq (plist-get seen :loop) :false)))
    (should (eq (plist-get (+test-awq--request "loop" "{\"name\":\"linus\",\"on\":true,\"agent\":\"max\"}") :ok) t))
    (should (eq (plist-get (+test-awq--request "wake" "{\"name\":\"linus\",\"agent\":\"max\"}") :ok) t))
    (should (agent-workspace-agent-loop linus))
    (should (+test-wait-for (lambda () (eq (agent-workspace-agent-state linus) 'nap)) 20))
    (should (equal (+test-awq--said project)
                   '(("max" "note" "linus" "turned linus's loop on")
                     ("max" "note" "linus" "woke linus"))))
    (should (equal (+test-awq--error "loop" "{\"name\":\"max\",\"on\":true,\"agent\":\"max\"}")
                   (format-message "max's role, lead, has no labels: no issue is its to take")))
    (should-not (agent-workspace-agent-loop max))))

;; ====== THE SCRIPT ======

(defmacro +test-awq--with-server (&rest body)
  "BODY with this Emacs a server only the script talks to (EMACS_SOCKET_NAME)."
  (declare (indent 0))
  `(let* ((server-socket-dir (make-temp-file "/tmp/awq-" t))
          (server-name "test")
          (process-environment
           (cons (concat "EMACS_SOCKET_NAME=" (expand-file-name server-name server-socket-dir))
                 process-environment)))
     (unwind-protect
         (progn (server-start nil t) ,@body)
       (server-force-delete)
       (delete-directory server-socket-dir t))))

(defun +test-awq--run (&rest args)
  "Run cmd/agent-workspace with ARGS: (STATUS . OUTPUT). Asynchronously:
this Emacs, its server, answers it meanwhile."
  (let* ((output (generate-new-buffer " *agent-workspace-run*"))
         (process (make-process :name "agent-workspace" :buffer output
                                :command (cons +test-awq-script args)
                                :connection-type 'pipe :noquery t :sentinel #'+test-process-sentinel
                                :stderr (get-buffer-create " *agent-workspace-stderr*"))))
    (with-timeout (30 (delete-process process) (ert-fail "cmd/agent-workspace didn't end"))
      (while (not (+test-process-ended-p process))
        (accept-process-output nil 0.02)))
    (prog1 (cons (process-exit-status process)
                 (with-current-buffer output (string-trim (buffer-string))))
      (kill-buffer output))))

(ert-deftest agent-workspace-request/the-script ()
  "cmd/agent-workspace status, sleep, wake and loop through Emacs's server,
the reply JSON, exit status 0; refused: 1. From an agent's shell
\(AGENT_WORKSPACE_AGENT) whose role doesn't lead: its status, not its
sleep."
  (+test-awq "script" nil (("ada" "builder"))
    (+test-awq--with-server
      (let ((run (+test-awq--run "status")))
        (should (= (car run) 0))
        (let ((reply (json-parse-string (cdr run) :object-type 'plist :array-type 'list)))
          (should (equal (mapcar (lambda (agent) (plist-get agent :name)) (plist-get reply :agents)) '("ada")))
          (should (equal (plist-get (car (plist-get reply :agents)) :words) "at the desk"))))
      (should (= (car (+test-awq--run "sleep" "ada")) 0))
      (should (eq (agent-workspace-agent-state ada) 'asleep))
      (let ((run (+test-awq--run "sleep" "ada")))
        (should (= (car run) 1))
        (should (equal (cdr run) "{\"ok\":false,\"error\":\"ada is asleep\"}")))
      (should (= (car (+test-awq--run "wake" "ada")) 0))
      (should (+test-wait-for (lambda () (eq (agent-workspace-agent-state ada) 'desk)) 20))
      (let ((run (+test-awq--run "loop" "ada" "off")))
        (should (= (car run) 0))
        (should (string-search "\"loop\":false" (cdr run))))
      (let ((process-environment (cons "AGENT_WORKSPACE_AGENT=ada" process-environment)))
        (should (= (car (+test-awq--run "status")) 0))
        (let ((run (+test-awq--run "sleep" "ada")))
          (should (= (car run) 1))
          (should (equal (cdr run)
                         "{\"ok\":false,\"error\":\"only a lead runs the crew: ada's role, builder, doesn't lead\"}"))))
      (should (agent-workspace-live-p ada))
      (should (equal (+test-awq--said project)
                     '(("shell" "note" "ada" "put ada to sleep")
                       ("shell" "note" "ada" "woke ada")))))))

(defun +test-awq--run-from (pid-var &rest args)
  "Run cmd/agent-workspace with ARGS as a command an agent's session runs:
its child, the session's process a sh whose id PID-VAR (a symbol) is set
to as it starts. (STATUS . OUTPUT)."
  (let* ((output (generate-new-buffer " *agent-workspace-run*"))
         (process (make-process :name "agent-session" :buffer output
                                ;; The script its child (not exec'd: a command after it).
                                :command (append (list "sh" "-c" "\"$0\" \"$@\"; exit $?" +test-awq-script) args)
                                :connection-type 'pipe :noquery t :sentinel #'+test-process-sentinel
                                :stderr (get-buffer-create " *agent-workspace-stderr*"))))
    (set pid-var (process-id process))
    (with-timeout (30 (delete-process process) (ert-fail "cmd/agent-workspace didn't end"))
      (while (not (+test-process-ended-p process))
        (accept-process-output nil 0.02)))
    (prog1 (cons (process-exit-status process)
                 (with-current-buffer output (string-trim (buffer-string))))
      (kill-buffer output))))

(defvar +test-awq--session-pid nil "The id of the process standing for ada's session.")

(ert-deftest agent-workspace-request/who-asks-is-where-it-comes-from ()
  "A command ada's session runs is hers, whatever its shell says: its
AGENT_WORKSPACE_AGENT unset, or the lead's name, give, wake, sleep, loop,
new and crew refused (she doesn't lead), nothing done; send --from
refused, a send her message, not ken's. Yours: done, from her worktree
too (your terminal there isn't her session) (doom-pbk.148)."
  (+test-awq "who" nil (("max" "lead") ("ada" "builder") ("ken" "builder"))
    (cl-letf* ((pid (symbol-function 'agent-workspace--agent-pid))
               ((symbol-function 'agent-workspace--agent-pid)
                (lambda (agent) (if (eq agent ada) +test-awq--session-pid (funcall pid agent)))))
      (+test-awq--with-server
        (let ((refused "{\"ok\":false,\"error\":\"only a lead runs the crew: ada's role, builder, doesn't lead\"}"))
          (dolist (env '(nil "AGENT_WORKSPACE_AGENT=max" "AGENT_WORKSPACE_AGENT="))
            (let ((process-environment (cons (or env "AGENT_WORKSPACE_AGENT") process-environment)))
              (dolist (args '(("sleep" "ken") ("wake" "ken") ("loop" "ken" "on") ("give" "demo-1" "--to" "ken")
                              ("new" "--role" "builder") ("crew" "pair")))
                (let ((run (apply #'+test-awq--run-from '+test-awq--session-pid args)))
                  (should (= (car run) 1))
                  (should (equal (cdr run) refused))))
              ;; Not an event from a source.
              (let ((run (+test-awq--run-from '+test-awq--session-pid "send" "--to" "ken" "--from" "ci" "hi")))
                (should (= (car run) 1))
                (should (string-search "--from is for scripts outside the agents' sessions; from ada's" (cdr run))))))
          (should (agent-workspace-live-p ken))
          (should-not (agent-workspace-agent-loop ken))
          (should (= (length (agent-workspace-agents project)) 3))
          (should-not (+test-awq--said project))
          ;; Her message, though her shell says ken.
          (let ((process-environment (cons "AGENT_WORKSPACE_AGENT=ken" process-environment)))
            (should (= (car (+test-awq--run-from '+test-awq--session-pid "send" "--to" "max" "who are you?")) 0)))
          (should (+test-wait-for (lambda () (seq-find (lambda (prompt) (string-prefix-p "Message from ada (builder)" prompt))
                                                       (+test-awq--prompts "max")))
                                  20))
          ;; Yours: done, from her worktree too.
          (setq +test-awq--session-pid nil)
          (let ((default-directory (agent-workspace-agent-worktree ada)))
            (should (= (car (+test-awq--run "sleep" "ken")) 0)))
          (should (eq (agent-workspace-agent-state ken) 'asleep)))))))

(ert-deftest agent-workspace-request/the-script-s-wrong-uses ()
  "status, give, wake, sleep and loop used wrong: 2, saying what's wrong,
no Emacs asked."
  (let ((process-environment (cons "EMACS_SOCKET_NAME=/tmp/no-such-agent-workspace-server"
                                   process-environment)))
    (dolist (case '((("status" "x") "status: unknown argument \\\"x\\\"; agent-workspace status")
                    (("give") "give: which issue? agent-workspace give ISSUE --to NAME")
                    (("give" "demo-1") "give: to whom? agent-workspace give demo-1 --to NAME")
                    (("give" "demo-1" "--to") "--to: give it a value")
                    (("give" "demo-1" "demo-2" "--to" "ada") "give: unknown argument \\\"demo-2\\\"")
                    (("give" "demo-1" "--for" "ada") "give: unknown argument \\\"--for\\\"")
                    (("wake") "wake: whom? agent-workspace wake NAME")
                    (("sleep" "ada" "ken") "sleep: unknown argument \\\"ken\\\"; agent-workspace sleep NAME")
                    (("sleep" "--all") "sleep: unknown argument \\\"--all\\\"")
                    (("loop") "loop: whose? agent-workspace loop NAME on|off")
                    (("loop" "ada") "loop: on or off? agent-workspace loop ada on|off")
                    (("loop" "ada" "yes") "loop: \\\"yes\\\" isn't on or off; agent-workspace loop ada on|off")
                    (("loop" "ada" "on" "now") "loop: unknown argument \\\"now\\\"")
                    (("fly") "operations: new, crew, send, status, give, wake, sleep, loop")))
      (let ((run (apply #'+test-awq--run (car case))))
        (should (= (car run) 2))
        (should (string-search (cadr case) (cdr run)))))
    ;; Well used, with no Emacs to ask: 3.
    (should (= (car (+test-awq--run "status")) 3))))
