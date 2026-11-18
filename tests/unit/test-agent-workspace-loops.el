;;; tests/unit/test-agent-workspace-loops.el -*- lexical-binding: t; -*-
;; config/agent-workspace/loops.el: an agent that, once free, takes the next
;; ready issue of its role by itself (claimed as itself, a fresh session for
;; each), or naps and says so once, waking when one comes; two looping agents
;; never take the same issue; one stops after failures in a row; a crew started
;; again brings a looping agent back asleep. Stand-in agents
;; (examples/agent-workspace/stand-in.el: "Work on ID: close..." closes it with
;; bd, "Work on ID: fail..." fails, else holds) on throwaway git repositories
;; whose issues bd tracks (skipped without bd). Batch Emacs gets no file-notify
;; events: a change to .beads is the watch's callback, called.
;; run.sh: split 3 (~110 s alone: a stand-in session and bd for each issue taken).

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(require 'agent-shell)
(require 'agent-shell-mock-agent)
(require 'json)
(+test-load "config/agent-shell" "config/agent-ui" "config/agent-workspace")
(load (expand-file-name "../helper-agent-workspace" (file-name-directory (or load-file-name buffer-file-name))) nil t)
(remove-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context)

(setq agent-shell-mock-agent-acp-command
      (list (expand-file-name invocation-name invocation-directory)
            "--batch" "-Q" (concat "--init-directory=" (+test-tmp-file "mock-acp-home/"))
            "-l" (expand-file-name "examples/agent-workspace/stand-in.el" +test-root) "-f" "mock-acp-main"))
(add-to-list 'agent-workspace-kinds '(mock :config agent-shell-mock-agent-make-agent-config))

;; ====== HELPERS ======

(defvar +test-awl--log nil "The stand-in's log file, this test's.")

(defvar +test-awl--template nil
  "A git repository with a commit whose issues bd tracks (none yet), made
once: each test's project is a copy (bd init takes seconds).")

(defun +test-awl--run (program &rest args)
  "PROGRAM run with ARGS in `default-directory': its output, an error if it
failed."
  (let ((errors (make-temp-file "awl-errors-")))
    (unwind-protect
        (with-temp-buffer
          (unless (eql 0 (apply #'call-process program nil (list t errors) nil args))
            (error "%s %S failed: %s %s" program args (buffer-string)
                   (with-temp-buffer (insert-file-contents errors) (buffer-string))))
          (buffer-string))
      (delete-file errors))))

(defun +test-awl--project (name &optional no-beads)
  "A project NAME in the temp folder, a copy of the template: a git
repository with a commit, its issues tracked by bd (NO-BEADS: not). Its
folder."
  (unless (or no-beads +test-awl--template)
    (let ((dir (file-name-as-directory (expand-file-name "awl/template" +test-tmp))))
      (when (file-exists-p dir) (delete-directory dir t))
      (make-directory dir t)
      (let ((default-directory dir))
        (+test-awl--run "git" "init" "-q" "-b" "main")
        (write-region "hello\n" nil "README")
        (+test-awl--run "git" "add" "README")
        (+test-awl--run "git" "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-m" "first")
        (+test-awl--run "bd" "init" "--quiet" "--skip-agents" "--prefix" "demo"))
      (setq +test-awl--template dir)))
  (let ((dir (file-name-as-directory (expand-file-name (concat "awl/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory (file-name-directory (directory-file-name dir)) t)
    (if no-beads
        (let ((default-directory (progn (make-directory dir t) dir)))
          (+test-awl--run "git" "init" "-q" "-b" "main")
          (write-region "hello\n" nil "README")
          (+test-awl--run "git" "add" "README")
          (+test-awl--run "git" "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-m" "first"))
      (copy-directory +test-awl--template dir nil t t))
    (file-name-as-directory (file-truename dir))))

(defun +test-awl--issue (project title label priority &optional type)
  "A ready issue of PROJECT: TITLE, LABEL, PRIORITY (TYPE: task). Its id."
  (let ((default-directory project))
    (alist-get 'id (json-parse-string
                    (+test-awl--run "bd" "create" "--title" title "--labels" label
                                    "--priority" (number-to-string priority) "--type" (or type "task")
                                    "--json")
                    :object-type 'alist))))

(defun +test-awl--status (project id)
  "Issue ID of PROJECT: its status (\"open\", \"closed\"...)."
  (let ((default-directory project))
    (alist-get 'status (car (json-parse-string (+test-awl--run "bd" "show" id "--json")
                                               :object-type 'alist :array-type 'list)))))

(defmacro +test-awl--with-crew (name &rest body)
  "BODY in a new project NAME whose issues bd tracks (`project'; skipped
without bd), its crew closed after, the stand-in's log fresh; a failure tried
again at once; no look every few minutes."
  (declare (indent 1))
  `(progn
     (skip-unless (executable-find "bd"))
     (+test-with-reset
       (let* ((project (+test-awl--project ,name))
              (default-directory project)
              (+test-awl--log (expand-file-name (concat "awl/" ,name ".log") +test-tmp))
              (process-environment (cons (concat "MOCK_ACP_LOG=" +test-awl--log) process-environment))
              (agent-workspace-loop-retry 0.2)
              (agent-workspace-loop-check nil))
         (ignore-errors (delete-file +test-awl--log))
         (unwind-protect (progn ,@body)
           (agent-workspace-close-all))))))

(defun +test-awl--wait (predicate &optional timeout)
  "Wait until PREDICATE returns non-nil, TIMEOUT seconds at most (default
60): its value, or nil."
  (let ((end (+ (float-time) (or timeout 60)))
        value)
    (while (and (not (setq value (funcall predicate))) (< (float-time) end))
      (accept-process-output nil 0.05))
    value))

(defun +test-awl--sleep (seconds)
  "SECONDS of processes and timers running."
  (+test-awl--wait #'ignore seconds))

(defun +test-awl--create (name)
  "A builder NAME (the stand-in), at the desk."
  (let ((agent (agent-workspace-create :role "builder" :name name :kind 'mock)))
    (should (+test-awl--wait (lambda () (eq (agent-workspace-agent-state agent) 'desk)) 20))
    agent))

(defun +test-awl--log-entries ()
  "What the stand-in logged: a plist each."
  (when (file-exists-p +test-awl--log)
    (with-temp-buffer
      (insert-file-contents +test-awl--log)
      (mapcar (lambda (line) (json-parse-string line :object-type 'plist :null-object nil
                                                :false-object nil :array-type 'list))
              (split-string (buffer-string) "\n" t)))))

(defun +test-awl--prompts (name)
  "The prompts the agent NAME got, in order."
  (cl-loop for entry in (+test-awl--log-entries)
           when (and (equal (plist-get entry :agent) name)
                     (equal (plist-get entry :method) "session/prompt"))
           collect (mapconcat (lambda (block) (plist-get block :text))
                              (plist-get (plist-get entry :params) :prompt) "")))

(defun +test-awl--sessions (name)
  "The agent NAME's sessions, in order: the prompts each got."
  (let (sessions)
    (dolist (entry (+test-awl--log-entries))
      (when (equal (plist-get entry :agent) name)
        (cond ((plist-get entry :start) (push nil sessions))
              ((equal (plist-get entry :method) "session/prompt")
               (push (mapconcat (lambda (block) (plist-get block :text))
                                (plist-get (plist-get entry :params) :prompt) "")
                     (car sessions))))))
    (nreverse (mapcar #'reverse sessions))))

(defun +test-awl--room (project name)
  "What PROJECT's room said of the agent NAME: (KIND . TEXT) each, in order."
  (let ((file (expand-file-name ".agent-shell/agent-workspace/room.jsonl" project)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (cl-loop for line in (split-string (buffer-string) "\n" t)
                 for entry = (json-parse-string line :object-type 'plist)
                 when (equal (plist-get entry :agent) name)
                 collect (cons (plist-get entry :kind) (plist-get entry :text)))))))

(defun +test-awl--naps (project name)
  "How many times PROJECT's room said the agent NAME naps."
  (seq-count (lambda (entry) (string-prefix-p "☾ napping" (cdr entry))) (+test-awl--room project name)))

(defun +test-awl--all-in (agents state &optional timeout)
  "Wait for AGENTS to be in STATE (TIMEOUT seconds at most, default 60);
else fail, saying where each is."
  (unless (+test-awl--wait (lambda () (seq-every-p (lambda (agent) (eq (agent-workspace-agent-state agent) state))
                                                   agents))
                           timeout)
    (ert-fail (cons (format "not all %s" state)
                    (mapcar (lambda (agent)
                              (list (agent-workspace-agent-name agent) (agent-workspace-agent-state agent)
                                    :run (gethash agent agent-workspace--loop-runs)
                                    :issue (agent-workspace-agent-issue agent)
                                    :error (agent-workspace-agent-error agent)
                                    :prompts (+test-awl--prompts (agent-workspace-agent-name agent))
                                    :room (+test-awl--room (agent-workspace-agent-project agent)
                                                           (agent-workspace-agent-name agent))))
                            agents)))))

(defun +test-awl--quiet (agent)
  "Wait for AGENT's loop to have nothing running (its bd commands answered)."
  (+test-awl--sleep 0.1)
  (should (+test-awl--wait (lambda () (not (agent-workspace--loop-get agent :busy))) 20)))

;; ====== ITS WORDS, ITS LOOK ======

(ert-deftest agent-workspace-loops/napping-in-its-role-s-verb ()
  "Napping says what there's nothing to do, in its role's verb: its base
form, roughly as English has it."
  (dolist (case '(("building" . "build") ("investigating" . "investigate") ("reviewing" . "review")
                  ("writing" . "write") ("testing" . "test") ("planning" . "plan") ("fixing" . "fix")
                  ("triaging" . "triage") ("making" . "make") ("adding" . "add") ("telling" . "tell")
                  ("debugging" . "debug") ("documenting" . "document") ("editing" . "edit")))
    (should (equal (agent-workspace--verb-base (car case)) (cdr case))))
  (should-not (agent-workspace--verb-base "build"))
  (should-not (agent-workspace--verb-base nil))
  (let ((agent (agent-workspace--make-agent :name "ada" :role "builder" :state 'nap)))
    (let ((agent-workspace-role-function (lambda (_project name) (list :name name :verb "building"))))
      (should (equal (agent-workspace-state-text agent) "napping: nothing to build")))
    (let ((agent-workspace-role-function #'agent-workspace--bare-role))
      (should (equal (agent-workspace-state-text agent) "napping: nothing to do")))))

(ert-deftest agent-workspace-loops/its-bar-and-its-key ()
  "↻ on its line while it loops, ☾ napping; L in the app's keys, in its
session's after SPC m w too."
  (let ((agent (agent-workspace--make-agent :name "ada" :role "builder" :colour "blue" :state 'desk
                                            :project "/tmp/awl-project/")))
    (should-not (string-search "↻" (agent-workspace-line agent 120)))
    (setf (agent-workspace-agent-loop agent) t)
    (should (string-search "ada ↻" (agent-workspace-line agent 120)))
    (should (string-search "ada ↻" (agent-workspace-line agent 80 nil t)))
    (setf (agent-workspace-agent-state agent) 'nap)
    (should (string-search "☾ napping: nothing to build" (agent-workspace-line agent 120))))
  (should (equal (assoc "L" +my/agent-workspace-keys) '("L" . agent-workspace-loop-here)))
  (dolist (map (list agent-workspace-bar-mode-map agent-workspace-issues-mode-map +my/agent-workspace-pane-map))
    (should (eq (lookup-key map "L") #'agent-workspace-loop-here)))
  (should (commandp #'agent-workspace-loop-here)))

(ert-deftest agent-workspace-loops/only-with-labels-and-beads ()
  "A role without labels has no issue to take, a project without Beads
none either: its loop refused, saying why. Turned on and off, said in the
room; off, a napping agent is at the desk."
  (+test-with-reset
    (let* ((agent-workspace--crews (make-hash-table :test #'equal))
           (project (+test-awl--project "refused" t))
           (scribe (agent-workspace--make-agent :name "sam" :role "scribe" :state 'desk :project project))
           (builder (agent-workspace--make-agent :name "ada" :role "builder" :state 'nap :project project)))
      (puthash project (list scribe builder) agent-workspace--crews)
      (should (string-match-p "sam.s role, scribe, has no labels"
                              (cadr (should-error (agent-workspace-loop-set scribe t) :type 'user-error))))
      (should (string-match-p "refused doesn.t track its issues with Beads"
                              (cadr (should-error (agent-workspace-loop-set builder t) :type 'user-error))))
      (should-not (agent-workspace-agent-loop builder))
      ;; Off, it's said; napping, it's at the desk.
      (setf (agent-workspace-agent-loop builder) t)
      (let ((changes nil))
        (let ((agent-workspace-change-functions (list (lambda (agent what) (push (cons agent what) changes)))))
          (should-not (agent-workspace-loop-set builder nil)))
        (should (member (cons builder 'loop) changes)))
      (should (eq (agent-workspace-agent-state builder) 'desk))
      (should (equal (+test-awl--room project "ada") '(("note" . "stopped looping")))))))

;; ====== TAKING THE NEXT ======

(ert-deftest agent-workspace-loops/works-through-the-ready-issues-then-naps ()
  "A builder looping takes the ready build issues one after the other, P1
first, each claimed as itself and given in a fresh session (the first in the
one it had, no turn yet), closes them; none left, it naps, said once, and
notified once. A look that finds nothing says nothing. A new issue: it
wakes, takes it, and naps again."
  (+test-awl--with-crew "three"
    (let* ((one (+test-awl--issue project "close: one" "build" 2))
           (two (+test-awl--issue project "close: two" "build" 1))
           (three (+test-awl--issue project "close: three" "build" 2))
           (review (+test-awl--issue project "close: a review" "review" 0))
           (epic (+test-awl--issue project "close: an epic" "build" 0 "epic"))
           (naps nil)
           (agent-workspace-nap-functions (list (lambda (agent) (push agent naps))))
           (ada (+test-awl--create "ada"))
           (root (agent-workspace-agent-project ada)))
      (agent-workspace-loop-set ada t)
      (+test-awl--all-in (list ada) 'nap 90)
      (dolist (id (list one two three))
        (should (equal (+test-awl--status project id) "closed")))
      ;; Not another role's, not an epic.
      (should (equal (+test-awl--status project review) "open"))
      (should (equal (+test-awl--status project epic) "open"))
      ;; P1 first; a session each.
      (let ((sessions (+test-awl--sessions "ada")))
        (should (= (length sessions) 3))
        (should (equal (car sessions) (list (format "Work on %s: close: two" two))))
        (should (equal (sort (mapcar #'car (cdr sessions)) #'string<)
                       (sort (list (format "Work on %s: close: one" one) (format "Work on %s: close: three" three))
                             #'string<))))
      ;; Said in the room, the nap once; notified once.
      (let ((room (+test-awl--room project "ada")))
        (should (member '("note" . "↻ loops: once free, takes the next ready build issue") room))
        (should (member (cons "issue" (format "took %s: close: two" two)) room))
        (should (= (seq-count (lambda (entry) (string-prefix-p "took " (cdr entry))) room) 3)))
      (should (= (+test-awl--naps project "ada") 1))
      (should (equal naps (list ada)))
      (should-not (agent-workspace-agent-issue ada))
      (should (equal (agent-workspace-state-text ada) "napping: nothing to build"))
      ;; A look finding nothing: nothing said.
      (agent-workspace--loop-look-all root)
      (+test-awl--quiet ada)
      (should (eq (agent-workspace-agent-state ada) 'nap))
      (should (= (+test-awl--naps project "ada") 1))
      (should (= (length naps) 1))
      ;; A new one: its .beads changed, it wakes and takes it.
      (let ((four (+test-awl--issue project "close: four" "build" 2)))
        (agent-workspace--loop-changed root)
        (should (+test-awl--wait (lambda () (equal (+test-awl--status project four) "closed")) 60))
        (should (member (cons "issue" (format "woke up, took %s: close: four" four))
                        (+test-awl--room project "ada")))
        (+test-awl--all-in (list ada) 'nap)
        (should (= (length (+test-awl--sessions "ada")) 4))
        (should (= (+test-awl--naps project "ada") 2))
        (should (= (length naps) 2))))))

(ert-deftest agent-workspace-loops/two-never-take-the-same-issue ()
  "Two looping builders on five ready issues: each issue claimed by one of
them only, all closed; then one issue for both, napping: one takes it, the
other naps on, saying nothing."
  (+test-awl--with-crew "two"
    (let* ((ids (mapcar (lambda (n) (+test-awl--issue project (format "close: %d" n) "build" 2)) '(1 2 3 4 5)))
           (ada (+test-awl--create "ada"))
           (ken (+test-awl--create "ken"))
           (root (agent-workspace-agent-project ada)))
      (agent-workspace-loop-set ada t)
      (agent-workspace-loop-set ken t)
      (+test-awl--all-in (list ada ken) 'nap 120)
      (let ((ada-took (+test-awl--prompts "ada"))
            (ken-took (+test-awl--prompts "ken")))
        (should (= (+ (length ada-took) (length ken-took)) 5))
        (should-not (seq-intersection ada-took ken-took))
        (should (equal (sort (append ada-took ken-took) #'string<)
                       (sort (mapcar (lambda (id) (format "Work on %s: close: %s" id (1+ (cl-position id ids)))) ids)
                             #'string<))))
      (dolist (id ids)
        (should (equal (+test-awl--status project id) "closed")))
      ;; One for both at once.
      (let ((six (+test-awl--issue project "close: 6" "build" 2))
            (before (+ (length (+test-awl--prompts "ada")) (length (+test-awl--prompts "ken")))))
        (agent-workspace--loop-changed root)
        (should (+test-awl--wait (lambda () (equal (+test-awl--status project six) "closed"))))
        (+test-awl--all-in (list ada ken) 'nap)
        (+test-awl--quiet ada)
        (+test-awl--quiet ken)
        (should (= (+ (length (+test-awl--prompts "ada")) (length (+test-awl--prompts "ken"))) (1+ before)))
        ;; The one that took it napped again, said; the other said nothing.
        (should (= (+ (+test-awl--naps project "ada") (+test-awl--naps project "ken")) 3))))))

(ert-deftest agent-workspace-loops/a-turn-with-its-issue-in-progress-waits ()
  "A turn that ended with its issue still in progress: done, for you to
look, no next issue. Its issue closed (by it, or you): it's free, and takes
the next."
  (+test-awl--with-crew "waits"
    (let* ((held (+test-awl--issue project "hold: the lexer" "build" 1))
           (next (+test-awl--issue project "close: the parser" "build" 2))
           (ada (+test-awl--create "ada"))
           (root (agent-workspace-agent-project ada)))
      (agent-workspace-loop-set ada t)
      (should (+test-awl--wait (lambda () (eq (agent-workspace-agent-state ada) 'working))))
      (should (equal (agent-workspace-agent-issue ada) held))
      (agent-workspace-interrupt ada)
      (should (+test-awl--wait (lambda () (eq (agent-workspace-agent-state ada) 'desk))))
      (+test-awl--quiet ada)
      (agent-workspace--loop-look-all root)
      (+test-awl--quiet ada)
      (should (eq (agent-workspace-agent-state ada) 'desk))
      (should (equal (+test-awl--prompts "ada") (list (format "Work on %s: hold: the lexer" held))))
      (should (equal (+test-awl--status project next) "open"))
      ;; Closed (as it would, as itself): it takes the next.
      (let ((default-directory project)
            (process-environment (cons "BEADS_ACTOR=ada" process-environment)))
        (+test-awl--run "bd" "close" held))
      (agent-workspace--loop-changed root)
      (should (+test-awl--wait (lambda () (equal (+test-awl--status project next) "closed"))))
      (should (equal (cadr (+test-awl--sessions "ada")) (list (format "Work on %s: close: the parser" next)))))))

(ert-deftest agent-workspace-loops/wakes-on-its-look-or-when-woken ()
  "A napping builder wakes on its look every few minutes, or when another
part wakes it (`agent-workspace-loop-wake'), for an issue that came."
  (+test-awl--with-crew "wakes"
    (let* ((agent-workspace-loop-check 0.02)
           (ada (+test-awl--create "ada")))
      (agent-workspace-loop-set ada t)
      (+test-awl--all-in (list ada) 'nap)
      ;; Its look, every 1.2 s here.
      (let ((one (+test-awl--issue project "close: one" "build" 2)))
        (should (+test-awl--wait (lambda () (equal (+test-awl--status project one) "closed"))))
        (+test-awl--all-in (list ada) 'nap))
      ;; Woken by another part.
      (agent-workspace-loop-set ada nil)
      (should-not (agent-workspace-loop-wake ada))
      (agent-workspace-loop-set ada t)
      (+test-awl--all-in (list ada) 'nap)
      (+test-awl--quiet ada)
      (let* ((agent-workspace-loop-check nil)
             (two (+test-awl--issue project "close: two" "build" 2)))
        (should (agent-workspace-loop-wake ada))
        (should (+test-awl--wait (lambda () (equal (+test-awl--status project two) "closed"))))))))

(ert-deftest agent-workspace-loops/a-slow-bd-still-gets-somewhere ()
  "bd slower than its looks come (one every 1.2 s here, bd's list taking
1.5 s): each look's answer is used, then the next look, not thrown away for
it: it naps, then takes an issue that came (doom-pbk.23)."
  (+test-awl--with-crew "slow"
    (let* ((bin (file-name-as-directory (make-temp-file (+test-tmp-file "slow-bd-") t)))
           (real (executable-find "bd"))
           (exec-path (cons bin exec-path))
           (process-environment (cons (concat "PATH=" bin path-separator (getenv "PATH")) process-environment))
           (agent-workspace-loop-check 0.02))
      (with-temp-file (expand-file-name "bd" bin)
        (insert "#!/bin/sh\n[ \"$1\" = list ] && sleep 1.5\nexec " (shell-quote-argument real) " \"$@\"\n"))
      (set-file-modes (expand-file-name "bd" bin) #o755)
      (let ((ada (+test-awl--create "ada")))
        (agent-workspace-loop-set ada t)
        (+test-awl--all-in (list ada) 'nap 60)
        (let ((one (+test-awl--issue project "close: one" "build" 2)))
          (should (+test-awl--wait (lambda () (equal (+test-awl--status project one) "closed")) 60)))))))

(ert-deftest agent-workspace-loops/a-branch-for-each-issue ()
  "Each issue it takes gets its branch in its worktree (TYPE/ID, from the
main branch) before its prompt comes; one left holding nothing, deleted.
Its worktree with changes not committed: a failure, nothing claimed; three
in a row, stuck, saying why."
  (+test-awl--with-crew "branches"
    (let* ((one (+test-awl--issue project "close: one" "build" 1))
           (two (+test-awl--issue project "close: two" "build" 2))
           (ada (+test-awl--create "ada"))
           (dir (agent-workspace-agent-worktree ada))
           (branches (lambda () (let ((default-directory project))
                                  (+test-awl--run "git" "branch" "--format=%(refname:short)")))))
      (agent-workspace-loop-set ada t)
      (+test-awl--all-in (list ada) 'nap 90)
      (should (equal (cl-loop for entry in (+test-awl--log-entries)
                              when (and (equal (plist-get entry :agent) "ada") (plist-get entry :branch))
                              collect (plist-get entry :branch))
                     (list (concat "task/" one) (concat "task/" two "-two"))))
      (should (equal (agent-workspace-agent-branch ada) (concat "task/" two "-two")))
      (should (equal (string-trim (let ((default-directory dir)) (+test-awl--run "git" "branch" "--show-current")))
                     (concat "task/" two "-two")))
      (should-not (string-search (concat "task/" one) (funcall branches)))
      ;; Changes left in its worktree: no issue claimed.
      (write-region "half\n" nil (expand-file-name "wip" dir))
      (let ((three (+test-awl--issue project "close: three" "build" 2)))
        (agent-workspace--loop-changed (agent-workspace-agent-project ada))
        (should (+test-awl--wait (lambda () (agent-workspace--loop-get ada :stopped))))
        (should (eq (agent-workspace-agent-state ada) 'stuck))
        (should (string-match-p (concat "\\`stopped looping, 3 failures in a row: ada has changes not committed, on task/"
                                        (regexp-quote two))
                                (agent-workspace-agent-error ada)))
        (should (equal (+test-awl--status project three) "open"))
        (should (= (length (+test-awl--prompts "ada")) 2))))))

;; ====== FAILURES ======

(ert-deftest agent-workspace-loops/stops-after-three-failures-in-a-row ()
  "Its turn failing on its issue: tried again, the same issue in its
session; the third failure in a row stops it, stuck, saying why, its issue
still its. Restarted by you: its loop goes on, its issue in progress, so it
waits."
  (+test-awl--with-crew "fails"
    (let* ((bad (+test-awl--issue project "fail: always" "build" 1))
           (ada (+test-awl--create "ada")))
      (agent-workspace-loop-set ada t)
      (should (+test-awl--wait (lambda () (agent-workspace--loop-get ada :stopped))))
      (should (eq (agent-workspace-agent-state ada) 'stuck))
      (should (string-match-p "\\`stopped looping, 3 failures in a row: .*mock failure"
                              (agent-workspace-agent-error ada)))
      (should (string-match-p "stuck on .*: stopped looping, 3 failures in a row"
                              (substring-no-properties (agent-workspace-state-words ada))))
      (should (equal (+test-awl--sessions "ada") (list (make-list 3 (format "Work on %s: fail: always" bad)))))
      (let ((room (+test-awl--room project "ada")))
        (should (member '("note" . "↻ tries again in 0.2s: 1 of 3 failures in a row") room))
        (should (member '("note" . "↻ tries again in 0.2s: 2 of 3 failures in a row") room))
        (should (seq-find (lambda (entry) (and (equal (car entry) "stuck")
                                               (string-match-p "stopped looping, 3 failures in a row" (cdr entry))))
                          room)))
      ;; Not tried again.
      (+test-awl--sleep 1)
      (should (= (length (+test-awl--prompts "ada")) 3))
      (should (equal (+test-awl--status project bad) "in_progress"))
      ;; Restarted: its run begins again; its issue still in progress, it waits.
      (agent-workspace-restart ada)
      (should (+test-awl--wait (lambda () (eq (agent-workspace-agent-state ada) 'desk))))
      (+test-awl--quiet ada)
      (should-not (agent-workspace--loop-get ada :stopped))
      (should (eq (agent-workspace-agent-state ada) 'desk))
      (should (= (length (+test-awl--prompts "ada")) 3)))))

(ert-deftest agent-workspace-loops/a-turn-that-ends-breaks-the-row ()
  "A failure, then a turn of yours that ends: its failures forgotten, its
try again cancelled."
  (+test-awl--with-crew "row"
    (let* ((agent-workspace-loop-retry 30)
           (bad (+test-awl--issue project "fail: once" "build" 1))
           (ada (+test-awl--create "ada")))
      (agent-workspace-loop-set ada t)
      (should (+test-awl--wait (lambda () (eql (agent-workspace--loop-get ada :failures) 1))))
      (should (agent-workspace--loop-get ada :timer))
      (agent-workspace-send ada "hello" :submit t)
      (should (+test-awl--wait (lambda () (memq (agent-workspace-agent-state ada) '(done desk)))))
      (should-not (agent-workspace--loop-get ada :failures))
      (should-not (agent-workspace--loop-get ada :timer))
      (+test-awl--quiet ada)
      (should (equal (+test-awl--prompts "ada") (list (format "Work on %s: fail: once" bad) "hello"))))))

;; ====== WHAT YOU TYPE ======

(ert-deftest agent-workspace-loops/text-typed-at-its-prompt-waits ()
  "Text typed at a napping agent's prompt, not sent: an issue coming isn't
taken (a fresh session would lose the text), the text still there; the
text gone, it takes it (doom-pbk.63)."
  (+test-awl--with-crew "typed"
    (let* ((ada (+test-awl--create "ada"))
           (root (agent-workspace-agent-project ada))
           (buffer (agent-workspace-agent-buffer ada)))
      (agent-workspace-loop-set ada t)
      (+test-awl--all-in (list ada) 'nap)
      (+test-awl--quiet ada)
      (with-current-buffer buffer
        (goto-char (point-max))
        (insert "half a thought"))
      (let ((one (+test-awl--issue project "close: one" "build" 2)))
        (agent-workspace--loop-changed root)
        (+test-awl--sleep 1.5)
        (+test-awl--quiet ada)
        (should (equal (+test-awl--status project one) "open"))
        (should (eq (agent-workspace-agent-buffer ada) buffer))
        (should (string-suffix-p "half a thought" (with-current-buffer buffer (buffer-string))))
        ;; Sent, or deleted: it goes on.
        (with-current-buffer buffer
          (delete-region (- (point-max) (length "half a thought")) (point-max)))
        (agent-workspace--loop-look-all root)
        (should (+test-awl--wait (lambda () (equal (+test-awl--status project one) "closed"))))))))

(ert-deftest agent-workspace-loops/what-s-typed-asked-of-a-shell-only ()
  "An agent whose session buffer isn't agent-shell's (the tests' stand-in
buffers): nothing asked of agent-shell for its prompt's text, which would
offer to make a shell, and wait for the answer (the GUI's end-to-end tests
hung on it)."
  (let* ((buffer (generate-new-buffer "ada · builder"))
         (ada (agent-workspace--make-agent :name "ada" :role "builder" :state 'nap :buffer buffer))
         (asked nil))
    (unwind-protect
        (cl-letf (((symbol-function 'agent-shell--input) (lambda () (setq asked t) "typed")))
          (should-not (agent-workspace--loop-typed-p ada))
          (should-not asked))
      (kill-buffer buffer))))

;; ====== RENAMED ======

(ert-deftest agent-workspace-loops/renamed-its-issue-follows ()
  "ada, looping, at rest with her issue in progress, renamed ann: the issue
is ann's in bd, and her loop waits on it, taking no other (doom-pbk.64)."
  (+test-awl--with-crew "renamed"
    (let* ((held (+test-awl--issue project "hold: the lexer" "build" 1))
           (next (+test-awl--issue project "close: the parser" "build" 2))
           (ada (+test-awl--create "ada"))
           (root (agent-workspace-agent-project ada))
           (assignee (lambda (id)
                       (let ((default-directory project))
                         (alist-get 'assignee (car (json-parse-string (+test-awl--run "bd" "show" id "--json")
                                                                      :object-type 'alist :array-type 'list)))))))
      (agent-workspace-loop-set ada t)
      (should (+test-awl--wait (lambda () (eq (agent-workspace-agent-state ada) 'working))))
      (should (equal (funcall assignee held) "ada"))
      (agent-workspace-interrupt ada)
      (should (+test-awl--wait (lambda () (eq (agent-workspace-agent-state ada) 'desk))))
      (+test-awl--quiet ada)
      (agent-workspace-rename ada "ann")
      (should (equal (funcall assignee held) "ann"))
      (should (+test-awl--wait (lambda () (memq (agent-workspace-agent-state ada) '(desk done))) 20))
      (agent-workspace--loop-look-all root)
      (+test-awl--quiet ada)
      (should (equal (+test-awl--status project next) "open"))
      (should (equal (agent-workspace-agent-issue ada) held)))))

;; ====== HANDED BACK ======

(ert-deftest agent-workspace-loops/one-handed-back-first ()
  "An issue handed back to a looping builder (open, assigned to him: a
reviewer asking for changes) is the one he takes, before a higher priority
one nobody has; then that one (doom-pbk.58)."
  (+test-awl--with-crew "back"
    (let* ((urgent (+test-awl--issue project "close: urgent" "build" 0))
           (back (+test-awl--issue project "close: the changes asked" "build" 2))
           (ken (+test-awl--create "ken")))
      (let ((default-directory project))
        (+test-awl--run "bd" "update" back "--assignee" "ken"))
      (agent-workspace-loop-set ken t)
      (+test-awl--all-in (list ken) 'nap 90)
      (should (equal (+test-awl--prompts "ken")
                     (list (format "Work on %s: close: the changes asked" back)
                           (format "Work on %s: close: urgent" urgent))))
      (should (equal (+test-awl--status project back) "closed"))
      (should (equal (+test-awl--status project urgent) "closed")))))

(ert-deftest agent-workspace-loops/the-branch-held-by-one-at-work ()
  "ada hands her issue on to the reviewers while her turn still runs (on its
branch): looping rex claims it, finds its branch hers at work, gives it
back and waits, said once, no failure counted; her turn over, he takes it,
on its branch (doom-pbk.59)."
  (+test-awl--with-crew "held"
    (let* ((issue (+test-awl--issue project "the lexer" "build" 1))
           (ada (+test-awl--create "ada"))
           (rex (agent-workspace-create :role "reviewer" :name "rex" :kind 'mock)))
      (should (+test-awl--wait (lambda () (eq (agent-workspace-agent-state rex) 'desk)) 20))
      (agent-workspace-give ada issue "the lexer" "task")
      (let ((branch (agent-workspace-agent-branch ada)))
        (agent-workspace-send ada "hold, please" :submit t)
        (should (+test-awl--wait (lambda () (eq (agent-workspace-agent-state ada) 'working))))
        ;; Handed on, as she's told, her turn still running.
        (let ((default-directory project)
              (process-environment (cons "BEADS_ACTOR=ada" process-environment)))
          (+test-awl--run "bd" "update" issue "--remove-label" "build" "--add-label" "review"
                          "--status" "open" "--assignee" ""))
        (agent-workspace-loop-set rex t)
        (should (+test-awl--wait (lambda () (member (cons "note" (format "waits for ada to finish with %s" issue))
                                                    (+test-awl--room project "rex")))))
        (+test-awl--quiet rex)
        (agent-workspace--loop-changed (agent-workspace-agent-project rex))
        (+test-awl--sleep 1.5)
        (+test-awl--quiet rex)
        (should-not (agent-workspace--loop-get rex :failures))
        (should-not (agent-workspace--loop-get rex :stopped))
        (should-not (+test-awl--prompts "rex"))
        (should (= (seq-count (lambda (entry) (string-prefix-p "waits for ada" (cdr entry)))
                              (+test-awl--room project "rex"))
                   1))
        ;; Her turn over: he takes it, on its branch.
        (agent-workspace-interrupt ada)
        (should (+test-awl--wait (lambda () (member (format "Work on %s: the lexer" issue) (+test-awl--prompts "rex")))))
        (should (equal (agent-workspace-agent-branch rex) branch))
        (should-not (agent-workspace--loop-get rex :failures))))))

(ert-deftest agent-workspace-loops/its-role-broken-for-a-while ()
  "Its role's file saved mid-edit (its front matter not closed: no labels):
the loop pauses, said once, still on, crew.json keeping it; the file
mended, it goes on and takes the next issue (doom-pbk.60)."
  (+test-aw-with-four-starters
    (+test-awl--with-crew "role-broken"
      (let* ((file (expand-file-name ".agent-workspace/roles/tester.md" project))
             (good "---\nname: tester\ndescription: tests\nlabels: test\n---\nTest what you're given.\n"))
        (make-directory (file-name-directory file) t)
        (write-region good nil file)
        (let ((tia (agent-workspace-create :role "tester" :name "tia" :kind 'mock))
              (root nil))
          (should (+test-awl--wait (lambda () (eq (agent-workspace-agent-state tia) 'desk)) 20))
          (setq root (agent-workspace-agent-project tia))
          (agent-workspace-loop-set tia t)
          (+test-awl--all-in (list tia) 'nap)
          ;; Saved mid-edit.
          (write-region "---\nname: tester\nlabels: te" nil file)
          (set-file-times file (time-add nil 2))
          (agent-workspace--loop-look-all root)
          (+test-awl--quiet tia)
          (agent-workspace--loop-look-all root)
          (+test-awl--quiet tia)
          (should (agent-workspace-agent-loop tia))
          (should (eq (agent-workspace-agent-state tia) 'nap))
          (should (= (seq-count (lambda (entry) (string-prefix-p "⏸ paused: its role, tester" (cdr entry)))
                                (+test-awl--room project "tia"))
                     1))
          (should-not (seq-some (lambda (entry) (string-prefix-p "stopped looping" (cdr entry)))
                                (+test-awl--room project "tia")))
          (agent-workspace-crew-save project)
          (let ((tia (seq-find (lambda (entry) (equal (plist-get entry :name) "tia"))
                               (plist-get (json-parse-string (agent-workspace-crew-text project) :object-type 'plist
                                                             :array-type 'list)
                                          :agents))))
            (should (equal (plist-get tia :role) "tester"))
            (should (eq (plist-get tia :loop) t)))
          ;; Mended: it goes on.
          (write-region good nil file)
          (set-file-times file (time-add nil 4))
          (let ((one (+test-awl--issue project "close: one" "test" 2)))
            (agent-workspace--loop-look-all root)
            (should (+test-awl--wait (lambda () (equal (+test-awl--status project one) "closed"))))
            (should (member '("note" . "▶ goes on: its role, tester, has labels again") (+test-awl--room project "tia")))))))))

;; ====== AN ISSUE YOU GIVE ======

(ert-deftest agent-workspace-loops/an-issue-you-give-is-never-taken ()
  "An issue you give a busy agent (t, an offer) is claimed for it in bd at
once, its prompt queued: a looping agent waking doesn't take it, it naps.
Given to another agent then: refused, saying who has it, nothing sent, no
issue noted (doom-pbk.55)."
  (+test-awl--with-crew "given"
    (let* ((given (+test-awl--issue project "the lexer" "build" 1))
           (ken (+test-awl--create "ken"))
           (ada (+test-awl--create "ada")))
      (agent-workspace-send ken "hold" :submit t)
      (should (+test-awl--wait (lambda () (eq (agent-workspace-agent-state ken) 'working))))
      (should (eq (agent-workspace-give-issue ken given "the lexer" "task") 'queued))
      (should (equal (agent-workspace-agent-issue ken) given))
      (let ((issue (let ((default-directory project))
                     (car (json-parse-string (+test-awl--run "bd" "show" given "--json")
                                             :object-type 'alist :array-type 'list)))))
        (should (equal (alist-get 'status issue) "in_progress"))
        (should (equal (alist-get 'assignee issue) "ken")))
      ;; A looping builder wakes: nothing for it.
      (agent-workspace-loop-set ada t)
      (+test-awl--all-in (list ada) 'nap)
      (agent-workspace--loop-changed (agent-workspace-agent-project ada))
      (+test-awl--sleep 1)
      (+test-awl--quiet ada)
      (should (eq (agent-workspace-agent-state ada) 'nap))
      (should-not (agent-workspace-agent-issue ada))
      (should-not (+test-awl--prompts "ada"))
      ;; Given to her too: refused, saying who has it.
      (agent-workspace-loop-set ada nil)
      (should (+test-awl--wait (lambda () (memq (agent-workspace-agent-state ada) '(desk done)))))
      (should (equal (cadr (should-error (agent-workspace-give-issue ada given "the lexer" "task") :type 'user-error))
                     (format "%s not given to ada: issue already claimed by ken" given)))
      (should-not (agent-workspace-agent-issue ada))
      (should-not (+test-awl--prompts "ada"))
      (should (equal (agent-workspace-agent-issue ken) given)))))

;; Its runs counted; how it fails by $MODE.
(defconst +test-awl--moody-bd
  "#!/bin/sh
n=$(cat \"$0.count\" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > \"$0.count\"
case \"$MODE:$n\" in
  silent-then-claimed:1) exit 1;;
  silent-then-claimed:*) echo \"Error updating $2: issue already claimed by ken\" >&2; exit 1;;
  locked-twice:1|locked-twice:2) echo \"Error: database is locked\" >&2; exit 1;;
  locked-twice:*) exit 0;;
  silent:*) exit 1;;
  condition:*) exit 13;;
esac
"
  "A stand-in bd failing as $MODE says, its runs counted in bd.count.")

(ert-deftest agent-workspace-loops/bd-run-again-when-it-fails-for-a-moment ()
  "A claim bd fails for a moment (its database locked by another bd, or
nothing said, as once on a busy machine: \"bd failed\"): run again, three
times at most; its answer then is the claim's. Exit status 13 (an --if-
condition not met) is an answer: not run again."
  (let* ((project (file-name-as-directory (make-temp-file (+test-tmp-file "bd-again-") t)))
         (bin (file-name-as-directory (make-temp-file (+test-tmp-file "moody-bd-") t)))
         (bd (expand-file-name "bd" bin))
         (exec-path (cons bin exec-path))
         (ada (agent-workspace--make-agent :name "ada" :role "builder" :project project)))
    (make-directory (expand-file-name ".beads" project))
    (with-temp-file bd (insert +test-awl--moody-bd))
    (set-file-modes bd #o755)
    (cl-flet ((run (mode thunk)
                (delete-file (concat bd ".count"))
                (let ((process-environment (append (list (concat "MODE=" mode)
                                                         (concat "PATH=" bin path-separator (getenv "PATH")))
                                                   process-environment)))
                  (list (funcall thunk)
                        (string-to-number (with-temp-buffer (insert-file-contents (concat bd ".count"))
                                                            (buffer-string)))))))
      (should (equal (run "silent-then-claimed" (lambda () (agent-workspace--bd-claim ada "demo-1")))
                     '("issue already claimed by ken" 2)))
      (should (equal (run "locked-twice" (lambda () (agent-workspace--bd-claim ada "demo-1")))
                     '(nil 3)))
      (should (equal (run "silent" (lambda () (agent-workspace--bd-claim ada "demo-1")))
                     '("bd failed" 3)))
      (should (equal (run "condition" (lambda () (agent-workspace--bd-now project "ada" '("update" "demo-1" "--if-assignee=ada"))))
                     '((13 . "") 1))))))

(ert-deftest agent-workspace-loops/killed-it-gives-its-issue-back ()
  "K on an agent with the issue you gave it in progress, its: open again,
unassigned, in bd, given back as the agent; bd failing: said in the room,
in bd's words (doom-pbk.36)."
  (+test-awl--with-crew "give-back"
    (let* ((one (+test-awl--issue project "the lexer" "build" 1))
           (two (+test-awl--issue project "the parser" "build" 1))
           (ada (+test-awl--create "ada"))
           (ken (+test-awl--create "ken"))
           (show (lambda (id)
                   (let ((default-directory project))
                     (car (json-parse-string (+test-awl--run "bd" "show" id "--json")
                                             :object-type 'alist :array-type 'list))))))
      (agent-workspace-give-issue ada one "the lexer" "task")
      (should (equal (alist-get 'assignee (funcall show one)) "ada"))
      (agent-workspace-kill ada)
      (should (+test-awl--wait (lambda () (equal (alist-get 'status (funcall show one)) "open"))))
      (should-not (alist-get 'assignee (funcall show one)))
      ;; bd refusing: said.
      (agent-workspace-give-issue ken two "the parser" "task")
      (let* ((bin (file-name-as-directory (make-temp-file (+test-tmp-file "refusing-bd-") t)))
             (real (executable-find "bd"))
             (exec-path (cons bin exec-path))
             (process-environment (cons (concat "PATH=" bin path-separator (getenv "PATH")) process-environment)))
        (with-temp-file (expand-file-name "bd" bin)
          (insert "#!/bin/sh\ncase \"$*\" in *--if-assignee*) echo \"Error updating $2: the database is locked\" >&2; exit 1;; esac\nexec "
                  (shell-quote-argument real) " \"$@\"\n"))
        (set-file-modes (expand-file-name "bd" bin) #o755)
        (agent-workspace-kill ken)
        (should (+test-awl--wait
                 (lambda () (member (cons "note" (format "couldn't give %s back: Error updating %s: the database is locked"
                                                         two two))
                                    (+test-awl--room project "ken")))
                 20)))
      (should (equal (alist-get 'assignee (funcall show two)) "ken")))))

(ert-deftest agent-workspace-loops/forgotten-it-gives-its-issue-back ()
  "X (forgotten) on an agent with the issue you gave it in progress, its:
open again, unassigned, as K does (doom-pbk.111)."
  (+test-awl--with-crew "forget-give-back"
    (let* ((one (+test-awl--issue project "the lexer" "build" 1))
           (ada (+test-awl--create "ada"))
           (show (lambda (id)
                   (let ((default-directory project))
                     (car (json-parse-string (+test-awl--run "bd" "show" id "--json")
                                             :object-type 'alist :array-type 'list))))))
      (agent-workspace-give-issue ada one "the lexer" "task")
      (should (equal (alist-get 'assignee (funcall show one)) "ada"))
      (agent-workspace-forget ada 'keep)
      (should-not (agent-workspace-agents project))
      (should (+test-awl--wait (lambda () (equal (alist-get 'status (funcall show one)) "open"))))
      (should-not (alist-get 'assignee (funcall show one))))))

;; ====== MERGED, ITS ISSUE CLOSED ======

(defmacro +test-awl--git-user (&rest body)
  "BODY, git's commits and merges made as a test user (no ~/.gitconfig)."
  (declare (indent 0))
  `(let ((process-environment (append '("GIT_AUTHOR_NAME=T" "GIT_AUTHOR_EMAIL=t@t"
                                        "GIT_COMMITTER_NAME=T" "GIT_COMMITTER_EMAIL=t@t")
                                      process-environment)))
     ,@body))

(defun +test-awl--worked (agent file)
  "AGENT's worktree with FILE committed on its branch: its branch."
  (let ((default-directory (agent-workspace-agent-worktree agent)))
    (write-region "done\n" nil file)
    (+test-awl--run "git" "add" file)
    (+test-awl--run "git" "commit" "-q" "-m" (concat "ada's " file))
    (string-trim (+test-awl--run "git" "branch" "--show-current"))))

(ert-deftest agent-workspace-loops/merging-closes-the-issue ()
  "M on an issue's branch merges it and closes the issue, its reason naming
the branch, the room saying so; a forgotten agent's kept branch too. Not:
a branch of no issue, an issue closed already, with
`agent-workspace-close-on-merge' nil, a merge stopped on conflicts
\(doom-pbk.116)."
  (+test-awl--with-crew "merge-closes"
    (+test-awl--git-user
      (let* ((one (+test-awl--issue project "the lexer" "build" 1 "bug"))
             (two (+test-awl--issue project "the parser" "build" 1))
             (three (+test-awl--issue project "the docs" "build" 1))
             (ada (+test-awl--create "ada"))
             (reason (lambda (id)
                       (let ((default-directory project))
                         (alist-get 'close_reason (car (json-parse-string (+test-awl--run "bd" "show" id "--json")
                                                                          :object-type 'alist :array-type 'list)))))))
        ;; An issue's branch: merged, closed.
        (agent-workspace-give-issue ada one "the lexer" "bug")
        (let ((branch (+test-awl--worked ada "lexer")))
          (should (string-prefix-p (concat "fix/" one) branch))
          (should (agent-workspace-merge ada))
          (should (equal (+test-awl--status project one) "closed"))
          (should (equal (funcall reason one) (format "Merged %s into main" branch)))
          (should (member (cons "note" (format "merged %s into main: %s closed" branch one))
                          (+test-awl--room project "ada"))))
        ;; Off: merged, not closed.
        (let ((ken (+test-awl--create "ken")))
          (agent-workspace-give-issue ken two "the parser" "task")
          (+test-awl--worked ken "parser")
          (let ((agent-workspace-close-on-merge nil))
            (should (agent-workspace-merge ken))))
        (should (equal (+test-awl--status project two) "in_progress"))
        ;; Closed already: nothing more.
        (let* ((liz (+test-awl--create "liz"))
               (branch (progn (agent-workspace-give-issue liz three "the docs" "task")
                              (+test-awl--worked liz "docs"))))
          (let ((default-directory project))
            (+test-awl--run "bd" "close" three "--force" "--reason" "by hand"))
          (should (agent-workspace-merge liz))
          (should (equal (funcall reason three) "by hand"))
          (should-not (agent-workspace--branch-issue project "fix-the-parser"))
          (should-not (agent-workspace--branch-issue project "agent/ada"))
          (should (equal (car (agent-workspace--branch-issue project branch)) three)))))))

(ert-deftest agent-workspace-loops/a-kept-branch-merged-closes-its-issue ()
  "A forgotten agent's branch merged (the branches view's M) closes its issue;
a merge stopped on conflicts closes nothing."
  (+test-awl--with-crew "merge-kept"
    (+test-awl--git-user
      (let* ((one (+test-awl--issue project "the lexer" "build" 1 "bug"))
             (two (+test-awl--issue project "the parser" "build" 1 "bug"))
             (ada (+test-awl--create "ada"))
             (ken (+test-awl--create "ken")))
        (agent-workspace-give-issue ada one "the lexer" "bug")
        (let ((branch (+test-awl--worked ada "lexer")))
          (agent-workspace-forget ada 'keep)
          (should (agent-workspace-merge-kept project branch))
          (should (equal (+test-awl--status project one) "closed")))
        ;; Conflicts: README changed on both sides.
        (agent-workspace-give-issue ken two "the parser" "bug")
        (let ((default-directory (agent-workspace-agent-worktree ken)))
          (write-region "ken's\n" nil "README")
          (+test-awl--run "git" "commit" "-q" "-am" "ken's README"))
        (let ((default-directory project))
          (write-region "yours\n" nil "README")
          (+test-awl--run "git" "commit" "-q" "-am" "your README"))
        (should-not (agent-workspace-merge ken))
        (let ((default-directory project))
          (+test-awl--run "git" "merge" "--abort"))
        (should (equal (+test-awl--status project two) "in_progress"))))))

;; ====== THE SAVED CREW ======

(ert-deftest agent-workspace-loops/reopening-never-starts-one ()
  "Its loop in crew.json; the crew started again from it brings it back
asleep, still looping, its session not started, no issue taken; woken, it
takes one."
  (+test-awl--with-crew "reopen"
    (let ((ada (+test-awl--create "ada")))
      (agent-workspace-loop-set ada t)
      (+test-awl--all-in (list ada) 'nap)
      (agent-workspace-crew-save project)
      (should (equal (car (plist-get (car (agent-workspace-crew-read project)) :agents))
                     '(:name "ada" :role "builder" :colour "blue" :loop t :kind mock)))
      (agent-workspace-close project))
    (let ((one (+test-awl--issue project "close: one" "build" 2)))
      (should (agent-workspace--crew-start project))
      (let ((ada (agent-workspace-agent "ada" project)))
        (should (eq (agent-workspace-agent-state ada) 'asleep))
        (should (agent-workspace-agent-loop ada))
        (agent-workspace--loop-changed (agent-workspace-agent-project ada))
        (+test-awl--sleep 1.5)
        (should-not (agent-workspace-agent-buffer ada))
        (should (eq (agent-workspace-agent-state ada) 'asleep))
        (should (equal (+test-awl--status project one) "open"))
        ;; Asleep, looping: both in crew.json.
        (let ((entry (car (plist-get (json-parse-string (agent-workspace-crew-text project) :object-type 'plist
                                                        :array-type 'list)
                                     :agents))))
          (should (eq (plist-get entry :asleep) t))
          (should (eq (plist-get entry :loop) t)))
        ;; Woken: it loops.
        (agent-workspace-wake ada)
        (should (+test-awl--wait (lambda () (equal (+test-awl--status project one) "closed"))))))))
