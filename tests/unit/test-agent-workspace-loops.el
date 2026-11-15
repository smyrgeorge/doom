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

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(require 'agent-shell)
(require 'agent-shell-mock-agent)
(require 'json)
(+test-load "config/agent-shell" "config/agent-ui" "config/agent-workspace")
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

;; ====== THE SAVED CREW ======

(ert-deftest agent-workspace-loops/reopening-never-starts-one ()
  "Its loop in crew.el; the crew started again from it brings it back
asleep, still looping, its session not started, no issue taken; woken, it
takes one."
  (+test-awl--with-crew "reopen"
    (let ((ada (+test-awl--create "ada")))
      (agent-workspace-loop-set ada t)
      (+test-awl--all-in (list ada) 'nap)
      (agent-workspace-crew-save project)
      (should (string-search "(:name \"ada\" :role \"builder\" :colour \"blue\" :loop t :kind mock)"
                             (with-temp-buffer
                               (insert-file-contents (expand-file-name ".agent-workspace/crew.el" project))
                               (buffer-string))))
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
        ;; Asleep, looping: both in crew.el.
        (should (string-search ":asleep t :loop t" (agent-workspace-crew-text project)))
        ;; Woken: it loops.
        (agent-workspace-wake ada)
        (should (+test-awl--wait (lambda () (equal (+test-awl--status project one) "closed"))))))))
