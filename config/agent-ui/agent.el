;;; $DOOMDIR/config/agent-ui/agent.el -*- lexical-binding: t; -*-
;; Agent UI and agent-shell's sessions: each session's agent finds its own
;; canvas, which closes with it. Loaded from config/agent-ui.el, after
;; request.el. No Doom here (see docs/agent-ui.md).
;;
;; - agent-shell starts each session's agent with AGENT_UI_SESSION in its
;;   environment, the session's name (its buffer's, when it started); the
;;   agent's shell inherits it, so cmd/agent-ui says whose request it is.
;; - Without it (an agent started otherwise, a session older than this), the
;;   session working in the request's directory: the deepest one, of those
;;   the most recently used.
;; - A canvas is named after its session, its others after it ("SESSION /
;;   tests"); killing the session kills them.

(require 'cl-lib)
(require 'subr-x)

;; ====== VARIABLES ======

(defvar-local agent-ui-session nil
  "In an agent-shell buffer: its session's name for Agent UI (its canvas's).")

;; Kept if the buffer's major mode is set after its agent was started.
(put 'agent-ui-session 'permanent-local t)

(defvar-local agent-ui--session-buffer nil
  "In a canvas: its session's agent-shell buffer, if it has one.")

(defvar-local agent-ui--canvas-part nil
  "In a session's other canvas: its own name (\"tests\"); nil in the
session's canvas.")

;; ====== THE SESSION'S ENVIRONMENT ======

(defun agent-ui--session-name (buffer)
  "BUFFER's session name (`agent-ui-session'): given once, its name then."
  (with-current-buffer buffer
    (or agent-ui-session
        (setq agent-ui-session (buffer-name)))))

(defun agent-ui--client-environment-a (args)
  "`agent-shell--make-acp-client''s ARGS, AGENT_UI_SESSION added to its
environment when it has a context buffer (the session's)."
  (let ((buffer (plist-get args :context-buffer)))
    (if (buffer-live-p buffer)
        (plist-put (copy-sequence args) :environment-variables
                   (cons (concat "AGENT_UI_SESSION=" (agent-ui--session-name buffer))
                         (plist-get args :environment-variables)))
      args)))

(advice-add 'agent-shell--make-acp-client :filter-args
            (lambda (args) (agent-ui--client-environment-a args))
            '((name . agent-ui-session-environment)))

;; ====== FINDING THE SESSION ======

(defun agent-ui--sessions ()
  "agent-shell's session buffers, the most recently used first."
  (when (fboundp 'agent-shell-buffers)
    (seq-filter #'buffer-live-p (agent-shell-buffers))))

(defun agent-ui--session-cwd (buffer)
  (file-name-as-directory
   (expand-file-name (with-current-buffer buffer
                       (if (fboundp 'agent-shell-cwd) (agent-shell-cwd) default-directory)))))

(defun agent-ui--session-buffer (session cwd)
  "The session buffer named SESSION (its `agent-ui-session'); else the one
working in CWD or above it, the deepest, then the most recently used."
  (let ((sessions (agent-ui--sessions)))
    (or (and session
             (seq-find (lambda (b) (equal (buffer-local-value 'agent-ui-session b) session))
                       sessions))
        (and cwd
             (let* ((dir (file-name-as-directory (expand-file-name cwd)))
                    (matches (seq-filter (lambda (b)
                                           (string-prefix-p (agent-ui--session-cwd b) dir))
                                         sessions)))
               ;; Stable: of the deepest, the most recent first.
               (car (cl-stable-sort matches #'>
                                    :key (lambda (b) (length (agent-ui--session-cwd b))))))))))

(defun agent-ui-session-canvas (session cwd)
  "The canvas for an agent's request (`agent-ui-canvas-function'), its
name: its session's (SESSION, else the one in CWD), named after it; else
SESSION, else the default. Made when an element is first shown in it
\(`agent-ui--link-session' then ties it to its session)."
  (let ((buffer (agent-ui--session-buffer session cwd)))
    (if buffer
        (agent-ui--session-name buffer)
      (agent-ui-request-canvas session cwd))))

(setq agent-ui-canvas-function #'agent-ui-session-canvas)

(defun agent-ui--canvas-session (name)
  "The session a canvas named NAME is of: (BUFFER . PART), PART its other
canvas's name (nil for the session's canvas); nil if none."
  (let ((sessions (agent-ui--sessions)))
    (cl-flet ((named (session)
                (seq-find (lambda (b) (equal (buffer-local-value 'agent-ui-session b) session))
                          sessions)))
      (if-let* ((buffer (named name)))
          (cons buffer nil)
        ;; "SESSION / PART": the session's other canvas.
        (let ((at (string-search agent-ui-canvas-separator name)))
          (while (and at (not (named (substring name 0 at))))
            (setq at (string-search agent-ui-canvas-separator name (1+ at))))
          (when at
            (cons (named (substring name 0 at))
                  (substring name (+ at (length agent-ui-canvas-separator))))))))))

(defun agent-ui--link-session ()
  "In a new canvas: tied to the session it's named after, if there's one
\(killed with it)."
  (when-let* ((name agent-ui--canvas-name)
              (found (agent-ui--canvas-session name)))
    (setq agent-ui--session-buffer (car found)
          agent-ui--canvas-part (cdr found))
    (with-current-buffer (car found)
      (add-hook 'kill-buffer-hook #'agent-ui--kill-canvas nil t))))

(add-hook 'agent-ui-canvas-hook #'agent-ui--link-session)

(defun agent-ui-session-canvases (session)
  "SESSION's (an agent-shell buffer) canvases: its own and its others."
  (seq-filter (lambda (b) (eq (buffer-local-value 'agent-ui--session-buffer b) session))
              (agent-ui-canvases)))

(defun agent-ui--kill-canvas ()
  "The session's buffer is killed: its canvases too."
  (mapc #'kill-buffer (agent-ui-session-canvases (current-buffer))))

;; ====== WHAT THE AGENT IS TOLD ======

(defvar agent-ui-agent-mcp nil
  "Non-nil when agents get Agent UI as MCP tools too (cmd/agent-ui-mcp.el):
their system prompt says so.")

(defcustom agent-ui-skill
  (expand-file-name "../../skills/agent-ui/SKILL.md"
                    (file-name-directory (or load-file-name buffer-file-name)))
  "The agent-ui skill: the guide the agent reads before using the canvas."
  :type 'file :group 'agent-ui)

(defun agent-ui--home-relative (file)
  "FILE as ~/..., if it's in the home folder."
  (abbreviate-file-name (expand-file-name file)))

(defun agent-ui-agent-context ()
  "What an agent starting in agent-shell is told of its canvas (for its system
prompt); nil while Emacs runs no server (the command couldn't reach it)."
  (when (and (fboundp 'server-running-p) (server-running-p))
    (let ((command (agent-ui--home-relative agent-ui-command))
          (skill (agent-ui--home-relative agent-ui-skill)))
      (format "Agent UI: beside this session, Emacs has a canvas (a pane of its \
own, opened without taking the user's focus when you first show something) \
that keeps things in view while the conversation scrolls: progress bars, \
checklists of steps, tables, charts, text, Markdown, each updated in place. Use it for \
what changes over time or deserves watching (a long build or test run, a \
multi-step task's progress, results arriving one by one), not for what a reply \
says once. Issues and plans go there too, always, without being asked: a project's \
or an epic's issues (bd ready, an epic's children) as the issues board, which \
follows your bd commands; a search's results as a table; a plan, or the ticket \
you're working on, as steps (its acceptance criteria), ticked as you go. From your shell: %s show \
'{\"id\":\"build\",\"type\":\"progress\",\"title\":\"Build\",\"max\":12}', then \
%s update build '{\"value\":5}'; append adds a table's rows or a \
checklist's steps; remove ID; clear; --canvas NAME on any of them uses \
another canvas of this session, in a pane of its own. It replies with JSON. Before using it \
the first time, read %s (its types, properties and examples; when none \
fits, how to make one). Remove what stops helping, and never leave something \
shown running once it stopped. When Agent UI itself misbehaves (a wrong drawing, \
an error, a property it lacks), ask the user, then file it: %s bug \
'{\"title\":...,\"description\":...,\"element\":\"ID\",\"repro\":{an element \
showing it}}' goes into Agent UI's own issues, never this project's (not filed: \
its reply's report, to show the user); then carry on with a workaround.%s"
              command command skill command
              (if agent-ui-agent-mcp
                  " The same operations are MCP tools too (the agent-ui server: show, \
update, append, remove, list, types, render, snapshot, batch, define, bug), with \
their schemas: use whichever you like."
                "")))))

;; ====== ACTIONS ======

;; While the agent works, its prompt may take no text (agent-shell said "Busy,
;; try later"): a button sending its prompt queues it, sent when the agent's
;; done (agent-shell's queue); one putting it into the prompt offers it to
;; queue, to read and change first, as agent-shell's own commands do then.
(defun agent-ui--session-busy-p (session)
  "Whether SESSION's prompt takes no text now (its agent working, no prompt
kept live meanwhile). Not known (not a shell yet): not busy, agent-shell
then has its say."
  (ignore-errors
    (with-current-buffer session
      (if (fboundp 'agent-shell--can-insert-into-prompt-p)
          (not (agent-shell--can-insert-into-prompt-p :shell-buffer session))
        (and (fboundp 'shell-maker-busy) (shell-maker-busy))))))

(defun agent-ui--act (prompt submit)
  "An element's action pressed, in its canvas: PROMPT into the prompt of the
canvas's session (sent if SUBMIT); while its agent works, queued (see above)."
  (let ((session (and (derived-mode-p 'agent-ui-canvas-mode) agent-ui--session-buffer)))
    (unless (buffer-live-p session)
      (user-error "This canvas has no agent-shell session"))
    (unless (fboundp 'agent-shell-insert)
      (user-error "agent-shell isn't loaded"))
    (cond
     ((not (and (fboundp 'agent-shell-prompt-queue) (agent-ui--session-busy-p session)))
      (agent-shell-insert :text prompt :submit submit :shell-buffer session))
     (submit
      (with-current-buffer session
        (agent-shell-prompt-queue prompt))
      (message "Queued: sent once the agent's done"))
     (t
      (let ((prompt (with-current-buffer session
                      (if (fboundp 'agent-shell--prompt-queue-read)
                          (agent-shell--prompt-queue-read :initial prompt)
                        (read-string "The agent's working; queue: " prompt)))))
        (with-current-buffer session
          (agent-shell-prompt-queue prompt)))))))

(declare-function agent-shell-insert "agent-shell")
(declare-function agent-shell-prompt-queue "agent-shell-prompt-queue")
(declare-function agent-shell--prompt-queue-read "agent-shell-prompt-queue")
(declare-function agent-shell--can-insert-into-prompt-p "agent-shell-prompt")
(declare-function shell-maker-busy "shell-maker")
(setq agent-ui-action-function #'agent-ui--act)
