;;; $DOOMDIR/config/treemacs.el -*- lexical-binding: t; -*-
;; Treemacs project sidebar (IntelliJ-like). Loaded from config.el.

;; ====== VARIABLES ======

;; TREEMACS (IntelliJ-like project view)
(setq +treemacs-git-mode 'deferred)     ; async git status, incl. folders (python3)

;; Treemacs hides its window from winum; number it (leftmost => SPC w 1).
(after! (treemacs winum)
  (setq winum-ignored-buffers-regexp
        (remove (regexp-quote treemacs-buffer-name-prefix)
                winum-ignored-buffers-regexp)))

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

;; EXPAND / COLLAPSE ALL
;; `treemacs-expand-all' (zR in treemacs) opens every folder of the project(s)
;; in the sidebar; `treemacs-collapse-all' (zM) closes them all again but keeps
;; each project open at its top level, like IntelliJ's Collapse All (treemacs's
;; own `treemacs-collapse-all-projects' folds the projects down to their names).
(defvar +my/treemacs-expand-all-warn 300
  "Ask before `treemacs-expand-all' opens more than this many folders.")

;; ====== KEY BINDINGS ======

;; Arrows mirror h/l (treemacs-evil binds h/l but leaves ←/→ as char motions).
(map! :after treemacs-evil
      :map evil-treemacs-state-map
      [left]  #'treemacs-COLLAPSE-action
      [right] #'treemacs-RET-action)

(map! :after treemacs-evil
      :map evil-treemacs-state-map
      "zR" #'treemacs-expand-all
      "zM" #'treemacs-collapse-all)

;; SINGLE CLICK
;; Open files and expand/collapse folders with one click (treemacs' default is
;; a double click). A double click then counts as one click, so it doesn't open
;; a folder and close it again.
(after! treemacs
  (define-key treemacs-mode-map [mouse-1] #'treemacs-single-click-expand-action)
  (define-key treemacs-mode-map [double-mouse-1] #'ignore))

;; ====== CODE ======

(after! treemacs
  (setq treemacs-is-never-other-window nil) ; reachable with SPC w w (Doom: t)
  (treemacs-follow-mode +1)             ; highlight the current file (Doom: off)
  (treemacs-project-follow-mode +1))    ; show the current buffer's project

;; PROJECT FOLLOW, RIGHT AWAY
;; `treemacs-project-follow-mode' switches to the current buffer's project only
;; after 1.5 s without any input (an idle timer): switch buffers or windows and
;; keep typing or scrolling, and treemacs went on showing the old project. Now it
;; follows a moment after every switch (several switches in a row: one update).
(defvar +my/treemacs--follow-timer nil)

(defun +my/treemacs-follow-project-soon (&rest _)
  (when (timerp +my/treemacs--follow-timer)
    (cancel-timer +my/treemacs--follow-timer))
  (setq +my/treemacs--follow-timer
        (run-at-time
         0.1 nil
         (lambda ()
           (setq +my/treemacs--follow-timer nil)
           (let ((buffer (window-buffer (selected-window))))
             (when (and (bound-and-true-p treemacs-project-follow-mode)
                        (not (minibufferp buffer))) ; e.g. M-x: stay
               ;; Treemacs itself (selected) and the home directory are
               ;; skipped there, like other buffers without a project.
               (with-current-buffer buffer
                 (ignore-errors (treemacs--do-follow-project)))))))))

(add-hook 'window-buffer-change-functions #'+my/treemacs-follow-project-soon)

(add-hook 'window-selection-change-functions #'+my/treemacs-follow-project-soon)

;; Update the saved file's git status in treemacs. macOS uses kqueue for file
;; notifications, which doesn't report in-place edits, so filewatch misses them.
(defun +my/treemacs-git-update-on-save-h ()
  (when-let* ((file buffer-file-name)
              ((featurep 'treemacs)))
    (dolist (win (window-list))
      (when (with-current-buffer (window-buffer win) (derived-mode-p 'treemacs-mode))
        (with-selected-window win
          (ignore-errors (treemacs-update-single-file-git-state file)))))))

(add-hook 'after-save-hook #'+my/treemacs-git-update-on-save-h)

;; Open treemacs the first time a project file is shown in each workspace
;; (SPC p p, SPC SPC, SPC f r, dashboard, ...). If you close it afterwards
;; (SPC o p) it stays closed for that workspace.
(defun +my/treemacs-auto-open-h (&rest _)
  (when-let* ((buf (window-buffer (selected-window)))
              ((buffer-file-name buf))
              ((with-current-buffer buf (doom-project-root)))
              (persp (and (bound-and-true-p persp-mode) (get-current-persp)))
              ((not (persp-parameter '+my/treemacs-opened persp))))
    (set-persp-parameter '+my/treemacs-opened t persp)
    (require 'treemacs)
    (when (eq (treemacs-current-visibility) 'none)
      (with-current-buffer buf
        (save-selected-window
          (treemacs-add-and-display-current-project-exclusively))))))

(add-hook 'window-buffer-change-functions #'+my/treemacs-auto-open-h)

(defun +my/treemacs-refresh-all ()
  (when (featurep 'treemacs)
    (setq +my/treemacs--last-refresh (float-time))
    ;; Quietly: no "[Treemacs] Refresh complete." on every focus / git change
    ;; (a manual refresh, g in treemacs, still says it).
    (let ((treemacs-silent-refresh t))
      (treemacs-run-in-every-buffer
       (ignore-errors
         (treemacs-without-recenter
          (treemacs--do-refresh (current-buffer) 'all)))))))

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

(defun +my/treemacs-focus-refresh ()
  (when (frame-focus-state) (+my/treemacs-schedule-refresh)))

(add-function :after after-focus-change-function #'+my/treemacs-focus-refresh)

(add-hook 'after-revert-hook #'+my/treemacs-git-update-on-save-h)

(defun +my/treemacs--count-dirs (dir limit)
  "Count the folders under DIR (not .git), stopping once past LIMIT."
  (let ((count 0) (stack (list dir)))
    (while (and stack (<= count limit))
      (dolist (file (directory-files (pop stack) t directory-files-no-dot-files-regexp t))
        (when (and (file-directory-p file)
                   (not (file-symlink-p file))
                   (not (equal (file-name-nondirectory file) ".git")))
          (cl-incf count)
          (push file stack))))
    count))

(defun +my/treemacs--do-projects (fn)
  "Call FN with each displayed project and its root button, in treemacs."
  (require 'treemacs)
  (let ((buffer (or (treemacs-get-local-buffer)
                    (user-error "Treemacs isn't open"))))
    (with-current-buffer buffer
      (save-excursion
        (dolist (project (treemacs-workspace->projects (treemacs-current-workspace)))
          (when-let* ((pos (treemacs-project->position project)))
            (goto-char pos)
            (funcall fn project pos)))))))

(defun treemacs-expand-all ()
  "Expand every folder of the projects shown in treemacs."
  (interactive)
  (+my/treemacs--do-projects
   (lambda (project pos)
     (let ((dirs (+my/treemacs--count-dirs (treemacs-project->path project)
                                           +my/treemacs-expand-all-warn)))
       (when (or (<= dirs +my/treemacs-expand-all-warn)
                 (y-or-n-p (format "%s has more than %d folders. Expand them all? "
                                   (treemacs-project->name project)
                                   +my/treemacs-expand-all-warn)))
         ;; Close it (forgetting what was open below), then reopen recursively.
         (when (eq (treemacs-button-get pos :state) 'root-node-open)
           (treemacs--collapse-root-node pos t))
         (treemacs--expand-root-node pos t))))))

(defun treemacs-collapse-all ()
  "Collapse every folder of the projects shown in treemacs (projects stay open)."
  (interactive)
  (+my/treemacs--do-projects
   (lambda (_project pos)
     (when (eq (treemacs-button-get pos :state) 'root-node-open)
       (treemacs--collapse-root-node pos t))
     (treemacs--expand-root-node pos))))
