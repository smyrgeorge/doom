;;; $DOOMDIR/config/agent-ui/workspaces.el -*- lexical-binding: t; -*-
;; A session's canvas in its session's workspace (persp-mode's: Doom's
;; workspaces), not the one you're in. Loaded from config/agent-ui.el, after
;; agent.el. No Doom here (see docs/agent-ui.md): persp-mode's own functions,
;; when it's on.
;;
;; A canvas's pane opens when it shows something and isn't in a window
;; (`agent-ui-display-function'). A workspace not shown has no live windows,
;; so a session working in one opened its canvas in the workspace you were
;; in, at each new element. Now, while its session's workspace isn't the
;; current one, the canvas joins that workspace and waits: its pane opens
;; when you switch there. A canvas without a session, or a session in no
;; workspace, or persp-mode off: shown where you are, as before.

(require 'cl-lib)

;; ====== VARIABLES ======

(defvar-local agent-ui--waiting nil
  "In a canvas: its workspace (a perspective), where it waits to be shown.")

;; ====== THE SESSION'S WORKSPACE ======

(defun agent-ui--session-workspace (canvas)
  "The workspace CANVAS's session is in, if that isn't the current one (the
selected frame's): a perspective; else nil, CANVAS to be shown here."
  (when-let* (((bound-and-true-p persp-mode))
              ((fboundp 'persp--buffer-in-persps))
              (session (buffer-local-value 'agent-ui--session-buffer canvas))
              ((buffer-live-p session))
              (workspaces (persp--buffer-in-persps session)))
    (unless (memq (get-current-persp) workspaces)
      (car workspaces))))

(defun agent-ui-workspace-display-canvas (buffer)
  "Show BUFFER, a canvas, as `agent-ui-display-canvas' does if its session is
in the current workspace; else BUFFER joins its session's, to be shown when
it's switched to (see above)."
  (if-let* ((workspace (agent-ui--session-workspace buffer)))
      (progn
        (persp-add-buffer buffer workspace nil nil)
        (with-current-buffer buffer
          (setq agent-ui--waiting workspace)))
    (with-current-buffer buffer
      (setq agent-ui--waiting nil))
    (agent-ui-display-canvas buffer)))

(setq agent-ui-display-function #'agent-ui-workspace-display-canvas)

(defun agent-ui--workspace-shown-h (frame-or-window)
  "A workspace now current (persp-mode's `persp-activated-functions'): the
canvases waiting for it, shown if they still aren't in a window."
  (when (eq frame-or-window 'frame)
    (let ((current (get-current-persp)))
      (dolist (canvas (agent-ui-canvases))
        (with-current-buffer canvas
          (when (and agent-ui--waiting (eq agent-ui--waiting current))
            (setq agent-ui--waiting nil)
            (unless (agent-ui--window)
              (agent-ui-display-canvas canvas))))))))

(add-hook 'persp-activated-functions #'agent-ui--workspace-shown-h)
