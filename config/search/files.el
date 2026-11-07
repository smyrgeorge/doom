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
