;;; $DOOMDIR/config/agent-shell/prompt.el -*- lexical-binding: t; -*-
;; Typing in Claude Code's prompt. Loaded from config/agent-shell.el.

;; NO SNIPPETS IN THE PROMPT
;; Typing stalled in a long session: each pause (corfu's completion, 0.4 s)
;; asked yasnippet for a snippet's key before point (`yasnippet-capf', which
;; Doom adds where yasnippet is on), a search that took a third of the time in
;; a session of 1.2 MB (thing-at-point-looking-at). Snippets have no place in
;; a prompt: yasnippet stays off in Claude Code's buffers, its completion with
;; it; agent-shell's own (/ commands, @ files) stays.
(defun +my/agent-shell-no-snippets-p ()
  "Non-nil in Claude Code's buffers: yasnippet stays off (see above)."
  (derived-mode-p 'agent-shell-mode))

(after! yasnippet
  (add-hook 'yas-dont-activate-functions #'+my/agent-shell-no-snippets-p))
