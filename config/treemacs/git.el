;;; $DOOMDIR/config/treemacs/git.el -*- lexical-binding: t; -*-
;; Git colours kept up to date. Loaded from config/treemacs.el.

;; Refresh git colors when a repo changes outside a save in Emacs, e.g. a commit
;; from the CLI or Claude Code. Watch each project's .git directory: git updates
;; its index/HEAD via lock-file renames, which kqueue does report. Also refresh
;; when Emacs regains focus, and re-check a file after it is reverted (edited
;; outside Emacs). Debounced; a short cooldown avoids a loop when `git status'
;; itself rewrites the index.
(defvar +my/treemacs--git-watches (make-hash-table :test #'equal))

(defvar +my/treemacs--refresh-timer nil)

(defvar +my/treemacs--last-refresh 0)

(defvar treemacs-silent-refresh)

(defvar +my/treemacs--git-poll-state (make-hash-table :test #'equal)
  "Each project's last `git status' output.")

(defvar +my/treemacs--git-poll-running (make-hash-table :test #'equal)
  "Projects whose check is still running.")

;; An expanded folder gets its git colours a moment later; if the tree is
;; redrawn meanwhile (a project switch, a refresh), that folder's button is gone:
;; "Error running timer `treemacs--apply-annotations-deferred':
;; (wrong-type-argument number-or-marker-p nil)". The redrawn tree gets its own
;; colours, so skip that (the git status is still cached first).
(defadvice! +my/treemacs-stale-annotations-a (fn &rest args)
  :around #'treemacs--apply-annotations-deferred
  (condition-case nil
      (apply fn args)
    (wrong-type-argument nil)))

(defun +my/treemacs-refresh-all ()
  "Refresh the trees on screen. Not the hidden ones (another workspace's):
their git colours wait until they're shown, when the poll compares their
projects' status with the last one it saw."
  (when (featurep 'treemacs)
    (setq +my/treemacs--last-refresh (float-time))
    ;; Quietly: no "[Treemacs] Refresh complete." on every focus / git change
    ;; (a manual refresh, g in treemacs, still says it).
    (let ((treemacs-silent-refresh t))
      (treemacs-run-in-every-buffer
       (when (get-buffer-window (current-buffer) t)
         (ignore-errors
           (treemacs-without-recenter
            (treemacs--do-refresh (current-buffer) 'all))))))))

;; A REFRESH FROM A FILE THE TREE STILL HAS
;; After a refresh, treemacs puts the cursor back on the file it was on, else
;; on the nearest folder above it the tree shows, going up until one is
;; (`treemacs-save-position'). A file of none of the tree's projects (the tree
;; switched to another project under it) has none: it went up from / forever,
;; Emacs hung (a refresh of the last workspace's tree, after SPC p p). From
;; such a file, the refresh starts at a project of the tree drawn there; with
;; none drawn, there's nothing a refresh can redraw (it failed, or went up
;; forever): none, the tree is drawn anew when it's shown.
(defun +my/treemacs--in-tree-p (path)
  "Non-nil if file PATH is one of the current treemacs workspace's projects,
or in one."
  (seq-some (lambda (project)
              (let ((root (treemacs-project->path project)))
                (or (string= path root)
                    (string-prefix-p (file-name-as-directory root) path))))
            (treemacs-workspace->projects (treemacs-current-workspace))))

(defun +my/treemacs--drawn-project ()
  "Where the first of the current workspace's projects drawn in this tree is,
if one is."
  (seq-some (lambda (project) (ignore-errors (treemacs-project->position project)))
            (treemacs-workspace->projects (treemacs-current-workspace))))

(defadvice! +my/treemacs-refresh-from-the-tree-a (fn buffer project)
  :around #'treemacs--do-refresh
  (if-let* ((path (with-current-buffer buffer
                    (when-let* ((button (ignore-errors (treemacs-current-button))))
                      (treemacs-button-get button :path))))
            ((stringp path))
            ((not (with-current-buffer buffer (+my/treemacs--in-tree-p path)))))
      (when-let* ((drawn (with-current-buffer buffer (+my/treemacs--drawn-project))))
        (with-current-buffer buffer (goto-char drawn))
        (funcall fn buffer project))
    (funcall fn buffer project)))

(defun +my/treemacs-schedule-refresh (&rest _)
  (when (> (- (float-time) +my/treemacs--last-refresh) 3)
    (when (timerp +my/treemacs--refresh-timer)
      (cancel-timer +my/treemacs--refresh-timer))
    (setq +my/treemacs--refresh-timer
          (run-with-timer 1 nil #'+my/treemacs-refresh-all))))

(defun +my/treemacs-watch-git-h (&rest _)
  (when-let* ((buf (window-buffer (selected-window)))
              ((buffer-file-name buf))
              (root (with-current-buffer buf (doom-project-root)))
              (git (expand-file-name ".git" root))
              ((file-directory-p git))
              ((not (gethash git +my/treemacs--git-watches))))
    (puthash git (file-notify-add-watch git '(change) #'+my/treemacs-schedule-refresh)
             +my/treemacs--git-watches)))

(add-hook 'window-buffer-change-functions #'+my/treemacs-watch-git-h)

(defun +my/treemacs--git-poll-project (root)
  "Compare ROOT's `git status' with the last one; refresh treemacs if it changed."
  (unless (gethash root +my/treemacs--git-poll-running)
    (puthash root t +my/treemacs--git-poll-running)
    (let ((output (generate-new-buffer " *treemacs-git-poll*"))
          ;; Started from the project: the current buffer's folder may be gone
          ;; (deleted outside Emacs), and git couldn't start there.
          (default-directory root))
      (condition-case nil
          (make-process
           :name "treemacs-git-poll" :buffer output :noquery t
           :connection-type 'pipe
           :command (list "git" "--no-optional-locks" "-C" root
                          ;; --branch: its first line, the branch and ↑↓,
                          ;; so a switch or a fetch elsewhere refreshes too.
                          "status" "--porcelain" "-z" "--branch")
           :sentinel
           (lambda (process _event)
             (unless (process-live-p process)
               (remhash root +my/treemacs--git-poll-running)
               (let ((status (and (zerop (process-exit-status process))
                                  (buffer-live-p output)
                                  (with-current-buffer output (buffer-string))))
                     (old (gethash root +my/treemacs--git-poll-state 'none)))
                 (when (buffer-live-p output) (kill-buffer output))
                 (when status
                   (puthash root status +my/treemacs--git-poll-state)
                   (unless (or (eq old 'none) (equal old status))
                     ;; Not `+my/treemacs-schedule-refresh': its cooldown
                     ;; would drop a change right after another refresh.
                     (when (timerp +my/treemacs--refresh-timer)
                       (cancel-timer +my/treemacs--refresh-timer))
                     (setq +my/treemacs--refresh-timer
                           (run-with-timer 0.3 nil #'+my/treemacs-refresh-all))))))))
        (error (remhash root +my/treemacs--git-poll-running)
               (kill-buffer output))))))

(defun +my/treemacs--git-poll ()
  (when (and (featurep 'treemacs)
             (frame-focus-state)          ; focusing Emacs refreshes anyway
             (eq (treemacs-current-visibility) 'visible))
    (dolist (project (ignore-errors
                       (treemacs-workspace->projects (treemacs-current-workspace))))
      (let ((root (treemacs-project->path project)))
        (when (file-directory-p root)
          (+my/treemacs--git-poll-project root))))))

(defvar +my/treemacs--git-poll-timer nil)

(when (timerp +my/treemacs--git-poll-timer)  ; reloading this file
  (cancel-timer +my/treemacs--git-poll-timer))

(setq +my/treemacs--git-poll-timer
      (and +my/treemacs-git-poll-interval
           (run-with-timer +my/treemacs-git-poll-interval +my/treemacs-git-poll-interval
                           #'+my/treemacs--git-poll)))

(defun +my/treemacs-focus-refresh ()
  (when (frame-focus-state) (+my/treemacs-schedule-refresh)))

(add-function :after after-focus-change-function #'+my/treemacs-focus-refresh)

(add-hook 'after-revert-hook #'+my/treemacs-git-update-on-save-h)
