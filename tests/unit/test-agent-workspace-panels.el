;;; tests/unit/test-agent-workspace-panels.el -*- lexical-binding: t; -*-
;; config/agent-workspace/panels.el: an agent's panels. A project panel
;; opened from two agents' worktrees: one each, named after them, never
;; shown in a pane; trusted as their project; closed when the agent is put to
;; sleep or killed, kept across a restart; yours from the main checkout its
;; own. In a throwaway git repository; sessions are plain buffers.

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(require 'agent-shell)
(+test-load "config/agent-ui" "config/agent-workspace")

(defconst +test-awp--panel
  ";;; tests.el --- Agent UI panel -*- lexical-binding: t; -*-
(agent-ui-panel
 :version 1
 :ui (:type \"text\" :id \"t\" :text \"\")
 :every 60
 :fetch (lambda (panel) (agent-ui-panel-update panel \"t\" :text default-directory)))
"
  "A panel showing where it runs.")

(defmacro +test-awp (&rest body)
  "BODY in a project with a committed panel, tests (`project'), its crew of
ada and ken (agents' sessions plain buffers), the trust file the test's own;
its panels and crew closed after."
  (declare (indent 0))
  `(+test-with-reset
     (let* ((project (file-name-as-directory
                      (file-truename (make-temp-file (+test-tmp-file "awp-") t))))
            (default-directory project)
            (agent-ui-panel-trust-file (+test-tmp-file (format "awp-trust-%s.eld" (random 100000))))
            (agent-workspace--crews (make-hash-table :test #'equal)))
       (make-directory (expand-file-name ".agent-ui/panels" project) t)
       (with-temp-file (expand-file-name ".agent-ui/panels/tests.el" project) (insert +test-awp--panel))
       (call-process "git" nil nil nil "init" "-q" "-b" "main")
       (call-process "git" nil nil nil "add" ".")
       (call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-m" "first")
       (cl-letf (((symbol-function 'agent-workspace--start)
                  (lambda (agent)
                    (let ((buffer (get-buffer-create (agent-workspace-buffer-name agent))))
                      (with-current-buffer buffer (setq agent-workspace--agent agent))
                      (setf (agent-workspace-agent-buffer agent) buffer)
                      (agent-workspace--set-state agent 'desk)
                      buffer)))
                 ((symbol-function 'agent-workspace--stop)
                  (lambda (agent state &rest _)
                    (when (buffer-live-p (agent-workspace-agent-buffer agent))
                      (kill-buffer (agent-workspace-agent-buffer agent)))
                    (setf (agent-workspace-agent-buffer agent) nil)
                    (agent-workspace--set-state agent state)
                    nil)))
         (unwind-protect
             (let ((ada (agent-workspace-create :role "builder" :name "ada"))
                   (ken (agent-workspace-create :role "builder" :name "ken")))
               ,@body)
           (agent-workspace-close-all)
           (dolist (buffer (buffer-list))
             (when (buffer-local-value 'agent-ui-panels--state buffer)
               (kill-buffer buffer))))))))

(defun +test-awp--open (dir)
  "Panel tests opened as an agent's request opens it, from DIR."
  (agent-ui-open-panel "tests" dir t))

(ert-deftest agent-workspace-panels/one-each-in-its-worktree ()
  "Opened from two agents' worktrees: one each, \"tests · ada\" and \"tests ·
ken\", rooted there, shown in no pane; theirs; yours from the main checkout
its own, shown."
  (+test-awp
    (agent-ui-panel-trust-project project)
    (let ((a (+test-awp--open (agent-workspace-agent-worktree ada)))
          (k (+test-awp--open (agent-workspace-agent-worktree ken)))
          (mine (+test-awp--open project)))
      (should (equal (mapcar #'buffer-name (list a k mine))
                     (list "Agent UI: tests · ada" "Agent UI: tests · ken"
                           (format "Agent UI: tests (%s)" (file-name-nondirectory (directory-file-name project))))))
      (should (equal (file-truename (agent-ui-panels--root (buffer-local-value 'agent-ui-panels--state a)))
                     (file-truename (agent-workspace-agent-worktree ada))))
      (should-not (get-buffer-window a t))
      (should-not (get-buffer-window k t))
      (should (get-buffer-window mine t))
      (should (equal (agent-workspace-agent-panels ada) (list a)))
      (should (equal (agent-workspace-agent-panels ken) (list k)))
      (should (eq (agent-workspace--panel-agent a) ada))
      (should-not (agent-workspace--panel-agent mine))
      ;; Opened again: the same one.
      (should (eq (+test-awp--open (agent-workspace-agent-worktree ada)) a))
      ;; Its --panel requests find it by its name, from its worktree.
      (should (eq (agent-ui-panel-canvas "tests" (agent-workspace-agent-worktree ada)) a)))))

(ert-deftest agent-workspace-panels/trusted-as-its-project ()
  "A worktree's panels share its project's trust; its file changed on the
agent's branch is asked about again unless the project is trusted."
  (+test-awp
    (let ((file (expand-file-name ".agent-ui/panels/tests.el" (agent-workspace-agent-worktree ada))))
      (should-not (agent-ui-panel-trusted-p file))
      ;; Its content let run (from the main checkout): the same in the worktree.
      (agent-ui-panel-trust (expand-file-name ".agent-ui/panels/tests.el" project))
      (should (agent-ui-panel-trusted-p file))
      ;; Changed on ada's branch: asked again.
      (write-region "\n;; changed\n" nil file t)
      (should-not (agent-ui-panel-trusted-p file))
      ;; The project trusted (asked from the worktree's panel: p): the
      ;; worktree's too, and the project's root remembered.
      (agent-ui-panel-trust-project (agent-workspace-agent-worktree ada))
      (should (agent-ui-panel-trusted-p file))
      (should (agent-ui-panel-project-trusted-p project))
      (should (equal (mapcar #'car (agent-ui-panel-trusted-projects)) (list project))))))

(ert-deftest agent-workspace-panels/closed-with-its-agent ()
  "Put to sleep or killed, an agent's panels close; a restart keeps them;
another agent's stay."
  (+test-awp
    (agent-ui-panel-trust-project project)
    (let ((a (+test-awp--open (agent-workspace-agent-worktree ada)))
          (k (+test-awp--open (agent-workspace-agent-worktree ken))))
      (agent-workspace-restart ada)
      (should (buffer-live-p a))
      (agent-workspace-sleep ada)
      (should-not (buffer-live-p a))
      (should (buffer-live-p k))
      (agent-workspace-kill ken)
      (should-not (buffer-live-p k)))))

(ert-deftest agent-workspace-panels/said-as-they-open-and-close ()
  "One opened or closed: said to `agent-workspace-change-functions' (its
pane, its bar, crew.el follow it)."
  (+test-awp
    (agent-ui-panel-trust-project project)
    (let* ((whats nil)
           (agent-workspace-change-functions (list (lambda (agent what) (push (cons (agent-workspace-agent-name agent) what) whats))))
           (a (+test-awp--open (agent-workspace-agent-worktree ada))))
      (should (member '("ada" . panels) whats))
      (setq whats nil)
      (kill-buffer a)
      (+test-sleep 0.05)
      (should (member '("ada" . panels) whats)))))
