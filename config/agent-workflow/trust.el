;;; $DOOMDIR/config/agent-workflow/trust.el -*- lexical-binding: t; -*-
;; Trust: code from a repository runs with your permissions. Loaded from
;; config/agent-workflow.el, after beads.el. No Doom here.
;;
;; A workflow's scripts, its elisp: steps and its if: run as you, with all
;; you may do: a project's own workflows (.agent-workflow/, committed) run
;; only once you trust the project. Asked the first time from Emacs: run it
;; (this once), trust the project (remembered, in
;; `agent-workflow-trust-file'), or no. From the shell, refused until you
;; trust it (M-x agent-workflow-trust). The starters (this config's) and
;; yours (out of git) are trusted. A project you no longer trust: M-x
;; agent-workflow-forget-trust.
;;
;; Agents can't change what runs them: every agent of the pool is denied
;; editing .agent-workflow/ (pool.el), and a branch that changes it is
;; merged only once you say so (steps.el), whatever the workflow's approve:
;; says.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar agent-workflow-trust-file)

(defun agent-workflow--trusted ()
  "The projects you trust: their folders."
  (when (file-readable-p agent-workflow-trust-file)
    (ignore-errors (with-temp-buffer (insert-file-contents agent-workflow-trust-file) (read (current-buffer))))))

(defun agent-workflow-trusted-p (project)
  "Non-nil if you trust PROJECT's workflows."
  (member (file-name-as-directory (expand-file-name project)) (agent-workflow--trusted)))

(defun agent-workflow-trust (project)
  "Trust PROJECT's workflows (default: the current project's): its scripts,
elisp and if: run as you."
  (interactive (list (or (agent-workflow-project) (user-error "Not in a git repository"))))
  (let ((project (file-name-as-directory (expand-file-name project))))
    (unless (agent-workflow-trusted-p project)
      (make-directory (file-name-directory agent-workflow-trust-file) t)
      (with-temp-file agent-workflow-trust-file
        (prin1 (cons project (agent-workflow--trusted)) (current-buffer))))
    (when (called-interactively-p 'any)
      (message "Trusted: %s's workflows" (file-name-nondirectory (directory-file-name project))))
    project))

(defun agent-workflow-forget-trust (project)
  "No longer trust PROJECT's workflows."
  (interactive (list (completing-read "No longer trust: " (agent-workflow--trusted) nil t)))
  (with-temp-file agent-workflow-trust-file
    (prin1 (remove (file-name-as-directory (expand-file-name project)) (agent-workflow--trusted)) (current-buffer))))

(defun agent-workflow--check-trust (project workflow ask)
  "A user error unless WORKFLOW (a plist) may run in PROJECT: a starter or
yours, or the project's when you trust it; ASK: asked if you don't (run it,
trust it, no)."
  (when (and (eq (plist-get workflow :origin) 'project) (not (agent-workflow-trusted-p project)))
    (let ((name (file-name-nondirectory (directory-file-name project))))
      (if (not ask)
          (agent-workflow--refuse "%s's workflows run as you, and you don't trust it yet: M-x agent-workflow-trust in it" name)
        (pcase (car (read-multiple-choice
                     (format "%s's workflow %s runs its scripts and Lisp as you. Run it?" name (plist-get workflow :name))
                     '((?y "run it" "this once")
                       (?t "trust the project" "its workflows from now on")
                       (?n "no" "nothing runs"))))
          (?y nil)
          (?t (agent-workflow-trust project))
          (_ (user-error "Not run: you don't trust %s's workflows" name)))))))
