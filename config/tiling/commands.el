;;; $DOOMDIR/config/tiling/commands.el -*- lexical-binding: t; -*-
;; SPC w SPC and SPC w a.
;; Loaded from config/tiling.el.

(defvar +my/focus-new-windows)          ; config/window.el

;; COMMANDS (see config/tiling.el)
(defun +my/tiling-split ()
  "SPC w SPC: a new pane where the tiling strategy puts it (config/tiling.el)."
  (interactive)
  (let ((from (selected-window))
        (panes (+my/tiling--panes))
        (strategy (+my/tiling--strategy)))
    (unless (memq from panes)
      (user-error "Not in a pane: side panels aren't tiled"))
    (let ((buffer (window-buffer from))
          (point (window-point from))
          (start (window-start from))
          (new (funcall (plist-get strategy :split) panes)))
      ;; The current buffer, its only tab (it showed another first).
      (set-window-buffer new buffer)
      (set-window-start new start t)
      (set-window-point new point)
      (set-window-prev-buffers new nil)
      (set-window-next-buffers new nil)
      (set-window-parameter new 'tab-line-buffers nil)
      ;; New panes take focus (config/window.el).
      (when (or (not (boundp '+my/focus-new-windows)) +my/focus-new-windows)
        (select-window new))
      new)))

(defun +my/tiling-arrange ()
  "SPC w a: lay the panes out as the tiling strategy does (config/tiling.el)."
  (interactive)
  (let ((panes (+my/tiling--panes))
        (strategy (+my/tiling--strategy)))
    (unless (memq (selected-window) panes)
      (user-error "Not in a pane: side panels aren't tiled"))
    (when (cdr panes)
      (funcall (plist-get strategy :arrange) panes))))
