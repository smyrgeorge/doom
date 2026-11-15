;;; $DOOMDIR/config/agent-workspace/worktree.el -*- lexical-binding: t; -*-
;; Every agent's own git worktree. Loaded from config/agent-workspace.el. No
;; Doom here.
;;
;; Named after its agent: the folder .agent-shell/worktrees/NAME of its
;; project, on the branch agent/NAME. Made when the agent is, kept when it's
;; killed, put to sleep or its crew closed (the next start reuses it), moved
;; when it's renamed.

(require 'cl-lib)
(require 'subr-x)

;; ====== VARIABLES ======

(defcustom agent-workspace-worktrees-directory ".agent-shell/worktrees"
  "Where agents' worktrees go, in their project (.agent-shell/ is kept out
of git: see `agent-workspace--keep-out-of-git')."
  :type 'string
  :group 'agent-workspace)

;; ====== A WORKTREE ======

(defun agent-workspace-worktree-directory (project name)
  "The worktree of the agent NAME of PROJECT's crew."
  (file-name-as-directory
   (expand-file-name name (expand-file-name agent-workspace-worktrees-directory project))))

(defun agent-workspace-branch (name)
  "The branch of the agent NAME: agent/NAME."
  (concat "agent/" name))

(defun agent-workspace--git (&rest args)
  "Run git with ARGS in `default-directory': its output, or a user error
with what git said."
  (with-temp-buffer
    (let ((status (apply #'process-file "git" nil t nil args)))
      (unless (eql status 0)
        (user-error "git %s: %s" (car args) (string-trim (buffer-string))))
      (string-trim (buffer-string)))))

(defun agent-workspace--keep-out-of-git (project)
  "PROJECT's .agent-shell/ kept out of git, if it isn't: in the repository's
info/exclude (every worktree shares it), so neither the project nor an
agent's branch gets a changed .gitignore."
  (let ((default-directory project))
    (unless (eql 0 (process-file "git" nil nil nil "check-ignore" "-q" ".agent-shell/worktrees"))
      (let ((exclude (expand-file-name
                      "info/exclude"
                      (agent-workspace--git "rev-parse" "--path-format=absolute" "--git-common-dir"))))
        (make-directory (file-name-directory exclude) t)
        (write-region "\n# Agents' worktrees, transcripts (agent-shell)\n/.agent-shell/\n"
                      nil exclude t 'silent)))))

(defun agent-workspace-worktree-ensure (agent)
  "AGENT's worktree, made if it isn't there yet (its branch too, from the
project's HEAD), else reused. Its folder and branch are set in AGENT."
  (let* ((project (agent-workspace-agent-project agent))
         (name (agent-workspace-agent-name agent))
         (dir (agent-workspace-worktree-directory project name))
         (branch (agent-workspace-branch name))
         (default-directory project))
    (unless (file-exists-p (expand-file-name ".git" dir))
      (agent-workspace--keep-out-of-git project)
      ;; A worktree whose folder went (deleted by hand) is still registered.
      (agent-workspace--git "worktree" "prune")
      (make-directory (file-name-directory (directory-file-name dir)) t)
      (if (eql 0 (process-file "git" nil nil nil "rev-parse" "--verify" "--quiet"
                               (concat "refs/heads/" branch)))
          (agent-workspace--git "worktree" "add" (directory-file-name dir) branch)
        (agent-workspace--git "worktree" "add" "-b" branch (directory-file-name dir))))
    (setf (agent-workspace-agent-worktree agent) dir
          (agent-workspace-agent-branch agent) branch)
    dir))

(defun agent-workspace-worktree-rename (agent name)
  "AGENT's worktree moved to the folder of NAME, its branch renamed after
it (AGENT not renamed yet). Its session must not run."
  (let* ((project (agent-workspace-agent-project agent))
         (old (agent-workspace-agent-worktree agent))
         (dir (agent-workspace-worktree-directory project name))
         (branch (agent-workspace-branch name))
         (default-directory project))
    (when (and old (file-exists-p old))
      (agent-workspace--git "worktree" "move" (directory-file-name old) (directory-file-name dir)))
    (when-let* ((old-branch (agent-workspace-agent-branch agent)))
      (when (eql 0 (process-file "git" nil nil nil "rev-parse" "--verify" "--quiet"
                                 (concat "refs/heads/" old-branch)))
        (agent-workspace--git "branch" "-m" old-branch branch)))
    (setf (agent-workspace-agent-worktree agent) dir
          (agent-workspace-agent-branch agent) branch)))
