;;; $DOOMDIR/config/agent-workflow/agents.el -*- lexical-binding: t; -*-
;; Agents: what an agent step may do. Loaded from config/agent-workflow.el,
;; after core.el. No Doom here.
;;
;; An agent is a Markdown file, NAME.md, as Claude Code's own agents are: a
;; front matter, then its instructions (added to the step's agent's system
;; prompt). A step names it (agent: build); the agent has no role of its own.
;;
;;   ---
;;   name: build                   its file's name, if given
;;   description: builds an issue with its tests
;;   tools: Read, Edit, Bash(git commit:*)   allowed without asking (Claude
;;                                 Code's allowedTools); a YAML list too
;;   deny: Bash(git push:*)        never available (disallowedTools)
;;   model: opus                   inherit (or none): your default
;;   effort: high                  low, medium, high, xhigh, max; default
;;                                 (or none): the model's
;;   mode: acceptEdits             its permission mode: default, acceptEdits,
;;                                 plan, auto, dontAsk, bypassPermissions
;;                                 (or accept-edits...)
;;   icon: md-hammer ⚙             a nerd icon (GUI), a glyph (terminal)
;;   verb: building                what it does: "building doom-a1b"
;;   colour: blue                  its steps' colour
;;   ---
;;   Its instructions.
;;
;; Its tools, deny and instructions may name variables, {main}, {branch}...
;; (`agent-workflow-variables'), filled in as its session starts. A problem
;; names the file and line: an error leaves the agent out, a warning
;; doesn't. Errors: no front matter or not closed, a line not a key, no
;; description, a name (its file's) not a lowercase letter then lowercase
;; letters, digits or -, a name: not its file's, a tools or deny entry not
;; Tool or Tool(pattern), a mode or colour not one there is, a variable not
;; one there is. Warnings: an unknown key, a key given twice, a model or an
;; effort not one there is, an icon no nerd icon, a tool both allowed and
;; denied, no instructions.
;;
;; Copied from config/agent-workspace/roles.el and adapted (never required:
;; either module goes without the other).

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; ====== VARIABLES ======

(defconst agent-workflow-modes '("default" "acceptEdits" "plan" "auto" "dontAsk" "bypassPermissions")
  "Claude Code's permission modes (auto: Claude decides what needs your OK).")

(defconst agent-workflow-colours '("blue" "magenta" "green" "yellow" "cyan" "red" "white" "black")
  "The colours an agent may have: the theme's ANSI faces' (`ansi-color-blue'...).")

(defvar agent-workflow-models '("fable" "opus" "sonnet" "haiku")
  "The models an agent names by their short names; a model's id
\(claude-...) too.")

(defvar agent-workflow-efforts '("low" "medium" "high" "xhigh" "max")
  "The efforts an agent may name: how hard its model thinks (Claude
Code's, a model offering some only: those it doesn't, skipped as its
session starts, saying so).")

(defconst agent-workflow--definition-keys
  '("name" "description" "tools" "deny" "model" "effort" "mode" "icon" "verb" "colour")
  "An agent's keys (color too, as Claude Code's agents spell it).")

(defconst agent-workflow--definition-list-keys '("tools" "deny")
  "An agent's keys holding a list.")

(defvar agent-workflow--definitions-cache (make-hash-table :test #'equal)
  "A project's agents, as last read: project to (STAMP (DEFINITIONS .
PROBLEMS)), STAMP the files and their modification times.")

;; ====== A DEFINITION FILE ======

(defun agent-workflow--unquote (value)
  "VALUE without the quotes around it, if any."
  (if (string-match "\\`\\([\"']\\)\\(.*\\)\\1\\'" value)
      (match-string 2 value)
    value))

(defun agent-workflow--list (value)
  "VALUE, a front matter's list: \"a, b\" or \"[a, b]\" as (\"a\" \"b\")."
  (let ((value (string-trim value)))
    (when (string-match "\\`\\[\\(.*\\)\\]\\'" value)
      (setq value (match-string 1 value)))
    (seq-remove #'string-empty-p
                (mapcar (lambda (item) (agent-workflow--unquote (string-trim item)))
                        (split-string value ",")))))

(defun agent-workflow--mode-id (value)
  "VALUE, a permission mode as Claude Code names it or in kebab-case
\(accept-edits), as Claude Code's id; nil if it isn't one."
  (let ((id (replace-regexp-in-string "-\\([a-z]\\)" (lambda (m) (upcase (substring m 1))) value)))
    (car (member id agent-workflow-modes))))

(defun agent-workflow--tool-p (entry)
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

(defun agent-workflow--model-p (model)
  "Non-nil if MODEL is one Claude Code takes: one of
`agent-workflow-models', or a model's id (claude-...)."
  (or (member model agent-workflow-models)
      (string-match-p "\\`claude-[a-z0-9.-]+\\'" model)))

(defun agent-workflow--nerd-name-p (icon)
  "Non-nil if ICON (md-hammer, nf-cod-bug) is a nerd icon, or there's no
nerd-icons to tell."
  (let ((name (concat "nf-" (string-remove-prefix "nf-" icon))))
    (or (not (require 'nerd-icons nil t))
        (cond ((string-prefix-p "nf-md-" name)
               (and (boundp 'nerd-icons/mdicon-alist) (assoc name nerd-icons/mdicon-alist)))
              ((string-prefix-p "nf-cod-" name)
               (and (boundp 'nerd-icons/codicon-alist) (assoc name nerd-icons/codicon-alist)))))))

(cl-defun agent-workflow--front-matter-read (file &key keys list-keys aliases problem store)
  "Read FILE's front matter: a first line ---, its keys, then a line ---
\(blank lines and # comments between them skipped). A key is KEY: VALUE,
its quotes taken off; one of LIST-KEYS holds a list, inline (a, b or [a,
b]) or, nothing after its colon, as YAML items on the lines below (  - a).
KEYS are the keys it takes, ALIASES other spellings of them ((ALIAS .
KEY)...). Each key's value is given to STORE (KEY VALUE LINE): VALUE a
string, or a list key's items ((ITEM . ITS LINE)...); each problem to
PROBLEM (LEVEL LINE FORMAT ARGS...). Return (CLOSED SEEN REST): the line
closing it (nil: not closed, or none), the keys seen ((KEY . LINE)...,
the last first), what's after it, trimmed."
  (let ((line 0) (seen nil) (closed nil) (rest ""))
    (cl-flet ((store (key value n)
                (funcall store key
                         (if (and (member key list-keys) (stringp value))
                             (mapcar (lambda (item) (cons item n)) (agent-workflow--list value))
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
                      (push (cons (agent-workflow--unquote (string-trim (match-string 1 text))) line) list)
                    (funcall problem 'error line "a list item with no key before it")))
                 ((string-match "\\`\\([A-Za-z_-]+\\):[ \t]*\\(.*\\)\\'" text)
                  (let* ((k (downcase (match-string 1 text)))
                         (value (agent-workflow--unquote (string-trim (match-string 2 text))))
                         (same (or (cdr (assoc k aliases)) k)))
                    (when key (store key (nreverse list) (1- line)))
                    (setq key nil list nil)
                    (when-let* ((before (and (member same keys) (assoc same seen))))
                      (funcall problem 'warning line "%s given twice (line %d too): the last is used" k (cdr before)))
                    (push (cons same line) seen)
                    (cond
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

(defun agent-workflow--unknown-variables (text)
  "The variables TEXT names that aren't ones: ((NAME . OFFSET)...)."
  (seq-remove (lambda (found) (agent-workflow-variable-p (car found)))
              (agent-workflow-variables-in text)))

(defun agent-workflow-definition-read (file)
  "Read the agent FILE: (DEFINITION . PROBLEMS). DEFINITION is a plist (see the
top of this file: :name :file :description :tools :deny :model :effort :mode :icon
:glyph :verb :colour :instructions), nil if FILE has errors; PROBLEMS, each
\(error|warning \"FILE:LINE: what\" FILE LINE \"what\"), in the order
of their lines."
  (let* ((name (file-name-sans-extension (file-name-nondirectory file)))
         (case-fold-search nil)
         (definition (list :name name :file file))
         (problems nil))
    (cl-flet ((problem (level n format &rest args)
                (push (apply #'agent-workflow--problem level file n format args) problems)))
      (unless (string-match-p agent-workflow--name-regexp name)
        (problem 'error 1 "its name %s (its file's): a lowercase letter, then lowercase letters, digits or -"
                 name))
      (pcase-let
          ((`(,closed ,seen ,instructions)
            (agent-workflow--front-matter-read
             file
             :keys agent-workflow--definition-keys
             :list-keys agent-workflow--definition-list-keys
             :aliases '(("color" . "colour"))
             :problem #'problem
             :store
             (lambda (key value n)
               (pcase key
                 ((or "tools" "deny")
                  (dolist (item value)
                    (if (not (agent-workflow--tool-p (car item)))
                        (problem 'error (cdr item) "%s %s: not a tool, Tool or Tool(pattern)" key (car item))
                      (dolist (unknown (agent-workflow--unknown-variables (car item)))
                        (problem 'error (cdr item) "%s %s: {%s} isn't a variable (%s)" key (car item)
                                 (car unknown) (agent-workflow--variables-said)))))
                  (setq definition (plist-put definition (intern (concat ":" key)) (mapcar #'car value))))
                 ("name"
                  (unless (equal value name)
                    (problem 'error n "its name is %s, its file's %s: they must agree" value name)))
                 ("description"
                  (if (string-empty-p value)
                      (problem 'error n "description: empty: say what it's for")
                    (setq definition (plist-put definition :description value))))
                 ("verb" (setq definition (plist-put definition :verb value)))
                 ("model"
                  (unless (member value '("" "inherit"))
                    (unless (agent-workflow--model-p value)
                      (problem 'warning n "model %s: not inherit, one of %s, nor a model's id (claude-...)"
                               value (string-join agent-workflow-models ", ")))
                    (setq definition (plist-put definition :model value))))
                 ("effort"
                  (unless (member value '("" "default"))
                    (unless (member value agent-workflow-efforts)
                      (problem 'warning n "effort %s: not default, nor one of %s"
                               value (string-join agent-workflow-efforts ", ")))
                    (setq definition (plist-put definition :effort value))))
                 ("mode"
                  (if-let* ((id (agent-workflow--mode-id value)))
                      (setq definition (plist-put definition :mode id))
                    (problem 'error n "mode %s: not one of %s" value (string-join agent-workflow-modes ", "))))
                 ("colour"
                  (if (member value agent-workflow-colours)
                      (setq definition (plist-put definition :colour value))
                    (problem 'error n "colour %s: not one of %s" value (string-join agent-workflow-colours ", "))))
                 ("icon"
                  (let ((parts (split-string value)))
                    (when (and (car parts) (not (agent-workflow--nerd-name-p (car parts))))
                      (problem 'warning n "icon %s: not a nerd icon (md-NAME or cod-NAME): %s is shown"
                               (car parts) (or (cadr parts) "its glyph")))
                    (setq definition (plist-put definition :icon (car parts)))
                    (when (cadr parts)
                      (setq definition (plist-put definition :glyph (cadr parts)))))))))))
        (when closed
          (unless (assoc "description" seen)
            (problem 'error 1 "no description: say what it's for (description: ...)"))
          (dolist (tool (plist-get definition :tools))
            (when (member tool (plist-get definition :deny))
              (problem 'warning (or (cdr (assoc "deny" seen)) 1)
                       "%s both allowed (tools) and denied (deny): denied" tool)))
          (if (string-empty-p instructions)
              (problem 'warning closed "no instructions after its front matter")
            (dolist (unknown (agent-workflow--unknown-variables instructions))
              (problem 'error (+ closed (agent-workflow--offset-line instructions (cdr unknown)))
                       "{%s} isn't a variable (%s)" (car unknown) (agent-workflow--variables-said)))
            (setq definition (plist-put definition :instructions instructions))))))
    (setq problems (agent-workflow--by-line (nreverse problems)))
    (cons (unless (agent-workflow--errors-p problems) definition) problems)))

(defun agent-workflow--variables-said ()
  "The variables, as a problem lists them."
  (concat (mapconcat (lambda (name) (concat "{" name "}")) agent-workflow-variables ", ")
          ", {jobs.JOB.outcome}, {jobs.JOB.notes}"))

(defun agent-workflow-definition-edits-p (definition)
  "Non-nil if DEFINITION (a plist) lets its agent change files: unless its
deny has both Edit and Write, it does."
  (let ((deny (plist-get definition :deny)))
    (not (and (member "Edit" deny) (member "Write" deny)))))

;; ====== A PROJECT'S DEFINITIONS ======

(defun agent-workflow--definitions-read (project)
  "PROJECT's agents and their problems, read again if a file changed:
\(DEFINITIONS . PROBLEMS), DEFINITIONS an alist of a name and its agent, in
order (the starters first), each agent's :origin where its file is
\(starter, project, local), its :replaces the origin of the one of its name
it replaced."
  (let* ((files (agent-workflow--files project "agents" "\\`[^.].*\\.md\\'"))
         (stamp (agent-workflow--stamp files))
         (key (or project ""))
         (cached (gethash key agent-workflow--definitions-cache)))
    (if (equal (car cached) stamp)
        (cadr cached)
      (let (definitions problems)
        (dolist (file files)
          (pcase-let ((`(,definition . ,found) (agent-workflow-definition-read (cdr file))))
            (setq problems (append problems found))
            (when definition
              (let* ((name (plist-get definition :name))
                     (replaced (alist-get name definitions nil nil #'equal)))
                (setq definition (plist-put definition :origin (car file)))
                (when replaced
                  (setq definition (plist-put definition :replaces (plist-get replaced :origin))))
                (setf (alist-get name definitions nil nil #'equal) definition)))))
        (let ((value (cons (nreverse definitions) problems)))
          (puthash key (list stamp value) agent-workflow--definitions-cache)
          value)))))

(defun agent-workflow-agent-definitions (&optional project)
  "PROJECT's agents (default: the current project's): an alist of a name
and its agent, the starters, the project's and yours."
  (car (agent-workflow--definitions-read (or project (agent-workflow-project)))))

(defun agent-workflow-definition-problems (&optional project)
  "What's wrong with PROJECT's agent files."
  (cdr (agent-workflow--definitions-read (or project (agent-workflow-project)))))
