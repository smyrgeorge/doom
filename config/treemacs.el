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
