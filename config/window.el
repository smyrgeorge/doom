;;; $DOOMDIR/config/window.el -*- lexical-binding: t; -*-
;; Frame and window behaviour. Loaded from config.el.

;; WINDOW
(add-hook 'window-setup-hook #'toggle-frame-maximized)

;; New windows get focus.
;; Splits (SPC w s / SPC w v): Doom always splits below/right; these only decide
;; which window gets the cursor. SPC w S / SPC w V now split and stay.
(setq evil-split-window-below t
      evil-vsplit-window-right t)
;; Anything else a command shows in a newly created window (diffs, file
;; previews, other-window commands...) is selected too. Not affected: side
;; windows (Doom popups follow their own :select rules; treemacs, which-key and
;; transient menus live there), child frames, windows opened from timers or
;; process output (no command running), and code that binds
;; `+my/focus-new-windows' to nil (e.g. the live Markdown preview).
(defvar +my/focus-new-windows t
  "When non-nil, select windows that `display-buffer' creates for a command.")

(defadvice! +my/focus-new-window-a (fn buffer &rest args)
  :around #'display-buffer
  (let* ((before (window-list-1 nil 'nomini t))
         (window (apply fn buffer args)))
    (when (and +my/focus-new-windows
               this-command
               (window-live-p window)
               (not (memq window before))
               (not (window-parameter window 'window-side))
               (not (frame-parameter (window-frame window) 'parent-frame)))
      (select-window window))
    window))
