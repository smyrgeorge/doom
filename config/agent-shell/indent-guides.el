;;; $DOOMDIR/config/agent-shell/indent-guides.el -*- lexical-binding: t; -*-
;; No indent guides in a session. Loaded from config/agent-shell.el.

;; NO INDENT GUIDES
;; Doom's :ui indent-guides turns indent-bars on in every buffer whose major
;; mode starts, unless one of `+indent-guides-inhibit-functions' says no: a
;; session (agent-shell-mode, a comint buffer, neither read-only nor special
;; to Doom) got them, and so did its viewport's buffers (text-mode), bars
;; down every reply (indented by agent-shell's line-prefix), list and code
;; block. They stay off in agent-shell's buffers. The rule is there before
;; any session opens (Doom's module, which defines the hook, loads first).
(defun +my/agent-shell-no-indent-guides-p ()
  "Non-nil in agent-shell's buffers (a session, its viewport's): no indent
guides there (see above)."
  (derived-mode-p 'agent-shell-mode
                  'agent-shell-viewport-view-mode
                  'agent-shell-viewport-edit-mode))

(add-hook '+indent-guides-inhibit-functions #'+my/agent-shell-no-indent-guides-p)
