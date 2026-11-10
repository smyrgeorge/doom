;;; $DOOMDIR/config/tiling/commands.el -*- lexical-binding: t; -*-
;; SPC w SPC, SPC w a, SPC w RET and resizing (SPC w ] / [).
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
    (define-key map "}" #'+my/tiling-pane-bigger)
    (define-key map "{" #'+my/tiling-pane-smaller)
    map)
  "After a resize (SPC w ] / [, the main area; } / {, the current pane): any
of them again (see config/tiling.el).")

;; RESIZING: each strategy says what it is (see `+my/tiling-strategies'): the
;; main area bigger in tall is its width, in another its height; the current
;; pane's size within the others. These only check the panes, ask it, and
;; say what it did.
(defun +my/tiling--resize (key what direction keys)
  "Resize by the strategy's KEY (:resize-main or :resize-pane), WHAT it
resizes (said if it has nothing so), in DIRECTION (1 bigger, -1 smaller);
then KEYS repeat it, and what the strategy did is said."
  (let* ((panes (+my/tiling--panes))
         (pane (selected-window))
         (resize (plist-get (+my/tiling--strategy) key)))
    (unless resize
      (user-error "The tiling strategy `%s' has no %s to resize" +my/tiling-strategy what))
    (unless (memq pane panes)
      (user-error "Not in a pane: side panels aren't tiled"))
    (unless (cdr panes)
      (user-error "Only one pane"))
    (let ((said (if (eq key :resize-pane)
                    (funcall resize panes pane direction)
                  (funcall resize panes direction))))
      (set-transient-map +my/tiling-resize-map t)
      (message "%s (%s again)" said keys))))

(defun +my/tiling-resize-main (direction)
  "The main area bigger (DIRECTION 1) or smaller (-1), as the strategy has
it (tall: the main pane's width)."
  (+my/tiling--resize :resize-main "main area" direction "] / ["))

(defun +my/tiling-resize-pane (direction)
  "The current pane bigger (DIRECTION 1) or smaller (-1) within the others,
as the strategy has it."
  (+my/tiling--resize :resize-pane "pane" direction "} / {"))

(defun +my/tiling-main-bigger ()
  "SPC w ]: the main area bigger, as the strategy has it (config/tiling.el)."
  (interactive)
  (+my/tiling-resize-main 1))

(defun +my/tiling-main-smaller ()
  "SPC w [: the main area smaller, as the strategy has it (config/tiling.el)."
  (interactive)
  (+my/tiling-resize-main -1))

(defun +my/tiling-pane-bigger ()
  "The current pane bigger, as the strategy has it (config/tiling.el)."
  (interactive)
  (+my/tiling-resize-pane 1))

(defun +my/tiling-pane-smaller ()
  "The current pane smaller, as the strategy has it (config/tiling.el)."
  (interactive)
  (+my/tiling-resize-pane -1))
