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
;; - A canvas is named after its session; killing the session kills it.

(require 'cl-lib)
(require 'subr-x)

;; ====== VARIABLES ======

(defvar-local agent-ui-session nil
  "In an agent-shell buffer: its session's name for Agent UI (its canvas's).")

;; Kept if the buffer's major mode is set after its agent was started.
(put 'agent-ui-session 'permanent-local t)

(defvar-local agent-ui--session-buffer nil
  "In a canvas: its session's agent-shell buffer, if it has one.")

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

(defun agent-ui--link-session ()
  "In a new canvas: tied to the session it's named after, if there's one
\(killed with it)."
  (when-let* ((name agent-ui--canvas-name)
              (buffer (seq-find (lambda (b) (equal (buffer-local-value 'agent-ui-session b) name))
                                (agent-ui--sessions))))
    (setq agent-ui--session-buffer buffer)
    (with-current-buffer buffer
      (add-hook 'kill-buffer-hook #'agent-ui--kill-canvas nil t))))

(add-hook 'agent-ui-canvas-hook #'agent-ui--link-session)

(defun agent-ui--kill-canvas ()
  "The session's buffer is killed: its canvas too."
  (when-let* ((name agent-ui-session)
              (canvas (get-buffer (agent-ui-canvas-buffer-name name))))
    (when (eq (buffer-local-value 'agent-ui--session-buffer canvas) (current-buffer))
      (kill-buffer canvas))))

;; ====== WHAT THE AGENT IS TOLD ======

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
says once. From your shell: %s show \
'{\"id\":\"build\",\"type\":\"progress\",\"title\":\"Build\",\"max\":12}', then \
%s update build '{\"value\":5}'; append adds a table's rows or a \
checklist's steps; remove ID; clear. It replies with JSON. Before using it \
the first time, read %s (its types, properties and examples; when none \
fits, how to make one). Remove what stops helping, and never leave something \
shown running once it stopped."
              command command skill))))
