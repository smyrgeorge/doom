;;; $DOOMDIR/config/agent-workspace/roles.el -*- lexical-binding: t; -*-
;; Roles: what each kind of agent does and may do. Loaded from
;; config/agent-workspace.el, after core.el. No Doom here.
;;
;; A role is a Markdown file, NAME.md, as Claude Code's own agents are
;; (.claude/agents/*.md): a front matter, then its instructions (added to its
;; agents' system prompt). The starters ship here, in roles/ (scribe,
;; investigator, builder, reviewer); a project's own, in its
;; .agent-workspace/roles/, add to them or replace one of the same name.
;;
;;   ---
;;   name: builder                  its file's name, if given
;;   description: builds what you give it
;;   tools: Read, Edit, Bash(git:*)  allowed without asking (Claude Code's
;;                                   allowedTools); a YAML list too
;;   deny: WebFetch                  never available (disallowedTools)
;;   model: opus                     inherit (or none): the user's default
;;   mode: acceptEdits               its permission mode: default,
;;                                   acceptEdits, plan, dontAsk,
;;                                   bypassPermissions (or accept-edits...)
;;   labels: build                   the issues it's for
;;   talks-to: reviewer              the roles it may message without your OK
;;   max: 4                          how many of it may run at once
;;   icon: md-hammer ⚙               a nerd icon (GUI), a glyph (terminal)
;;   verb: building                  what it does, working: "building doom-a1b"
;;   colour: blue                    its agents' colour, while it's free
;;   ---
;;   Its instructions.
;;
;; There's no worktree key: every agent has its own (worktree.el). A
;; problem names the file and line: an error leaves the role out, a warning
;; (an unknown key) doesn't.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; ====== VARIABLES ======

(defcustom agent-workspace-roles-directory ".agent-workspace/roles"
  "Where a project keeps its own roles."
  :type 'string
  :group 'agent-workspace)

(defvar agent-workspace-starter-roles-directory
  (expand-file-name "roles/" (file-name-directory (or load-file-name buffer-file-name)))
  "The starter roles, shipped with this module.")

(defconst agent-workspace-modes '("default" "acceptEdits" "plan" "dontAsk" "bypassPermissions")
  "Claude Code's permission modes.")

(defconst agent-workspace--role-keys
  '("name" "description" "tools" "deny" "model" "mode" "labels" "talks-to" "max" "icon" "verb" "colour" "color")
  "A role file's keys (color as Claude Code's agents spell it).")

(defvar agent-workspace--roles-cache (make-hash-table :test #'equal)
  "A project's roles, as last read: project to (STAMP ROLES PROBLEMS), STAMP
the role files and their modification times.")

;; ====== A ROLE FILE ======

(defun agent-workspace--role-list (value)
  "VALUE, a role file's list: \"a, b\" or \"[a, b]\" as (\"a\" \"b\")."
  (let ((value (string-trim value)))
    (when (string-match "\\`\\[\\(.*\\)\\]\\'" value)
      (setq value (match-string 1 value)))
    (seq-remove #'string-empty-p
                (mapcar (lambda (item) (agent-workspace--role-unquote (string-trim item)))
                        (split-string value ",")))))

(defun agent-workspace--role-unquote (value)
  "VALUE without the quotes around it, if any."
  (if (string-match "\\`\\([\"']\\)\\(.*\\)\\1\\'" value)
      (match-string 2 value)
    value))

(defun agent-workspace--mode-id (value)
  "VALUE, a permission mode as Claude Code names it or in kebab-case
\(accept-edits), as Claude Code's id; nil if it isn't one."
  (let ((id (replace-regexp-in-string "-\\([a-z]\\)" (lambda (m) (upcase (substring m 1))) value)))
    (car (member id agent-workspace-modes))))

(defun agent-workspace-role-read (file)
  "Read the role FILE: (ROLE . PROBLEMS). ROLE is a plist (see the top of
this file), nil if FILE has errors; PROBLEMS, each (error|warning
\"FILE:LINE: what\")."
  (let* ((name (file-name-sans-extension (file-name-nondirectory file)))
         (shown (abbreviate-file-name file))
         (role (list :name name :file file))
         (problems nil)
         (line 0))
    (cl-flet ((problem (level n format &rest args)
                (push (list level (format "%s:%d: %s" shown n (apply #'format format args)))
                      problems)))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (if (not (looking-at-p "---[ \t]*$"))
            (problem 'error 1 "no front matter: it starts with a line ---, its keys, then a line ---")
          (forward-line 1)
          (setq line 2)
          (let ((key nil) (list nil) (closed nil))
            (cl-flet ((store (key value n)
                        (pcase key
                          ((or "tools" "deny" "labels" "talks-to")
                           (setq role (plist-put role (intern (concat ":" key))
                                                 (if (listp value) value (agent-workspace--role-list value)))))
                          ("name"
                           (unless (equal value name)
                             (problem 'error n "its name is %s, its file's %s: they must agree" value name)))
                          ("description" (setq role (plist-put role :description value)))
                          ("verb" (setq role (plist-put role :verb value)))
                          ("model"
                           (unless (member value '("" "inherit"))
                             (setq role (plist-put role :model value))))
                          ("mode"
                           (if-let* ((id (agent-workspace--mode-id value)))
                               (setq role (plist-put role :mode id))
                             (problem 'error n "mode %s: not one of %s" value
                                      (string-join agent-workspace-modes ", "))))
                          ("max"
                           (if (string-match-p "\\`[1-9][0-9]*\\'" value)
                               (setq role (plist-put role :max (string-to-number value)))
                             (problem 'error n "max %s: not a number above 0" value)))
                          ((or "colour" "color")
                           (if (member value agent-workspace-colours)
                               (setq role (plist-put role :colour value))
                             (problem 'error n "colour %s: not one of %s" value
                                      (string-join agent-workspace-colours ", "))))
                          ("icon"
                           (let ((parts (split-string value)))
                             (setq role (plist-put role :icon (car parts)))
                             (when (cadr parts)
                               (setq role (plist-put role :glyph (cadr parts)))))))))
              (while (and (not closed) (not (eobp)))
                (let ((text (buffer-substring-no-properties (point) (line-end-position))))
                  (cond
                   ((string-match-p "\\`---[ \t]*\\'" text)
                    (when key (store key (nreverse list) (1- line)))
                    (setq closed t key nil))
                   ((string-match-p "\\`[ \t]*\\(#.*\\)?\\'" text))
                   ;; An item of a YAML list, under its key.
                   ((string-match "\\`[ \t]+-[ \t]+\\(.*\\)\\'" text)
                    (if key
                        (push (agent-workspace--role-unquote (string-trim (match-string 1 text))) list)
                      (problem 'error line "a list item with no key before it")))
                   ((string-match "\\`\\([A-Za-z_-]+\\):[ \t]*\\(.*\\)\\'" text)
                    (when key (store key (nreverse list) (1- line)))
                    (setq key nil list nil)
                    (let ((k (downcase (match-string 1 text)))
                          (value (agent-workspace--role-unquote (string-trim (match-string 2 text)))))
                      (cond
                       ((equal k "worktree")
                        (problem 'warning line "worktree: ignored (every agent has its own worktree)"))
                       ((not (member k agent-workspace--role-keys))
                        (problem 'warning line "unknown key %s: ignored" k))
                       ((and (string-empty-p value) (member k '("tools" "deny" "labels" "talks-to")))
                        ;; Its items on the lines below.
                        (setq key k))
                       (t (store k value line)))))
                   (t (problem 'error line "not a key: %s" (string-trim text))))
                  (forward-line 1)
                  (cl-incf line)))
              (if (not closed)
                  (problem 'error line "its front matter isn't closed: a line --- after its keys")
                (let ((instructions (string-trim (buffer-substring-no-properties (point) (point-max)))))
                  (unless (string-empty-p instructions)
                    (setq role (plist-put role :instructions instructions))))))))))
    (setq problems (nreverse problems))
    (cons (unless (assq 'error problems) role) problems)))

;; ====== A PROJECT'S ROLES ======

(defun agent-workspace--role-files (project)
  "The role files for PROJECT: the starters, then its own (which replace
those of the same name)."
  (append (directory-files agent-workspace-starter-roles-directory t "\\`[^.].*\\.md\\'")
          (when project
            (let ((dir (expand-file-name agent-workspace-roles-directory project)))
              (when (file-directory-p dir)
                (directory-files dir t "\\`[^.].*\\.md\\'"))))))

(defun agent-workspace--roles-read (project)
  "PROJECT's roles and their problems, read again if a file changed:
\(ROLES . PROBLEMS), ROLES an alist of a name and its role, in order (the
starters first). New problems are shown as warnings."
  (let* ((files (agent-workspace--role-files project))
         (stamp (mapcar (lambda (file)
                          (cons file (file-attribute-modification-time (file-attributes file))))
                        files))
         (key (or project ""))
         (cached (gethash key agent-workspace--roles-cache)))
    (if (equal (car cached) stamp)
        (cdr cached)
      (let (roles problems)
        (dolist (file files)
          (pcase-let ((`(,role . ,found) (agent-workspace-role-read file)))
            (setq problems (append problems found))
            (when role
              (setf (alist-get (plist-get role :name) roles nil nil #'equal) role))))
        (dolist (problem problems)
          (unless (member problem (cddr cached))
            (display-warning 'agent-workspace (cadr problem) (car problem))))
        (let ((value (cons (nreverse roles) problems)))
          (puthash key (cons stamp value) agent-workspace--roles-cache)
          value)))))

(defun agent-workspace-roles (&optional project)
  "PROJECT's roles (default: the current project's): an alist of a name and
its role, the starters and the project's own."
  (car (agent-workspace--roles-read (or project (agent-workspace-project)))))

(defun agent-workspace-role-problems (&optional project)
  "What's wrong with PROJECT's role files: (error|warning MESSAGE) each."
  (cdr (agent-workspace--roles-read (or project (agent-workspace-project)))))

(defun agent-workspace--project-role (project name)
  "PROJECT's role NAME; one with nothing of its own if there's none (its
file gone since)."
  (or (alist-get name (agent-workspace-roles project) nil nil #'equal)
      (agent-workspace--bare-role project name)))

(setq agent-workspace-role-function #'agent-workspace--project-role)

;; ====== MAKING AN AGENT OF IT ======

(defun agent-workspace-role-count (project role)
  "How many agents of ROLE run in PROJECT's crew (not asleep, not gone
home)."
  (seq-count (lambda (agent)
               (and (equal (agent-workspace-agent-role agent) role)
                    (not (memq (agent-workspace-agent-state agent) '(asleep home)))))
             (agent-workspace-agents project)))

(defun agent-workspace--check-role (project role)
  "Signal a user error if PROJECT has no ROLE, or as many of it run as it
allows."
  (let ((roles (agent-workspace-roles project)))
    (unless (alist-get role roles nil nil #'equal)
      (user-error "No role %s: %s" role (string-join (mapcar #'car roles) ", ")))
    (agent-workspace--check-room project role)))

(defun agent-workspace--check-room (project role)
  "Signal a user error if as many agents of ROLE run in PROJECT's crew as
it allows."
  (when-let* ((max (plist-get (agent-workspace--project-role project role) :max)))
    (when (>= (agent-workspace-role-count project role) max)
      (user-error "%d %s%s run already, as many as the role allows"
                  max role (if (= max 1) "" "s")))))

(defun agent-workspace-copy-role (name &optional project)
  "Copy the starter role NAME into PROJECT's roles (default: the current
project's), to change it there: its file. Interactively, asked, then
visited."
  (interactive
   (list (completing-read "Copy the role: "
                          (mapcar #'file-name-base
                                  (directory-files agent-workspace-starter-roles-directory nil "\\.md\\'"))
                          nil t)))
  (let* ((project (or project (agent-workspace-project)
                      (user-error "Not in a git repository")))
         (from (expand-file-name (concat name ".md") agent-workspace-starter-roles-directory))
         (dir (expand-file-name agent-workspace-roles-directory project))
         (to (expand-file-name (concat name ".md") dir)))
    (unless (file-exists-p from) (user-error "No starter role %s" name))
    (when (file-exists-p to) (user-error "%s has its own %s already" (file-name-nondirectory (directory-file-name project)) name))
    (make-directory dir t)
    (copy-file from to)
    (when (called-interactively-p 'any) (find-file to))
    to))
