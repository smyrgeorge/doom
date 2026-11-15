;;; $DOOMDIR/config/agent-workspace/new.el -*- lexical-binding: t; -*-
;; Making an agent: what you're asked, a name made for it. Loaded from
;; config/agent-workspace.el, after roles.el. No Doom here.
;;
;; `agent-workspace-new' (what the app's c runs) asks its role, annotated with
;; what it does and how many of it run against its max (one at its max is
;; refused), then its name: left empty, one from `agent-workspace-names'. With
;; C-u, its model, permission mode and colour too. Then
;; `agent-workspace-create' makes it: its worktree, its session; given an
;; issue, that issue is its first message.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; ====== VARIABLES ======

(defcustom agent-workspace-names
  '("ada" "grace" "linus" "ken" "margaret" "barbara" "edsger" "dennis" "frances" "hedy" "joan" "radia"
    "tim" "ivan" "niklaus" "ole" "peter" "sophie" "vint" "whitfield" "yukihiro")
  "The names a new agent gets when you leave its name empty, in order: one
in use, whose initial an agent has, or left by a forgotten agent (its
worktree or branch there) is passed over. None left: its role and a number
\(builder-3)."
  :type '(repeat string)
  :group 'agent-workspace)

(defcustom agent-workspace-models '("opus" "sonnet" "haiku")
  "The models offered when you choose one (C-u c); \"inherit\": your
default."
  :type '(repeat string)
  :group 'agent-workspace)

;; ====== A NAME ======

(defun agent-workspace--name-left-p (project name)
  "Non-nil if a forgotten agent NAME left its worktree or branch in PROJECT."
  (let ((default-directory project)
        (worktrees (expand-file-name agent-workspace-worktrees-directory project)))
    (or (agent-workspace--branch-p (agent-workspace-branch name))
        ;; Its folder: NAME, as they were named before, or ROLE-NAME (one
        ;; whose lock or branch says another name isn't its: ROLE-mary-NAME).
        (seq-some (lambda (folder)
                    (or (equal folder name)
                        (and (string-suffix-p (concat "-" name) folder)
                             (member (agent-workspace--worktree-agent-name (expand-file-name folder worktrees))
                                     (list name nil)))))
                  (and (file-directory-p worktrees) (directory-files worktrees nil "\\`[^.]"))))))

(defun agent-workspace-pool-name (project role)
  "A name for a new agent of ROLE in PROJECT's crew (see
`agent-workspace-names')."
  (let* ((names (mapcar #'agent-workspace-agent-name (agent-workspace-agents project)))
         (initials (mapcar (lambda (name) (aref name 0)) names)))
    (or (seq-find (lambda (name)
                    (and (not (member name names))
                         (not (memq (aref name 0) initials))
                         (not (agent-workspace--name-left-p project name))))
                  agent-workspace-names)
        (cl-loop for n from 1
                 for name = (format "%s-%d" role n)
                 unless (or (member name names) (agent-workspace--name-left-p project name))
                 return name))))

;; ====== WHAT YOU'RE ASKED ======

(defun agent-workspace--role-annotation (project role)
  "What ROLE does and how many of it run, after its name: \" · builds what
you give it · 2 of 4\"; nil if it says neither."
  (let* ((spec (agent-workspace--project-role project role))
         (max (plist-get spec :max))
         (count (agent-workspace-role-count project role)))
    (when-let* ((parts (delq nil (list (plist-get spec :description)
                                       (cond (max (format "%d of %d" count max))
                                             ((> count 0) (format "%d" count)))))))
      (concat " · " (string-join parts " · ")))))

(defun agent-workspace-read-role (project &optional default)
  "A role of PROJECT's read in the minibuffer (DEFAULT first), each
annotated (`agent-workspace--role-annotation'); one with as many agents as
it allows is refused, and asked again."
  (let* ((roles (mapcar #'car (agent-workspace-roles project)))
         (roles (if (member default roles) (cons default (delete default roles)) roles))
         (completion-extra-properties
          (list :annotation-function (lambda (role) (agent-workspace--role-annotation project role)))))
    (catch 'role
      (while t
        (let ((role (completing-read "Role: " roles nil t nil nil (car roles))))
          (condition-case err
              (progn (agent-workspace--check-room project role)
                     (throw 'role role))
            (user-error (message "%s" (error-message-string err))
                        (sit-for 1.5))))))))

(defun agent-workspace-read-name (project role)
  "A name for a new agent of ROLE read in the minibuffer: left empty, one
made for it; one taken or not valid is refused, and asked again."
  (let ((made (agent-workspace-pool-name project role)))
    (catch 'name
      (while t
        (let ((name (string-trim (read-string (format "Name (empty: %s): " made)))))
          (if (string-empty-p name)
              (throw 'name made)
            (condition-case err
                (progn (agent-workspace--check-name name project)
                       (throw 'name name))
              (user-error (message "%s" (error-message-string err))
                          (sit-for 1.5)))))))))

(defun agent-workspace--read-more (project role)
  "Its model, permission mode and colour, read (its role's, else
`agent-workspace-mode', and a free one by default): (:model :mode :colour)."
  (let* ((spec (agent-workspace--project-role project role))
         (model (completing-read (format "Model (%s's: %s): " role (or (plist-get spec :model) "inherit"))
                                 (cons "inherit" agent-workspace-models) nil nil nil nil
                                 (or (plist-get spec :model) "inherit")))
         (mode (completing-read "Permission mode: " agent-workspace-modes nil t nil nil
                                (or (plist-get spec :mode) agent-workspace-mode "default")))
         (colour (completing-read "Colour: " agent-workspace-colours nil t nil nil
                                  (agent-workspace-free-colour project (plist-get spec :colour)))))
    (list :model (unless (member model '("" "inherit")) model)
          :mode mode
          :colour colour)))

(defun agent-workspace-new (&optional more role issue title)
  "Make a new agent in this project's crew: you're asked its role, then its
name (left empty, one is made for it); MORE (C-u): its model, permission
mode and colour too. ROLE is offered first. ISSUE (with its TITLE): the
issue it's for, its first message. It gets its worktree, its session
starts, then it waits for you. Return it."
  (interactive "P")
  (let ((project (agent-workspace-project)))
    (when-let* ((reason (agent-workspace-no-crew-reason)))
      (user-error "No crew here: %s" reason))
    (let* ((role (agent-workspace-read-role project role))
           (name (agent-workspace-read-name project role))
           (more (and more (agent-workspace--read-more project role))))
      (apply #'agent-workspace-create
             :project project :role role :name name :issue issue :issue-title title
             more))))
