;;; $DOOMDIR/config/projectile/readme.el -*- lexical-binding: t; -*-
;; A project (SPC p p) opens on its README. Loaded from config/projectile.el.

;; README FIRST
;; Picking a project (SPC p p) opens its README straight away when it has one
;; at its root, instead of asking for a file; otherwise it asks, as Doom does.
;; Only in a workspace that shows nothing yet (a new one): picking a project
;; open in its own workspace again (Doom runs this then too) put its README
;; over the pane you'd left there; it asks there, as Doom does. Several
;; READMEs: as `+my/project-readme-extensions' orders them
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
  "After switching to project DIR: its README in a workspace that shows
nothing yet (Doom's fallback buffer), else Doom's file prompt (see above).
The workspace is DIR's first (config/projectile/workspaces.el): Doom says so
only of a workspace it makes, not of an empty one it took over, which the
prompt left (C-g) then put in ~."
  (when (and (bound-and-true-p persp-mode) (get-current-persp))
    (set-persp-parameter '+workspace-project dir))
  (if-let* (((eq (window-buffer) (doom-fallback-buffer)))
            (readme (+my/project-readme dir)))
      (find-file readme)
    (doom-project-find-file dir)))

(setq +workspaces-switch-project-function #'+my/project-open-readme)
