;;; $DOOMDIR/config/agent-workspace/roles.el -*- lexical-binding: t; -*-
;; Roles: what each kind of agent does and may do. Loaded from
;; config/agent-workspace.el, after core.el. No Doom here.
;;
;; A role is a Markdown file, NAME.md, as Claude Code's own agents are
;; (.claude/agents/*.md): a front matter, then its instructions (added to its
;; agents' system prompt). The starters ship here, in roles/ (scribe,
;; investigator, builder, reviewer, tester, documenter, triager, planner,
;; merger, designer, security, profiler, lead); a project's own, in its
;; .agent-workspace/roles/ (committed), and your own for it, in its
;; .agent-shell/agent-workspace/roles/ (local: .agent-shell/ is out of git),
;; add to them; a later place's role replaces one of the same name (starter
;; < project < local). Each role knows where it comes from (:origin) and
;; what it replaced (:replaces).
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
;;   hands-to: tester, reviewer      where its finished issues go: the first
;;                                   role the crew has; any: every role
;;                                   with labels, the agent choosing
;;   returns-to: builder             where work goes back (changes asked)
;;   max: 4                          how many of it may run at once
;;   leads: true                     it runs the crew from its shell
;;                                   (cmd/agent-workspace give, wake, sleep,
;;                                   loop): true or false (default)
;;   icon: md-hammer ⚙               a nerd icon (GUI), a glyph (terminal)
;;   verb: building                  what it does, working: "building doom-a1b"
;;   colour: blue                    its agents' colour, while it's free
;;   ---
;;   Its instructions.
;;
;; There's no worktree key: every agent has its own (worktree.el). A
;; problem names the file and line: an error leaves the role out, a warning
;; doesn't. Errors: no front matter or not closed, a line not a key, no
;; description (or an empty one), a name (its file's) not a lowercase
;; letter then lowercase letters, digits or -, a name: not its file's, a
;; tools or deny entry not Tool or Tool(pattern), a mode, max or colour not
;; one there is, a leads neither true nor false. Warnings: an unknown key, a
;; key given twice, a model not one there is, an icon no nerd icon, a tool
;; both allowed and denied, no instructions, a talks-to, hands-to or
;; returns-to naming no role of the project's (or its own). M-x
;; agent-workspace-check-roles lists them all.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; ====== VARIABLES ======

(defcustom agent-workspace-roles-directory ".agent-workspace/roles"
  "Where a project keeps its own roles, committed: shared with whoever
works on it."
  :type 'string
  :group 'agent-workspace)

(defcustom agent-workspace-local-roles-directory ".agent-shell/agent-workspace/roles"
  "Where a project keeps your own roles, out of git (.agent-shell/ is
ignored): relative to its main checkout, so its agents' worktrees have
them too. They replace the project's and the starters of the same name."
  :type 'string
  :group 'agent-workspace)

(defvar agent-workspace-starter-roles-directory
  (expand-file-name "roles/" (file-name-directory (or load-file-name buffer-file-name)))
  "The starter roles, shipped with this module.")

(defconst agent-workspace-modes '("default" "acceptEdits" "plan" "auto" "dontAsk" "bypassPermissions")
  "Claude Code's permission modes (auto: Claude decides what needs your OK).")

(defconst agent-workspace--role-keys
  '("name" "description" "tools" "deny" "model" "mode" "labels" "talks-to" "hands-to" "returns-to" "max"
    "leads" "icon" "verb" "colour" "color")
  "A role file's keys (color as Claude Code's agents spell it).")

(defvar agent-workspace--roles-quiet nil
  "Non-nil: role files' new problems aren't shown as warnings (they're
listed elsewhere).")

(defvar agent-workspace-models)

;; crews.el's, loaded after.
(defvar agent-workspace--crew-specs-cache)
(declare-function agent-workspace-crew-spec-problems "agent-workspace/crews")
(declare-function agent-workspace-crew-specs "agent-workspace/crews")

(defvar agent-workspace--roles-cache (make-hash-table :test #'equal)
  "A project's roles, as last read: project to (STAMP (ROLES . PROBLEMS)
LEFT-OUT), STAMP the role files and their modification times.")

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

(defconst agent-workspace--role-list-keys '("tools" "deny" "labels" "talks-to" "hands-to" "returns-to")
  "A role file's keys holding a list.")

(defun agent-workspace--tool-p (entry)
  "Non-nil if ENTRY names a tool as Claude Code does: Tool, or
Tool(pattern), its parentheses closed (an MCP server's mcp__server__tool
too)."
  (and (string-match "\\`[A-Za-z0-9_-]+\\(?:(\\(.*\\))\\)?\\'" entry)
       (let ((depth 0))
         (catch 'open
           (dolist (char (string-to-list (or (match-string 1 entry) "")))
             (pcase char
               (?\( (cl-incf depth))
               (?\) (when (< (cl-decf depth) 0) (throw 'open nil)))))
           (= depth 0)))))

(defun agent-workspace--model-p (model)
  "Non-nil if MODEL is one Claude Code takes: one of
`agent-workspace-models', or a model's id (claude-...)."
  (or (member model (bound-and-true-p agent-workspace-models))
      (string-match-p "\\`claude-[a-z0-9.-]+\\'" model)))

(defun agent-workspace--nerd-name-p (icon)
  "Non-nil if ICON (md-hammer, nf-cod-bug) is a nerd icon the roles draw,
or there's no nerd-icons to tell."
  (let ((name (concat "nf-" (string-remove-prefix "nf-" icon))))
    (or (not (require 'nerd-icons nil t))
        (cond ((string-prefix-p "nf-md-" name)
               (and (boundp 'nerd-icons/mdicon-alist) (assoc name nerd-icons/mdicon-alist)))
              ((string-prefix-p "nf-cod-" name)
               (and (boundp 'nerd-icons/codicon-alist) (assoc name nerd-icons/codicon-alist)))))))

(cl-defun agent-workspace--front-matter-read (file &key keys list-keys aliases ignored problem store)
  "Read FILE's front matter, as role and crew files have it: a first line
---, its keys, then a line --- (blank lines and # comments between them
skipped). A key is KEY: VALUE, its quotes taken off; one of LIST-KEYS
holds a list, inline (a, b or [a, b]) or, nothing after its colon, as YAML
items on the lines below (  - a). KEYS are the keys it takes, ALIASES
other spellings of them ((ALIAS . KEY)...), IGNORED keys warned about as
ignored ((KEY . WHY)...). Each key's value is given to STORE (KEY VALUE
LINE), KEY as KEYS spell it: VALUE a string, or a list key's items ((ITEM
. ITS LINE)...); each problem to PROBLEM (LEVEL LINE FORMAT ARGS...).
Return (CLOSED SEEN REST): the line closing it (nil: not closed, or no
front matter), the keys seen ((KEY . LINE)..., the last first), what's
after it, trimmed."
  (let ((line 0) (seen nil) (closed nil) (rest ""))
    (cl-flet ((store (key value n)
                (funcall store key
                         (if (and (member key list-keys) (stringp value))
                             (mapcar (lambda (item) (cons item n)) (agent-workspace--role-list value))
                           value)
                         n)))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (if (not (looking-at-p "---[ \t]*$"))
            (funcall problem 'error 1 "no front matter: it starts with a line ---, its keys, then a line ---")
          (forward-line 1)
          (setq line 2)
          (let ((key nil) (list nil))
            (while (and (not closed) (not (eobp)))
              (let ((text (buffer-substring-no-properties (point) (line-end-position))))
                (cond
                 ((string-match-p "\\`---[ \t]*\\'" text)
                  (when key (store key (nreverse list) (1- line)))
                  (setq closed line key nil))
                 ((string-match-p "\\`[ \t]*\\(#.*\\)?\\'" text))
                 ;; An item of a YAML list, under its key.
                 ((string-match "\\`[ \t]+-[ \t]+\\(.*\\)\\'" text)
                  (if key
                      (push (cons (agent-workspace--role-unquote (string-trim (match-string 1 text))) line) list)
                    (funcall problem 'error line "a list item with no key before it")))
                 ((string-match "\\`\\([A-Za-z_-]+\\):[ \t]*\\(.*\\)\\'" text)
                  (let* ((k (downcase (match-string 1 text)))
                         (value (agent-workspace--role-unquote (string-trim (match-string 2 text))))
                         (same (or (cdr (assoc k aliases)) k)))
                    (when key (store key (nreverse list) (1- line)))
                    (setq key nil list nil)
                    (when-let* ((before (and (member same keys) (assoc same seen))))
                      (funcall problem 'warning line "%s given twice (line %d too): the last is used" k (cdr before)))
                    (push (cons same line) seen)
                    (cond
                     ((assoc k ignored)
                      (funcall problem 'warning line "%s" (cdr (assoc k ignored))))
                     ((not (member same keys))
                      (funcall problem 'warning line "unknown key %s: ignored" k))
                     ((and (string-empty-p value) (member same list-keys))
                      ;; Its items on the lines below.
                      (setq key same))
                     (t (store same value line)))))
                 (t (funcall problem 'error line "not a key: %s" (string-trim text))))
                (forward-line 1)
                (cl-incf line)))
            (if (not closed)
                (funcall problem 'error line "its front matter isn't closed: a line --- after its keys")
              (setq rest (string-trim (buffer-substring-no-properties (point) (point-max)))))))))
    (list closed seen rest)))

(defun agent-workspace-role-read (file)
  "Read the role FILE: (ROLE . PROBLEMS). ROLE is a plist (see the top of
this file), nil if FILE has errors; PROBLEMS, each (error|warning
\"FILE:LINE: what\" FILE LINE \"what\"). ROLE's :lines has the line of
each item of its talks-to, hands-to and returns-to: ((KEY (ITEM . LINE)...)...)."
  (let* ((name (file-name-sans-extension (file-name-nondirectory file)))
         (shown (abbreviate-file-name file))
         (case-fold-search nil)
         (role (list :name name :file file))
         (problems nil)
         (lines nil))
    (cl-flet ((problem (level n format &rest args)
                (let ((what (apply #'format format args)))
                  (push (list level (format "%s:%d: %s" shown n what) file n what) problems))))
      (unless (string-match-p "\\`[a-z][a-z0-9-]*\\'" name)
        (problem 'error 1 "its name %s (its file's): a lowercase letter, then lowercase letters, digits or -"
                 name))
      (pcase-let
          ((`(,closed ,seen ,instructions)
            (agent-workspace--front-matter-read
             file
             :keys (remove "color" agent-workspace--role-keys)
             :list-keys agent-workspace--role-list-keys
             :aliases '(("color" . "colour"))
             :ignored '(("worktree" . "worktree: ignored (every agent has its own worktree)"))
             :problem #'problem
             :store
             (lambda (key value n)
               ;; VALUE: a string, or a list's items, each (ITEM . ITS LINE).
               (pcase key
                 ((or "tools" "deny" "labels" "talks-to" "hands-to" "returns-to")
                  (when (member key '("tools" "deny"))
                    (dolist (item value)
                      (unless (agent-workspace--tool-p (car item))
                        (problem 'error (cdr item) "%s %s: not a tool, Tool or Tool(pattern)"
                                 key (car item)))))
                  (when (member key '("talks-to" "hands-to" "returns-to"))
                    (push (cons key value) lines))
                  (setq role (plist-put role (intern (concat ":" key)) (mapcar #'car value))))
                 ("name"
                  (unless (equal value name)
                    (problem 'error n "its name is %s, its file's %s: they must agree" value name)))
                 ("description"
                  (if (string-empty-p value)
                      (problem 'error n "description: empty: say what it does")
                    (setq role (plist-put role :description value))))
                 ("verb" (setq role (plist-put role :verb value)))
                 ("model"
                  (unless (member value '("" "inherit"))
                    (unless (agent-workspace--model-p value)
                      (problem 'warning n "model %s: not inherit, one of %s, nor a model's id (claude-...)"
                               value (string-join (bound-and-true-p agent-workspace-models) ", ")))
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
                 ("leads"
                  (pcase (downcase value)
                    ((or "true" "yes") (setq role (plist-put role :leads t)))
                    ((or "false" "no"))
                    (_ (problem 'error n "leads %s: true or false" value))))
                 ("colour"
                  (if (member value agent-workspace-colours)
                      (setq role (plist-put role :colour value))
                    (problem 'error n "colour %s: not one of %s" value
                             (string-join agent-workspace-colours ", "))))
                 ("icon"
                  (let ((parts (split-string value)))
                    (when (and (car parts) (not (agent-workspace--nerd-name-p (car parts))))
                      (problem 'warning n "icon %s: not a nerd icon (md-NAME or cod-NAME): %s is shown"
                               (car parts) (or (cadr parts) "its glyph")))
                    (setq role (plist-put role :icon (car parts)))
                    (when (cadr parts)
                      (setq role (plist-put role :glyph (cadr parts)))))))))))
        (when closed
          (unless (assoc "description" seen)
            (problem 'error 1 "no description: say what it does (description: ...)"))
          (dolist (tool (plist-get role :tools))
            (when (member tool (plist-get role :deny))
              (problem 'warning (or (cdr (assoc "deny" seen)) 1)
                       "%s both allowed (tools) and denied (deny): denied" tool)))
          (if (string-empty-p instructions)
              (problem 'warning closed "no instructions after its front matter")
            (setq role (plist-put role :instructions instructions))))))
    (when lines
      (setq role (plist-put role :lines (nreverse lines))))
    (setq problems (nreverse problems))
    (cons (unless (assq 'error problems) role) problems)))

(defun agent-workspace--role-names-problems (roles)
  "What's wrong with the talks-to, hands-to and returns-to of ROLES (an
alist of a name and its role, a project's all): each naming a role not
among them, or its own (hands-to's any is every role); warnings as
`agent-workspace-role-read' gives them."
  (let (problems)
    (pcase-dolist (`(,name . ,role) roles)
      (pcase-dolist (`(,key . ,items) (plist-get role :lines))
        (pcase-dolist (`(,item . ,n) items)
          (let ((what (cond ((and (equal item "any") (equal key "hands-to")) nil)
                            ((equal item name) (format "%s %s: its own role" key item))
                            ((not (assoc item roles))
                             (format "%s %s: no such role (%s)" key item (string-join (mapcar #'car roles) ", "))))))
            (when what
              (let ((file (plist-get role :file)))
                (push (list 'warning (format "%s:%d: %s" (abbreviate-file-name file) n what) file n what)
                      problems)))))))
    (nreverse problems)))

;; ====== A PROJECT'S ROLES ======

(defun agent-workspace--role-places (project)
  "Where PROJECT's roles come from, in order (a later one's replace an
earlier one's of the same name): ((ORIGIN . FOLDER)...), ORIGIN starter,
project or local."
  (cons (cons 'starter agent-workspace-starter-roles-directory)
        (when project
          (list (cons 'project (expand-file-name agent-workspace-roles-directory project))
                (cons 'local (expand-file-name agent-workspace-local-roles-directory project))))))

(defun agent-workspace--role-files (project)
  "The role files for PROJECT, in order: the starters, its own, then your
local ones (each replacing those of the same name before it): ((ORIGIN .
FILE)...)."
  (seq-mapcat (lambda (place)
                (when (file-directory-p (cdr place))
                  (mapcar (lambda (file) (cons (car place) file))
                          (directory-files (cdr place) t "\\`[^.].*\\.md\\'"))))
              (agent-workspace--role-places project)))

(defun agent-workspace--roles-read (project)
  "PROJECT's roles and their problems, read again if a file changed:
\(ROLES . PROBLEMS), ROLES an alist of a name and its role, in order (the
starters first), each role's :origin where its file is (starter, project,
local), its :replaces the origin of the one of its name it replaced. New
problems are shown as warnings."
  (let* ((files (agent-workspace--role-files project))
         (stamp (mapcar (lambda (file)
                          (cons (cdr file) (file-attribute-modification-time (file-attributes (cdr file)))))
                        files))
         (key (or project ""))
         (cached (gethash key agent-workspace--roles-cache)))
    (if (equal (car cached) stamp)
        (cadr cached)
      (let (roles problems left-out)
        (dolist (file files)
          (pcase-let ((`(,role . ,found) (agent-workspace-role-read (cdr file))))
            (setq problems (append problems found))
            (if role
                (let* ((name (plist-get role :name))
                       (replaced (alist-get name roles nil nil #'equal)))
                  (setq role (plist-put role :origin (car file)))
                  (when replaced
                    (setq role (plist-put role :replaces (plist-get replaced :origin))))
                  (setf (alist-get name roles nil nil #'equal) role))
              (pcase-let ((`(,_ ,message ,_ ,n ,what) (assq 'error found)))
                (push (list (file-name-base (cdr file)) :file (cdr file) :origin (car file) :message message
                            :error (format "line %d: %s" n what))
                      left-out)))))
        (setq roles (nreverse roles)
              problems (append problems (agent-workspace--role-names-problems roles)))
        (unless agent-workspace--roles-quiet
          (dolist (problem problems)
            (unless (member problem (cdr (cadr cached)))
              (display-warning 'agent-workspace (cadr problem) (car problem)))))
        (let ((value (cons roles problems)))
          (puthash key (list stamp value (nreverse left-out)) agent-workspace--roles-cache)
          value)))))

(defun agent-workspace-roles (&optional project)
  "PROJECT's roles (default: the current project's): an alist of a name and
its role, the starters, the project's own and your local ones."
  (car (agent-workspace--roles-read (or project (agent-workspace-project)))))

(defun agent-workspace-roles-left-out (&optional project)
  "PROJECT's role files left out for their errors (default: the current
project's), in the order they're read: ((NAME :file FILE :origin ORIGIN
:message MESSAGE :error TEXT)...), NAME its file's, MESSAGE its first error
\(\"FILE:LINE: what\"), TEXT the same without its file (\"line 4: what\")."
  (let ((project (or project (agent-workspace-project))))
    (agent-workspace--roles-read project)
    (nth 2 (gethash (or project "") agent-workspace--roles-cache))))

(defun agent-workspace-role-problems (&optional project)
  "What's wrong with PROJECT's role files: (error|warning MESSAGE) each."
  (cdr (agent-workspace--roles-read (or project (agent-workspace-project)))))

(defun agent-workspace-check-roles (&optional project)
  "Check PROJECT's role and crew files (default: the current project's),
all of them read anew (the starters, the project's, your local ones):
every problem a line FILE:LINE: error|warning: what, in a buffer whose
lines visit their file and line (RET, a click); none, said. Return the
problems."
  (interactive)
  (let* ((project (or project (agent-workspace-project)))
         (problems (progn (remhash (or project "") agent-workspace--roles-cache)
                          (remhash (or project "") agent-workspace--crew-specs-cache)
                          (let ((agent-workspace--roles-quiet t))
                            (append (agent-workspace-role-problems project)
                                    (agent-workspace-crew-spec-problems project))))))
    (if (not problems)
        (message "%d roles, %d crews, no problems" (length (agent-workspace-roles project))
                 (length (agent-workspace-crew-specs project)))
      (let ((buffer (get-buffer-create "*agent-workspace roles*")))
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (setq default-directory (or project default-directory))
            (insert (format "The roles and crews of %s: %d error%s, %d warning%s\n\n"
                            (if project (abbreviate-file-name (directory-file-name project)) "no project")
                            (seq-count (lambda (p) (eq (car p) 'error)) problems)
                            (if (= 1 (seq-count (lambda (p) (eq (car p) 'error)) problems)) "" "s")
                            (seq-count (lambda (p) (eq (car p) 'warning)) problems)
                            (if (= 1 (seq-count (lambda (p) (eq (car p) 'warning)) problems)) "" "s")))
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

(defun agent-workspace--project-role (project name)
  "PROJECT's role NAME; one with nothing of its own if there's none (its
file gone since)."
  (or (alist-get name (agent-workspace-roles project) nil nil #'equal)
      (agent-workspace--bare-role project name)))

(setq agent-workspace-role-function #'agent-workspace--project-role)

;; ====== MAKING AN AGENT OF IT ======

(defun agent-workspace-role-count (project role &optional all)
  "How many agents of ROLE run in PROJECT's crew (not asleep, not gone
home); ALL: how many it has, asleep and gone home too."
  (seq-count (lambda (agent)
               (and (equal (agent-workspace-agent-role agent) role)
                    (or all (not (memq (agent-workspace-agent-state agent) '(asleep home))))))
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

(defun agent-workspace--copy-role-sources (project where)
  "The roles that can be copied into PROJECT's roles WHERE (project or
local): an alist of a name and its file. Into the project's, the starters;
into your local ones, the project's too (its own replacing a starter)."
  (let (sources)
    (dolist (file (agent-workspace--role-files project))
      (when (or (eq (car file) 'starter) (and (eq where 'local) (eq (car file) 'project)))
        (setf (alist-get (file-name-base (cdr file)) sources nil nil #'equal) (cdr file))))
    (nreverse sources)))

(defun agent-workspace-copy-role (name &optional project where)
  "Copy the role NAME into PROJECT's roles (default: the current project's),
to change it there: its file. WHERE: project (default), its committed
roles, shared, a starter copied; local, your own, out of git, a starter or
the project's own copied. Interactively, both asked, then visited."
  (interactive
   (let* ((where (if (equal (completing-read "Copy into: "
                                             '("project: committed, shared" "local: yours, out of git")
                                             nil t)
                            "local: yours, out of git")
                     'local
                   'project))
          (sources (agent-workspace--copy-role-sources (agent-workspace-project) where)))
     (list (completing-read "Copy the role: " (mapcar #'car sources) nil t)
           nil where)))
  (let* ((project (or project (agent-workspace-project)
                      (user-error "Not in a git repository")))
         (where (or where 'project))
         (from (alist-get name (agent-workspace--copy-role-sources project where) nil nil #'equal))
         (dir (expand-file-name (if (eq where 'local)
                                    agent-workspace-local-roles-directory
                                  agent-workspace-roles-directory)
                                project))
         (to (expand-file-name (concat name ".md") dir)))
    (unless from
      (user-error (if (eq where 'local) "No starter or project role %s" "No starter role %s") name))
    (when (file-exists-p to)
      (user-error "%s has %s %s already" (file-name-nondirectory (directory-file-name project))
                  (if (eq where 'local) "a local" "its own") name))
    (make-directory dir t)
    (copy-file from to)
    (when (called-interactively-p 'any) (find-file to))
    to))
