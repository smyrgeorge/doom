;;; $DOOMDIR/config/treemacs.el -*- lexical-binding: t; -*-
;; Treemacs project sidebar (IntelliJ-like). Loaded from config.el.

;; TREEMACS (IntelliJ-like project view)
(setq +treemacs-git-mode 'deferred)     ; async git status, incl. folders (python3)
(after! treemacs
  (setq treemacs-is-never-other-window nil) ; reachable with SPC w w (Doom: t)
  (treemacs-follow-mode +1)             ; highlight the current file (Doom: off)
  (treemacs-project-follow-mode +1))    ; show the current buffer's project
;; Arrows mirror h/l (treemacs-evil binds h/l but leaves ←/→ as char motions).
(map! :after treemacs-evil
      :map evil-treemacs-state-map
      [left]  #'treemacs-COLLAPSE-action
      [right] #'treemacs-RET-action)
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
;; Treemacs hides its window from winum; number it (leftmost => SPC w 1).
(after! (treemacs winum)
  (setq winum-ignored-buffers-regexp
        (remove (regexp-quote treemacs-buffer-name-prefix)
                winum-ignored-buffers-regexp)))

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

;; Refresh git colors when a repo changes outside a save in Emacs, e.g. a commit
;; from the CLI or Claude Code. Watch each project's .git directory: git updates
;; its index/HEAD via lock-file renames, which kqueue does report. Also refresh
;; when Emacs regains focus, and re-check a file after it is reverted (edited
;; outside Emacs). Debounced; a short cooldown avoids a loop when `git status'
;; itself rewrites the index.
(defvar +my/treemacs--git-watches (make-hash-table :test #'equal))
(defvar +my/treemacs--refresh-timer nil)
(defvar +my/treemacs--last-refresh 0)

(defun +my/treemacs-refresh-all ()
  (when (featurep 'treemacs)
    (setq +my/treemacs--last-refresh (float-time))
    (treemacs-run-in-every-buffer
     (ignore-errors
       (treemacs-without-recenter
        (treemacs--do-refresh (current-buffer) 'all))))))

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
