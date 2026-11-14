;;; $DOOMDIR/config/search/files.el -*- lexical-binding: t; -*-
;; Files: the project's, recently opened ones first.
;; Loaded from config/search.el.

(defun +my/search-everywhere--files (root)
  "ROOT's project files relative to ROOT, recently opened ones first."
  (require 'projectile)
  (let* ((root (expand-file-name root))
         (recent (cl-loop for file in (bound-and-true-p recentf-list)
                          for abs = (expand-file-name file)
                          when (and (string-prefix-p root abs) (file-exists-p abs))
                          collect (file-relative-name abs root))))
    (delete-dups (append recent (projectile-project-files root)))))

(defun +my/search-everywhere--file-items (files)
  "FILES (relative to the project's root) as the list shows them: each one's
name first, then its folder, dimmed, so a narrow frame still shows the name.
Picking one gives its relative path."
  (mapcar (lambda (file)
            (let ((folder (file-name-directory file)))
              (cons (concat (file-name-nondirectory file)
                            (and folder
                                 (propertize (concat "  " (directory-file-name folder))
                                             'face 'completions-annotations)))
                    file)))
          files))
