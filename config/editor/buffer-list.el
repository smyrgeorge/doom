;;; $DOOMDIR/config/editor/buffer-list.el -*- lexical-binding: t; -*-
;; The buffer list (SPC b i: ibuffer) grouped by workspace. Loaded from
;; config/editor.el.

;; BY WORKSPACE
;; Doom's groups were projects (ibuffer-projectile), and only for buffers with
;; a file or a folder: Beads' issues, Claude Code's sessions, Agent UI's
;; canvases were under Default, with *Messages*, though their workspace's.
;; Now a group per workspace (persp-mode's: Doom's workspaces), in their
;; order: each buffer under the one it's in (the first, if several); a buffer
;; in none under Default. Without workspaces, projects as before.
(defun +my/buffer-list-in-workspace-p (name)
  "Non-nil if the current buffer is in the workspace NAME."
  (let ((persp (persp-get-by-name name)))
    (and (persp-p persp) (persp-contain-buffer-p (current-buffer) persp))))

(defun +my/buffer-list-groups ()
  "The buffer list's groups: one per workspace (see above); nil without
workspaces."
  (when (bound-and-true-p persp-mode)
    (mapcar (lambda (name)
              (list name (cons 'predicate `(+my/buffer-list-in-workspace-p ,name))))
            (remove persp-nil-name (persp-names-current-frame-fast-ordered)))))

(defun +my/buffer-list-group-h ()
  "In the buffer list just drawn (`ibuffer-hook'): grouped by workspace, else
by project (see above)."
  (if-let* ((groups (+my/buffer-list-groups)))
      (progn
        (setq ibuffer-filter-groups groups)
        (ibuffer-update nil t))
    (when (fboundp 'ibuffer-projectile-set-filter-groups)
      (ibuffer-projectile-set-filter-groups))))

(remove-hook 'ibuffer-hook #'ibuffer-projectile-set-filter-groups)
(add-hook 'ibuffer-hook #'+my/buffer-list-group-h)
