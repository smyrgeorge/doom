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
(remove-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context)

(setq agent-shell-mock-agent-acp-command
      (list (expand-file-name invocation-name invocation-directory)
            "--batch" "-Q" (concat "--init-directory=" (+test-tmp-file "mock-acp-home/"))
            "-l" (expand-file-name "examples/agent-workspace/stand-in.el" +test-root) "-f" "mock-acp-main"))
(add-to-list 'agent-workspace-kinds '(mock :config agent-shell-mock-agent-make-agent-config))

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
            (should (equal (car (last (agent-workspace-activity-lane ada))) '(edit read)))
            (should (equal (with-temp-buffer
                             (insert-file-contents (expand-file-name "src/a.el" (agent-workspace-agent-worktree ada)))
                             (buffer-string))
                           "edited by the stand-in\n")))
        (agent-workspace-close-all)))))
