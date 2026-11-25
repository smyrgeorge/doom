;;; $DOOMDIR/config/emacs/window.el -*- lexical-binding: t; -*-
;; The frame and its windows: maximized, new windows get focus
;; (config/emacs.el, FRAMES AND WINDOWS). Loaded from config/emacs.el.

;; THE FRAME
;; Maximized at startup. Set, not toggled: a frame the window manager already
;; maximized or tiled (Linux's tiling ones) isn't made small again.
(defun +my/maximize-frame-h ()
  "Maximize the selected frame, unless it is already (or full screen)."
  (unless (memq (frame-parameter nil 'fullscreen) '(maximized fullboth fullscreen))
    (set-frame-parameter nil 'fullscreen 'maximized)))

(add-hook 'window-setup-hook #'+my/maximize-frame-h)

;; NEW WINDOWS GET FOCUS (config/emacs.el). The command's end: once
;; `post-command-hook' runs at the level it ran at (a prompt it shows runs
;; commands of its own, a level deeper); a command that never ended (an
;; error) is forgotten as the next one starts.
(defvar +my/focus--pending nil
  "The window `display-buffer' made for the command running: (NEW SELECTED
DEPTH), the window selected then and the `recursion-depth'; NEW is selected
once the command ends.")

(defun +my/focus--forget ()
  (remove-hook 'post-command-hook #'+my/focus-new-window-h)
  (remove-hook 'pre-command-hook #'+my/focus-forget-h)
  (setq +my/focus--pending nil))

(defun +my/focus-new-window-h ()
  "Once a command ends: the window it showed something new in selected
\(config/emacs.el, NEW WINDOWS GET FOCUS), still there, unless it selected
another itself."
  (pcase-let ((`(,new ,selected ,depth) +my/focus--pending))
    (unless (and depth (> (recursion-depth) depth))
      (+my/focus--forget)
      (when (and (eql (recursion-depth) depth)
                 (window-live-p new)
                 (eq (selected-window) selected))
        (select-window new)))))

(defun +my/focus-forget-h ()
  "As a command starts at the level of one that showed a new window: that
one never ended (see NEW WINDOWS GET FOCUS), its window forgotten."
  (pcase-let ((`(,_ ,_ ,depth) +my/focus--pending))
    (unless (and depth (> (recursion-depth) depth))
      (+my/focus--forget))))

(defadvice! +my/focus-new-window-a (fn buffer &rest args)
  :around #'display-buffer
  (let* ((before (window-list-1 nil 'nomini t))
         (window (apply fn buffer args)))
    (when (and +my/focus-new-windows
               this-command
               (not (window-minibuffer-p))
               (window-live-p window)
               (not (memq window before))
               (not (window-parameter window 'window-side))
               (not (frame-parameter (window-frame window) 'parent-frame)))
      (setq +my/focus--pending (list window (selected-window) (recursion-depth)))
      (add-hook 'post-command-hook #'+my/focus-new-window-h)
      (add-hook 'pre-command-hook #'+my/focus-forget-h))
    window))
