;;; $DOOMDIR/config/agent-shell/here.el -*- lexical-binding: t; -*-
;; Claude Code in the window you're in (SPC o C; see CLAUDE CODE HERE in
;; config/agent-shell.el). Loaded from config/agent-shell.el.

;; agent-shell asks which session (a new one, one to resume) once Claude Code
;; lists them, and shows the session after: later than the command. It keeps
;; the command's `display-buffer-overriding-action' for that (the prefixes
;; C-x 4 4, C-x 4 1 work so): the action below, put first in it for the
;; command, shows the session then, in the window that was selected; any
;; other buffer goes on as the override had it.

(defun +my/agent-shell-here-display (buffer alist)
  "A `display-buffer' action: BUFFER, a session of agent-shell's, in the
selected window (what it showed kept, its tab under it). Nil for any other
buffer, or when the selected window can't show it (the minibuffer's, one
dedicated to its buffer): the next action then."
  (when (with-current-buffer buffer (derived-mode-p 'agent-shell-mode))
    (display-buffer-same-window buffer alist)))

(defun +my/agent-shell--here-action (action)
  "ACTION, a `display-buffer' action (FUNCTIONS . ALIST), with
`+my/agent-shell-here-display' tried first."
  (let ((functions (car action)))
    (cons (cons #'+my/agent-shell-here-display
                (if (functionp functions) (list functions) functions))
          (cdr action))))

(defun +my/agent-shell-claude-here ()
  "Start Claude Code as SPC o c does (agent-shell asking which session: a
new one, or one to resume), the session shown in the selected window instead
of where agent-shell shows it (SPC o C)."
  (interactive)
  (let ((display-buffer-overriding-action
         (+my/agent-shell--here-action display-buffer-overriding-action)))
    (agent-shell-anthropic-start-claude-code)))
