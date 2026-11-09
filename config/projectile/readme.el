;;; $DOOMDIR/config/projectile/readme.el -*- lexical-binding: t; -*-
;; A project (SPC p p) opens on its README. Loaded from config/projectile.el.

;; README FIRST
;; Picking a project (SPC p p) opens its README straight away when it has one
;; at its root, instead of asking for a file; otherwise it asks, as Doom does.
;; Several READMEs: as `+my/project-readme-extensions' orders them
;; (config/projectile.el); any case (readme.md too).
(defun +my/project-readme (dir)
  "The README file at DIR's root, if any (see above)."
  (let ((found (seq-filter
                (lambda (file)
                  (and (string-match-p "\\`readme\\(\\.[[:alnum:]]+\\)?\\'" (downcase file))
                       (member (downcase (or (file-name-extension file) ""))
                               +my/project-readme-extensions)
                       (file-regular-p (expand-file-name file dir))))
                (directory-files dir))))
    (when found
      (expand-file-name
       (car (seq-sort-by (lambda (file)
                           (seq-position +my/project-readme-extensions
                                         (downcase (or (file-name-extension file) ""))))
                         #'< found))
       dir))))

(defun +my/project-open-readme (dir)
  "After switching to project DIR: its README, else Doom's file prompt."
  (if-let* ((readme (+my/project-readme dir)))
      (find-file readme)
    (doom-project-find-file dir)))

(setq +workspaces-switch-project-function #'+my/project-open-readme)
