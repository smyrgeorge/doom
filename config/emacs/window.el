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

;; A WINDOW QUIT GETS ITS SIZE BACK ON THE SIDE IT HAD IT
;; A buffer shown in a window (`display-buffer' reusing it) has the window's
;; size noted, to give back once it's quit (q): its height if it's in a
;; column then, else its width. Emacs gives it back along the side the window
;; is combined on when it's quit, though that may have changed: a session's
;; pane over its Agent UI canvas (in a column with it) showing the issue list
;; (SPC o i), the canvas closing meanwhile (its session not shown), was beside
;; the sidebar once q quit it, and got its old height (53 lines) as its width:
;; 53 columns of 202, the 149 others the sidebar's (kept so by
;; config/treemacs/width.el, as if you had resized it). The side is noted with
;; the size; a window combined the other way when quit keeps its size.
(defvar +my/quit-restore--sides (make-hash-table :test #'eq :weakness 'key)
  "A `quit-restore' parameter's size (its buffer's quadruple) to the side it
was noted on: `height' or `width' (see above).")

(defun +my/quit-restore--side (window)
  "The side of WINDOW's size `display-buffer' notes, and quitting gives back."
  (if (window-combined-p window) 'height 'width))

(defun +my/quit-restore--quads (window)
  "WINDOW's noted buffers with their sizes: its `quit-restore' parameters'."
  (seq-filter (lambda (quad) (and (consp quad) (integerp (nth 3 quad))))
              (mapcar (lambda (parameter) (nth 1 (window-parameter window parameter)))
                      '(quit-restore quit-restore-prev))))

(defadvice! +my/quit-restore-note-side-a (type window _buffer)
  "The side of the size just noted for WINDOW (see above)."
  :after #'display-buffer-record-window
  (when (eq type 'reuse)
    (dolist (quad (+my/quit-restore--quads window))
      (unless (gethash quad +my/quit-restore--sides)
        (puthash quad (+my/quit-restore--side window) +my/quit-restore--sides)))))

(defadvice! +my/quit-restore-same-side-a (&optional window _bury-or-kill)
  "WINDOW's noted size given back only on the side it was noted on (see above)."
  :before #'quit-restore-window
  (let ((window (window-normalize-window window t)))
    (dolist (quad (+my/quit-restore--quads window))
      (unless (eq (gethash quad +my/quit-restore--sides) (+my/quit-restore--side window))
        (setcar (nthcdr 3 quad) nil)))))
