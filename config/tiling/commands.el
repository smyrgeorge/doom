;;; $DOOMDIR/config/tiling/commands.el -*- lexical-binding: t; -*-
;; SPC w SPC, SPC w a, SPC w RET and SPC w ] / [.
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

(defun +my/tiling-swap-main ()
  "SPC w RET: the selected pane's buffer to the main pane (the first one), the
main's to where it was; the focus to the main pane. From the main pane: the
next pane's buffer to it (config/tiling.el). Tabs, point and history move
with each; the panes' sizes stay."
  (interactive)
  (let ((from (selected-window))
        (panes (+my/tiling--panes)))
    (unless (memq from panes)
      (user-error "Not in a pane: side panels aren't tiled"))
    (unless (cdr panes)
      (user-error "Only one pane"))
    (let* ((main (car panes))
           (other (if (eq from main) (cadr panes) from))
           (main-state (+my/tiling--state main))
           (other-state (+my/tiling--state other)))
      (+my/tiling--restore main other-state)
      (+my/tiling--restore other main-state)
      (select-window main)
      main)))

(defvar +my/tiling-resize-map
  (let ((map (make-sparse-keymap)))
    (define-key map "]" #'+my/tiling-main-bigger)
    (define-key map "[" #'+my/tiling-main-smaller)
    map)
  "After SPC w ] / [: ] and [ again (see config/tiling.el).")

(defun +my/tiling--resize-main (delta)
  "The main pane DELTA (a share of the width) bigger, by the strategy."
  (let ((panes (+my/tiling--panes))
        (resize (plist-get (+my/tiling--strategy) :resize)))
    (unless resize
      (user-error "The tiling strategy `%s' has no main pane to resize" +my/tiling-strategy))
    (unless (memq (selected-window) panes)
      (user-error "Not in a pane: side panels aren't tiled"))
    (unless (cdr panes)
      (user-error "Only one pane"))
    (let ((ratio (funcall resize panes delta)))
      (set-transient-map +my/tiling-resize-map t)
      (message "Main pane: %d%% of the width (] / [ again)" (round (* 100 ratio))))))

(defun +my/tiling-main-bigger ()
  "SPC w ]: the main pane bigger (config/tiling.el)."
  (interactive)
  (+my/tiling--resize-main +my/tiling-resize-step))

(defun +my/tiling-main-smaller ()
  "SPC w [: the main pane smaller (config/tiling.el)."
  (interactive)
  (+my/tiling--resize-main (- +my/tiling-resize-step)))
