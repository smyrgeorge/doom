;;; $DOOMDIR/config/agent-workspace/session.el -*- lexical-binding: t; -*-
;; An agent's session. Loaded from config/agent-workspace.el, after core.el
;; and worktree.el. No Doom here.
;;
;; agent-shell's, started in its worktree with a config of its own (its name
;; on its buffer, its role's model, mode, tools and instructions, its
;; environment), its events moving its state (core.el), and stopped without a
;; question, leaving no process behind.

(require 'cl-lib)
(require 'subr-x)
(require 'map)

(declare-function agent-shell--start "agent-shell")
(declare-function agent-shell-subscribe-to "agent-shell")
(declare-function agent-shell-interrupt "agent-shell")
(declare-function agent-shell-insert "agent-shell")
(declare-function agent-shell--prompt-queue-enqueue "agent-shell-prompt-queue")
(declare-function agent-shell--prompt-queue-confirm-kill-buffer "agent-shell-prompt-queue")
(declare-function shell-maker-busy "shell-maker")
(declare-function shell-maker--process "shell-maker")
(defvar agent-shell--state)
(defvar agent-shell-mcp-servers)
(defvar agent-shell-buffer-name-format)
(defvar agent-shell-show-welcome-message)
(defvar shell-maker-prompt-before-killing-buffer)

;; ====== VARIABLES ======

(defcustom agent-workspace-kinds
  '((claude-code :config agent-shell-anthropic-make-claude-code-config :claude-code t))
  "The agents a crew can have: a kind (a symbol) and how its session starts.
:config, a function returning agent-shell's config for it; :claude-code,
non-nil if it's Claude Code (its role's tools go to Claude Code's options)."
  :type '(alist :key-type symbol :value-type plist)
  :group 'agent-workspace)

(defcustom agent-workspace-exit-timeout 7
  "Seconds a stopped session's processes have to exit, before any left is
killed (acp.el gives the agent's process group 5, then kills the group: this
catches what left the group)."
  :type 'number
  :group 'agent-workspace)

(defvar agent-workspace-session-functions nil
  "Called with an agent and its session's buffer, once its session started.")

(defvar agent-workspace--starting nil
  "The agent whose session starts, while its config is made (see
`agent-workspace-agent-context').")

(defvar-local agent-workspace--watched nil
  "In an agent's session: its agent's process, once watched for its end.")

;; ====== STARTING ======

(defun agent-workspace--start (agent)
  "Start AGENT's session, fresh, in its worktree (made again if it went): its
buffer, not shown. If it can't start, AGENT is stuck, saying why."
  (require 'agent-shell)
  (when (buffer-live-p (agent-workspace-agent-buffer agent))
    (agent-workspace--stop agent 'waking))
  (setf (agent-workspace-agent-buffer agent) nil)
  (agent-workspace--set-state agent 'waking)
  (condition-case err
      (let* ((dir (agent-workspace-worktree-ensure agent))
             (config (let ((agent-workspace--starting agent))
                       (agent-workspace--config agent)))
             ;; Its buffer named as its config says: "ada · builder".
             (agent-shell-buffer-name-format (lambda (name _project) name))
             ;; No welcome: its pane is small, its line says who it is.
             (agent-shell-show-welcome-message nil)
             (buffer (agent-shell--start :config config :no-focus t :new-session t
                                         :session-strategy 'new :cwd dir)))
        (with-current-buffer buffer
          (setq agent-workspace--agent agent)
          ;; Stopping it asks nothing: not agent-shell's "N prompts
          ;; queued. Kill anyway?", nor shell-maker's to save its transcript,
          ;; nor Emacs's about its process when quitting.
          (remove-hook 'kill-buffer-query-functions #'agent-shell--prompt-queue-confirm-kill-buffer t)
          (setq-local shell-maker-prompt-before-killing-buffer nil)
          (when-let* ((process (ignore-errors (shell-maker--process))))
            (set-process-query-on-exit-flag process nil))
          (add-hook 'window-buffer-change-functions #'agent-workspace--shown-h nil t))
        (setf (agent-workspace-agent-buffer agent) buffer)
        (agent-shell-subscribe-to
         :shell-buffer buffer
         :on-event (lambda (event)
                     ;; An old session's events, once it's been replaced, aren't its.
                     (when (eq (agent-workspace-agent-buffer agent) buffer)
                       (agent-workspace--watch-process agent buffer)
                       (agent-workspace--event agent event))))
        (run-hook-with-args 'agent-workspace-session-functions agent buffer)
        (agent-workspace--changed agent 'session)
        buffer)
    (error
     (setf (agent-workspace-agent-buffer agent) nil)
     (agent-workspace--set-state agent 'stuck)
     (setf (agent-workspace-agent-error agent) (concat "its session: " (error-message-string err)))
     (agent-workspace--changed agent 'state)
     (message "%s's session didn't start: %s" (agent-workspace-agent-name agent) (error-message-string err))
     nil)))

(defun agent-workspace--config (agent)
  "agent-shell's config for AGENT's session (see the top of this file)."
  (let* ((kind (or (alist-get (agent-workspace-agent-kind agent) agent-workspace-kinds)
                   (error "No such kind of agent: %s" (agent-workspace-agent-kind agent))))
         (role (agent-workspace-role agent))
         (model (or (agent-workspace-agent-model agent) (plist-get role :model)))
         (mode (or (agent-workspace-agent-mode agent) (plist-get role :mode)))
         ;; A copy: the maker's own values (a quoted session meta) stay.
         (config (copy-tree (funcall (plist-get kind :config))))
         (maker (alist-get :client-maker config))
         (environment (agent-workspace--environment agent)))
    (setf (alist-get :buffer-name config) (agent-workspace-buffer-name agent))
    (when model
      (setf (alist-get :default-model-id config) (lambda () model)))
    (when mode
      (setf (alist-get :default-session-mode-id config) (lambda () mode)))
    (when-let* ((servers (plist-get role :mcp-servers)))
      (setf (alist-get :mcp-servers config)
            (append (bound-and-true-p agent-shell-mcp-servers) servers)))
    (when (plist-get kind :claude-code)
      (setf (alist-get :session-meta config)
            (agent-workspace--claude-options (alist-get :session-meta config) role)))
    ;; Its environment added to whatever the kind's client has.
    (when maker
      (setf (alist-get :client-maker config)
            (lambda (buffer)
              (let ((client (funcall maker buffer)))
                (when client
                  (setf (alist-get :environment-variables client)
                        (append environment (alist-get :environment-variables client))))
                client))))
    config))

(defun agent-workspace--claude-options (meta role)
  "META, Claude Code's session meta, with ROLE's tools in Claude Code's
options (allowedTools, disallowedTools). Its model goes through agent-shell
\(:default-model-id), checked by the agent."
  (let* ((claude (alist-get 'claudeCode meta))
         (options (alist-get 'options claude)))
    (when-let* ((tools (plist-get role :tools)))
      (setf (alist-get 'allowedTools options) (vconcat tools)))
    (when-let* ((deny (plist-get role :deny)))
      (setf (alist-get 'disallowedTools options) (vconcat deny)))
    (when options
      (setf (alist-get 'options claude) options
            (alist-get 'claudeCode meta) claude))
    meta))

(defun agent-workspace--environment (agent)
  "AGENT's environment variables (\"NAME=VALUE\"): its name for Beads
\(BEADS_ACTOR: who it is in the issues' history, the assignee of an issue it
claims) and for us (AGENT_WORKSPACE_AGENT); the project's issues (BEADS_DIR:
it works in a worktree)."
  (let ((name (agent-workspace-agent-name agent))
        (beads (expand-file-name ".beads" (agent-workspace-agent-project agent))))
    (append (list (concat "BEADS_ACTOR=" name)
                  (concat "AGENT_WORKSPACE_AGENT=" name))
            (when (file-directory-p beads)
              (list (concat "BEADS_DIR=" beads))))))

(defvar agent-workspace-context-functions nil
  "Called with the agent whose session starts: a paragraph more it's told
\(its crew and messages: messages.el), or nil.")

(defun agent-workspace-agent-context ()
  "What the agent whose session starts is told, after what every session
is: who it is and how it works, then its role's instructions. nil for any
other session."
  (when-let* ((agent agent-workspace--starting))
    (let* ((name (agent-workspace-agent-name agent))
           (project (agent-workspace-agent-project agent))
           (instructions (plist-get (agent-workspace-role agent) :instructions)))
      (concat
       (format "You are %s, the %s in a crew of coding agents the user runs at once on \
%s, from Emacs (its agent workspace). Each agent has a name, a role and a colour. You \
work for the user: your work comes from them (in your session, from the crew's room, \
an issue they give you), and you answer them. Don't hand work to other agents or wait \
for them.

You work in your own git worktree, %s, on the branch %s: make your changes and \
commits there, never in the project's main checkout (%s), which is the user's. They \
review your branch and merge it. Your bd commands run as %s (BEADS_ACTOR), on the \
project's issues: an issue the user gives you, claim it as yourself. Your notifications \
carry your name already."
               name (agent-workspace-agent-role agent)
               (file-name-nondirectory (directory-file-name project))
               (directory-file-name (agent-workspace-agent-worktree agent))
               (agent-workspace-agent-branch agent)
               (directory-file-name project)
               name)
       (mapconcat (lambda (more) (concat "\n\n" more))
                  (delq nil (mapcar (lambda (function) (funcall function agent))
                                    agent-workspace-context-functions))
                  "")
       (when (and instructions (not (string-empty-p (string-trim instructions))))
         (concat "\n\n" (string-trim instructions)))))))

;; ====== WHILE IT RUNS ======

(defun agent-workspace--session-process (buffer)
  "The agent's process of the session BUFFER (its ACP client's), or nil."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when-let* ((client (and (boundp 'agent-shell--state)
                               (map-elt agent-shell--state :client))))
        (map-elt client :process)))))

(defun agent-workspace--watch-process (agent buffer)
  "AGENT's process watched, once there is one: its end (not stopped by us)
sends AGENT home."
  (unless (buffer-local-value 'agent-workspace--watched buffer)
    (when-let* ((process (agent-workspace--session-process buffer)))
      (with-current-buffer buffer
        (setq agent-workspace--watched process))
      (add-function :after (process-sentinel process)
                    (lambda (process _event)
                      (when (and (not (process-live-p process))
                                 (eq (agent-workspace-agent-buffer agent) buffer)
                                 (not (agent-workspace-agent-stopping agent)))
                        (agent-workspace--set-state agent 'home)))))))

(defun agent-workspace--shown-h (window)
  "An agent's session shown in WINDOW: you looked (done becomes at the
desk). Buffer-local in `window-buffer-change-functions'."
  (when-let* ((agent (agent-workspace-buffer-agent (window-buffer window))))
    (agent-workspace-seen agent)))

(declare-function agent-ui-ask-question "agent-ui/ask")
(declare-function agent-ui-get "agent-ui/canvas")

(defun agent-workspace--question-waiting (session canvas id)
  "SESSION's turn ended with question ID waiting on its Agent UI CANVAS: its
agent raises its hand, asking it. In `agent-ui-question-waiting-functions'."
  (when-let* ((agent (agent-workspace-buffer-agent session)))
    (when (eq (agent-workspace-agent-buffer agent) session)
      (agent-workspace--raise-hand
       agent (list :kind 'question :canvas canvas :id id
                   :title (or (and (buffer-live-p canvas) (fboundp 'agent-ui-ask-question)
                                   (ignore-errors (agent-ui-ask-question (agent-ui-get id :canvas canvas))))
                              "a question on its canvas"))))))

(cl-defun agent-workspace-send (agent text &key submit)
  "Put TEXT in AGENT's prompt; SUBMIT: send it. Working, it gets it after
its turn (agent-shell's queue); still waking up, once it's ready. Return
`sent', `queued' or `inserted'."
  (let ((buffer (agent-workspace--live-or-error agent)))
    (cond
     ((and submit (memq (agent-workspace-agent-state agent) '(working hand))
           (with-current-buffer buffer (shell-maker-busy)))
      (with-current-buffer buffer
        (agent-shell--prompt-queue-enqueue :prompt text))
      'queued)
     (t
      (agent-shell-insert :text text :submit submit :no-focus t :shell-buffer buffer)
      (if submit 'sent 'inserted)))))

;; ====== STOPPING ======
;; A session's buffer killed: agent-shell shuts its agent down (acp.el: the
;; agent's process group sent SIGTERM, then SIGKILL 5 s later). What it
;; started outside its group (a command in a session of its own) is found
;; first, and killed if it's still there `agent-workspace-exit-timeout' later.

(defun agent-workspace--process-table ()
  "Every process: (PID PPID START STATE)."
  (delq nil (mapcar (lambda (pid)
                      (when-let* ((attributes (process-attributes pid)))
                        (list pid (alist-get 'ppid attributes) (alist-get 'start attributes)
                              (alist-get 'state attributes))))
                    (list-system-processes))))

(defun agent-workspace--process-tree (pid table)
  "PID and its descendants in TABLE (`agent-workspace--process-table'), each
\(PID . START)."
  (let ((tree (list pid))
        (more t))
    (while more
      (setq more nil)
      (dolist (entry table)
        (when (and (memq (nth 1 entry) tree) (not (memq (car entry) tree)))
          (push (car entry) tree)
          (setq more t))))
    (delq nil (mapcar (lambda (pid)
                        (when-let* ((entry (assq pid table)))
                          (cons pid (nth 2 entry))))
                      tree))))

(defun agent-workspace--alive-p (process)
  "Non-nil if PROCESS, (PID . START), still runs (the same one: not a pid
used again, nor a zombie)."
  (when-let* ((attributes (process-attributes (car process))))
    (and (equal (alist-get 'start attributes) (cdr process))
         (not (member (alist-get 'state attributes) '("Z" "X"))))))

(defun agent-workspace--reap (processes)
  "Kill PROCESSES, each (PID . START), still running."
  (dolist (process processes)
    (when (agent-workspace--alive-p process)
      (ignore-errors (signal-process (car process) 'SIGKILL)))))

(defun agent-workspace--stop (agent state &optional table)
  "Stop AGENT's session, if it runs, without asking; AGENT then in STATE.
TABLE: the processes now (`agent-workspace--process-table'), when several
are stopped at once. Return its processes, (PID . START) each, killed
`agent-workspace-exit-timeout' later if still running."
  (let ((buffer (agent-workspace-agent-buffer agent))
        processes)
    (setf (agent-workspace-agent-stopping agent) t)
    (unwind-protect
        (when (buffer-live-p buffer)
          (when-let* ((process (agent-workspace--session-process buffer))
                      (pid (and (process-live-p process) (process-id process))))
            (setq processes (agent-workspace--process-tree
                             pid (or table (agent-workspace--process-table)))))
          (let ((kill-buffer-query-functions nil))
            (kill-buffer buffer))
          (when processes
            (run-at-time agent-workspace-exit-timeout nil #'agent-workspace--reap processes)))
      (setf (agent-workspace-agent-stopping agent) nil
            (agent-workspace-agent-buffer agent) nil))
    (agent-workspace--set-state agent state)
    processes))

(defun agent-workspace--quit-h ()
  "Emacs quits: every crew closed, their processes given a second to exit,
then killed. In `kill-emacs-hook'."
  (let ((processes (agent-workspace-close-all))
        (deadline (+ (float-time) 1.0)))
    (while (and (seq-some #'agent-workspace--alive-p processes)
                (< (float-time) deadline))
      (sleep-for 0.05))
    (agent-workspace--reap processes)))

(add-hook 'kill-emacs-hook #'agent-workspace--quit-h)

(defun agent-workspace--no-question-a (fn &rest args)
  "agent-shell asking, as Emacs quits, about queued prompts: not the crews'
\(their sessions end with Emacs, asking nothing)."
  (let (held)
    (dolist (buffer (buffer-list))
      (when-let* ((agent (agent-workspace-buffer-agent buffer))
                  ((boundp 'agent-shell--state))
                  (state (buffer-local-value 'agent-shell--state buffer))
                  (prompts (map-elt state :pending-prompts)))
        (push (cons state prompts) held)
        (map-put! state :pending-prompts nil)))
    (unwind-protect (apply fn args)
      (dolist (entry held)
        (map-put! (car entry) :pending-prompts (cdr entry))))))

(with-eval-after-load 'agent-shell-prompt-queue
  (advice-add 'agent-shell--prompt-queue-confirm-kill-emacs :around #'agent-workspace--no-question-a))
