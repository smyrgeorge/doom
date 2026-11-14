;;; $DOOMDIR/config/treemacs/expand.el -*- lexical-binding: t; -*-
;; Expanding and collapsing all folders. Loaded from config/treemacs.el.

;; zR opens the folders the count counts, no more: not .git (git's, hundreds of
;; folders), not links to folders (one to a big folder elsewhere was opened
;; whole without asking, and a link up the tree opened it again and again,
;; until Emacs gave up half way: "Apparent cycle of symbolic links"), not
;; folders it can't read (both the count and zR failed on one: "Opening
;; directory: Permission denied", nothing opened).
(defun +my/treemacs--expandable-dir-p (file)
  "Non-nil if zR opens folder FILE (see above)."
  (and (not (file-symlink-p file))
       (not (equal (file-name-nondirectory (directory-file-name file)) ".git"))
       (file-accessible-directory-p file)))

(defun +my/treemacs--count-dirs (dir limit)
  "Count the folders under DIR that zR opens, stopping once past LIMIT."
  (let ((count 0) (stack (list dir)))
    (while (and stack (<= count limit))
      (dolist (file (directory-files (pop stack) t directory-files-no-dot-files-regexp t))
        (when (and (file-directory-p file) (+my/treemacs--expandable-dir-p file))
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
         ;; Close it (forgetting what was open below), then reopen recursively,
         ;; the folders the count skips left closed (see above).
         (when (eq (treemacs-button-get pos :state) 'root-node-open)
           (treemacs--collapse-root-node pos t))
         (let ((expand-dir (symbol-function 'treemacs--expand-dir-node)))
           (cl-letf (((symbol-function 'treemacs--expand-dir-node)
                      (lambda (btn &rest args)
                        (when (+my/treemacs--expandable-dir-p (treemacs-button-get btn :path))
                          (apply expand-dir btn args)))))
             (treemacs--expand-root-node pos t))))))))

(defun treemacs-collapse-all ()
  "Collapse every folder of the projects shown in treemacs (projects stay open)."
  (interactive)
  (+my/treemacs--do-projects
   (lambda (_project pos)
     (when (eq (treemacs-button-get pos :state) 'root-node-open)
       (treemacs--collapse-root-node pos t))
     (treemacs--expand-root-node pos))))
