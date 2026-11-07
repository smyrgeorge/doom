;;; $DOOMDIR/config/treemacs/follow.el -*- lexical-binding: t; -*-
;; The sidebar following the current project and file. Loaded from config/treemacs.el.

;; PROJECT FOLLOW, RIGHT AWAY
;; `treemacs-project-follow-mode' switches to the current buffer's project only
;; after 1.5 s without any input (an idle timer): switch buffers or windows and
;; keep typing or scrolling, and treemacs went on showing the old project. Now it
;; follows a moment after every switch (several switches in a row: one update),
;; and shows the file there (see SELECTION in selection.el).
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
             (unless (minibufferp buffer) ; e.g. M-x: stay
               ;; Treemacs itself (selected) and the home directory are
               ;; skipped there, like other buffers without a project.
               (when (bound-and-true-p treemacs-project-follow-mode)
                 (with-current-buffer buffer
                   (ignore-errors (treemacs--do-follow-project))))
               (+my/treemacs--follow-file buffer)))))))

;; Treemacs followed the current file a moment after any change to Emacs's
;; buffer list (see above): only on a change of buffer now.
(defadvice! +my/treemacs-follow-not-on-any-buffer-a (&rest _)
  :override #'treemacs--follow-after-buffer-list-update
  nil)

(defun +my/treemacs--follow-file (buffer)
  "Show and select BUFFER's file in the sidebar, if BUFFER is new to the
selected window since the last time (see above)."
  (unless (eq buffer (frame-parameter nil '+my/treemacs-followed))
    (when (with-current-buffer buffer
            (or buffer-file-name (derived-mode-p 'dired-mode)))
      (set-frame-parameter nil '+my/treemacs-followed buffer)
      (when (bound-and-true-p treemacs-follow-mode)
        (with-current-buffer buffer
          (treemacs--follow))))))

;; Followed: the file is the selection (point is on it).
(defadvice! +my/treemacs-select-followed-a (&rest _)
  :after #'treemacs--follow
  (when-let* ((file (or buffer-file-name
                        (and (derived-mode-p 'dired-mode) (dired-current-directory))))
              ((featurep 'treemacs))
              (window (treemacs-get-local-window)))
    (with-selected-window window
      (when-let* ((path (+my/treemacs--path-at (point)))
                  ((stringp path))
                  ((ignore-errors (file-equal-p path file))))
        (+my/treemacs--select-here)
        (hl-line-highlight)))))

(add-hook 'window-buffer-change-functions #'+my/treemacs-follow-project-soon)

(add-hook 'window-selection-change-functions #'+my/treemacs-follow-project-soon)

;; FOLLOW PROJECT BUFFERS ONLY
;; The follow (above, and treemacs's own idle one) switched the sidebar to the
;; directory of any buffer selected: popups and logs too, e.g. `doom/reload''s,
;; in Doom's ~/.config/emacs. Back and forth in a moment, and switching back
;; once left the old project's root drawn on the new one's line ("doom emacs").
;; Now only buffers that belong to a project: files, dired, magit.
(defadvice! +my/treemacs-follow-project-buffers-a (fn &rest args)
  :around #'treemacs--do-follow-project
  (when (or buffer-file-name (derived-mode-p 'dired-mode 'magit-mode))
    (apply fn args)))

;; Same race for the follow timer with two frames on different workspaces (e.g.
;; a terminal client next to the GUI): one frame's treemacs switched projects,
;; and the follow looked for a file in a tree not redrawn yet: "Error running
;; timer `treemacs--follow': (wrong-type-argument arrayp nil)". The next
;; follow finds it.
(defadvice! +my/treemacs-follow-guard-a (fn &rest args)
  :around #'treemacs--follow
  (condition-case nil
      (apply fn args)
    (wrong-type-argument nil)))

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
