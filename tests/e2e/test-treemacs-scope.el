;;; tests/e2e/test-treemacs-scope.el -*- lexical-binding: t; -*-
;; config/treemacs/scope.el in a GUI Emacs, with persp-mode's workspaces and
;; treemacs-persp's scope, as Doom has them: a workspace's sidebar its own. A
;; new workspace showing a project file before treemacs-persp's timer (the
;; sidebar opened there at once: config/treemacs/follow.el's auto-open) gets
;; its own treemacs workspace, another's untouched; the nil workspace too; a
;; workspace renamed to a name another treemacs workspace had: one of it.

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(let ((build (file-name-directory
              (directory-file-name (file-name-directory (locate-library "treemacs"))))))
  (load (expand-file-name "treemacs/treemacs-autoloads" build) t t))

(setq treemacs-persist-file (+test-tmp-file "treemacs/persist")
      treemacs-last-error-persist-file (+test-tmp-file "treemacs/last-error"))

(+test-load "config/window" "config/treemacs")

(require 'treemacs)
(treemacs-git-mode -1)
(treemacs-filewatch-mode -1)
(when (timerp +my/treemacs--git-poll-timer)
  (cancel-timer +my/treemacs--git-poll-timer))
;; As Doom: a project's root found by projectile; workspaces persp-mode's, a
;; sidebar each (treemacs-persp).
(require 'projectile)
(projectile-mode 1)
(require 'persp-mode)
(setq persp-auto-resume-time -1
      persp-auto-save-opt 0
      persp-save-dir (+test-tmp-file "persp/"))
(persp-mode 1)
(require 'treemacs-persp)
(treemacs-set-scope-type 'Perspectives)

;; ====== HELPERS ======

(defun +test-tms--project (name)
  "A git repository NAME (a commit, a folder): its folder."
  (let ((dir (file-name-as-directory (file-truename (make-temp-file (+test-tmp-file (concat name "-")) t)))))
    (let ((default-directory dir))
      (call-process "git" nil nil nil "init" "-q" "-b" "main")
      (make-directory "src" t)
      (write-region "x\n" nil "src/a.txt")
      (write-region "hello\n" nil "README")
      (call-process "git" nil nil nil "add" ".")
      (call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-m" "first"))
    dir))

(defun +test-tms--workspaces (name)
  "The treemacs workspaces named NAME."
  (seq-filter (lambda (ws) (equal (treemacs-workspace->name ws) name)) treemacs--workspaces))

(defun +test-tms--projects (name)
  "The project folders of the treemacs workspace named NAME."
  (mapcar #'treemacs-project->path (treemacs-workspace->projects (car (+test-tms--workspaces name)))))

(defun +test-tms--first (name)
  "The treemacs workspace named NAME first in the list, as the user's was
\(the one taken by a scope with none: the bug's)."
  (let ((ws (car (+test-tms--workspaces name))))
    (setq treemacs--workspaces (cons ws (delq ws treemacs--workspaces)))))

(defmacro +test-tms (&rest body)
  "BODY in a frame of its own windows, workspaces and treemacs's sidebars
put back after: the persp workspaces it made killed, the frame in the nil
workspace."
  (declare (indent 0))
  `(let ((persps (persp-names)))
     (+test-e2e-frame-reset)
     (delete-other-windows)
     (unwind-protect (progn ,@body)
       (persp-frame-switch persp-nil-name)
       (dolist (name (persp-names))
         (unless (member name persps) (persp-kill name)))
       (delete-other-windows))))

;; ====== TESTS ======

(ert-deftest e2e-treemacs-scope/a-new-workspace-gets-its-own ()
  "A workspace on project A, its sidebar opened on its file; a new workspace
showing B's file at once, its sidebar opened before treemacs-persp's timer
\(as redisplay runs the auto-open, before it): its own treemacs workspace
\(B), A's untouched. Before, the new one took the first in the list, A's,
and replaced its project: A's sidebar showed B."
  (let ((a (+test-tms--project "a"))
        (b (+test-tms--project "b")))
    (+test-tms
      (persp-add-new "ws-a")
      (persp-frame-switch "ws-a")
      (+test-sleep 0.3)
      (find-file (expand-file-name "README" a))
      (+test-sleep 0.8)
      (should (equal (+test-tms--projects "Perspective ws-a") (list (directory-file-name a))))
      (+test-tms--first "Perspective ws-a")
      (persp-add-new "ws-b")
      (persp-frame-switch "ws-b")
      (find-file (expand-file-name "README" b))
      (+my/treemacs-auto-open-h)
      (+test-sleep 0.8)
      (should (equal (+test-tms--projects "Perspective ws-a") (list (directory-file-name a))))
      (should (equal (+test-tms--projects "Perspective ws-b") (list (directory-file-name b))))
      (should (= (length (+test-tms--workspaces "Perspective ws-b")) 1)))))

(ert-deftest e2e-treemacs-scope/the-nil-workspace-its-own ()
  "The nil workspace (child frames, a new frame not in one yet) with no
treemacs workspace yet: its own (\"No Perspective\"), never the first in the
list, another workspace's."
  (let ((a (+test-tms--project "a")))
    (+test-tms
      (persp-add-new "ws-c")
      (persp-frame-switch "ws-c")
      (find-file (expand-file-name "README" a))
      (+test-sleep 0.8)
      (+test-tms--first "Perspective ws-c")
      (persp-frame-switch persp-nil-name)
      (setq treemacs--scope-storage (assq-delete-all 'none treemacs--scope-storage))
      (should (equal (treemacs-workspace->name (treemacs-current-workspace)) "No Perspective"))
      (should (equal (+test-tms--projects "Perspective ws-c") (list (directory-file-name a)))))))

(ert-deftest e2e-treemacs-scope/renamed-to-a-taken-name ()
  "A workspace renamed (Doom's \"#1\" named after its project) to a name a
treemacs workspace has already (left from an earlier session): one of that
name after, the renamed workspace's, its projects kept."
  (let ((a (+test-tms--project "a")))
    (+test-tms
      (treemacs-do-create-workspace "Perspective ws-d")
      (persp-add-new "#9")
      (persp-frame-switch "#9")
      (find-file (expand-file-name "README" a))
      (+test-sleep 0.8)
      (should (equal (+test-tms--projects "Perspective #9") (list (directory-file-name a))))
      (persp-rename "ws-d" (get-current-persp))
      (+test-sleep 0.3)
      (should (= (length (+test-tms--workspaces "Perspective ws-d")) 1))
      (should (equal (+test-tms--projects "Perspective ws-d") (list (directory-file-name a))))
      (should-not (+test-tms--workspaces "Perspective #9")))))
