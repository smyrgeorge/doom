;;; tests/unit/test-agent-workspace-new.el -*- lexical-binding: t; -*-
;; config/agent-workspace/new.el and request.el, with cmd/agent-workspace:
;; making an agent. Its name made from the pool, what you're asked, made from
;; an issue, a failing step said; from the shell. In throwaway git
;; repositories; no session starts (test-agent-workspace-session.el runs them).

(require 'server)

;; Git as git is, not as your ~/.gitconfig has it (hooks, signing...).
(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(+test-load "config/agent-workspace")

(defconst +test-awn-script (expand-file-name "cmd/agent-workspace" +test-root))

;; ====== HELPERS ======

(defun +test-awn--git (&rest args)
  "Run git with ARGS in `default-directory'; its output."
  (with-temp-buffer
    (unless (eql 0 (apply #'call-process "git" nil t nil args))
      (error "git %S: %s" args (buffer-string)))
    (string-trim (buffer-string))))

(defun +test-awn--project (name)
  "A git repository NAME in the temp folder, with a commit: its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awn/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (+test-awn--git "init" "-q" "-b" "main")
      (write-region "hello\n" nil "README")
      (+test-awn--git "add" "README")
      (+test-awn--git "-c" "user.name=Test" "-c" "user.email=test@example.com" "commit" "-q" "-m" "first"))
    (file-name-as-directory (file-truename dir))))

(defmacro +test-awn (name &rest body)
  "BODY in a new project NAME (`project', `default-directory'), with crews of
its own and no session started: an agent's start leaves it at the desk;
`started' lists the agents started, `sent' what they were sent."
  (declare (indent 1))
  `(let* ((project (+test-awn--project ,name))
          (default-directory project)
          (agent-workspace--crews (make-hash-table :test #'equal))
          (started nil)
          (sent nil))
     (ignore started sent)
     (cl-letf (((symbol-function 'agent-workspace--start)
                (lambda (agent)
                  (push (agent-workspace-agent-name agent) started)
                  (setf (agent-workspace-agent-state agent) 'desk)
                  t))
               ((symbol-function 'agent-workspace-send)
                (lambda (agent text &rest args)
                  (push (list (agent-workspace-agent-name agent) text args) sent)
                  'sent)))
       ,@body)))

(defun +test-awn--agent (project name &optional role state)
  "An agent record NAME (ROLE, STATE) put in PROJECT's crew."
  (let ((agent (agent-workspace--make-agent :name name :role (or role "builder") :colour "blue"
                                            :state (or state 'desk) :project project)))
    (puthash project (append (gethash project agent-workspace--crews) (list agent))
             agent-workspace--crews)
    agent))

(defmacro +test-awn--answering (answers &rest body)
  "BODY with the minibuffer's questions answered with ANSWERS, in order
\(`completing-read' and `read-string' alike); `asked' lists their prompts."
  (declare (indent 1))
  `(let ((answers ,answers)
         (asked nil))
     (cl-letf* ((answer (lambda (prompt &rest _)
                          (push prompt asked)
                          (or (pop answers) (error "Asked more: %s" prompt))))
                ((symbol-function 'completing-read) answer)
                ((symbol-function 'read-string) answer)
                ((symbol-function 'sit-for) #'ignore))
       ,@body)))

;; ====== A NAME ======

(ert-deftest agent-workspace-new/names ()
  "A name is typed after # in the room: a lowercase letter, then lowercase
letters, digits or -."
  (dolist (name '("ada" "builder-3" "a" "x2" "abcdefghijabcdefghij"))
    (should (agent-workspace-name-valid-p name)))
  (dolist (name '("Ada" "x_y" "3ada" "-ada" "ada lovelace" "abcdefghijabcdefghijk" "ádá" ""))
    (should-not (agent-workspace-name-valid-p name))))

(ert-deftest agent-workspace-new/a-name-from-the-pool ()
  "The pool's first name not in use, whose initial no agent has, not left by
a forgotten agent; none left, its role and a number."
  (+test-awn "pool"
    (should (equal (agent-workspace-pool-name project "builder") "ada"))
    (+test-awn--agent project "ada")
    (should (equal (agent-workspace-pool-name project "builder") "grace"))
    ;; An initial taken: george has g, so grace is passed over.
    (+test-awn--agent project "george")
    (should (equal (agent-workspace-pool-name project "builder") "linus"))
    ;; Left by a forgotten agent: its branch, or its worktree.
    (+test-awn--git "branch" "agent/linus")
    (make-directory (expand-file-name ".agent-shell/worktrees/builder-ken" project) t)
    (should (equal (agent-workspace-pool-name project "builder") "margaret"))
    ;; The pool run out.
    (let ((agent-workspace-names '("ada" "grace")))
      (should (equal (agent-workspace-pool-name project "builder") "builder-1"))
      (+test-awn--agent project "builder-1")
      (+test-awn--git "branch" "agent/builder-2")
      (should (equal (agent-workspace-pool-name project "builder") "builder-3")))))

;; ====== WHAT YOU'RE ASKED ======

(ert-deftest agent-workspace-new/its-role-annotated ()
  "Each role says what it does and how many of it run against its max."
  (+test-awn "annotated"
    (+test-awn--agent project "ada" "builder")
    (+test-awn--agent project "ken" "builder" 'asleep)
    (should (equal (agent-workspace--role-annotation project "builder") " · builds what you give it · 1 of 4"))
    (should (equal (agent-workspace--role-annotation project "scribe") " · writes issues with you · 0 of 1"))
    (should (equal (agent-workspace--role-annotation project "gone") nil))))

(ert-deftest agent-workspace-new/a-full-role-refused ()
  "A role at its max is refused, and asked again; the role given is
offered first."
  (+test-awn "full"
    (+test-awn--agent project "sam" "scribe")
    (+test-awn--answering '("scribe" "investigator")
      (let ((collection nil))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (prompt roles &rest args)
                     (push prompt asked)
                     (setq collection roles)
                     (should (equal (nth 4 args) (car roles)))
                     (pop answers))))
          (should (equal (agent-workspace-read-role project "reviewer") "investigator"))
          (should (equal (car collection) "reviewer"))
          (should (= (length asked) 2)))))))

(ert-deftest agent-workspace-new/its-name-asked ()
  "Left empty, the name made for it; one taken or not valid, asked again."
  (+test-awn "name"
    (+test-awn--agent project "ada")
    (+test-awn--answering '("Ada" "no good" "" )
      (should (equal (agent-workspace-read-name project "builder") "grace"))
      (should (equal (car asked) "Name (empty: grace): "))
      (should (= (length asked) 3)))
    (+test-awn--answering '(" linus ")
      (should (equal (agent-workspace-read-name project "builder") "linus")))))

(ert-deftest agent-workspace-new/made-from-what-you-answer ()
  "Its role and name asked, then made: its worktree, in the crew, started;
with C-u its model, mode and colour asked too (its role's by default)."
  (+test-awn "new"
    (+test-awn--answering '("investigator" "")
      (let ((agent (agent-workspace-new)))
        (should (equal (agent-workspace-agent-name agent) "ada"))
        (should (equal (agent-workspace-agent-role agent) "investigator"))
        (should (equal (agent-workspace-agent-colour agent) "magenta"))
        (should (equal started '("ada")))
        (should (file-directory-p (expand-file-name ".agent-shell/worktrees/investigator-ada" project)))
        (should (equal (agent-workspace-agents project) (list agent)))
        (should-not sent)))
    (+test-awn--answering '("builder" "ken" "haiku" "plan" "yellow")
      (let ((agent (agent-workspace-new '(4))))
        (should (equal (list (agent-workspace-agent-model agent) (agent-workspace-agent-mode agent)
                             (agent-workspace-agent-colour agent))
                       '("haiku" "plan" "yellow")))
        (should (equal (nth 2 (reverse asked)) "Model (builder's: inherit): "))))
    (+test-awn--answering '("reviewer" "linus" "inherit" "default" "green")
      (should-not (agent-workspace-agent-model (agent-workspace-new '(4)))))))

(ert-deftest agent-workspace-new/made-from-an-issue ()
  "Made for an issue: its role offered first, its worktree on the issue's
branch (TYPE/ID: task/ when its type isn't known), the issue its first
message, noted as its."
  (+test-awn "issue"
    (+test-awn--answering '("builder" "")
      (let ((agent (agent-workspace-new nil "builder" "doom-a1b" "Fix the thing" "bug")))
        (should (equal (agent-workspace-agent-issue agent) "doom-a1b"))
        (should (equal (agent-workspace-agent-issue-title agent) "Fix the thing"))
        (should (equal (agent-workspace-agent-branch agent) "fix/doom-a1b"))
        (should (equal sent '(("ada" "Work on doom-a1b: Fix the thing" (:submit t)))))))
    ;; A prompt of its own wins.
    (let ((ken (agent-workspace-create :role "builder" :name "ken" :issue "doom-b2c" :prompt "Look at it")))
      (should (equal (car sent) '("ken" "Look at it" (:submit t))))
      (should (equal (agent-workspace-agent-branch ken) "task/doom-b2c")))))

(ert-deftest agent-workspace-new/no-crew-here ()
  "Outside git, or with no commit: no crew, saying why; nothing asked."
  (let ((default-directory (file-name-as-directory (make-temp-file (+test-tmp-file "awn-nogit-") t))))
    (+test-awn--answering nil
      (should (string-match-p "No crew here: not a git repository"
                              (cadr (should-error (agent-workspace-new) :type 'user-error)))))))

(ert-deftest agent-workspace-new/a-failing-step-said ()
  "Its worktree not made: nothing is, saying so; its session not started:
it's in the crew, stuck, saying why."
  (+test-awn "failing"
    ;; A file where its worktree goes.
    (make-directory (expand-file-name ".agent-shell/worktrees" project) t)
    (write-region "" nil (expand-file-name ".agent-shell/worktrees/builder-ada" project))
    (should (string-match-p "\\`ada.s worktree: git worktree"
                             (cadr (should-error (agent-workspace-create :role "builder" :name "ada")
                                                 :type 'user-error))))
    (should-not (agent-workspace-agents project))
    (should-not started))
  (+test-awn "failing-session"
    (cl-letf (((symbol-function 'agent-workspace--start)
                (symbol-function (if (fboundp '+test-awn--real-start) '+test-awn--real-start 'ignore))))
      (let* ((agent-workspace-kinds '((claude-code :config (lambda () (error "No agent here")))))
             (agent (agent-workspace-create :role "builder" :name "ada" :prompt "hi")))
        (should (eq (agent-workspace-agent-state agent) 'stuck))
        (should (equal (agent-workspace-agent-error agent) "its session: No agent here"))
        (should (equal (agent-workspace-agents project) (list agent)))
        ;; Its first message not sent to a session that isn't.
        (should-not sent)))))

;; The real session start (the tests above stand it in), for the failing one.
(defalias '+test-awn--real-start (symbol-function 'agent-workspace--start))

;; ====== FROM THE SHELL ======

(defun +test-awn--request (op &optional payload cwd)
  "OP's reply (parsed) as cmd/agent-workspace gets it: a request folder with
PAYLOAD (JSON text), from CWD."
  (let ((dir (make-temp-file (+test-tmp-file "awn-request-") t)))
    (with-temp-file (expand-file-name "request" dir)
      (insert op "\n" (or cwd default-directory) "\n"))
    (when payload
      (with-temp-file (expand-file-name "payload" dir) (insert payload)))
    (should (eq (agent-workspace-request dir) t))
    (with-temp-buffer
      (insert-file-contents (expand-file-name "reply" dir))
      (json-parse-buffer :object-type 'plist :false-object nil :null-object nil))))

(ert-deftest agent-workspace-new/a-request ()
  "new from the shell: made in the shell's folder's project, its name made
if not given, the reply saying where it works; a wrong request said."
  (+test-awn "request"
    (let ((reply (+test-awn--request "new" "{\"role\":\"builder\",\"name\":\"\",\"prompt\":\"\"}"
                                     (expand-file-name ".git/../" project))))
      (should (equal reply (list :ok t :name "ada" :role "builder"
                                 :worktree (expand-file-name ".agent-shell/worktrees/builder-ada" project)
                                 :branch "agent/ada" :state "desk")))
      (should-not sent))
    (should (equal (plist-get (+test-awn--request "new" "{\"role\":\"investigator\",\"name\":\"sam\",\"prompt\":\"Look\"}")
                              :name)
                   "sam"))
    (should (equal (car sent) '("sam" "Look" (:submit t))))
    (dolist (case '(("new" "{\"name\":\"x\"}" "new: which role? --role ROLE")
                    ("new" "{\"role\":\"wizard\"}" "No role wizard: builder, investigator, reviewer, scribe")
                    ("new" "{\"role\":\"builder\",\"name\":\"Bad Name\"}" "Not a name for an agent")
                    ("new" "{nope" "not JSON")
                    ("old" "{}" "unknown operation \"old\"; operations: new")))
      (let ((reply (+test-awn--request (nth 0 case) (nth 1 case))))
        (should-not (plist-get reply :ok))
        (should (string-search (nth 2 case) (plist-get reply :error)))))))

(defmacro +test-awn--with-server (&rest body)
  "BODY with this Emacs a server only the script talks to (EMACS_SOCKET_NAME)."
  (declare (indent 0))
  `(let* ((server-socket-dir (make-temp-file "/tmp/aws-" t))
          (server-name "test")
          (process-environment
           (cons (concat "EMACS_SOCKET_NAME=" (expand-file-name server-name server-socket-dir))
                 process-environment)))
     (unwind-protect
         (progn (server-start nil t) ,@body)
       (server-force-delete)
       (delete-directory server-socket-dir t))))

(defun +test-awn--run (&rest args)
  "Run cmd/agent-workspace with ARGS: (STATUS . OUTPUT). Asynchronously:
this Emacs, its server, answers it meanwhile."
  (let* ((output (generate-new-buffer " *agent-workspace-run*"))
         (process (make-process :name "agent-workspace" :buffer output
                                :command (cons +test-awn-script args)
                                :connection-type 'pipe :noquery t :sentinel #'+test-process-sentinel
                                :stderr (get-buffer-create " *agent-workspace-stderr*"))))
    (with-timeout (30 (delete-process process) (ert-fail "cmd/agent-workspace didn't end"))
      (while (not (+test-process-ended-p process))
        (accept-process-output nil 0.02)))
    (prog1 (cons (process-exit-status process)
                 (with-current-buffer output (string-trim (buffer-string))))
      (kill-buffer output))))

(ert-deftest agent-workspace-new/the-script ()
  "cmd/agent-workspace new: the agent made through Emacs's server, the
reply JSON; its exit status 0, 1 when not done."
  (+test-awn "script"
    (+test-awn--with-server
      (let ((run (+test-awn--run "new" "--role" "reviewer" "--prompt" "Review \"main\"")))
        (should (= (car run) 0))
        (should (string-prefix-p "{\"ok\":true,\"name\":\"ada\",\"role\":\"reviewer\"" (cdr run))))
      (should (equal (car sent) '("ada" "Review \"main\"" (:submit t))))
      (let ((run (+test-awn--run "new" "--role=builder" "--name=ada")))
        (should (= (car run) 1))
        (should (string-match-p "\\`{\"ok\":false,\"error\":\"There.s an agent named ada" (cdr run)))))))

(ert-deftest agent-workspace-new/the-script-sends ()
  "cmd/agent-workspace send: an event queued for a role through Emacs's
server (nobody of it free), its words joined; wrong uses: 2, saying why."
  (+test-awn "script-send"
    (let ((agent-workspace--inboxes (make-hash-table :test #'equal))
          (agent-workspace--inbox-sent (make-hash-table :test #'equal)))
      (+test-awn--with-server
        (let ((run (+test-awn--run "send" "--to" "#builder" "--from=ci" "the" "build broke")))
          (should (= (car run) 0))
          (should (equal (cdr run) "{\"ok\":true,\"events\":[{\"id\":1,\"to\":\"#builder\",\"state\":\"queued\"}]}")))
        (should (equal (plist-get (car (agent-workspace-inbox project)) :text) "the build broke"))
        (let ((run (+test-awn--run "send" "--to" "nobody" "hi")))
          (should (= (car run) 1))
          (should (string-search "No agent nobody in this crew" (cdr run)))))
      (dolist (case '((("send" "hi") "send: to whom?")
                      (("send" "--to" "ada") "send: what?")
                      (("send" "--to" "ada" "--bcc" "x") "send: unknown argument \\\"--bcc\\\"")))
        (let ((run (apply #'+test-awn--run (car case))))
          (should (= (car run) 2))
          (should (string-search (cadr case) (cdr run))))))))

(ert-deftest agent-workspace-new/the-script-s-wrong-uses ()
  "Wrong uses: 2, saying what's wrong; no Emacs: 3."
  (let ((process-environment (cons "EMACS_SOCKET_NAME=/tmp/no-such-agent-workspace-server"
                                   process-environment)))
    (dolist (case '((("new") "new: which role?")
                    (("new" "--role") "--role: give it a value")
                    (("new" "--role" "x" "extra") "new: unknown argument \\\"extra\\\"")
                    (("old") "unknown operation \\\"old\\\"; operations: new")))
      (let ((run (apply #'+test-awn--run (car case))))
        (should (= (car run) 2))
        (should (string-search (cadr case) (cdr run)))))
    (should (= (car (+test-awn--run)) 2))
    (should (string-search "agent-workspace new --role ROLE" (cdr (+test-awn--run "--help"))))
    (let ((run (+test-awn--run "new" "--role" "builder")))
      (should (= (car run) 3))
      (should (string-match-p "no Emacs server answered" (cdr run))))))
