;;; $DOOMDIR/config/beads/project.el -*- lexical-binding: t; -*-
;; The project's issues: SPC o i, SPC o I. Loaded from config/beads.el.

;; THE PROJECT'S ISSUES
;; SPC o i: the issues of the project the current buffer is in (its .beads/),
;; SPC o I: a new one there (title, type, priority). A project without .beads/
;; isn't made one here: `bd init' does that, and adds files for agents too.
(defun +my/beads-root ()
  "The current project's root, if it tracks its issues with Beads."
  (when-let* ((root (or (doom-project-root) default-directory)))
    (and (file-directory-p (expand-file-name ".beads" root))
         (file-name-as-directory (expand-file-name root)))))

(defun +my/beads--root-or-error ()
  (or (+my/beads-root)
      (user-error "No issues here: run `bd init' in %s to track them with Beads"
                  (abbreviate-file-name (or (doom-project-root) default-directory)))))

(defun +my/beads-project ()
  "The current project's issues (see above)."
  (interactive)
  (let ((default-directory (+my/beads--root-or-error)))
    (beads-list)))

(defun +my/beads-new-issue ()
  "A new issue in the current project (see above)."
  (interactive)
  (let ((default-directory (+my/beads--root-or-error)))
    (require 'beads)
    (call-interactively #'beads-create-issue)))
