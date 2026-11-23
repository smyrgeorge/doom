;;; $DOOMDIR/config/agent-workflow/check.el -*- lexical-binding: t; -*-
;; M-x agent-workflow-check: every workflow and profile of a project read
;; anew, their problems listed, each line taking you to its file and line.
;; Loaded from config/agent-workflow.el, after workflows.el. No Doom here.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defun agent-workflow--check-file (file project)
  "FILE checked alone, as a workflow (.yml, .yaml) or a profile (.md):
its problems, a workflow's against PROJECT's profiles."
  (cond
   ((string-match-p "\\.ya?ml\\'" file)
    (cdr (agent-workflow-workflow-read file (mapcar #'car (agent-workflow-profiles project)))))
   ((string-match-p "\\.md\\'" file) (cdr (agent-workflow-profile-read file)))
   (t (user-error "%s: a workflow (.yml) or a profile (.md)" (abbreviate-file-name file)))))

(defun agent-workflow-check-problems (&optional project file)
  "The problems of PROJECT's workflows and profiles (default: the current
project's), all read anew; FILE: only that file's, a workflow or a profile
anywhere. Each (error|warning \"FILE:LINE: what\" FILE LINE \"what\")."
  (let ((project (or project (agent-workflow-project))))
    (remhash (or project "") agent-workflow--profiles-cache)
    (remhash (or project "") agent-workflow--workflows-cache)
    (if file
        (agent-workflow--check-file (expand-file-name file) project)
      (append (agent-workflow-profile-problems project) (agent-workflow-workflow-problems project)))))

(defun agent-workflow-check (&optional project file)
  "Check PROJECT's workflows and profiles (default: the current project's),
all read anew (the starters, the project's, yours); FILE: only that file.
Every problem a line FILE:LINE: error|warning: what, in a buffer whose lines
visit their file and line (RET, a click); none, said. Return the problems."
  (interactive)
  (let* ((project (or project (agent-workflow-project)))
         (problems (agent-workflow-check-problems project file))
         (errors (seq-count (lambda (p) (eq (car p) 'error)) problems))
         (warnings (- (length problems) errors)))
    (if (not problems)
        (message "%s" (if file
                          (format "%s: no problems" (abbreviate-file-name file))
                        (format "%d workflows, %d profiles, no problems"
                                (length (agent-workflow-workflows project))
                                (length (agent-workflow-profiles project)))))
      (let ((buffer (get-buffer-create "*agent-workflow check*")))
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (setq default-directory (or project default-directory))
            (insert (format "The workflows and profiles of %s: %d error%s, %d warning%s\n\n"
                            (if project (abbreviate-file-name (directory-file-name project)) "no project")
                            errors (if (= errors 1) "" "s") warnings (if (= warnings 1) "" "s")))
            (pcase-dolist (`(,level ,_ ,file ,n ,what) problems)
              (insert (format "%s:%d: %s: %s\n"
                              (if (and project (file-in-directory-p file project))
                                  (file-relative-name file project)
                                (abbreviate-file-name file))
                              n level what))))
          (require 'compile)
          (compilation-mode)
          (goto-char (point-min)))
        (when (called-interactively-p 'any)
          (pop-to-buffer buffer))))
    problems))
