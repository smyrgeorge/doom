;;; $DOOMDIR/config/window.el -*- lexical-binding: t; -*-
;; Frame and window behaviour. Loaded from config.el.

;; ====== VARIABLES ======

;; New windows get focus.
;; Splits (SPC w s / SPC w v): Doom always splits below/right; these only decide
;; which window gets the cursor. SPC w S / SPC w V now split and stay.
(setq evil-split-window-below t
      evil-vsplit-window-right t)

;; Anything else a command shows in a newly created window (diffs, file
;; previews, other-window commands...) is selected too, once the command is
;; done: not while it runs, as a command may go on working in its own window
;; (M-x checkdoc, its status shown, recentred its file in the status's window
;; and failed); another window it selects itself stays so. Not affected: side
;; windows (Doom popups follow their own :select rules; treemacs, which-key and
;; transient menus live there), child frames, windows opened from timers or
;; process output (no command running), windows a command typed in the
;; minibuffer shows (TAB's *Completions*: the focus stays with what you're
;; typing), and code that binds `+my/focus-new-windows' to nil (e.g. the live
;; Markdown preview).
(defvar +my/focus-new-windows t
  "When non-nil, select windows that `display-buffer' creates for a command.")

;; FRINGES
;; Every window's right fringe is a character wider (16 px instead of Doom's 8):
;; the arrows of lines cut off at the window's edge (e.g. long names in
;; treemacs) sit in the middle of it instead of against the text. File windows
;; get the same on the left too (config/stripe.el, PADDING).
(defvar +my/right-fringe-padding 1
  "Columns added to every window's right fringe (nil: none).")

;; ====== CODE ======

;; WINDOW
;; Maximized at startup. Set, not toggled: a frame the window manager already
;; maximized or tiled (Linux's tiling ones) isn't made small again.
(defun +my/maximize-frame-h ()
  "Maximize the selected frame, unless it is already (or full screen)."
  (unless (memq (frame-parameter nil 'fullscreen) '(maximized fullboth fullscreen))
    (set-frame-parameter nil 'fullscreen 'maximized)))

(add-hook 'window-setup-hook #'+my/maximize-frame-h)

;; FRINGES (see above). A frame's character width is known once it's
;; graphical; a terminal's has no fringes.
(when +my/right-fringe-padding
  (fringe-mode (cons (or (frame-parameter nil 'left-fringe) 8)
                     (+ 8 (* +my/right-fringe-padding
                             (if (display-graphic-p) (frame-char-width) 8))))))

;; NEW WINDOWS GET FOCUS (see above). The command's end: once
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
\(see above), still there, unless it selected another itself."
  (pcase-let ((`(,new ,selected ,depth) +my/focus--pending))
    (unless (and depth (> (recursion-depth) depth))
      (+my/focus--forget)
      (when (and (eql (recursion-depth) depth)
                 (window-live-p new)
                 (eq (selected-window) selected))
        (select-window new)))))

(defun +my/focus-forget-h ()
  "As a command starts at the level of one that showed a new window: that
one never ended (see above), its window forgotten."
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
