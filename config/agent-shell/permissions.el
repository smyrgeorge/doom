;;; $DOOMDIR/config/agent-shell/permissions.el -*- lexical-binding: t; -*-
;; A session's permission request answered from elsewhere (an agent
;; workspace's raised hand, a workflow run's pane): agent-shell's own buttons
;; (Allow, Always allow, Reject...), read from its buffer and pressed as they
;; are. Loaded from config/agent-shell.el.

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
;; starting with git push, Bash(git -C * push) one with * anything (a command
;; line by its simple commands: each allowed, or any refused), Edit
;; (docs/**) a path under docs/ (relative to the session's folder; /x and ./x
;; from there, //x absolute, ~/x your home's; **/ any folders, none too),
;; Read, Grep, Glob, WebFetch, WebSearch by kind alone.
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

(defconst +my/agent-shell--shells '("sh" "bash" "zsh" "dash" "ksh")
  "The shells an argv's command line is unwrapped from (bash -lc \"git push\").")

(defun +my/agent-shell--argv-command (argv)
  "ARGV (a list of strings) as the command line it runs: a shell's -c
script (bash -lc \"git push\": git push), else its words quoted."
  (let ((argv (mapcar (lambda (part) (format "%s" part)) argv)))
    (or (and (member (file-name-nondirectory (car argv)) +my/agent-shell--shells)
             (let ((rest (cdr argv)))
               ;; Its options, up to the one with c (-c, -lc, -ic...).
               (while (and rest (string-match-p "\\`-[a-z]*\\'" (car rest))
                           (not (string-match-p "\\`-[a-z]*c[a-z]*\\'" (car rest))))
                 (setq rest (cdr rest)))
               (and rest (string-match-p "\\`-[a-z]*c[a-z]*\\'" (car rest)) (cadr rest))))
        (combine-and-quote-strings argv))))

(defun +my/agent-shell--tool-call-command (tool-call)
  "The command TOOL-CALL runs (its raw input's command, command_line or
cmd: a string, or an argv, a shell's -c unwrapped), else its title: a
string, or nil."
  (let* ((input (map-elt tool-call :raw-input))
         (command (or (map-elt input 'command) (map-elt input 'command_line) (map-elt input 'cmd))))
    (cond ((stringp command) command)
          ((and (sequencep command) (> (length command) 0))
           (+my/agent-shell--argv-command (append command nil)))
          ((stringp (map-elt tool-call :title))
           (string-trim (map-elt tool-call :title) "[` ]+" "[` ]+")))))

(defun +my/agent-shell--tool-call-paths (tool-call)
  "The files TOOL-CALL acts on: its raw input's (file_path, path, filePath,
filepath, fileName, notebook_path), its diffs', its locations'."
  (let ((input (map-elt tool-call :raw-input)))
    (delete-dups
     (seq-filter (lambda (path) (and (stringp path) (not (string-empty-p path))))
                 (append (mapcar (lambda (key) (map-elt input key))
                                 '(file_path path filePath filepath fileName notebook_path))
                         (mapcar (lambda (diff) (map-elt diff :file)) (append (map-elt tool-call :diffs) nil))
                         (mapcar (lambda (location) (map-elt location 'path))
                                 (append (map-elt tool-call :locations) nil)))))))

(defun +my/agent-shell--glob-regexp (glob &optional paths)
  "GLOB as an anchored regexp: * anything (in PATHS: but /), ** anything;
in PATHS, **/ any folders, none too (**/.env the top's, docs/**/*.md
docs/a.md)."
  (let ((i 0) (n (length glob)) (out nil))
    (while (< i n)
      (cond
       ((and paths (string-prefix-p "**/" (substring glob i)))
        (push "\\(?:.*/\\)?" out) (cl-incf i 3))
       ((string-prefix-p "**" (substring glob i))
        (push ".*" out) (cl-incf i 2))
       ((eq (aref glob i) ?*)
        (push (if paths "[^/]*" ".*") out) (cl-incf i))
       (t (push (regexp-quote (string (aref glob i))) out) (cl-incf i))))
    (concat "\\`" (apply #'concat (nreverse out)) "\\'")))

(defun +my/agent-shell--command-parts (command)
  "COMMAND's simple commands, split where the shell would run another (;
&& || | & and a new line, outside quotes), each trimmed, its blanks outside
quotes one space; nil if it can't be split so: it runs a command of its own
inside (`$(...)', backquotes, `<(...)'), a subshell or a group ({ ...; }),
or a quote isn't closed."
  (let ((parts nil) (part nil) (quoting nil) (i 0) (n (length command)) (ok t))
    (cl-flet ((end () (let ((text (string-trim (apply #'string (nreverse part)))))
                        (unless (string-empty-p text) (push text parts))
                        (setq part nil))))
      (while (and ok (< i n))
        (let ((c (aref command i))
              (next (and (< (1+ i) n) (aref command (1+ i)))))
          (cond
           ;; Inside '...': all as it is.
           ((eq quoting ?')
            (push c part)
            (when (eq c ?') (setq quoting nil)))
           ((and (eq c ?\\) next)
            (push c part) (push next part) (cl-incf i))
           ((or (eq c ?`) (and (eq c ?$) (eq next ?\()))
            (setq ok nil))
           ((eq quoting ?\")
            (push c part)
            (when (eq c ?\") (setq quoting nil)))
           ((memq c '(?' ?\"))
            (push c part) (setq quoting c))
           ((and (memq c '(?< ?>)) (eq next ?\())
            (setq ok nil))
           ;; A subshell, a group: a { starting a word (not ${VAR}, {}).
           ((or (memq c '(?\( ?\)))
                (and (eq c ?{) (memq (car part) '(nil ?\s)) (memq next '(?\s ?\t ?\n))))
            (setq ok nil))
           ;; A redirection's & (2>&1, &>file): not an operator.
           ((and (eq c ?&) (or (memq (car part) '(?> ?<)) (eq next ?>)))
            (push c part))
           ((memq c '(?\; ?& ?| ?\n))
            (end)
            (when (and next (memq next '(?& ?| ?\;)) (not (eq c ?\n)))
              (cl-incf i)))
           ((memq c '(?\s ?\t))
            (unless (eq (car part) ?\s) (push ?\s part)))
           (t (push c part))))
        (cl-incf i))
      (when (and ok (not quoting))
        (end)
        (nreverse parts)))))

(defun +my/agent-shell--command-forms (part)
  "PART (a simple command) and the forms a deny rule matches too: its
variables' assignments before it left out, its program's folder (/usr/bin/git
as git)."
  (let* ((words (split-string part " "))
         (words (seq-drop-while (lambda (word) (string-match-p "\\`[A-Za-z_][A-Za-z0-9_]*=" word)) words))
         (words (if (and words (string-match-p "/" (car words)))
                    (cons (file-name-nondirectory (car words)) (cdr words))
                  words)))
    (delete-dups (list part (string-join words " ")))))

(defun +my/agent-shell--command-matches-p (pattern command)
  "Non-nil if Bash's PATTERN matches COMMAND (one simple command):
prefix:* it, or it then a space; else a glob, * anything, the whole."
  (if (string-suffix-p ":*" pattern)
      (let ((prefix (string-remove-suffix ":*" pattern)))
        (or (equal command prefix) (string-prefix-p (concat prefix " ") command)))
    (string-match-p (+my/agent-shell--glob-regexp pattern) command)))

(defun +my/agent-shell--bash-verdict (rules tool-call)
  "What RULES (:tools :deny) say of TOOL-CALL, a command run: reject if a
deny rule matches any of its simple commands (or, one that can't be split,
it whole), allow if each of them matches a tools rule, else nil (asked)."
  (let* ((command (+my/agent-shell--tool-call-command tool-call))
         (parts (and command (+my/agent-shell--command-parts command)))
         (applies (lambda (rule text)
                    (pcase-let ((`(,tool . ,pattern) (+my/agent-shell--rule-parse rule)))
                      (and (member "execute" (cdr (assoc tool +my/agent-shell-rule-kinds)))
                           (or (null pattern)
                               (and text (+my/agent-shell--command-matches-p pattern text))))))))
    (cond
     ((seq-some (lambda (rule)
                  (seq-some (lambda (text) (funcall applies rule text))
                            (or (seq-mapcat #'+my/agent-shell--command-forms parts) (list command))))
                (plist-get rules :deny))
      'reject)
     ;; Its command not known, a deny rule naming commands: asked, not
     ;; allowed by a rule for every command.
     ((and (null command)
           (seq-some (lambda (rule) (pcase-let ((`(,tool . ,pattern) (+my/agent-shell--rule-parse rule)))
                                      (and pattern (member "execute" (cdr (assoc tool +my/agent-shell-rule-kinds))))))
                     (plist-get rules :deny)))
      nil)
     ((if parts
          (seq-every-p (lambda (part) (seq-some (lambda (rule) (funcall applies rule part)) (plist-get rules :tools)))
                       parts)
        ;; Not split (or none known): only a rule for every command.
        (seq-some (lambda (rule) (funcall applies rule nil)) (plist-get rules :tools)))
      'allow))))

(defun +my/agent-shell-rule-matches-p (rule tool-call &optional dir)
  "Non-nil if RULE (Claude Code's syntax) matches TOOL-CALL (agent-shell's:
its :kind, :title, :raw-input, :locations), DIR its session's folder. A
command: each of its simple commands matching (see
`+my/agent-shell--command-parts'), none if it can't be split."
  (pcase-let* ((`(,tool . ,pattern) (+my/agent-shell--rule-parse rule))
               (kinds (cdr (assoc tool +my/agent-shell-rule-kinds))))
    (and (member (map-elt tool-call :kind) kinds)
         (or (null pattern)
             (if (equal tool "Bash")
                 (when-let* ((command (+my/agent-shell--tool-call-command tool-call))
                             (parts (+my/agent-shell--command-parts command)))
                   (seq-every-p (lambda (part) (+my/agent-shell--command-matches-p pattern part)) parts))
               (let ((dir (and dir (file-name-as-directory (expand-file-name dir)))))
                 (seq-some
                  (lambda (path)
                    (let* ((path (expand-file-name path dir))
                           ;; //x and ~/x: absolute; /x and ./x: from the
                           ;; session's folder, as x.
                           (absolute (or (string-prefix-p "//" pattern) (string-prefix-p "~/" pattern)))
                           (target (cond (absolute path)
                                         ((and dir (string-prefix-p dir path)) (substring path (length dir)))
                                         (t path)))
                           (glob (cond ((string-prefix-p "//" pattern) (substring pattern 1))
                                       ((string-prefix-p "~/" pattern)
                                        (concat (expand-file-name "~/") (substring pattern 2)))
                                       ((string-prefix-p "./" pattern) (substring pattern 2))
                                       ((string-prefix-p "/" pattern) (substring pattern 1))
                                       (t pattern))))
                      (string-match-p (+my/agent-shell--glob-regexp glob t) target)))
                  (+my/agent-shell--tool-call-paths tool-call))))))))

(defun +my/agent-shell-permission-by-rules (rules tool-call &optional dir)
  "What RULES ((:tools RULES :deny RULES)) say of TOOL-CALL: reject (a deny
rule matches), allow (a tools rule does), or nil (ask). A command, by its
simple commands (`+my/agent-shell--bash-verdict')."
  (if (equal (map-elt tool-call :kind) "execute")
      (+my/agent-shell--bash-verdict rules tool-call)
    (cond ((seq-some (lambda (rule) (+my/agent-shell-rule-matches-p rule tool-call dir)) (plist-get rules :deny))
           'reject)
          ;; What it acts on not known, a deny rule naming paths of its
          ;; kind: asked, not allowed by a rule for all of them.
          ((and (null (+my/agent-shell--tool-call-paths tool-call))
                (seq-some (lambda (rule)
                            (pcase-let ((`(,tool . ,pattern) (+my/agent-shell--rule-parse rule)))
                              (and pattern (member (map-elt tool-call :kind) (cdr (assoc tool +my/agent-shell-rule-kinds))))))
                          (plist-get rules :deny)))
           nil)
          ((seq-some (lambda (rule) (+my/agent-shell-rule-matches-p rule tool-call dir)) (plist-get rules :tools))
           'allow))))

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
