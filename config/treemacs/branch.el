;;; $DOOMDIR/config/treemacs/branch.el -*- lexical-binding: t; -*-
;; Each git project's branch after its name in the sidebar, and how far it is
;; ahead / behind its upstream: "doom  main ↑2 ↓1" (a detached HEAD: its short
;; commit; not a git project: nothing). Loaded from config/treemacs.el.
;;
;; Treemacs has no branch of its own: this is a suffix annotation (its API, as
;; its `treemacs-git-commit-diff-mode' shows ↑↓). That mode stays off: the
;; counts come here with the branch, from the same `git status' (no python),
;; and its magit hook runs its script without git's path, so it never updated.
;;
;; Read in the background when a project's root line is drawn (treemacs opened,
;; a project followed), after a refresh (g, focus, .git changes, the poll: its
;; `git status' has the branch line, so a switch in a terminal shows), and
;; after magit refreshes (a checkout, a commit, a pull...).

(defface +my/treemacs-branch-face
  '((t :inherit shadow))
  "The branch after a project's name in treemacs.")

(defconst +my/treemacs--branch-source "+my-branch"
  "Its annotation source (treemacs sorts a node's suffixes by source).")

(defvar +my/treemacs--branch-running (make-hash-table :test #'equal)
  "Projects whose branch is being read: t, or `again' when asked meanwhile.")

(defun +my/treemacs--branch-suffix (output)
  "The suffix for OUTPUT of `git status --porcelain=v2 --branch', or nil."
  (let (oid head ahead behind)
    (dolist (line (split-string output "\n" t))
      (cond ((string-match "\\`# branch\\.oid \\(.+\\)" line)
             (setq oid (match-string 1 line)))
            ((string-match "\\`# branch\\.head \\(.+\\)" line)
             (setq head (match-string 1 line)))
            ((string-match "\\`# branch\\.ab \\+\\([0-9]+\\) -\\([0-9]+\\)" line)
             (setq ahead (string-to-number (match-string 1 line))
                   behind (string-to-number (match-string 2 line))))))
    (when head
      (concat (propertize (concat "  " (if (and (equal head "(detached)") oid)
                                           (substring oid 0 (min 7 (length oid)))
                                         head))
                          'face '+my/treemacs-branch-face)
              (when (and ahead (> ahead 0))
                (propertize (format " ↑%d" ahead) 'face 'treemacs-git-commit-diff-face))
              (when (and behind (> behind 0))
                (propertize (format " ↓%d" behind) 'face 'treemacs-git-commit-diff-face))))))

(defun +my/treemacs--branch-shown (root)
  "ROOT's branch suffix as treemacs has it, or nil."
  (when-let* ((ann (treemacs-get-annotation root)))
    (cdr (assoc +my/treemacs--branch-source (treemacs-annotation->suffix ann)))))

(defun +my/treemacs--branch-set (root suffix)
  "SUFFIX (nil: none) after ROOT's name in every treemacs buffer, if it
changed (a redraw for nothing would move the sidebar's lines)."
  (unless (equal (+my/treemacs--branch-shown root) suffix)
    (if suffix
        (treemacs-set-annotation-suffix root suffix +my/treemacs--branch-source)
      (treemacs-remove-annotation-suffix root +my/treemacs--branch-source))
    (treemacs-apply-single-annotation root)))

(defun +my/treemacs-update-branch (root)
  "Read project ROOT's branch from git, in the background, then show it.
Asked while it runs: read again once it ends."
  (cond
   ((file-remote-p root))
   ((gethash root +my/treemacs--branch-running)
    (puthash root 'again +my/treemacs--branch-running))
   (t
    (puthash root t +my/treemacs--branch-running)
    (let ((output (generate-new-buffer " *treemacs-branch*"))
          (default-directory (file-name-as-directory root)))
      (condition-case nil
          (make-process
           :name "treemacs-branch" :buffer output :noquery t
           :connection-type 'pipe
           ;; No lock taken (nothing written to .git), no untracked files
           ;; listed: only the header matters.
           :command (list "git" "--no-optional-locks" "-C" root "status"
                          "--porcelain=v2" "--branch" "--untracked-files=no"
                          "--ignore-submodules=all")
           :sentinel
           (lambda (process _event)
             (unless (process-live-p process)
               (let ((again (eq (gethash root +my/treemacs--branch-running) 'again))
                     (text (and (eq (process-status process) 'exit)
                                (zerop (process-exit-status process))
                                (buffer-live-p output)
                                (with-current-buffer output (buffer-string)))))
                 (remhash root +my/treemacs--branch-running)
                 (when (buffer-live-p output) (kill-buffer output))
                 (when (featurep 'treemacs)
                   (ignore-errors
                     (+my/treemacs--branch-set
                      root (and text (+my/treemacs--branch-suffix text)))))
                 (when again (+my/treemacs-update-branch root))))))
        (error (remhash root +my/treemacs--branch-running)
               (kill-buffer output)))))))

;; A root line drawn anew (treemacs opened, a project followed, a workspace
;; shown, a rename): treemacs leaves out its suffixes until one changes. Put
;; them back as last known, then read the branch again.
(defadvice! +my/treemacs-branch-on-root-a (project)
  :after #'treemacs--add-root-element
  (let ((root (treemacs-project->path project)))
    (when-let* ((ann (treemacs-get-annotation root))
                (suffix (treemacs-annotation->suffix-value ann)))
      (let ((inhibit-read-only t))
        (insert suffix)))
    (+my/treemacs-update-branch root)))

(defun +my/treemacs-branch-after-refresh-h (project &rest _)
  "After a refresh of PROJECT (`all': each), read its branch again."
  (dolist (project (if (eq project 'all)
                       (treemacs-workspace->projects (treemacs-current-workspace))
                     (list project)))
    (+my/treemacs-update-branch (treemacs-project->path project))))

(add-hook 'treemacs-post-refresh-hook #'+my/treemacs-branch-after-refresh-h)

(defun +my/treemacs-branch-after-magit-h ()
  "After magit refreshes, read its repository's branch again, if treemacs
shows it."
  (when-let* (((featurep 'treemacs))
              (top (ignore-errors (magit-toplevel))))
    (dolist (project (ignore-errors
                       (treemacs-workspace->projects (treemacs-current-workspace))))
      (let ((root (treemacs-project->path project)))
        (when (and (not (file-remote-p root))
                   (file-equal-p root top))
          (+my/treemacs-update-branch root))))))

(add-hook 'magit-post-refresh-hook #'+my/treemacs-branch-after-magit-h)
