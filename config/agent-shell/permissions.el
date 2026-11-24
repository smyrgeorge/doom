;;; $DOOMDIR/config/agent-shell/permissions.el -*- lexical-binding: t; -*-
;; A session's permission request answered from elsewhere (an agent
;; workspace's raised hand, a workflow run's pane): agent-shell's own buttons
;; (Allow, Always allow, Reject...), read from its buffer and pressed as they
;; are. Loaded from config/agent-shell.el.

(require 'text-property-search)
(require 'map)
(require 'seq)
(require 'subr-x)

(declare-function agent-shell-cwd "agent-shell")
(defvar agent-shell-permission-responder-function)

(defun +my/agent-shell-permission-buttons (buffer)
  "The permission buttons waiting in agent-shell's session BUFFER, its
latest row: ((LABEL POSITION . ACTION)...), ACTION its own command, run with
point at POSITION."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-max))
      (when-let* ((last (text-property-search-backward 'button 'permission t)))
        (let ((start (save-excursion (goto-char (prop-match-beginning last)) (line-beginning-position)))
              (end (save-excursion (goto-char (prop-match-beginning last)) (line-end-position)))
              buttons match)
          (goto-char start)
          (while (and (setq match (text-property-search-forward 'button 'permission t))
                      (< (prop-match-beginning match) end))
            (let* ((from (prop-match-beginning match))
                   (label (string-trim (buffer-substring-no-properties from (prop-match-end match)) "[[ ]+" "[] ]+"))
                   (map (get-text-property from 'keymap))
                   (action (and (keymapp map) (lookup-key map (kbd "RET")))))
              (when (functionp action)
                (push (cons label (cons from action)) buttons))))
          (nreverse buttons))))))

(defun +my/agent-shell-press-permission (buffer label)
  "Press the permission button LABEL waiting in agent-shell's session
BUFFER, as RET on it does. Nil if there's none of that label."
  (when-let* ((button (assoc label (+my/agent-shell-permission-buttons buffer))))
    (with-current-buffer buffer
      (save-excursion
        (goto-char (cadr button))
        (funcall-interactively (cddr button))))
    t))

;; RULES FOR AN AGENT THAT HAS NONE OF ITS OWN
;; Claude Code takes a session's tools (allowed without asking) and deny
;; (never offered) as its own options (allowedTools, disallowedTools): an
;; agent workspace's role's, a workflow run's agent's. Another agent takes
;; none: its permission requests are answered here by the same rules, in
;; Claude Code's syntax, the session's (`+my/agent-shell-permission-rules'):
;; a deny rule matching, refused; else a tools rule matching, allowed; else
;; asked, as any. A rule is a tool, or a tool and its pattern, matched against
;; the request's kind (ACP's) and what it acts on: Bash(git push:*) a command
;; starting with git push, Bash(git -C * push) one with * anything, Edit
;; (docs/**) a path under docs/ (relative to the session's folder; /x from
;; there, //x absolute), Read, Grep, Glob, WebFetch, WebSearch by kind alone.
;; Weaker than Claude Code's: a tool can't be hidden, and an agent in a mode
;; that asks nothing (its own auto) is refused nothing.
(defvar-local +my/agent-shell-permission-rules nil
  "In a session whose agent takes no rules of its own: (:tools RULES :deny
RULES), its permission requests answered by them (see above).")

(defconst +my/agent-shell-rule-kinds
  '(("Read" "read") ("LS" "read") ("Grep" "search") ("Glob" "search")
    ("Edit" "edit" "delete" "move") ("Write" "edit") ("MultiEdit" "edit") ("NotebookEdit" "edit")
    ("Bash" "execute") ("WebFetch" "fetch") ("WebSearch" "fetch"))
  "Claude Code's tools as ACP's kinds of tool call: (TOOL KIND...).")

(defun +my/agent-shell--rule-parse (rule)
  "RULE, Tool or Tool(pattern): (TOOL . PATTERN), PATTERN nil for none."
  (if (string-match "\\`\\([A-Za-z0-9_]+\\)(\\(.*\\))\\'" rule)
      (cons (match-string 1 rule) (match-string 2 rule))
    (cons rule nil)))

(defun +my/agent-shell--tool-call-command (tool-call)
  "The command TOOL-CALL runs (its raw input's command, a string or a
list), else its title: a string, or nil."
  (let* ((input (map-elt tool-call :raw-input))
         (command (or (map-elt input 'command) (map-elt input 'cmd))))
    (cond ((stringp command) command)
          ((and (sequencep command) (> (length command) 0))
           (mapconcat (lambda (part) (format "%s" part)) command " "))
          ((stringp (map-elt tool-call :title))
           (string-trim (map-elt tool-call :title) "[` ]+" "[` ]+")))))

(defun +my/agent-shell--tool-call-paths (tool-call)
  "The files TOOL-CALL acts on: its raw input's, its locations'."
  (let ((input (map-elt tool-call :raw-input)))
    (delete-dups
     (delq nil (append (mapcar (lambda (key) (let ((value (map-elt input key))) (and (stringp value) value)))
                               '(file_path path filePath notebook_path))
                       (mapcar (lambda (location) (map-elt location 'path))
                               (append (map-elt tool-call :locations) nil)))))))

(defun +my/agent-shell--glob-regexp (glob &optional paths)
  "GLOB as an anchored regexp: * anything (in PATHS: but /), ** anything."
  (let ((parts (split-string glob "\\*\\*")))
    (concat "\\`"
            (mapconcat (lambda (part)
                         (mapconcat #'regexp-quote (split-string part "\\*") (if paths "[^/]*" ".*")))
                       parts ".*")
            "\\'")))

(defun +my/agent-shell-rule-matches-p (rule tool-call &optional dir)
  "Non-nil if RULE (Claude Code's syntax) matches TOOL-CALL (agent-shell's:
its :kind, :title, :raw-input, :locations), DIR its session's folder."
  (pcase-let* ((`(,tool . ,pattern) (+my/agent-shell--rule-parse rule))
               (kinds (cdr (assoc tool +my/agent-shell-rule-kinds))))
    (and (member (map-elt tool-call :kind) kinds)
         (or (null pattern)
             (if (equal tool "Bash")
                 (when-let* ((command (+my/agent-shell--tool-call-command tool-call)))
                   (if (string-suffix-p ":*" pattern)
                       (let ((prefix (string-remove-suffix ":*" pattern)))
                         (or (equal command prefix) (string-prefix-p (concat prefix " ") command)))
                     (string-match-p (+my/agent-shell--glob-regexp pattern) command)))
               (let ((dir (and dir (file-name-as-directory (expand-file-name dir)))))
                 (seq-some
                  (lambda (path)
                    (let* ((path (expand-file-name path dir))
                           (absolute (string-prefix-p "//" pattern))
                           (target (cond (absolute path)
                                         ((and dir (string-prefix-p dir path)) (substring path (length dir)))
                                         (t path)))
                           (glob (cond (absolute (substring pattern 1))
                                       ((string-prefix-p "/" pattern) (substring pattern 1))
                                       (t pattern))))
                      (string-match-p (+my/agent-shell--glob-regexp glob t) target)))
                  (+my/agent-shell--tool-call-paths tool-call))))))))

(defun +my/agent-shell-permission-by-rules (rules tool-call &optional dir)
  "What RULES ((:tools RULES :deny RULES)) say of TOOL-CALL: reject (a deny
rule matches), allow (a tools rule does), or nil (ask)."
  (cond ((seq-some (lambda (rule) (+my/agent-shell-rule-matches-p rule tool-call dir)) (plist-get rules :deny))
         'reject)
        ((seq-some (lambda (rule) (+my/agent-shell-rule-matches-p rule tool-call dir)) (plist-get rules :tools))
         'allow)))

(defvar +my/agent-shell--requesting nil
  "agent-shell's state while a request of its agent is handled: whose it is.")

(defadvice! +my/agent-shell--requesting-a (fn &rest args)
  "A request of an agent (agent-shell's, ARGS): its state known while it's
handled (`+my/agent-shell--requesting')."
  :around #'agent-shell--on-request
  (let ((+my/agent-shell--requesting (plist-get args :state)))
    (apply fn args)))

(defvar +my/agent-shell-permission-responder-next nil
  "The permission responder there was before ours: asked when the rules
say nothing.")

(defun +my/agent-shell-permission-responder (permission)
  "PERMISSION (agent-shell's) answered by its session's rules
\(`+my/agent-shell-permission-rules'), as an option of its kind; else the
responder before ours's, else nil (asked)."
  (let* ((buffer (map-elt +my/agent-shell--requesting :buffer))
         (rules (and (buffer-live-p buffer) (buffer-local-value '+my/agent-shell-permission-rules buffer)))
         (verdict (and rules (+my/agent-shell-permission-by-rules
                              rules (map-elt permission :tool-call)
                              (with-current-buffer buffer (ignore-errors (agent-shell-cwd))))))
         (option (and verdict
                      (seq-some (lambda (kind)
                                  (seq-find (lambda (option) (equal (map-elt option :kind) kind))
                                            (map-elt permission :options)))
                                (if (eq verdict 'allow) '("allow_once" "allow_always") '("reject_once" "reject_always"))))))
    (if option
        (progn (funcall (map-elt permission :respond) (map-elt option :option-id)) t)
      (and (functionp +my/agent-shell-permission-responder-next)
           (funcall +my/agent-shell-permission-responder-next permission)))))

(with-eval-after-load 'agent-shell
  (unless (eq agent-shell-permission-responder-function #'+my/agent-shell-permission-responder)
    (setq +my/agent-shell-permission-responder-next agent-shell-permission-responder-function
          agent-shell-permission-responder-function #'+my/agent-shell-permission-responder)))
