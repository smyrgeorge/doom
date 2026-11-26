;;; $DOOMDIR/config/agent-shell/nyan.el -*- lexical-binding: t; -*-
;; Nyan Cat in a session's mode line. Loaded from config/agent-shell.el.

;; NYAN CAT
;; A session's mode line shows Nyan Cat (nyan-mode) for where you are in the
;; conversation: doom-modeline's position draws it in a buffer where
;; `nyan-mode' is non-nil. Set in the session's buffer alone,
;; the mode never turned on: other buffers keep their mode line, and no
;; timer redraws every mode line (the cat stays still, its animation off).
(defun +my/agent-shell-nyan-h ()
  "Nyan Cat in this session's mode line (see above)."
  (when (require 'nyan-mode nil t)
    (setq-local nyan-mode t)))

(add-hook 'agent-shell-mode-hook #'+my/agent-shell-nyan-h)
