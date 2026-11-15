;;; tests/unit/test-agent-workspace-worktree.el -*- lexical-binding: t; -*-
;; config/agent-workspace/worktree.el and names.el: every agent's own git
;; worktree, named after it (.agent-shell/worktrees/ROLE-NAME, agent/NAME, its lock's
;; reason), in throwaway git repositories; forgetting it without losing work;
;; reviewing and merging its branch; a crew's project found from them; its
;; name on it in Emacs (the project's name, the mode line, its tabs).

;; Git as git is, not as your ~/.gitconfig has it (hooks, signing...).
(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(+test-load "config/agent-workspace")

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

(defun +test-aww--dir (name)
  "A new, empty folder NAME in the temp folder (its true name)."
  (let ((dir (file-name-as-directory (expand-file-name (concat "aww/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (file-name-as-directory (file-truename dir))))

(defun +test-aww--porcelain (project)
  "git worktree list --porcelain in PROJECT."
  (let ((default-directory project)) (+test-aww--git "worktree" "list" "--porcelain")))

(defun +test-aww--change (dir file text &optional message)
  "FILE in DIR now holds TEXT; MESSAGE: committed with it."
  (let ((default-directory dir))
    (write-region text nil file)
    (when message
      (+test-aww--git "add" file)
      (+test-aww--commit message))))

(defun +test-aww--read (file)
  "FILE's text."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defmacro +test-aww--with-crew (project agents &rest body)
  "BODY with AGENTS (records) PROJECT's crew."
  (declare (indent 2))
  `(let ((agent-workspace--crews (make-hash-table :test #'equal)))
     (puthash ,project ,agents agent-workspace--crews)
     ,@body))

(ert-deftest agent-workspace-worktree/made-named-after-it ()
  "Its worktree: .agent-shell/worktrees/ROLE-NAME, on a new branch agent/NAME
from the project's HEAD; the project's checkout untouched."
  (let* ((project (+test-aww--project "made"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent)))
    (should (equal dir (expand-file-name ".agent-shell/worktrees/builder-ada/" project)))
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
    (let ((default-directory (expand-file-name ".agent-shell/worktrees/builder-ada/" project)))
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
    ;; Removed with git (locked: forced twice).
    (let ((default-directory project))
      (+test-aww--git "worktree" "remove" "-f" "-f" (directory-file-name dir)))
    (agent-workspace-worktree-ensure (+test-aww--agent project "ada"))
    (should (file-exists-p (expand-file-name "work" dir)))))

(ert-deftest agent-workspace-worktree/git-s-refusal-said ()
  "git refusing: a user error with what it said."
  (let* ((project (+test-aww--project "refused"))
         (agent (+test-aww--agent project "ada")))
    ;; A file where its folder goes.
    (make-directory (expand-file-name ".agent-shell/worktrees/" project) t)
    (write-region "" nil (expand-file-name ".agent-shell/worktrees/builder-ada" project))
    (should-error (agent-workspace-worktree-ensure agent) :type 'user-error)))

(ert-deftest agent-workspace-worktree/renamed ()
  "Renamed: its worktree moved and its branch renamed, its work kept; its
role changed: moved, its branch as it was."
  (let* ((project (+test-aww--project "renamed"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent)))
    (write-region "wip\n" nil (expand-file-name "wip" dir))
    (agent-workspace-worktree-move agent "grace" "builder")
    (let ((new (expand-file-name ".agent-shell/worktrees/builder-grace/" project)))
      (should (equal (agent-workspace-agent-worktree agent) new))
      (should (equal (agent-workspace-agent-branch agent) "agent/grace"))
      (should-not (file-exists-p dir))
      (should (file-exists-p (expand-file-name "wip" new)))
      (let ((default-directory new))
        (should (equal (+test-aww--git "branch" "--show-current") "agent/grace")))
      (let ((default-directory project))
        (should-not (string-search "agent/ada" (+test-aww--git "branch" "--list"))))
      ;; A reviewer now.
      (agent-workspace-worktree-move agent "grace" "reviewer")
      (let ((moved (expand-file-name ".agent-shell/worktrees/reviewer-grace/" project)))
        (should (equal (agent-workspace-agent-worktree agent) moved))
        (should (equal (agent-workspace-agent-role agent) "reviewer"))
        (should (equal (agent-workspace-agent-branch agent) "agent/grace"))
        (should-not (file-exists-p new))
        (should (file-exists-p (expand-file-name "wip" moved)))
        (should (string-search "locked agent grace (reviewer)" (+test-aww--porcelain project)))))))

(ert-deftest agent-workspace-worktree/named-otherwise-moved ()
  "A worktree on its branch named as before (worktrees/NAME), or for its
role before (crew.json edited): moved to ROLE-NAME as its agent starts, its
work kept, locked as it. Its branch checked out outside the agents' folder
\(yours): never moved, git's refusal said."
  (let* ((project (+test-aww--project "before"))
         (old (expand-file-name ".agent-shell/worktrees/ada/" project)))
    (let ((default-directory project))
      (make-directory (expand-file-name ".agent-shell/worktrees/" project) t)
      (+test-aww--git "worktree" "add" "-q" "-b" "agent/ada" (directory-file-name old) "HEAD")
      (+test-aww--git "worktree" "lock" "--reason" "agent ada (builder), crew of before" (directory-file-name old)))
    (write-region "wip\n" nil (expand-file-name "wip" old))
    (let* ((agent (+test-aww--agent project "ada"))
           (dir (agent-workspace-worktree-ensure agent)))
      (should (equal dir (expand-file-name ".agent-shell/worktrees/builder-ada/" project)))
      (should-not (file-exists-p old))
      (should (file-exists-p (expand-file-name "wip" dir)))
      (should (string-search "locked agent ada (builder)" (+test-aww--porcelain project)))
      ;; Its role changed in crew.json meanwhile.
      (setf (agent-workspace-agent-role agent) "reviewer")
      (let ((moved (agent-workspace-worktree-ensure agent)))
        (should (equal moved (expand-file-name ".agent-shell/worktrees/reviewer-ada/" project)))
        (should (file-exists-p (expand-file-name "wip" moved)))
        (should-not (file-exists-p dir))))
    ;; Its branch checked out outside the agents' folder.
    (let ((yours (expand-file-name "aww/yours/" +test-tmp)))
      (when (file-exists-p yours) (delete-directory yours t))
      (let ((default-directory project))
        (+test-aww--git "worktree" "add" "-q" "-b" "agent/ken" (directory-file-name yours) "HEAD"))
      (should-error (agent-workspace-worktree-ensure (+test-aww--agent project "ken")) :type 'user-error)
      (should (file-exists-p (expand-file-name "README" yours))))))

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


;; ====== LOCKED, ITS NAME ON IT ======

(ert-deftest agent-workspace-worktree/locked-with-its-name ()
  "Its worktree is locked as it's made, its reason naming it; git's own name
for it is its folder's; prune leaves it; one found unlocked is locked;
renamed, its reason too."
  (let* ((project (+test-aww--project "locked"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent)))
    (should (string-search (concat "worktree " (directory-file-name dir)) (+test-aww--porcelain project)))
    (should (string-search "locked agent ada (builder), crew of locked" (+test-aww--porcelain project)))
    (should (file-directory-p (expand-file-name ".git/worktrees/builder-ada" project)))
    (let ((default-directory project))
      (+test-aww--git "worktree" "prune")
      (should (file-directory-p dir))
      (+test-aww--git "worktree" "unlock" (directory-file-name dir)))
    (should-not (string-search "\nlocked" (+test-aww--porcelain project)))
    (agent-workspace-worktree-ensure agent)
    (should (string-search "locked agent ada (builder)" (+test-aww--porcelain project)))
    (agent-workspace-worktree-move agent "grace" "builder")
    (should (string-search "locked agent grace (builder), crew of locked" (+test-aww--porcelain project)))
    (should-not (string-search "agent ada" (+test-aww--porcelain project)))))

(ert-deftest agent-workspace-worktree/no-crew-without-a-commit ()
  "A folder outside git, or a repository with no commit: no crew, saying
why; nothing made."
  (should (string-prefix-p "not a git repository"
                           (agent-workspace-no-crew-reason (+test-aww--dir "outside-git"))))
  (let ((empty (+test-aww--dir "no-commit")))
    (let ((default-directory empty)) (+test-aww--git "init" "-q" "-b" "main"))
    (should (string-prefix-p "no commit yet" (agent-workspace-no-crew-reason empty)))
    (should-error (agent-workspace-worktree-ensure (+test-aww--agent empty "ada")) :type 'user-error)
    (should-not (file-exists-p (expand-file-name ".agent-shell/worktrees/builder-ada" empty))))
  (should-not (agent-workspace-no-crew-reason (+test-aww--project "fine"))))

(ert-deftest agent-workspace-worktree/two-agents-at-once ()
  "Two agents change the same file at once, each in its worktree, and
commit: neither sees the other's change, and your checkout is untouched."
  (let* ((project (+test-aww--project "together"))
         (head (let ((default-directory project)) (+test-aww--git "rev-parse" "HEAD")))
         (ada (agent-workspace-worktree-ensure (+test-aww--agent project "ada")))
         (grace (agent-workspace-worktree-ensure (+test-aww--agent project "grace"))))
    (+test-aww--change ada "README" "ada's\n" "ada's change")
    (+test-aww--change grace "README" "grace's\n" "grace's change")
    (should (equal (+test-aww--read (expand-file-name "README" ada)) "ada's\n"))
    (should (equal (+test-aww--read (expand-file-name "README" grace)) "grace's\n"))
    (let ((default-directory project))
      (should (equal (+test-aww--git "rev-parse" "HEAD") head))
      (should (equal (+test-aww--git "status" "--porcelain") ""))
      (should (equal (+test-aww--read "README") "hello\n")))))

;; ====== FORGETTING IT ======

(ert-deftest agent-workspace-worktree/forgotten-with-nothing-left ()
  "Holding nothing the main checkout hasn't: removed, its branch deleted,
without asking."
  (let* ((project (+test-aww--project "forget-clean"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent)))
    (+test-aww--with-crew project (list agent)
      (cl-letf (((symbol-function 'read-multiple-choice) (lambda (&rest _) (error "Asked"))))
        (agent-workspace-forget agent))
      (should-not (agent-workspace-agents project))
      (should-not (file-exists-p dir))
      (should-not (string-search "ada" (+test-aww--porcelain project)))
      (let ((default-directory project))
        (should (equal (+test-aww--git "branch" "--list" "agent/ada") ""))))))

(ert-deftest agent-workspace-worktree/forgotten-with-work-asks ()
  "Holding work (not committed, or commits not on the main branch): you're
shown it and asked; kept, it's all there; removed, it's gone."
  (let* ((project (+test-aww--project "forget-work"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (shown nil))
    (+test-aww--change dir "new" "work\n")
    (+test-aww--change dir "done" "work\n" "ada's work")
    (should (equal (agent-workspace-worktree-work agent)
                   (list :changes '("?? new")
                         :commits (list (let ((default-directory project))
                                          (+test-aww--git "log" "--oneline" "-1" "agent/ada"))))))
    (should (= (agent-workspace-branch-ahead agent) 1))
    (cl-letf (((symbol-function 'read-multiple-choice)
               (lambda (&rest _)
                 (setq shown (with-current-buffer "*ada's work*" (buffer-string)))
                 '(?k "keep it"))))
      (+test-aww--with-crew project (list agent)
        (agent-workspace-forget agent)
        (should-not (agent-workspace-agents project))))
    (should (string-search "Not committed:\n  ?? new" shown))
    (should (string-search "Not on main:\n  " shown))
    (should (string-search "ada's work" shown))
    (should-not (get-buffer "*ada's work*"))
    (should (file-exists-p (expand-file-name "new" dir)))
    ;; Forgotten again (another agent named so), removed this time.
    (cl-letf (((symbol-function 'read-multiple-choice) (lambda (&rest _) '(?r "remove it anyway"))))
      (+test-aww--with-crew project (list agent)
        (agent-workspace-forget agent)))
    (should-not (file-exists-p dir))
    (let ((default-directory project))
      (should (equal (+test-aww--git "branch" "--list" "agent/ada") "")))))

;; ====== REVIEW AND MERGE ======

(ert-deftest agent-workspace-worktree/review ()
  "Its branch's changes since it left the main branch, in magit."
  (require 'magit)
  (let* ((project (+test-aww--project "review"))
         (agent (+test-aww--agent project "ada"))
         (called nil))
    (agent-workspace-worktree-ensure agent)
    (cl-letf (((symbol-function 'magit-diff-range)
               (lambda (range &rest _) (setq called (list range default-directory)))))
      (agent-workspace-review agent))
    (should (equal called (list "main...agent/ada" project)))))

(ert-deftest agent-workspace-worktree/merge ()
  "Merged into the main checkout: the agent told; its branch reset to the
merged main when you say so; nothing ahead after."
  (let* ((project (+test-aww--project "merge"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (told nil))
    (+test-aww--change dir "feature" "done\n" "ada's feature")
    (+test-aww--change project "other" "mine\n" "my own work")
    (cl-letf (((symbol-function 'agent-workspace-live-p) (lambda (_) t))
              ((symbol-function 'agent-workspace-send)
               (lambda (_agent text &rest _) (push text told))))
      (let ((default-directory project))
        (cl-letf (((symbol-function 'process-file)
                   (let ((process-file (symbol-function 'process-file)))
                     (lambda (program &optional infile buffer display &rest args)
                       (apply process-file program infile buffer display
                              (if (equal (car args) "merge")
                                  (append '("-c" "user.name=Test" "-c" "user.email=test@example.com")
                                          args)
                                args))))))
          (should (agent-workspace-merge agent t)))))
    (should (equal (+test-aww--read (expand-file-name "feature" project)) "done\n"))
    (should (equal told '("The user merged your branch agent/ada into main. It's been reset to main: start your next work from there.")))
    (let ((default-directory project))
      (should (equal (+test-aww--git "rev-parse" "agent/ada") (+test-aww--git "rev-parse" "main"))))
    (should (file-exists-p (expand-file-name "other" dir)))
    (should (= (agent-workspace-branch-ahead agent) 0))))

(ert-deftest agent-workspace-worktree/merge-never-fast-forwards ()
  "Merged when a fast-forward could do (the main branch hasn't moved since
it left): a merge commit all the same, two parents, naming its branch; its
branch reset to it, nothing ahead after."
  (let* ((project (+test-aww--project "merge-no-ff"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (before nil)
         (ada nil))
    (+test-aww--change dir "feature" "done\n" "ada's feature")
    (let ((default-directory project))
      (setq before (+test-aww--git "rev-parse" "main")
            ada (+test-aww--git "rev-parse" "agent/ada")))
    (cl-letf (((symbol-function 'agent-workspace-live-p) (lambda (_) nil)))
      (let ((default-directory project))
        (cl-letf (((symbol-function 'process-file)
                   (let ((process-file (symbol-function 'process-file)))
                     (lambda (program &optional infile buffer display &rest args)
                       (apply process-file program infile buffer display
                              (if (equal (car args) "merge")
                                  (append '("-c" "user.name=Test" "-c" "user.email=test@example.com")
                                          args)
                                args))))))
          (should (agent-workspace-merge agent t)))))
    (should (equal (+test-aww--read (expand-file-name "feature" project)) "done\n"))
    (let ((default-directory project))
      (should (equal (split-string (+test-aww--git "rev-list" "--parents" "-n" "1" "main"))
                     (list (+test-aww--git "rev-parse" "main") before ada)))
      (should (equal (+test-aww--git "log" "-1" "--format=%s" "main") "Merge branch 'agent/ada'"))
      (should (equal (+test-aww--git "rev-parse" "agent/ada") (+test-aww--git "rev-parse" "main"))))
    (should (= (agent-workspace-branch-ahead agent) 0))))

(ert-deftest agent-workspace-worktree/merge-stopped-on-conflicts ()
  "A merge that conflicts is left to you, said; nothing reset or told."
  (let* ((project (+test-aww--project "conflict"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (told nil))
    (+test-aww--change dir "README" "ada's\n" "ada's change")
    (+test-aww--change project "README" "mine\n" "my change")
    (cl-letf (((symbol-function 'agent-workspace-send) (lambda (&rest args) (push args told))))
      (should-not (agent-workspace-merge agent t)))
    (should-not told)
    (let ((default-directory project))
      (should (string-search "UU README" (+test-aww--git "status" "--porcelain")))
      (+test-aww--git "merge" "--abort"))
    (should (= (agent-workspace-branch-ahead agent) 1))))

;; ====== IN EMACS ======

(ert-deftest agent-workspace-worktree/a-file-s-agent ()
  "A file of an agent's worktree (ROLE-NAME): its project and agent, found
through the crew (the outermost worktree); a folder nobody's and unreadable,
its own name; none for the main checkout's files."
  (+test-aww--with-crew "/p/doom/" (list (agent-workspace--make-agent :name "ada" :role "builder"
                                                                      :project "/p/doom/"))
    (should (equal (agent-workspace-worktree-of "/p/doom/.agent-shell/worktrees/builder-ada/src/a.el")
                   '("/p/doom/" "ada")))
    (should (equal (agent-workspace-worktree-of "/p/doom/.agent-shell/worktrees/builder-ada")
                   '("/p/doom/" "ada")))
    (should (equal (agent-workspace-worktree-of
                    "/p/doom/.agent-shell/worktrees/builder-ada/.agent-shell/worktrees/x/a.el")
                   '("/p/doom/" "ada")))
    (should (equal (agent-workspace-worktree-of "/p/doom/.agent-shell/worktrees/scribe-bob/a.el")
                   '("/p/doom/" "scribe-bob")))
    (should-not (agent-workspace-worktree-of "/p/doom/src/a.el"))
    (should (equal (agent-workspace-project-name "/p/doom/.agent-shell/worktrees/builder-ada/") "doom · ada"))
    (should-not (agent-workspace-project-name "/p/doom/"))))

(ert-deftest agent-workspace-worktree/its-project-s-name ()
  "projectile's and project.el's name for its worktree: \"PROJECT · NAME\"."
  (require 'projectile)
  (require 'project)
  (let* ((project (+test-aww--project "named"))
         (dir (agent-workspace-worktree-ensure (+test-aww--agent project "ada"))))
    (should (equal (projectile-default-project-name dir) "named · ada"))
    (should (equal (projectile-default-project-name project) "named"))
    (should (equal (project-name (project-current nil dir)) "named · ada"))
    (should (equal (project-name (project-current nil project)) "named"))))

(ert-deftest agent-workspace-worktree/its-mode-line-and-tabs ()
  "Its files' mode line shows the agent (avatar, name, role), a click
selecting it; their tab starts with its avatar. A forgotten agent's
worktree: its name dimmed."
  (let* ((project (+test-aww--project "mode-line"))
         (agent (+test-aww--agent project "ada"))
         (dir (agent-workspace-worktree-ensure agent))
         (selected nil)
         (agent-workspace-select-function (lambda (a) (setq selected a))))
    (+test-with-reset
      (find-file (expand-file-name "README" dir))
      (+test-aww--with-crew project (list agent)
        (let ((text (agent-workspace-mode-line)))
          (should (equal (substring-no-properties text) " ▌A ada · builder "))
          (should (member '(:eval (agent-workspace-mode-line)) mode-line-misc-info))
          (should (eq (lookup-key (get-text-property 1 'local-map text) [mode-line mouse-1])
                      #'agent-workspace-mode-line-select))
          (should (equal (plist-get (get-text-property 1 'face text) :foreground)
                         (face-foreground 'ansi-color-blue nil t)))
          ;; Its role readable, the same for every agent.
          (should (eq (get-text-property (string-search "builder" text) 'face text) 'agent-workspace-label)))
        (agent-workspace-mode-line-select (list 'mouse-1 (list (selected-window) 1 '(0 . 0) 0)))
        (should (eq selected agent))
        (should (equal (substring-no-properties (agent-workspace-tab-prefix (current-buffer))) "▌A ")))
      ;; No longer in the crew.
      (let ((agent-workspace--crews (make-hash-table :test #'equal)))
        (let ((text (agent-workspace-mode-line)))
          (should (equal (substring-no-properties text) " ▌A ada "))
          (should (eq (get-text-property 1 'face text) 'shadow)))
        (should (eq (get-text-property 0 'face (agent-workspace-tab-prefix (current-buffer))) 'shadow)))
      (find-file (expand-file-name "README" project))
      (should-not (agent-workspace-mode-line))
      (should-not (agent-workspace-tab-prefix (current-buffer))))))
