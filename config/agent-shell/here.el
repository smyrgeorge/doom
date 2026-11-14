;;; $DOOMDIR/config/agent-shell/here.el -*- lexical-binding: t; -*-
;; Claude Code in the window you're in (SPC o C; see CLAUDE CODE HERE in
;; config/agent-shell.el). Loaded from config/agent-shell.el.

;; agent-shell asks which session (a new one, one to resume) once Claude Code
;; lists them, and shows the session after: later than the command. It keeps
;; the command's `display-buffer-overriding-action' for that (the prefixes
;; C-x 4 4, C-x 4 1 work so): the action below, put first in it for the
;; command, shows the session then, in the window that was selected when the
;; command ran (taken along in the action's alist: you may have moved since);
;; that window gone, in the selected one. Any other buffer goes on as the
;; override had it.

(defun +my/agent-shell-here-display (buffer alist)
  "A `display-buffer' action: BUFFER, a session of agent-shell's, in the
window SPC o C was pressed in (ALIST's `+my/agent-shell-here-window'), what
it showed kept, its tab under it; that window gone (or none), the selected
one. Nil for any other buffer, or when that window can't show it (the
minibuffer's, one dedicated to its buffer): the next action then."
  (when (with-current-buffer buffer (derived-mode-p 'agent-shell-mode))
    (let ((window (alist-get '+my/agent-shell-here-window alist)))
      (if (window-live-p window)
          (unless (or (window-dedicated-p window) (window-minibuffer-p window))
            (window--display-buffer buffer window 'reuse alist))
        (display-buffer-same-window buffer alist)))))

(defun +my/agent-shell--here-action (action window)
  "ACTION, a `display-buffer' action (FUNCTIONS . ALIST), with
`+my/agent-shell-here-display' tried first, for WINDOW."
  (let ((functions (car action)))
    (cons (cons #'+my/agent-shell-here-display
                (if (functionp functions) (list functions) functions))
          (cons (cons '+my/agent-shell-here-window window) (cdr action)))))

(defun +my/agent-shell-claude-here ()
  "Start Claude Code as SPC o c does (agent-shell asking which session: a
new one, or one to resume), the session shown in the window you're in
instead of where agent-shell shows it (SPC o C)."
  (interactive)
  (let ((display-buffer-overriding-action
         (+my/agent-shell--here-action display-buffer-overriding-action (selected-window))))
    (agent-shell-anthropic-start-claude-code)))
