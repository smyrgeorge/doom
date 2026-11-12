;;; $DOOMDIR/config/agent-shell/prompt.el -*- lexical-binding: t; -*-
;; Typing in Claude Code's prompt. Loaded from config/agent-shell.el.

;; NO SNIPPETS IN THE PROMPT
;; Typing stalled in a long session: each pause (corfu's completion, 0.4 s)
;; asked yasnippet for a snippet's key before point (`yasnippet-capf', which
;; Doom adds where yasnippet is on), a search that took a third of the time in
;; a session of 1.2 MB (thing-at-point-looking-at). Snippets have no place in
;; a prompt: yasnippet stays off in Claude Code's buffers, its completion with
;; it; agent-shell's own (/ commands, @ files) stays.
;;
;; The rule alone misses a session opened before yasnippet loads (Doom loads
;; it lazily): Doom's own setup, which runs first, turns yasnippet on in every
;; buffer already open, the session's too, before the rule is there. So as
;; yasnippet loads, it's turned off again in the sessions already open. And
;; Doom adds `yasnippet-capf' as yasnippet turns off too (on
;; `yas-minor-mode-hook', run both ways): it's taken out again where yasnippet
;; is off.
(defun +my/agent-shell-no-snippets-p ()
  "Non-nil in Claude Code's buffers: yasnippet stays off (see above)."
  (derived-mode-p 'agent-shell-mode))

(defun +my/agent-shell-no-snippet-capf-h ()
  "No `yasnippet-capf' in a Claude Code buffer where yasnippet is off."
  (when (and (+my/agent-shell-no-snippets-p)
             (not (bound-and-true-p yas-minor-mode)))
    (remove-hook 'completion-at-point-functions #'yasnippet-capf t)))

(defun +my/agent-shell-snippets-off ()
  "Yasnippet off in the Claude Code buffers already open (see above)."
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when (+my/agent-shell-no-snippets-p)
        (when (bound-and-true-p yas-minor-mode)
          (yas-minor-mode -1))
        (+my/agent-shell-no-snippet-capf-h)))))

(after! yasnippet
  (add-hook 'yas-dont-activate-functions #'+my/agent-shell-no-snippets-p)
  ;; After Doom's, which adds it.
  (add-hook 'yas-minor-mode-hook #'+my/agent-shell-no-snippet-capf-h 90)
  (+my/agent-shell-snippets-off))
