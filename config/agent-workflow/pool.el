;;; $DOOMDIR/config/agent-workflow/pool.el -*- lexical-binding: t; -*-
;; The pool: agent sessions, as many at once as `agent-workflow-pool' says.
;; Loaded from config/agent-workflow.el, after worktree.el. No Doom here.
;;
;; An agent has no role and no name: it's a job's, known by its issue and
;; job ("doom-a1b · review"), started for an agent step with that step's
;; profile, in the issue's worktree (worktree.el). Its session is
;; agent-shell's (its buffer named so): its permissions, questions, usage
;; and resuming (by its session's id) are agent-shell's. It's told, in its
;; system prompt, the job it does, where, what it never does and how it
;; ends a step; then its profile's instructions, their variables filled in.
;; Its bd commands run as ISSUE/JOB (BEADS_ACTOR): Beads' history says which
;; job did what.
;;
;; Its Agent UI canvas is its session's, as any session's, but opens no pane
;; of its own: it's kept, and shown in its ticket's pane (doom-38o.9).
;;
;; A project whose agent-workspace crew runs has no agents of the pool: its
;; loops would take the same issues. Read from that module's lock and
;; agents, never requiring it.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'map)

(declare-function agent-shell--start "agent-shell")
(declare-function agent-shell-subscribe-to "agent-shell")
(declare-function agent-shell-insert "agent-shell")
(declare-function agent-shell--prompt-queue-confirm-kill-buffer "agent-shell-prompt-queue")
(declare-function shell-maker--process "shell-maker")
(declare-function agent-workspace-agents "agent-workspace/core")
(declare-function agent-workspace-agent-state "agent-workspace/core")
(defvar agent-shell--state)
(defvar agent-shell-buffer-name-format)
(defvar shell-maker-prompt-before-killing-buffer)
(defvar agent-ui-display-function)
(defvar agent-ui--session-buffer)
(defvar agent-workflow-pool)
(defvar agent-workflow-mode)
(defvar agent-workflow-kind)
(defvar agent-workflow-kinds)
(defvar agent-workflow-exit-timeout)

;; ====== AN AGENT ======

(cl-defstruct (agent-workflow-agent (:constructor agent-workflow-agent--make)
                                    (:copier nil))
  project                ; its project's main checkout
  issue                  ; the issue whose run it works for: "doom-a1b"
  job                    ; its job: "review"
  profile                ; its step's profile, a name
  worktree               ; the issue's worktree, where it works
  branch                 ; the issue's branch
  commit                 ; a reading job's: the commit its snapshot is at
  buffer                 ; its agent-shell session
  session-id             ; its session's id, once known: to resume it
  resumed                ; the session it was asked to resume, if any
  values                 ; its variables' values: an alist
  outcomes               ; the outcomes it may give, besides done
  stopping)              ; non-nil while it's stopped by us

(defvar agent-workflow--agents nil
  "Every agent of the pool, in every project, as they started.")

(defvar agent-workflow--starting nil
  "The agent whose session starts, while its config is made (see
`agent-workflow-agent-context').")

(defvar-local agent-workflow--agent nil
  "In an agent's session: its agent.")

(defvar agent-workflow-agent-event-functions nil
  "Called with an agent and an event of its session (agent-shell's: an
alist, its :event turn-complete, clean-up...), as they come.")

(defun agent-workflow-agents (&optional project)
  "The pool's agents (PROJECT: only its), as they started."
  (seq-filter (lambda (agent)
                (or (null project) (equal (agent-workflow-agent-project agent) project)))
              agent-workflow--agents))

(defun agent-workflow-agent-name (agent)
  "How AGENT is known: \"doom-a1b · review\"."
  (format "%s · %s" (agent-workflow-agent-issue agent) (agent-workflow-agent-job agent)))

(defun agent-workflow-buffer-agent (&optional buffer)
  "The agent whose session BUFFER (default: the current one) is, or nil."
  (let ((buffer (or buffer (current-buffer))))
    (and (buffer-live-p buffer) (buffer-local-value 'agent-workflow--agent buffer))))

(defun agent-workflow-pool-used ()
  "How many of the pool's agents work: those whose session lives."
  (seq-count (lambda (agent) (buffer-live-p (agent-workflow-agent-buffer agent))) agent-workflow--agents))

;; ====== A CREW THERE ======

(defun agent-workflow-crew-running-p (project)
  "Non-nil if PROJECT's agent-workspace crew runs: its agents in this Emacs,
or its lock held by an Emacs alive (this one or another)."
  (or (and (fboundp 'agent-workspace-agents)
           (seq-some (lambda (agent) (not (memq (agent-workspace-agent-state agent) '(asleep home))))
                     (ignore-errors (agent-workspace-agents project))))
      (when-let* ((file (expand-file-name ".agent-shell/agent-workspace/crew.lock" project))
                  ((file-readable-p file))
                  (pid (ignore-errors
                         (with-temp-buffer (insert-file-contents file)
                                           (string-to-number (car (split-string (buffer-string)))))))
                  ((> pid 0))
                  (attributes (process-attributes pid)))
        (and (not (member (alist-get 'state attributes) '("Z" "X")))
             (string-match-p "emacs" (downcase (or (alist-get 'comm attributes) "")))))))

;; ====== ITS PROFILE, FILLED IN ======

(defun agent-workflow--agent-values (agent)
  "AGENT's variables' values: where it works, then those it was given."
  (let ((project (directory-file-name (agent-workflow-agent-project agent))))
    (append (list (cons "issue" (agent-workflow-agent-issue agent))
                  (cons "branch" (agent-workflow-agent-branch agent))
                  (cons "worktree" (directory-file-name (agent-workflow-agent-worktree agent)))
                  (cons "main" project)
                  (cons "main-branch" (let ((default-directory (file-name-as-directory project)))
                                        (car (agent-workflow--git-lines "branch" "--show-current"))))
                  (cons "project" (file-name-nondirectory project)))
            (agent-workflow-agent-values agent))))

(defun agent-workflow-profile-filled (agent)
  "AGENT's profile (a copy), its tools and deny with their variables
filled in shell-quoted (a rule names an exact command: Bash(git -C {main}
commit:*)), its instructions with them as they are."
  (let* ((profile (copy-sequence (alist-get (agent-workflow-agent-profile agent)
                                            (agent-workflow-profiles (agent-workflow-agent-project agent))
                                            nil nil #'equal)))
         (values (agent-workflow--agent-values agent))
         (quoted (mapcar (lambda (value) (cons (car value) (and (cdr value) (shell-quote-argument (cdr value)))))
                         values)))
    (dolist (key '(:tools :deny))
      (when (plist-get profile key)
        (setq profile (plist-put profile key (mapcar (lambda (rule) (agent-workflow-fill rule quoted))
                                                     (plist-get profile key))))))
    (when (plist-get profile :instructions)
      (setq profile (plist-put profile :instructions (agent-workflow-fill (plist-get profile :instructions) values))))
    profile))

;; ====== WHAT IT'S TOLD ======

(defun agent-workflow-agent-context ()
  "What the agent whose session starts is told, after what every session
is: the job it does and where, how it ends a step, what it never does;
then its profile's instructions. nil for any other session. One of
`+my/agent-shell-claude-context-functions'."
  (when-let* ((agent agent-workflow--starting))
    (let* ((profile (agent-workflow-profile-filled agent))
           (instructions (plist-get profile :instructions))
           (outcomes (cons "done" (agent-workflow-agent-outcomes agent))))
      (concat
       (format "You are an agent of the user's agent workflow, in Emacs: you do the job %s of the \
run on the issue %s, in %s, and nothing else. You have no name: you're known as \"%s\".

%s Never switch, make or rename branches, push, or change, relabel or close the issue: the \
workflow does that. Your bd commands run as %s (BEADS_ACTOR).

When your job is done, end it with %s done %s \"notes\": the outcome (%s), and what the \
next jobs and the user need to know, in a few lines. Then end your turn. Without it, the run \
waits for the user."
               (agent-workflow-agent-job agent) (agent-workflow-agent-issue agent)
               (file-name-nondirectory (directory-file-name (agent-workflow-agent-project agent)))
               (agent-workflow-agent-name agent)
               (if-let* ((commit (agent-workflow-agent-commit agent)))
                   (format "You work in a snapshot of the issue's branch %s at %s, a git worktree of its own, \
%s: read it, run what you need there, but change nothing and commit nothing: your job only reads."
                           (agent-workflow-agent-branch agent) (substring commit 0 (min 12 (length commit)))
                           (directory-file-name (agent-workflow-agent-worktree agent)))
                 (format "You work in the issue's git worktree, %s, on its branch %s: make your changes and \
commits there, never in the project's main checkout (%s), which is the user's. Commit on that branch."
                         (directory-file-name (agent-workflow-agent-worktree agent))
                         (agent-workflow-agent-branch agent)
                         (directory-file-name (agent-workflow-agent-project agent))))
               (concat (agent-workflow-agent-issue agent) "/" (agent-workflow-agent-job agent))
               agent-workflow-command
               (if (cdr outcomes) "OUTCOME" "done")
               (if (cdr outcomes)
                   (concat "one of " (string-join outcomes ", "))
                 "done"))
       (when (and instructions (not (string-empty-p (string-trim instructions))))
         (concat "\n\n" (string-trim instructions)))))))

;; ====== STARTING ONE ======

(defun agent-workflow--environment (agent)
  "AGENT's environment variables (\"NAME=VALUE\"): who it is for Beads
\(BEADS_ACTOR: ISSUE/JOB) and for us (AGENT_WORKFLOW_ISSUE, _JOB); the
project's issues (BEADS_DIR: it works in a worktree)."
  (let ((beads (expand-file-name ".beads" (agent-workflow-agent-project agent))))
    (append (list (concat "BEADS_ACTOR=" (agent-workflow-agent-issue agent) "/" (agent-workflow-agent-job agent))
                  (concat "AGENT_WORKFLOW_ISSUE=" (agent-workflow-agent-issue agent))
                  (concat "AGENT_WORKFLOW_JOB=" (agent-workflow-agent-job agent)))
            (when (file-directory-p beads)
              (list (concat "BEADS_DIR=" beads))))))

(defun agent-workflow--claude-options (meta profile)
  "META, Claude Code's session meta, with PROFILE's tools in Claude Code's
options (allowedTools, disallowedTools); ending its step
\(`agent-workflow-command' done) always allowed."
  (let* ((claude (alist-get 'claudeCode meta))
         (options (alist-get 'options claude)))
    (setf (alist-get 'allowedTools options)
          (vconcat (plist-get profile :tools)
                   (list (format "Bash(%s done:*)" agent-workflow-command))))
    (when-let* ((deny (plist-get profile :deny)))
      (setf (alist-get 'disallowedTools options) (vconcat deny)))
    (when options
      (setf (alist-get 'options claude) options
            (alist-get 'claudeCode meta) claude))
    meta))

(defun agent-workflow--config (agent)
  "agent-shell's config for AGENT's session (see the top of this file)."
  (let* ((kind (or (alist-get agent-workflow-kind agent-workflow-kinds)
                   (error "No such kind of agent: %s" agent-workflow-kind)))
         (profile (agent-workflow-profile-filled agent))
         (model (plist-get profile :model))
         (mode (or (plist-get profile :mode) agent-workflow-mode))
         (config (copy-tree (let ((agent-workflow--starting agent)) (funcall (plist-get kind :config)))))
         (maker (alist-get :client-maker config))
         (environment (agent-workflow--environment agent)))
    (setf (alist-get :buffer-name config) (agent-workflow-agent-name agent))
    (when model
      (setf (alist-get :default-model-id config) (lambda () model)))
    (when mode
      (setf (alist-get :default-session-mode-id config) (lambda () mode)))
    (when (plist-get kind :claude-code)
      (setf (alist-get :session-meta config)
            (agent-workflow--claude-options (alist-get :session-meta config) profile)))
    (when maker
      (setf (alist-get :client-maker config)
            (lambda (buffer)
              (let ((client (funcall maker buffer)))
                (when client
                  (setf (alist-get :environment-variables client)
                        (append environment (alist-get :environment-variables client))))
                client))))
    config))

(cl-defun agent-workflow-start-agent (&key project issue job profile type title values outcomes prompt
                                           snapshot resume)
  "Start an agent of the pool for the JOB of ISSUE's run in PROJECT, with
the PROFILE (a name): its session, fresh, in ISSUE's worktree (made on its
branch from TYPE and TITLE if it isn't there). VALUES: its variables'
values (an alist); OUTCOMES: those it may give besides done; PROMPT: its
first message, its variables filled in, sent once it's ready. SNAPSHOT:
\(DIR BRANCH COMMIT), a reading job's snapshot it works in instead of the
issue's worktree (`agent-workflow-snapshot'). RESUME: a session's id, its
session resumed (agent-shell's; a fresh one if its agent can't). Return the
agent. A user error, nothing started, if PROJECT's crew runs, the pool is
full or PROFILE isn't one."
  (require 'agent-shell)
  (let ((project (file-name-as-directory project)))
    (when (agent-workflow-crew-running-p project)
      (user-error "The agent-workspace crew of %s runs: its agents would take the same issues"
                  (file-name-nondirectory (directory-file-name project))))
    (when (>= (agent-workflow-pool-used) agent-workflow-pool)
      (user-error "The pool is full: %d of %d agents work (agent-workflow-pool)"
                  (agent-workflow-pool-used) agent-workflow-pool))
    (unless (alist-get profile (agent-workflow-profiles project) nil nil #'equal)
      (user-error "No profile %s: %s" profile
                  (agent-workflow--listed (mapcar #'car (agent-workflow-profiles project)))))
    (pcase-let* ((`(,dir . ,branch) (if snapshot
                                        (cons (nth 0 snapshot) (nth 1 snapshot))
                                      (agent-workflow-worktree project issue :type type :title title)))
                 (agent (agent-workflow-agent--make :project project :issue issue :job job :profile profile
                                                    :worktree dir :branch branch :commit (nth 2 snapshot)
                                                    :values values :outcomes outcomes :resumed resume))
                 (made nil))
      (condition-case err
          (let* ((config (agent-workflow--config agent))
                 (agent-shell-buffer-name-format (lambda (name _project) name))
                 (buffer (setq made (agent-shell--start :config config :no-focus t :new-session t
                                                        :session-strategy 'new :cwd dir :session-id resume))))
            (with-current-buffer buffer
              (setq agent-workflow--agent agent)
              ;; Stopping it asks nothing: not agent-shell's "N prompts
              ;; queued. Kill anyway?", nor shell-maker's to save its
              ;; transcript, nor Emacs's about its process when quitting.
              (remove-hook 'kill-buffer-query-functions #'agent-shell--prompt-queue-confirm-kill-buffer t)
              (setq-local shell-maker-prompt-before-killing-buffer nil)
              (when-let* ((process (ignore-errors (shell-maker--process))))
                (set-process-query-on-exit-flag process nil)))
            (setf (agent-workflow-agent-buffer agent) buffer)
            (push agent agent-workflow--agents)
            (agent-shell-subscribe-to
             :shell-buffer buffer
             :on-event (lambda (event)
                         ;; An old session's events, once it's been replaced,
                         ;; aren't its; nor those of one we stop.
                         (when (and (eq (agent-workflow-agent-buffer agent) buffer)
                                    (not (agent-workflow-agent-stopping agent)))
                           (run-hook-with-args 'agent-workflow-agent-event-functions agent event))))
            (when prompt
              (agent-shell-insert :text (agent-workflow-fill prompt (agent-workflow--agent-values agent))
                                  :submit t :no-focus t :shell-buffer buffer))
            agent)
        (error
         (when (buffer-live-p made)
           (let ((kill-buffer-query-functions nil)) (kill-buffer made)))
         (signal (car err) (cdr err)))))))

(defun agent-workflow-agent-session (agent)
  "AGENT's session's id, once agent-shell knows it (kept: to resume it)."
  (or (agent-workflow-agent-session-id agent)
      (when-let* ((buffer (agent-workflow-agent-buffer agent))
                  ((buffer-live-p buffer))
                  (id (with-current-buffer buffer
                        (and (local-variable-p 'agent-shell--state)
                             (map-elt (map-elt agent-shell--state :session) :id)))))
        (setf (agent-workflow-agent-session-id agent) id))))

;; ====== STOPPING ONE ======

(defun agent-workflow--session-process (buffer)
  "The agent's process of the session BUFFER (its ACP client's), or nil."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when-let* ((client (and (local-variable-p 'agent-shell--state)
                               (map-elt agent-shell--state :client))))
        (map-elt client :process)))))

(defun agent-workflow--process-tree (pid)
  "PID and its descendants, each (PID . START)."
  (let* ((table (delq nil (mapcar (lambda (pid)
                                    (when-let* ((attributes (process-attributes pid)))
                                      (list pid (alist-get 'ppid attributes) (alist-get 'start attributes))))
                                  (list-system-processes))))
         (tree (list pid))
         (more t))
    (while more
      (setq more nil)
      (dolist (entry table)
        (when (and (memq (nth 1 entry) tree) (not (memq (car entry) tree)))
          (push (car entry) tree)
          (setq more t))))
    (delq nil (mapcar (lambda (pid) (when-let* ((entry (assq pid table))) (cons pid (nth 2 entry)))) tree))))

(defun agent-workflow--reap (processes)
  "Kill PROCESSES, each (PID . START), still running (the same ones: a pid
used again starts later)."
  (dolist (process processes)
    (when-let* ((attributes (process-attributes (car process)))
                (start (alist-get 'start attributes)))
      (when (and (cdr process) (< (abs (float-time (time-subtract start (cdr process)))) 1.0)
                 (not (member (alist-get 'state attributes) '("Z" "X"))))
        (ignore-errors (signal-process (car process) 'SIGKILL))))))

(defun agent-workflow-stop-agent (agent)
  "Stop AGENT's session without asking, its processes killed
`agent-workflow-exit-timeout' seconds later if they're still running; it
leaves the pool. Its session's id is kept, to resume it."
  (let ((buffer (agent-workflow-agent-buffer agent))
        processes)
    (agent-workflow-agent-session agent)
    (setf (agent-workflow-agent-stopping agent) t)
    (unwind-protect
        (when (buffer-live-p buffer)
          (when-let* ((process (agent-workflow--session-process buffer))
                      (pid (and (process-live-p process) (process-id process))))
            (setq processes (agent-workflow--process-tree pid)))
          (let ((kill-buffer-query-functions nil))
            (kill-buffer buffer))
          (when processes
            (run-at-time agent-workflow-exit-timeout nil #'agent-workflow--reap processes)))
      (setf (agent-workflow-agent-stopping agent) nil
            (agent-workflow-agent-buffer agent) nil)
      (setq agent-workflow--agents (delq agent agent-workflow--agents)))
    processes))

(defun agent-workflow--quit-h ()
  "Emacs quits: every agent of the pool stopped, its processes given a
second to exit, then killed. In `kill-emacs-hook'."
  (let ((processes (apply #'append (mapcar #'agent-workflow-stop-agent agent-workflow--agents)))
        (deadline (+ (float-time) 1.0)))
    (while (and processes (< (float-time) deadline)
                (seq-some (lambda (process) (process-attributes (car process))) processes))
      (sleep-for 0.05))
    (agent-workflow--reap processes)))

;; ====== ITS CANVAS ======

(defvar agent-workflow--canvas-fallback nil
  "Agent UI's display function before the pool's: for canvases not an
agent's of the pool.")

(defun agent-workflow--canvas-agent (canvas)
  "The pool's agent whose session CANVAS is, or nil."
  (when-let* ((session (and (buffer-local-boundp 'agent-ui--session-buffer canvas)
                            (buffer-local-value 'agent-ui--session-buffer canvas))))
    (agent-workflow-buffer-agent session)))

(defun agent-workflow--display-canvas (canvas)
  "Agent UI's display function: an agent's of the pool CANVAS opens no pane
\(kept, shown in its ticket's pane); any other as before."
  (unless (agent-workflow--canvas-agent canvas)
    (funcall (or agent-workflow--canvas-fallback #'ignore) canvas)))

(defun agent-workflow--take-canvases ()
  "The pool's agents' canvases kept out of panes (see above)."
  (when (and (boundp 'agent-ui-display-function)
             (not (eq agent-ui-display-function #'agent-workflow--display-canvas)))
    (setq agent-workflow--canvas-fallback agent-ui-display-function
          agent-ui-display-function #'agent-workflow--display-canvas)))
