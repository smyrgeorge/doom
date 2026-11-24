;;; tests/unit/test-agent-workspace-activity.el -*- lexical-binding: t; -*-
;; config/agent-workspace/activity.el: what each agent did, minute by minute,
;; where it is, the files it changed and those two agents change. agent-shell's
;; events stood in for, then a stand-in agent's real ones
;; (examples/agent-workspace/stand-in.el) in a throwaway git repository.

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(require 'agent-shell)
(require 'agent-shell-mock-agent)
(+test-load "config/agent-shell" "config/agent-workspace")
(remove-hook '+my/agent-shell-context-functions #'+my/agent-shell-beads-context)

(setq agent-shell-mock-agent-acp-command
      (list (expand-file-name invocation-name invocation-directory)
            "--batch" "-Q" (concat "--init-directory=" (+test-tmp-file "mock-acp-home/"))
            "-l" (expand-file-name "examples/agent-workspace/stand-in.el" +test-root) "-f" "mock-acp-main"))
;; The stand-in's modes: Claude Code's, as it lists them; it starts in auto.
(add-to-list 'agent-workspace-kinds `(mock :config agent-shell-mock-agent-make-agent-config :modes ,agent-workspace-modes :mode "auto"))

;; ====== HELPERS ======

(defun +test-awa2--project ()
  "A git repository with a commit (README, src/a.el): its folder."
  (let ((dir (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file "awa2-") t)))))
    (let ((default-directory dir))
      (make-directory "src" t)
      (write-region "hello\n" nil "README")
      (write-region "(a)\n" nil "src/a.el")
      (call-process "git" nil nil nil "init" "-q" "-b" "main")
      (call-process "git" nil nil nil "add" ".")
      (call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-m" "first"))
    dir))

(defun +test-awa2--agent (project name)
  "An agent NAME of PROJECT's crew, its worktree made (no session)."
  (let ((agent (agent-workspace--make-agent :name name :role "builder" :colour "blue" :state 'desk
                                            :project project)))
    (agent-workspace-worktree-ensure agent)
    (puthash project (append (gethash project agent-workspace--crews) (list agent)) agent-workspace--crews)
    agent))

(defun +test-awa2--tool (agent kind &optional path line)
  "AGENT's tool call of KIND (ACP's), at PATH and LINE."
  (agent-workspace--activity-event
   agent `((:event . tool-call-update)
           (:data . ((:tool-call . ((:kind . ,kind)
                                    (:locations . ,(and path (vector `((path . ,path) (line . ,line))))))))))))

;; ====== TESTS ======

(ert-deftest agent-workspace-activity/minute-by-minute ()
  "Its tool calls and raised hands, by minute: what it did, where it is
now; only the last minutes kept; the lane oldest first."
  (let* ((agent-workspace--crews (make-hash-table :test #'equal))
         (agent-workspace--activity (make-hash-table :test #'eq :weakness 'key))
         (project (+test-awa2--project))
         (ada (+test-awa2--agent project "ada"))
         (now 6000000.0)
         (minute (lambda (n) (+ now (* 60 n)))))
    (cl-letf (((symbol-function 'float-time) (lambda (&rest _) now)))
      (+test-awa2--tool ada "read" (expand-file-name "src/a.el" (agent-workspace-agent-worktree ada)) 12)
      (+test-awa2--tool ada "search")
      (+test-awa2--tool ada "think")
      (setq now (funcall minute 2))
      (+test-awa2--tool ada "execute")
      (agent-workspace--activity-event ada '((:event . permission-request)))
      (+test-awa2--tool ada "unknown-kind")
      (should (equal (plist-get (agent-workspace-activity ada) :location) '("src/a.el" . 12)))
      (let ((lane (agent-workspace-activity-lane ada)))
        (should (= (length lane) agent-workspace-activity-minutes))
        (should (equal (car (last lane)) '(asked run)))
        (should (equal (nth (- agent-workspace-activity-minutes 3) lane) '(read)))
        (should-not (nth (- agent-workspace-activity-minutes 2) lane)))
      ;; Twenty minutes on: the old ones forgotten.
      (setq now (funcall minute 22))
      (+test-awa2--tool ada "edit" "/elsewhere/b.el" 1)
      (should (= (length (plist-get (agent-workspace-activity ada) :minutes)) 1))
      (should (equal (plist-get (agent-workspace-activity ada) :location) '("/elsewhere/b.el" . 1))))))

(ert-deftest agent-workspace-activity/no-git-on-emacs-s-thread ()
  "A turn's end, and a napping loop's look with nothing ready, run no git
Emacs waits for: what the turn changed is worked out in the background
\(doom-pbk.65)."
  (let* ((agent-workspace--crews (make-hash-table :test #'equal))
         (agent-workspace--activity (make-hash-table :test #'eq :weakness 'key))
         (project (+test-awa2--project))
         (ada (+test-awa2--agent project "ada"))
         (waited 0))
    (write-region "(a ada)\n" nil (expand-file-name "src/a.el" (agent-workspace-agent-worktree ada)))
    (cl-letf* ((process-file-real (symbol-function 'process-file))
               (call-process-real (symbol-function 'call-process))
               ((symbol-function 'process-file)
                (lambda (program &rest args) (when (equal program "git") (cl-incf waited)) (apply process-file-real program args)))
               ((symbol-function 'call-process)
                (lambda (program &rest args) (when (equal program "git") (cl-incf waited)) (apply call-process-real program args))))
      (agent-workspace--activity-event ada '((:event . turn-complete)))
      (should (= waited 0))
      (should (+test-wait-for (lambda () (plist-get (agent-workspace-activity ada) :changed)) 10))
      (should (equal (plist-get (agent-workspace-activity ada) :changed) '("src/a.el")))
      ;; A loop's claim asks bd only (git when it takes an issue).
      (setq waited 0)
      (cl-letf (((symbol-function 'agent-workspace--loop-labels) (lambda (_) '("build")))
                ((symbol-function 'agent-workspace--loop-bd) #'ignore))
        (agent-workspace--loop-claim ada))
      (should (= waited 0)))))

(ert-deftest agent-workspace-activity/a-path-in-its-worktree-by-its-name ()
  "A path in an agent's worktree is relative to it by its name, the file
system not asked: once, on a busy machine, `file-in-directory-p' said no
and the path stayed whole among its changed files. Elsewhere: as it is."
  (let* ((agent-workspace--crews (make-hash-table :test #'equal))
         (agent-workspace--activity (make-hash-table :test #'eq :weakness 'key))
         (project (+test-awa2--project))
         (ken (+test-awa2--agent project "ken"))
         (worktree (agent-workspace-agent-worktree ken)))
    (cl-letf (((symbol-function 'file-in-directory-p) #'ignore))
      (should (equal (agent-workspace--relative ken (expand-file-name "README" worktree)) "README"))
      (should (equal (agent-workspace--relative ken (expand-file-name "src/a.el" (directory-file-name worktree)))
                     "src/a.el"))
      (should (equal (agent-workspace--relative ken "src/b.el") "src/b.el"))
      (should (equal (agent-workspace--relative ken "/elsewhere/b.el") "/elsewhere/b.el"))
      (agent-workspace--activity-event
       ken `((:event . file-write) (:data . ((:path . ,(expand-file-name "README" worktree))))))
      (should (equal (plist-get (agent-workspace-activity ken) :changed) '("README"))))))

(ert-deftest agent-workspace-activity/two-agents-in-one-file ()
  "The files each agent changed (written, its branch, uncommitted); one two
of them changed, a conflict."
  (let* ((agent-workspace--crews (make-hash-table :test #'equal))
         (agent-workspace--activity (make-hash-table :test #'eq :weakness 'key))
         (project (+test-awa2--project))
         (ada (+test-awa2--agent project "ada"))
         (ken (+test-awa2--agent project "ken")))
    ;; ada commits a change to src/a.el; ken leaves one to it uncommitted.
    (let ((default-directory (agent-workspace-agent-worktree ada)))
      (write-region "(a ada)\n" nil "src/a.el")
      (call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-am" "ada's"))
    (write-region "(a ken)\n" nil (expand-file-name "src/a.el" (agent-workspace-agent-worktree ken)))
    (agent-workspace--activity-event ada '((:event . turn-complete)))
    (agent-workspace--activity-event ken '((:event . turn-complete)))
    ;; Written while git works out what its turn changed: kept (doom-pbk.65).
    (agent-workspace--activity-event
     ken `((:event . file-write) (:data . ((:path . ,(expand-file-name "README" (agent-workspace-agent-worktree ken)))))))
    ;; Worked out in the background.
    (should (+test-wait-for (lambda () (and (plist-get (agent-workspace-activity ada) :changed)
                                            (member "src/a.el" (plist-get (agent-workspace-activity ken) :changed))))
                            10))
    (should (equal (plist-get (agent-workspace-activity ada) :changed) '("src/a.el")))
    (should (equal (sort (copy-sequence (plist-get (agent-workspace-activity ken) :changed)) #'string<)
                   '("README" "src/a.el")))
    (should (equal (agent-workspace-conflicts project) (list (list "src/a.el" ada ken))))))

(defun +test-awa2--commit (agent &rest files)
  "FILES changed in AGENT's worktree, committed on the branch it's on."
  (let ((default-directory (agent-workspace-agent-worktree agent)))
    (dolist (file files)
      (write-region (format "(%s)\n" (agent-workspace-agent-name agent)) nil file))
    (call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-am"
                  (agent-workspace-agent-name agent))))

(defun +test-awa2--changed (agent)
  "AGENT's changed files, sorted."
  (sort (copy-sequence (plist-get (agent-workspace-activity agent) :changed)) #'string<))

(defun +test-awa2--settled (&rest agents)
  "Non-nil once git works out none of AGENTS' changed files, nor any
agent's (an earlier run, its answer to come)."
  (and (seq-every-p (lambda (agent) (not (gethash agent agent-workspace--changes-since))) agents)
       (not (seq-some (lambda (process) (string-prefix-p "agent-workspace-changes" (process-name process)))
                      (process-list)))))

(ert-deftest agent-workspace-activity/a-reviewer-on-its-builder-s-branch ()
  "A reviewer on its builder's branch: no ⚠ with that builder, one branch
can't conflict with itself; nor once it's taken back, the reviewer's turn
having ended on it: its files dropped at once, and that turn's answer
from git, come later, dropped too (doom-pbk.133)."
  (let* ((agent-workspace--crews (make-hash-table :test #'equal))
         (agent-workspace--activity (make-hash-table :test #'eq :weakness 'key))
         (agent-workspace--changes-since (make-hash-table :test #'eq :weakness 'key))
         (project (+test-awa2--project))
         (grace (+test-awa2--agent project "grace"))
         (linus (+test-awa2--agent project "linus"))
         (files '("README" "src/a.el")))
    (agent-workspace--branch-switch grace "feat/x" "main")
    (+test-awa2--commit grace "README" "src/a.el")
    (agent-workspace--activity-event grace '((:event . turn-complete)))
    (should (+test-wait-for (lambda () (equal (+test-awa2--changed grace) files)) 10))
    ;; linus takes it for its review: grace rests, her files dropped at once.
    (agent-workspace-branch-open linus "feat/x")
    (should (equal (agent-workspace-agent-branch grace) "agent/grace"))
    (should-not (plist-get (agent-workspace-activity grace) :changed))
    (should (+test-wait-for (lambda () (and (equal (+test-awa2--changed linus) files)
                                            (+test-awa2--settled grace linus)))
                            10))
    (should-not (plist-get (agent-workspace-activity grace) :changed))
    (should-not (agent-workspace-conflicts project))
    ;; Its review over, its turn ends on her branch; she takes it back.
    (agent-workspace--activity-event linus '((:event . turn-complete)))
    (agent-workspace-branch-open grace "feat/x")
    (should (equal (agent-workspace-agent-branch linus) "agent/linus"))
    (should-not (plist-get (agent-workspace-activity linus) :changed))
    (should-not (agent-workspace-conflicts project))
    (should (+test-wait-for (lambda () (and (equal (+test-awa2--changed grace) files)
                                            (+test-awa2--settled grace linus)))
                            10))
    ;; The turn's git, answered meanwhile (before or after), dropped.
    (should-not (plist-get (agent-workspace-activity linus) :changed))
    (should-not (agent-workspace-conflicts project))
    ;; linus checks her branch out itself (beside hers): both on it, no ⚠.
    (let ((default-directory (agent-workspace-agent-worktree linus)))
      (call-process "git" nil nil nil "switch" "--quiet" "--ignore-other-worktrees" "feat/x"))
    (agent-workspace--branch-sync linus)
    (should (+test-wait-for (lambda () (and (equal (+test-awa2--changed linus) files)
                                            (+test-awa2--settled linus)))
                            10))
    (should (equal (+test-awa2--changed grace) files))
    (should-not (agent-workspace-conflicts project))))

(ert-deftest agent-workspace-activity/two-branches-in-one-file ()
  "A file changed on two different branches, or uncommitted in two
worktrees on no branch: ⚠, every agent that changed it; agents on one
branch among them (doom-pbk.133)."
  (let* ((agent-workspace--crews (make-hash-table :test #'equal))
         (agent-workspace--activity (make-hash-table :test #'eq :weakness 'key))
         (agent-workspace--changes-since (make-hash-table :test #'eq :weakness 'key))
         (project (+test-awa2--project))
         (ada (+test-awa2--agent project "ada"))
         (ken (+test-awa2--agent project "ken"))
         (liz (+test-awa2--agent project "liz"))
         (sam (+test-awa2--agent project "sam"))
         (zoe (+test-awa2--agent project "zoe")))
    (agent-workspace--branch-switch ada "feat/one" "main")
    (agent-workspace--branch-switch ken "fix/two" "main")
    (+test-awa2--commit ada "src/a.el")
    (+test-awa2--commit ken "src/a.el")
    ;; liz on ken's branch: one with him.
    (let ((default-directory (agent-workspace-agent-worktree liz)))
      (call-process "git" nil nil nil "switch" "--quiet" "--ignore-other-worktrees" "fix/two"))
    ;; sam and zoe on no branch, README not committed in either.
    (dolist (agent (list sam zoe))
      (let ((default-directory (agent-workspace-agent-worktree agent)))
        (call-process "git" nil nil nil "switch" "--quiet" "--detach")
        (write-region "hi\n" nil "README")))
    (dolist (agent (list ada ken liz sam zoe))
      (agent-workspace--branch-sync agent)
      (agent-workspace--activity-event agent '((:event . turn-complete))))
    (should (+test-wait-for (lambda () (apply #'+test-awa2--settled (list ada ken liz sam zoe))) 10))
    (should-not (agent-workspace-agent-branch sam))
    (should (equal (agent-workspace-conflicts project)
                   (list (list "README" sam zoe) (list "src/a.el" ada ken liz))))
    ;; ada and ken only: ken and liz on one branch, no ⚠ between them.
    (puthash project (list ken liz) agent-workspace--crews)
    (should-not (agent-workspace-conflicts project))))

(ert-deftest agent-workspace-activity/a-stand-in-agent-s-own ()
  "A stand-in agent reads a file, then edits one (agent-shell writing it):
its minutes, its location, its changed file, from agent-shell's events."
  (+test-with-reset
    (let* ((project (+test-awa2--project))
           (default-directory project)
           (agent-workspace--crews (make-hash-table :test #'equal)))
      (unwind-protect
          (let ((ada (agent-workspace-create :role "builder" :name "ada" :kind 'mock)))
            (should (+test-wait-for (lambda () (eq (agent-workspace-agent-state ada) 'desk)) 20))
            (agent-workspace-send ada (concat "read " (expand-file-name "README" (agent-workspace-agent-worktree ada)))
                                  :submit t)
            (should (+test-wait-for (lambda () (plist-get (agent-workspace-activity ada) :location)) 20))
            (should (equal (plist-get (agent-workspace-activity ada) :location) '("README" . 3)))
            (should (+test-wait-for (lambda () (memq (agent-workspace-agent-state ada) '(done desk))) 20))
            (agent-workspace-send ada (concat "edit " (expand-file-name "src/a.el" (agent-workspace-agent-worktree ada)))
                                  :submit t)
            (should (+test-wait-for (lambda () (member "src/a.el" (plist-get (agent-workspace-activity ada) :changed))) 20))
            ;; Its read, then its edit, in the same minute or the next: the
            ;; clock's minute may turn between them (or before this looks).
            (let* ((lane (agent-workspace-activity-lane ada))
                   (read (cl-position-if (lambda (kinds) (memq 'read kinds)) lane))
                   (edit (cl-position-if (lambda (kinds) (memq 'edit kinds)) lane)))
              (should (equal (sort (delete-dups (apply #'append lane)) #'string<) '(edit read)))
              (should (and read edit (<= 0 (- edit read) 1))))
            (should (equal (with-temp-buffer
                             (insert-file-contents (expand-file-name "src/a.el" (agent-workspace-agent-worktree ada)))
                             (buffer-string))
                           "edited by the stand-in\n")))
        (agent-workspace-close-all)))))
