;;; $DOOMDIR/config/agent-workflow/beads.el -*- lexical-binding: t; -*-
;; The project's issues, as runs need them: an issue read (its title, text,
;; type, labels, its blockers still open), an epic's issues, and what the
;; engine writes on an issue. Loaded from config/agent-workflow.el, after
;; pool.el. No Doom here.
;;
;; bd runs in the project, waiting for it. The engine writes as
;; `agent-workflow-bd-actor' (agent-workflow): a run's state in the issue's
;; metadata (workflow, workflow_run, workflow_state, workflow_jobs), its job
;; running as a label (job:NAME), what each job said in its notes. Agents
;; never change the issue: only the engine does.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'json)

(defvar agent-workflow-bd-actor "agent-workflow"
  "Who the engine's writes are in the issues' history (BEADS_ACTOR).")

;; ====== BD ======

(defun agent-workflow--bd (project args &optional actor)
  "Run bd with ARGS in PROJECT as ACTOR (default: the engine), waiting for
it: (STATUS . OUTPUT). A user error without bd, or Beads there."
  (unless (executable-find "bd")
    (user-error "No bd: a run's issues are Beads' (scripts/tools.sh installs it)"))
  (unless (file-directory-p (expand-file-name ".beads" project))
    (user-error "%s tracks no issues with Beads (bd init)" (file-name-nondirectory (directory-file-name project))))
  (with-temp-buffer
    (let* ((default-directory (file-name-as-directory project))
           (process-environment (cons (concat "BEADS_ACTOR=" (or actor agent-workflow-bd-actor))
                                      process-environment))
           (status (apply #'process-file "bd" nil (list t nil) nil args)))
      (cons status (buffer-string)))))

(defun agent-workflow--bd-json (project &rest args)
  "bd's JSON for ARGS in PROJECT (--json added): alists, lists; a user error
if it fails."
  (pcase-let ((`(,status . ,output) (agent-workflow--bd project (append args '("--json")))))
    (unless (eql status 0)
      (user-error "bd %s: %s" (car args) (string-trim output)))
    (json-parse-string output :object-type 'alist :array-type 'list :null-object nil :false-object nil)))

(defun agent-workflow--bd-write (project id &rest args)
  "bd update ID ARGS in PROJECT, as the engine: nil, or what went wrong
\(said, never an error: the run goes on)."
  (pcase-let ((`(,status . ,output) (ignore-errors (agent-workflow--bd project (append (list "update" id) args)))))
    (unless (eql status 0)
      (let ((why (string-trim (or output "no bd"))))
        (message "agent workflow: bd update %s: %s" id why)
        why))))

;; ====== AN ISSUE ======

(defun agent-workflow-issue (project id)
  "Issue ID of PROJECT, read: a plist (:id :title :description
:acceptance :notes :type :priority :status :labels :blockers), its
blockers those it depends on still open. A user error if there's none."
  (let* ((found (agent-workflow--bd-json project "show" id))
         (issue (if (and (listp found) (consp (car found)) (not (symbolp (caar found)))) (car found) found)))
    (unless (alist-get 'id issue)
      (user-error "No issue %s" id))
    (list :id (alist-get 'id issue)
          :title (or (alist-get 'title issue) "")
          :description (or (alist-get 'description issue) "")
          :acceptance (or (alist-get 'acceptance_criteria issue) "")
          :notes (or (alist-get 'notes issue) "")
          :type (or (alist-get 'issue_type issue) "task")
          :priority (or (alist-get 'priority issue) 2)
          :status (or (alist-get 'status issue) "open")
          :labels (alist-get 'labels issue)
          :blockers (delq nil (mapcar (lambda (dependency)
                                        (and (equal (alist-get 'dependency_type dependency) "blocks")
                                             (not (equal (alist-get 'status dependency) "closed"))
                                             (alist-get 'id dependency)))
                                      (alist-get 'dependencies issue))))))

(defun agent-workflow-epic-issues (project id)
  "The open issues of PROJECT's epic ID (its descendants, not epics
themselves), their ids, in the order bd lists them."
  (delq nil (mapcar (lambda (issue)
                      (unless (equal (alist-get 'issue_type issue) "epic")
                        (alist-get 'id issue)))
                    (agent-workflow--bd-json project "list" "--parent" id "--status" "open,in_progress"
                                             "--limit" "0"))))

(defun agent-workflow-open-issues (project)
  "PROJECT's open issues: ((ID TITLE TYPE) ...), as bd lists them."
  (mapcar (lambda (issue)
            (list (alist-get 'id issue) (alist-get 'title issue) (alist-get 'issue_type issue)))
          (agent-workflow--bd-json project "list" "--status" "open,in_progress" "--limit" "0")))
