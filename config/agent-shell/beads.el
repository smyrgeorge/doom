;;; $DOOMDIR/config/agent-shell/beads.el -*- lexical-binding: t; -*-
;; Issues for Claude: a project's Beads issues (config/beads.el) in its
;; sessions (see ISSUES FOR CLAUDE there). Loaded from config/agent-shell.el.

;; THE PROJECT'S ISSUES

(defun +my/agent-shell-beads--root (&optional dir)
  "DIR's (else the session's, else a new session's) folder, if it tracks its
issues with Beads (a .beads/ folder there)."
  (let ((dir (file-name-as-directory
              (expand-file-name (or dir (if (fboundp 'agent-shell-cwd)
                                            (agent-shell-cwd)
                                          default-directory))))))
    (and (file-directory-p (expand-file-name ".beads" dir))
         dir)))

(defun +my/agent-shell-beads--bd (root &rest args)
  "bd's output with ARGS in ROOT, or nil (no bd, or it failed)."
  (when (executable-find "bd")
    (with-temp-buffer
      (let ((default-directory root))
        (when (eql 0 (ignore-errors (apply #'call-process "bd" nil '(t nil) nil args)))
          (string-trim (buffer-string)))))))

;; WHAT CLAUDE IS TOLD (a session's system prompt, config/agent-shell/context.el)

;; Beads' guide once: a project whose Claude Code settings run bd prime as a
;; session starts (a SessionStart hook: `bd setup claude' adds one; this
;; config's own .claude/settings.json has it) gives Claude the guide already,
;; 7 KB: claude-agent-acp loads the user's, the project's and its local
;; settings, as Claude Code in a terminal does.
(defun +my/agent-shell-beads--claude-settings (root)
  "Claude Code's settings files for a session in ROOT: the project's, its
local ones, the user's."
  (list (expand-file-name ".claude/settings.json" root)
        (expand-file-name ".claude/settings.local.json" root)
        (expand-file-name "settings.json" (or (getenv "CLAUDE_CONFIG_DIR") "~/.claude"))))

(defun +my/agent-shell-beads--primed-p (root)
  "Non-nil if Claude Code's settings for ROOT run bd prime when a session
starts (see above)."
  (seq-some
   (lambda (file)
     (when-let* (((file-readable-p file))
                 (settings (ignore-errors
                             (with-temp-buffer
                               (insert-file-contents file)
                               (json-parse-buffer :object-type 'alist :array-type 'list
                                                  :null-object nil :false-object nil)))))
       (seq-some (lambda (matcher)
                   (seq-some (lambda (hook)
                               (let ((command (alist-get 'command hook)))
                                 (and (stringp command)
                                      (string-match-p "\\bbd prime\\b" command))))
                             (alist-get 'hooks matcher)))
                 (alist-get 'SessionStart (alist-get 'hooks settings)))))
   (+my/agent-shell-beads--claude-settings root)))

(defun +my/agent-shell-beads-context ()
  "For a session in a project tracking its issues with Beads: what Claude is
told of them, Beads' guide after (see ISSUES FOR CLAUDE), unless the
project's Claude Code settings give it already (see above); else nil."
  (when-let* ((root (+my/agent-shell-beads--root))
              ((executable-find "bd")))
    (string-join (delq nil (list +my/agent-shell-beads-context
                                 (and +my/agent-shell-beads-prime
                                      (not (+my/agent-shell-beads--primed-p root))
                                      (+my/agent-shell-beads--bd root "prime"))))
                 "\n\n")))

(add-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context t)

;; EMACS FOLLOWS CLAUDE'S CHANGES
;; Each of Claude's shell commands running bd, once done: the project's issue
;; lists and issues open in Emacs refreshed (once for a burst of them in that
;; project, each project its own: one for all refreshed only the last one's),
;; in the background (config/beads/refresh.el: those not shown, once shown
;; again).

(defconst +my/agent-shell-beads--command-regexp
  "\\(?:\\`\\|[;&|(`]\\|\\$(\\|[[:space:]]\\)bd\\(?:[[:space:]]\\|\\'\\)"
  "A shell command running bd.")

(defvar +my/agent-shell-beads--refresh-timers (make-hash-table :test #'equal)
  "Each project's refresh to come: its root -> a timer.")

(defun +my/agent-shell-beads--buffers (root)
  "Beads' issue lists and issues of ROOT's project."
  (seq-filter (lambda (buffer)
                (with-current-buffer buffer
                  (and (derived-mode-p '(beads-list-mode beads-detail-mode beads-detail-vui-mode))
                       (string-prefix-p root (file-name-as-directory
                                              (expand-file-name default-directory))))))
              (buffer-list)))

(defun +my/agent-shell-beads-refresh (root)
  "Refresh the issue lists and issues of ROOT's project open in Emacs."
  (remhash root +my/agent-shell-beads--refresh-timers)
  (dolist (buffer (+my/agent-shell-beads--buffers root))
    (with-current-buffer buffer
      (with-demoted-errors "Beads refresh: %S"
        (let ((inhibit-message t))
          (cond ((fboundp '+my/beads-refresh-async) (+my/beads-refresh-async buffer t))
                ((derived-mode-p 'beads-list-mode) (beads-list-refresh))
                ((fboundp 'beads-detail-refresh) (beads-detail-refresh))))))))

(defun +my/agent-shell-beads--tool-call (root event)
  "EVENT (a tool call updated) in a session in ROOT: a bd command done
refreshes ROOT's issues soon."
  (let* ((tool-call (map-nested-elt event '(:data :tool-call)))
         (command (map-elt tool-call :command)))
    (when (and (member (map-elt tool-call :status) '("completed" "failed"))
               (stringp command)
               (string-match-p +my/agent-shell-beads--command-regexp command))
      (when-let* ((timer (gethash root +my/agent-shell-beads--refresh-timers))
                  ((timerp timer)))
        (cancel-timer timer))
      (puthash root (run-at-time 0.3 nil #'+my/agent-shell-beads-refresh root)
               +my/agent-shell-beads--refresh-timers))))

(defun +my/agent-shell-beads--watch-h ()
  "In a new session in a project tracking its issues with Beads: follow
Claude's bd commands (see above)."
  (when-let* ((root (+my/agent-shell-beads--root)))
    (agent-shell-subscribe-to
     :shell-buffer (current-buffer)
     :event 'tool-call-update
     :on-event (lambda (event) (+my/agent-shell-beads--tool-call root event)))))

(add-hook 'agent-shell-mode-hook #'+my/agent-shell-beads--watch-h)

;; AN ISSUE INTO THE PROMPT

(defun +my/agent-shell-beads--text (issue)
  "How ISSUE (bd's JSON) goes into a prompt: Beads issue ID: title."
  (format "Beads issue %s: %s" (alist-get 'id issue) (alist-get 'title issue)))

(defun +my/agent-shell-beads--candidates (root)
  "ROOT's open issues as completion candidates (TEXT . ISSUE), the ready ones
first, then by priority."
  (let* ((default-directory root)
         (ready (mapcar (lambda (issue) (alist-get 'id issue)) (beads-client-ready)))
         (issues (seq-remove (lambda (issue) (equal (alist-get 'status issue) "closed"))
                             (beads-client-list))))
    (mapcar (lambda (issue)
              (cons (format "%-10s P%s %-8s %-12s %s"
                            (alist-get 'id issue)
                            (alist-get 'priority issue)
                            (alist-get 'issue_type issue)
                            (if (member (alist-get 'id issue) ready) "ready" (alist-get 'status issue))
                            (alist-get 'title issue))
                    issue))
            (sort issues
                  (lambda (a b)
                    (let ((ra (member (alist-get 'id a) ready))
                          (rb (member (alist-get 'id b) ready)))
                      (if (eq (not ra) (not rb))
                          (< (or (alist-get 'priority a) 9) (or (alist-get 'priority b) 9))
                        ra)))))))

(defun +my/agent-shell-beads-insert ()
  "One of the project's open issues, picked, into this session's prompt (see
ISSUES FOR CLAUDE in config/agent-shell.el)."
  (interactive)
  (let ((shell (if (derived-mode-p 'agent-shell-mode)
                   (current-buffer)
                 (user-error "Not in an agent-shell"))))
    (let* ((root (or (+my/agent-shell-beads--root)
                     (user-error "This session's project doesn't track its issues with Beads (bd init)")))
           (candidates (progn (require 'beads)
                              (+my/agent-shell-beads--candidates root)))
           (choice (if candidates
                       (completing-read "Issue: " candidates nil t)
                     (user-error "No open issues"))))
      (agent-shell-insert :text (+my/agent-shell-beads--text (cdr (assoc choice candidates)))
                          :shell-buffer shell))))

(defun +my/agent-shell-beads--issue-here ()
  "The issue at point (an issue list) or shown (an issue's buffer)."
  (cond ((derived-mode-p 'beads-list-mode) (beads-list--get-issue-at-point))
        ((bound-and-true-p beads-detail--current-issue))))

(defun +my/agent-shell-beads-send ()
  "The issue at point, or shown, into the prompt of the project's session (see
ISSUES FOR CLAUDE in config/agent-shell.el)."
  (interactive)
  (let* ((issue (or (+my/agent-shell-beads--issue-here)
                    (user-error "No issue here")))
         (shell (progn (require 'agent-shell)
                       (or (agent-shell--shell-buffer :no-create t :no-error t)
                           (user-error "No Claude Code session in this project: SPC o C starts one")))))
    (agent-shell-insert :text (+my/agent-shell-beads--text issue) :shell-buffer shell)))
