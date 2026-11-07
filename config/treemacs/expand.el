;;; $DOOMDIR/config/treemacs/expand.el -*- lexical-binding: t; -*-
;; Expanding and collapsing all folders. Loaded from config/treemacs.el.

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
