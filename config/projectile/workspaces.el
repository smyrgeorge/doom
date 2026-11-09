;;; $DOOMDIR/config/projectile/workspaces.el -*- lexical-binding: t; -*-
;; Each workspace remembers its project. Loaded from config/projectile.el.

;; WORKSPACES REMEMBER THEIR PROJECT
;; What an empty workspace shows is Doom's dashboard, shared by the
;; workspaces, which moves to each one's last project as you switch
;; (`last-project-root'). But leaving a workspace recorded the project of
;; whatever it showed, the dashboard too, still in the previous workspace's
;; project: a workspace whose files were all closed took on another's, and
;; there SPC SPC listed the other project's files and the sidebar followed it.
;; Only files count now, recorded as they're shown; a workspace made for a
;; project (SPC p p) stays in it, one without a file yet starts in ~, never in
;; another's.
(defun +my/workspace-shown-file ()
  "The file buffer the selected window shows, if any. Not the current buffer:
Doom's hook on buffer switches runs in whatever buffer is current, and right
after switching workspace that could still be the previous one's file, whose
project then got recorded as the new workspace's."
  (when-let* (((bound-and-true-p persp-mode))
              ((get-current-persp))
              (buffer (window-buffer)))
    (with-current-buffer buffer
      (and buffer-file-name
           (not (file-remote-p default-directory))
           buffer))))

(defun +my/workspace-record-project-h ()
  "Record the project of the file shown as the current workspace's."
  (when-let* ((buffer (+my/workspace-shown-file))
              (root (with-current-buffer buffer (doom-project-root))))
    (set-persp-parameter 'last-project-root root (get-current-persp))))

(add-hook 'doom-switch-buffer-hook #'+my/workspace-record-project-h)

(defadvice! +my/workspace-record-files-only-a (fn &optional persp &rest args)
  "Leaving a workspace, record its project only from the file it shows (see
above). Not when one is made (PERSP): what's shown is still the previous
workspace's."
  :around #'+dashboard--persp-record-project-h
  (unless (and persp (persp-p persp))
    (when-let* ((buffer (+my/workspace-shown-file)))
      (with-current-buffer buffer
        (apply fn persp args)))))

(defun +my/workspace-project ()
  "The current workspace's project (see above), or nil without workspaces."
  (when (and (bound-and-true-p persp-mode) (get-current-persp))
    (file-name-as-directory
     (expand-file-name (or (persp-parameter '+workspace-project)
                           (persp-parameter 'last-project-root)
                           "~")))))

(defadvice! +my/workspace-own-project-a (&rest _)
  "Entering a workspace, put the dashboard in its project (see above)."
  :override #'+dashboard--persp-detect-project-h
  (when-let* ((project (+my/workspace-project)))
    (+dashboard-update-pwd-h project)))

;; The dashboard's reload also sets its folder, after the above, from the last
;; file visited in any workspace (`+dashboard-pwd-policy' `last-project'):
;; switching with SPC TAB 1, 2... put it back in the previous workspace's
;; project. That's the current workspace's project too now.
(defadvice! +my/workspace-dashboard-pwd-a (fn)
  :around #'+dashboard--pwd
  (or (+my/workspace-project) (funcall fn)))
