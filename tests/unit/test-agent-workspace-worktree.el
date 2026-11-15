;;; tests/unit/test-agent-workspace-worktree.el -*- lexical-binding: t; -*-
;; config/agent-workspace/worktree.el: every agent's own git worktree, named
;; after it (.agent-shell/worktrees/NAME, agent/NAME), in throwaway git
;; repositories; a crew's project found from them.

;; Git as git is, not as your ~/.gitconfig has it (hooks, signing...).
(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(+test-load "config/agent-workspace/core" "config/agent-workspace/worktree")

;; ====== HELPERS ======

(defun +test-aww--git (&rest args)
  "Run git with ARGS in `default-directory'; its output."
  (with-temp-buffer
    (unless (eql 0 (apply #'call-process "git" nil t nil args))
      (error "git %S: %s" args (buffer-string)))
    (string-trim (buffer-string))))

(defun +test-aww--commit (message)
  "Commit what's staged, MESSAGE."
  (+test-aww--git "-c" "user.name=Test" "-c" "user.email=test@example.com" "commit" "-q" "-m" message))

(defun +test-aww--project (name &optional gitignore)
  "A git repository NAME in the temp folder, with a commit (GITIGNORE: a
.gitignore with it): its folder (its true name)."
  (let ((dir (file-name-as-directory (expand-file-name (concat "aww/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (+test-aww--git "init" "-q" "-b" "main")
      (write-region "hello\n" nil (expand-file-name "README" dir))
      (when gitignore (write-region gitignore nil (expand-file-name ".gitignore" dir)))
      (+test-aww--git "add" ".")
      (+test-aww--commit "first"))
    (file-name-as-directory (file-truename dir))))

(defun +test-aww--agent (project name)
  "An agent NAME of PROJECT's crew (a record: no session)."
  (agent-workspace--make-agent :name name :role "builder" :colour "blue" :project project))

(defun +test-aww--exclude (project)
  "PROJECT's info/exclude."
  (let ((file (expand-file-name ".git/info/exclude" project)))
    (if (file-exists-p file)
        (with-temp-buffer (insert-file-contents file) (buffer-string))
      "")))

;; ====== MAKING ONE ======

(ert-deftest agent-workspace-worktree/made-named-after-it ()
  "Its worktree: .agent-shell/worktrees/NAME, on a new branch agent/NAME
from the project's HEAD; the project's checkout untouched."
  (let* ((project (+test-aww--project "made"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent)))
    (should (equal dir (expand-file-name ".agent-shell/worktrees/ada/" project)))
    (should (equal (agent-workspace-agent-worktree agent) dir))
    (should (equal (agent-workspace-agent-branch agent) "agent/ada"))
    (should (file-exists-p (expand-file-name "README" dir)))
    (let ((default-directory dir))
      (should (equal (+test-aww--git "branch" "--show-current") "agent/ada")))
    (let ((default-directory project))
      (should (equal (+test-aww--git "branch" "--show-current") "main"))
      ;; Nothing new in the project: .agent-shell/ kept out of git.
      (should (equal (+test-aww--git "status" "--porcelain") ""))
      (should (equal (+test-aww--git "rev-parse" "agent/ada") (+test-aww--git "rev-parse" "main"))))))

(ert-deftest agent-workspace-worktree/kept-out-of-git ()
  ".agent-shell/ goes in the repository's info/exclude once, when no
.gitignore keeps it out; with one that does, nothing is added."
  (let ((project (+test-aww--project "exclude")))
    (agent-workspace-worktree-ensure (+test-aww--agent project "ada"))
    (agent-workspace-worktree-ensure (+test-aww--agent project "grace"))
    (should (= (cl-count "/.agent-shell/" (split-string (+test-aww--exclude project) "\n") :test #'equal) 1))
    ;; In the agent's worktree too (it shares info/exclude).
    (let ((default-directory (expand-file-name ".agent-shell/worktrees/ada/" project)))
      (make-directory ".agent-shell/transcripts" t)
      (write-region "x" nil ".agent-shell/transcripts/a.md")
      (should (equal (+test-aww--git "status" "--porcelain") ""))))
  (let ((project (+test-aww--project "ignored" "/.agent-shell/\n")))
    (agent-workspace-worktree-ensure (+test-aww--agent project "ada"))
    (should-not (string-search ".agent-shell" (+test-aww--exclude project)))))

(ert-deftest agent-workspace-worktree/reused ()
  "There already: reused as it is, its work kept."
  (let* ((project (+test-aww--project "reused"))
         (dir (agent-workspace-worktree-ensure (+test-aww--agent project "ada"))))
    (write-region "work in progress\n" nil (expand-file-name "wip" dir))
    (should (equal (agent-workspace-worktree-ensure (+test-aww--agent project "ada")) dir))
    (should (file-exists-p (expand-file-name "wip" dir)))))

(ert-deftest agent-workspace-worktree/its-branch-reused ()
  "Its folder gone (removed, or deleted by hand), its branch is checked out
again, with its commits."
  (let* ((project (+test-aww--project "branch"))
         (dir (agent-workspace-worktree-ensure (+test-aww--agent project "ada"))))
    (let ((default-directory dir))
      (write-region "done\n" nil "work")
      (+test-aww--git "add" "work")
      (+test-aww--commit "ada's work"))
    ;; Deleted by hand: still registered with git.
    (delete-directory dir t)
    (should (equal (agent-workspace-worktree-ensure (+test-aww--agent project "ada")) dir))
    (should (file-exists-p (expand-file-name "work" dir)))
    ;; Removed with git.
    (let ((default-directory project))
      (+test-aww--git "worktree" "remove" "--force" (directory-file-name dir)))
    (agent-workspace-worktree-ensure (+test-aww--agent project "ada"))
    (should (file-exists-p (expand-file-name "work" dir)))))

(ert-deftest agent-workspace-worktree/git-s-refusal-said ()
  "git refusing: a user error with what it said."
  (let* ((project (+test-aww--project "refused"))
         (agent (+test-aww--agent project "ada")))
    ;; A file where its folder goes.
    (make-directory (expand-file-name ".agent-shell/worktrees/" project) t)
    (write-region "" nil (expand-file-name ".agent-shell/worktrees/ada" project))
    (should-error (agent-workspace-worktree-ensure agent) :type 'user-error)))

(ert-deftest agent-workspace-worktree/renamed ()
  "Renamed: its worktree moved and its branch renamed, its work kept."
  (let* ((project (+test-aww--project "renamed"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent)))
    (write-region "wip\n" nil (expand-file-name "wip" dir))
    (agent-workspace-worktree-rename agent "grace")
    (let ((new (expand-file-name ".agent-shell/worktrees/grace/" project)))
      (should (equal (agent-workspace-agent-worktree agent) new))
      (should (equal (agent-workspace-agent-branch agent) "agent/grace"))
      (should-not (file-exists-p dir))
      (should (file-exists-p (expand-file-name "wip" new)))
      (let ((default-directory new))
        (should (equal (+test-aww--git "branch" "--show-current") "agent/grace")))
      (let ((default-directory project))
        (should-not (string-search "agent/ada" (+test-aww--git "branch" "--list")))))))

;; ====== A CREW'S PROJECT ======

(ert-deftest agent-workspace-worktree/the-project ()
  "A crew's project: the repository's main checkout, from inside it, a
folder of it, or an agent's worktree; none outside git."
  (let* ((project (+test-aww--project "project"))
         (dir (agent-workspace-worktree-ensure (+test-aww--agent project "ada"))))
    (make-directory (expand-file-name "src" project) t)
    (should (equal (agent-workspace-project project) project))
    (should (equal (agent-workspace-project (expand-file-name "src" project)) project))
    (should (equal (agent-workspace-project dir) project))
    (let ((default-directory dir))
      (should (equal (agent-workspace-project) project)))
    (let ((outside (expand-file-name "aww/outside/" +test-tmp)))
      (make-directory outside t)
      (should-not (agent-workspace-project outside)))
    (should-not (agent-workspace-project (expand-file-name "aww/nowhere/" +test-tmp)))))
