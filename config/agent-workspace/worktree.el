;;; $DOOMDIR/config/agent-workspace/worktree.el -*- lexical-binding: t; -*-
;; Every agent's own git worktree. Loaded from config/agent-workspace.el. No
;; Doom here.
;;
;; Named after its agent: the folder .agent-shell/worktrees/ROLE-NAME of its
;; project (builder-ada), on the branch agent/NAME. Made when the agent is,
;; kept when it's killed, put to sleep or its crew closed (the next start
;; reuses it), moved when it's renamed or its role changes. One found
;; elsewhere in .agent-shell/worktrees on its branch (worktrees/NAME, as
;; they were named before; its role's before crew.el changed it) is moved
;; to its folder as it starts.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; ====== VARIABLES ======

(defcustom agent-workspace-worktrees-directory ".agent-shell/worktrees"
  "Where agents' worktrees go, in their project (.agent-shell/ is kept out
of git: see `agent-workspace--keep-out-of-git')."
  :type 'string
  :group 'agent-workspace)

;; ====== A WORKTREE ======

(defun agent-workspace-worktree-directory (project name role)
  "The worktree of the agent NAME, of ROLE, of PROJECT's crew: ROLE-NAME."
  (file-name-as-directory
   (expand-file-name (concat role "-" name) (expand-file-name agent-workspace-worktrees-directory project))))

(defun agent-workspace--worktree-branch-name (dir)
  "The agent's name the worktree DIR's branch says (agent/NAME), or nil:
read from its git files, git not run (a mode line asks)."
  (ignore-errors
    (let* ((gitdir (with-temp-buffer
                     (insert-file-contents (expand-file-name ".git" dir))
                     (and (looking-at "gitdir: \\(.*\\)") (match-string 1))))
           (head (with-temp-buffer
                   (insert-file-contents (expand-file-name "HEAD" (expand-file-name gitdir dir)))
                   (buffer-string))))
      (and (string-match "\\`ref: refs/heads/agent/\\([^\n]+\\)" head)
           (match-string 1 head)))))

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

(defun agent-workspace-no-crew-reason (&optional directory)
  "Why DIRECTORY's project (default: `default-directory''s) can have no
crew, or nil if it can: every agent needs a worktree, branched from a
commit."
  (let ((default-directory (file-name-as-directory (expand-file-name (or directory default-directory)))))
    (cond ((not (agent-workspace-project))
           "not a git repository: every agent works in a git worktree of its own")
          ((not (eql 0 (process-file "git" nil nil nil "rev-parse" "--verify" "--quiet" "HEAD")))
           "no commit yet: an agent's worktree branches from one"))))

(defun agent-workspace-worktree-reason (agent)
  "Why AGENT's worktree is locked, naming it: \"agent ada (builder), crew of
doom\"."
  (format "agent %s (%s), crew of %s"
          (agent-workspace-agent-name agent) (agent-workspace-agent-role agent)
          (file-name-nondirectory (directory-file-name (agent-workspace-agent-project agent)))))

(defun agent-workspace--worktrees (project)
  "PROJECT's worktrees as git lists them: a plist each (:dir, :branch,
:locked: its reason, or t)."
  (let ((default-directory project)
        worktrees current)
    (dolist (line (split-string (agent-workspace--git "worktree" "list" "--porcelain") "\n"))
      (cond ((string-prefix-p "worktree " line)
             (when current (push current worktrees))
             (setq current (list :dir (file-name-as-directory (substring line 9)))))
            ((string-prefix-p "branch refs/heads/" line)
             (setq current (plist-put current :branch (substring line 18))))
            ((string-match "\\`locked\\(?: \\(.*\\)\\)?\\'" line)
             (setq current (plist-put current :locked (or (match-string 1 line) t))))))
    (when current (push current worktrees))
    (nreverse worktrees)))

(defun agent-workspace--worktree-entry (project dir)
  "PROJECT's worktree DIR as git lists it, or nil."
  (let ((dir (file-name-as-directory (file-truename dir))))
    (seq-find (lambda (worktree) (equal (plist-get worktree :dir) dir))
              (agent-workspace--worktrees project))))

(defun agent-workspace--worktree-lock (agent)
  "AGENT's worktree locked with its reason (`agent-workspace-worktree-reason'),
if it isn't: `git worktree prune' and `remove' leave it alone."
  (let ((default-directory (agent-workspace-agent-project agent))
        (dir (agent-workspace-agent-worktree agent)))
    (unless (plist-get (agent-workspace--worktree-entry default-directory dir) :locked)
      (agent-workspace--git "worktree" "lock" "--reason" (agent-workspace-worktree-reason agent)
                            (directory-file-name dir)))))

(defun agent-workspace--worktree-unlock (project dir)
  "PROJECT's worktree DIR unlocked, if it's locked."
  (when (plist-get (agent-workspace--worktree-entry project dir) :locked)
    (let ((default-directory project))
      (agent-workspace--git "worktree" "unlock" (directory-file-name dir)))))

(defun agent-workspace--branch-worktrees (project branch)
  "PROJECT's worktrees on BRANCH in its agents' folder
\(`agent-workspace-worktrees-directory'; never its main checkout, nor one
of yours elsewhere): their folders."
  (let ((under (file-name-as-directory
                (file-truename (expand-file-name agent-workspace-worktrees-directory project)))))
    (delq nil (mapcar (lambda (worktree)
                        (and (equal (plist-get worktree :branch) branch)
                             (string-prefix-p under (plist-get worktree :dir))
                             (plist-get worktree :dir)))
                      (agent-workspace--worktrees project)))))

(defun agent-workspace-worktree-ensure (agent)
  "AGENT's worktree, made if it isn't there yet (its branch too, from the
project's HEAD), else reused (moved to its folder if it's elsewhere in its
agents' folder); locked with AGENT's name. Its folder and branch are set in
AGENT."
  (let* ((project (agent-workspace-agent-project agent))
         (name (agent-workspace-agent-name agent))
         (dir (agent-workspace-worktree-directory project name (agent-workspace-agent-role agent)))
         (branch (agent-workspace-branch name))
         (default-directory project))
    (unless (file-exists-p (expand-file-name ".git" dir))
      (when-let* ((reason (agent-workspace-no-crew-reason project)))
        (user-error "%s: %s" (file-name-nondirectory (directory-file-name project)) reason))
      (agent-workspace--keep-out-of-git project)
      (let* ((here (file-name-as-directory (file-truename dir)))
             (others (and (agent-workspace--branch-p branch)
                          (remove here (agent-workspace--branch-worktrees project branch))))
             (old (seq-find #'file-directory-p others)))
        ;; Its folder went (deleted by hand) while git still lists it: locked,
        ;; it's never pruned.
        (when (file-directory-p (file-name-directory (directory-file-name dir)))
          (agent-workspace--worktree-unlock project dir))
        (dolist (gone (seq-remove #'file-directory-p others))
          (agent-workspace--worktree-unlock project gone))
        (agent-workspace--git "worktree" "prune")
        (make-directory (file-name-directory (directory-file-name dir)) t)
        (cond
         ;; Its worktree, named otherwise (as before, or for its role before):
         ;; moved here, its work with it. git won't move a locked one.
         (old
          (agent-workspace--worktree-unlock project old)
          (agent-workspace--git "worktree" "move" (directory-file-name old) (directory-file-name dir)))
         ((agent-workspace--branch-p branch)
          (agent-workspace--git "worktree" "add" (directory-file-name dir) branch))
         (t (agent-workspace--git "worktree" "add" "-b" branch (directory-file-name dir) "HEAD")))))
    (setf (agent-workspace-agent-worktree agent) dir
          (agent-workspace-agent-branch agent) branch)
    (agent-workspace--worktree-lock agent)
    dir))

(defun agent-workspace--branch-p (branch)
  "Non-nil if BRANCH is a branch of `default-directory''s repository."
  (eql 0 (process-file "git" nil nil nil "rev-parse" "--verify" "--quiet" (concat "refs/heads/" branch))))

(defun agent-workspace-worktree-move (agent name role)
  "AGENT's worktree moved to the folder of NAME and ROLE, its branch renamed
after NAME, its lock's reason too (AGENT renamed, given ROLE, meanwhile).
Its session must not run."
  (let* ((project (agent-workspace-agent-project agent))
         (old (agent-workspace-agent-worktree agent))
         (dir (agent-workspace-worktree-directory project name role))
         (branch (agent-workspace-branch name))
         (default-directory project))
    (when (and old (file-exists-p old) (not (equal (file-truename old) (file-truename dir))))
      ;; git won't move a locked worktree.
      (agent-workspace--worktree-unlock project old)
      (agent-workspace--git "worktree" "move" (directory-file-name old) (directory-file-name dir)))
    (when-let* ((old-branch (agent-workspace-agent-branch agent)))
      (when (and (agent-workspace--branch-p old-branch) (not (equal old-branch branch)))
        (agent-workspace--git "branch" "-m" old-branch branch)))
    (setf (agent-workspace-agent-worktree agent) dir
          (agent-workspace-agent-branch agent) branch
          (agent-workspace-agent-name agent) name
          (agent-workspace-agent-role agent) role)
    (when (file-exists-p dir)
      (agent-workspace--worktree-lock agent))))

;; ====== ITS WORK ======

(defun agent-workspace-main-branch (project)
  "The branch PROJECT's main checkout is on (\"main\"), or its commit."
  (let ((default-directory project))
    (or (agent-workspace--git-line "branch" "--show-current")
        (agent-workspace--git "rev-parse" "HEAD"))))

(defun agent-workspace-worktree-work (agent)
  "What AGENT's worktree holds that the main checkout hasn't: a plist,
:changes (git status's lines: not committed) and :commits (one line each:
not on the main checkout's branch)."
  (let* ((project (agent-workspace-agent-project agent))
         (dir (agent-workspace-agent-worktree agent))
         (branch (agent-workspace-agent-branch agent))
         (main (agent-workspace-main-branch project)))
    (list :changes (when (and dir (file-directory-p dir))
                     (let ((default-directory dir))
                       (split-string (agent-workspace--git "status" "--porcelain") "\n" t)))
          :commits (let ((default-directory project))
                     (when (agent-workspace--branch-p branch)
                       (split-string (agent-workspace--git "log" "--oneline" (concat main ".." branch))
                                     "\n" t))))))

(defun agent-workspace-branch-ahead (agent)
  "How many commits AGENT's branch has that the main checkout's hasn't."
  (length (plist-get (agent-workspace-worktree-work agent) :commits)))

(defun agent-workspace-worktree-remove (agent)
  "AGENT's worktree removed, and its branch deleted, whatever they hold."
  (let* ((project (agent-workspace-agent-project agent))
         (dir (agent-workspace-agent-worktree agent))
         (branch (agent-workspace-agent-branch agent))
         (default-directory project))
    (when (and dir (agent-workspace--worktree-entry project dir))
      (agent-workspace--worktree-unlock project dir)
      (agent-workspace--git "worktree" "remove" "--force" (directory-file-name dir)))
    (when (and branch (agent-workspace--branch-p branch))
      (agent-workspace--git "branch" "-D" branch))))

(defun agent-workspace--ask-about-work (agent work)
  "Ask whether to keep AGENT's worktree, which holds WORK (see
`agent-workspace-worktree-work'), shown meanwhile: `keep' or `remove'."
  (let ((buffer (get-buffer-create (format "*%s's work*" (agent-workspace-agent-name agent)))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "%s's worktree, %s, on %s, holds work the main checkout hasn't.\n"
                        (agent-workspace-agent-name agent)
                        (abbreviate-file-name (agent-workspace-agent-worktree agent))
                        (agent-workspace-agent-branch agent)))
        (when-let* ((changes (plist-get work :changes)))
          (insert "\nNot committed:\n" (mapconcat (lambda (line) (concat "  " line)) changes "\n") "\n"))
        (when-let* ((commits (plist-get work :commits)))
          (insert (format "\nNot on %s:\n" (agent-workspace-main-branch (agent-workspace-agent-project agent)))
                  (mapconcat (lambda (line) (concat "  " line)) commits "\n") "\n")))
      (special-mode))
    (unwind-protect
        (save-window-excursion
          (pop-to-buffer buffer)
          (if (eq (car (read-multiple-choice
                        (format "Forget %s: its worktree " (agent-workspace-agent-name agent))
                        '((?k "keep it" "Keep its worktree and branch, as they are")
                          (?r "remove it anyway" "Remove its worktree and delete its branch, losing this work"))))
                  ?r)
              'remove
            'keep))
      (kill-buffer buffer))))

(defun agent-workspace-worktree-fate (agent &optional how)
  "What becomes of AGENT's worktree as AGENT is forgotten: HOW (`keep' or
`remove'), or if nil, `remove' when it holds nothing the main checkout
hasn't, else what you choose, shown what it holds."
  (or how
      (let ((work (agent-workspace-worktree-work agent)))
        (if (or (plist-get work :changes) (plist-get work :commits))
            (agent-workspace--ask-about-work agent work)
          'remove))))

;; ====== REVIEW AND MERGE ======

(declare-function magit-diff-range "magit-diff")

(defun agent-workspace-review (agent)
  "Show what AGENT's branch changed since it left the main checkout's
branch (MAIN...agent/NAME): in magit, else as a diff."
  (interactive (list (agent-workspace-read-agent "Review the branch of: ")))
  (let* ((project (agent-workspace-agent-project agent))
         (range (concat (agent-workspace-main-branch project) "..." (agent-workspace-agent-branch agent)))
         (default-directory project))
    (if (require 'magit nil t)
        (magit-diff-range range)
      (let ((buffer (get-buffer-create (format "*%s's changes*" (agent-workspace-agent-name agent)))))
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (process-file "git" nil t nil "diff" range))
          (diff-mode)
          (setq buffer-read-only t)
          (goto-char (point-min)))
        (pop-to-buffer buffer)))))

(defun agent-workspace-merge (agent &optional reset)
  "Merge AGENT's branch into the main checkout's branch. Merged, AGENT is
told (if its session runs) and RESET: its branch reset to the merged one
\(`ask': asked; only if its worktree has nothing uncommitted and it isn't
working). A merge stopped on conflicts is left to you, in the main
checkout. Return non-nil if it merged."
  (interactive (list (agent-workspace-read-agent "Merge the branch of: ") 'ask))
  (let* ((project (agent-workspace-agent-project agent))
         (branch (agent-workspace-agent-branch agent))
         (main (agent-workspace-main-branch project))
         (name (agent-workspace-agent-name agent))
         (default-directory project))
    (with-temp-buffer
      (if (not (eql 0 (process-file "git" nil t nil "merge" "--no-edit" branch)))
          (progn
            (message "Merging %s stopped: %s" branch (string-trim (buffer-string)))
            nil)
        (let* ((work (agent-workspace-worktree-work agent))
               (resettable (and (not (plist-get work :changes))
                                (not (memq (agent-workspace-agent-state agent) '(working hand)))))
               (reset (and resettable
                           (if (eq reset 'ask)
                               (y-or-n-p (format "Merged.  Reset %s to %s, for %s's next work? " branch main name))
                             reset))))
          (when reset
            (let ((default-directory (agent-workspace-agent-worktree agent)))
              (agent-workspace--git "reset" "--hard" main)))
          (when (agent-workspace-live-p agent)
            (agent-workspace-send
             agent (format "The user merged your branch %s into %s.%s" branch main
                           (if reset (format " It's been reset to %s: start your next work from there." main) ""))
             :submit t))
          (message "Merged %s into %s%s" branch main (if reset (format "; %s reset to it" branch) ""))
          t)))))
