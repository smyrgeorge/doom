;;; $DOOMDIR/config/beads/project.el -*- lexical-binding: t; -*-
;; The project's issues: SPC o i, SPC o I. Loaded from config/beads.el.

;; THE PROJECT'S ISSUES
;; SPC o i: the issues of the project the current buffer is in (its .beads/),
;; SPC o I: a new one there (title, type, priority). A project without .beads/
;; is offered one (see STARTING below).
(defun +my/beads--project-root ()
  "The current project's root (else this folder)."
  (file-name-as-directory (expand-file-name (or (doom-project-root) default-directory))))

(defun +my/beads-root ()
  "The current project's root, if it tracks its issues with Beads."
  (let ((root (+my/beads--project-root)))
    (and (file-directory-p (expand-file-name ".beads" root))
         root)))

;; STARTING
;; In a project without .beads/, SPC o i and SPC o I ask to start tracking its
;; issues, then run `bd init' (`+my/beads-init-args'). bd commits what it adds
;; (.beads/, .gitignore), and what's staged with it: with something staged it
;; isn't run (commit or unstage it first).
(defun +my/beads--staged-p (root)
  "Non-nil if ROOT's git repository has staged changes."
  (let ((default-directory root))
    (eql 1 (ignore-errors (call-process "git" nil nil nil "diff" "--cached" "--quiet")))))

(defun +my/beads-init (root)
  "Start tracking ROOT's issues with Beads, once asked (see STARTING)."
  (unless (executable-find "bd")
    (user-error "No bd: scripts/tools.sh installs it"))
  (when (+my/beads--staged-p root)
    (user-error "bd init would commit what's staged in %s too: commit or unstage it first"
                (abbreviate-file-name root)))
  (unless (y-or-n-p (format "Track %s's issues with Beads? (bd init: .beads/, committed) "
                            (abbreviate-file-name root)))
    (user-error "Not tracking %s's issues" (abbreviate-file-name root)))
  (with-temp-buffer
    (let ((default-directory root))
      (unless (eql 0 (apply #'call-process "bd" nil t nil +my/beads-init-args))
        (user-error "bd init failed: %s" (string-trim (buffer-string))))))
  (message "Tracking %s's issues with Beads" (abbreviate-file-name root))
  root)

(defun +my/beads--root-or-init ()
  "The current project's root, its issues tracked with Beads (started now if
need be, see STARTING)."
  (or (+my/beads-root)
      (+my/beads-init (+my/beads--project-root))))

(defun +my/beads-project ()
  "The current project's issues (see above)."
  (interactive)
  (let ((default-directory (+my/beads--root-or-init)))
    (beads-list)))

(defun +my/beads-new-issue ()
  "A new issue in the current project (see above)."
  (interactive)
  (let ((default-directory (+my/beads--root-or-init)))
    (require 'beads)
    (call-interactively #'beads-create-issue)))
