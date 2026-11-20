;;; $DOOMDIR/config/tiling/panes.el -*- lexical-binding: t; -*-
;; The panes, in order, and the strategy chosen.
;; Loaded from config/tiling.el.

(defun +my/tiling--strategy ()
  "The strategy chosen (see config/tiling.el)."
  (or (alist-get +my/tiling-strategy +my/tiling-strategies)
      (user-error "No tiling strategy `%s' (see `+my/tiling-strategies')"
                  +my/tiling-strategy)))

(defun +my/tiling--children (window)
  "WINDOW's child windows, in order."
  (let ((child (window-child window))
        children)
    (while child
      (push child children)
      (setq child (window-next-sibling child)))
    (nreverse children)))

(defun +my/tiling--panes (&optional frame)
  "FRAME's (the selected frame's) panes: its windows besides side panels and
a layout kept whole (see below), in order."
  (let (panes)
    (named-let walk ((window (window-main-window frame)))
      (cond ((window-parameter window 'window-atom))
            ((window-live-p window) (push window panes))
            (t (mapc #'walk (+my/tiling--children window)))))
    (nreverse panes)))

;; A LAYOUT KEPT WHOLE
;; An atomic window (Emacs's `window-atom' parameter: its windows split,
;; deleted and resized as one), as a merge's bar and three panes are
;; (config/merge.el): its windows aren't panes, and tiling lays nothing out
;; in its frame. An application, a file shown from it, SPC w SPC open in a
;; pane beside it (`+my/tiling--beside-atom'); the panes beside it stay as
;; they are (SPC w a, RET, resizing say so). Once it's gone (the merge done:
;; its windows as they were), as before.
(defun +my/tiling--atom (&optional frame)
  "The root of a layout kept whole (see above) among FRAME's (the selected
frame's) windows, or nil."
  (catch 'found
    (walk-window-tree (lambda (window)
                        (when (window-parameter window 'window-atom)
                          (throw 'found (window-atom-root window))))
                      frame t 'nomini)
    nil))

(defun +my/tiling--not-in-pane ()
  "Say the selected window isn't a pane: a side panel, or a layout kept
whole's."
  (user-error (if (window-parameter nil 'window-atom)
                  "Not in a pane: a layout kept whole (a merge) stays as it is"
                "Not in a pane: side panels aren't tiled")))

;; THE MAIN PANE FIRST
;; The panes are in order on the screen, but the main pane first: where SPC w
;; RET, SPC w a and resizing find it. It's the pane a strategy made the main
;; one (marked when it laid the panes out, or split the only one): switching
;; strategy (tall-right's on the right, tall's on the left) keeps it. None
;; marked (a workspace switched to makes its windows anew): the strategy finds
;; it (its :order: tall-right's is the last on the screen), else the first.
(defun +my/tiling--mark-main (window)
  "WINDOW the main pane (see above), the only one of its frame."
  (dolist (pane (+my/tiling--panes (window-frame window)))
    (set-window-parameter pane '+my/tiling-main nil))
  (set-window-parameter window '+my/tiling-main t))

(defun +my/tiling--ordered-panes (&optional frame)
  "FRAME's panes (`+my/tiling--panes'), the main pane first (see above)."
  (let* ((panes (+my/tiling--panes frame))
         (main (seq-find (lambda (pane) (window-parameter pane '+my/tiling-main)) panes))
         (order (plist-get (+my/tiling--strategy) :order)))
    (cond (main (cons main (remq main panes)))
          ((and order panes) (funcall order panes))
          (t panes))))

(defun +my/tiling--state (window)
  "What WINDOW shows, to show it again in another window."
  (list :buffer (window-buffer window)
        :point (window-point window)
        :start (window-start window)
        :hscroll (window-hscroll window)
        :prev (window-prev-buffers window)
        :next (window-next-buffers window)
        :tabs (window-parameter window 'tab-line-buffers)
        :dedicated (window-dedicated-p window)))

(defun +my/tiling--restore (window state)
  "Show STATE (`+my/tiling--state') in WINDOW, its tabs included."
  (set-window-dedicated-p window nil)
  (set-window-buffer window (plist-get state :buffer))
  (set-window-start window (plist-get state :start) t)
  (set-window-point window (plist-get state :point))
  (set-window-hscroll window (plist-get state :hscroll))
  (set-window-prev-buffers window (plist-get state :prev))
  (set-window-next-buffers window (plist-get state :next))
  (set-window-parameter window 'tab-line-buffers (plist-get state :tabs))
  (set-window-dedicated-p window (plist-get state :dedicated)))

;; A PANE CLOSED (see config/tiling.el)
(defun +my/tiling--left-alone-p (&optional frame)
  "Non-nil if tiling leaves FRAME (the selected one) alone
\(`+my/tiling-left-alone')."
  (let ((frame (or frame (selected-frame))))
    (seq-some (lambda (fn) (and (functionp fn) (funcall fn frame))) +my/tiling-left-alone)))

(defun +my/tiling--closed-h (frame)
  "FRAME's panes fewer than when last seen (one closed, however): the others
laid out again by the strategy's :closed. Not a child frame's (notices, the
stripe), nor down to one pane, nor a frame left alone or holding a layout
kept whole (the panes beside it as they are)."
  (unless (or (frame-parent frame) (+my/tiling--left-alone-p frame) (+my/tiling--atom frame))
    (let ((count (length (+my/tiling--panes frame)))
          (before (frame-parameter frame '+my/tiling-panes)))
      (set-frame-parameter frame '+my/tiling-panes count)
      (when (and before (< count before) (> count 1))
        (when-let* ((closed (plist-get (+my/tiling--strategy) :closed)))
          (with-selected-frame frame
            (let ((sizes (+my/tiling--sizes frame)))
              (funcall closed (+my/tiling--ordered-panes))
              (+my/tiling--tell-sizes frame sizes))))))))

(add-hook 'window-state-change-functions #'+my/tiling--closed-h)

;; THE SIZES TOLD
;; Emacs records each window's size once its window change functions have
;; run, `+my/tiling--closed-h' among them: the panes it lays out again are
;; never seen resized by `window-size-change-functions' (a Markdown preview's
;; page kept its height from before, the rest of its pane blank). So they're
;; told here, as Emacs tells them: the functions of the buffer a resized (or
;; new) window shows, with that window; then the default ones, with the frame.
(defun +my/tiling--sizes (frame)
  "FRAME's windows, each with its sizes in pixels: total and text area."
  (mapcar (lambda (window)
            (list window (window-pixel-width window) (window-pixel-height window)
                  (window-body-width window t) (window-body-height window t)))
          (window-list frame 'nomini)))

(defun +my/tiling--tell-sizes (frame before)
  "Run `window-size-change-functions' for FRAME's windows whose sizes differ
from BEFORE (`+my/tiling--sizes'), see above. A function's error is said,
not raised (as Emacs's are)."
  (when-let* ((resized (seq-remove (lambda (size) (member size before))
                                   (+my/tiling--sizes frame))))
    (dolist (size resized)
      (let ((window (car size)))
        (when (window-live-p window)
          (with-current-buffer (window-buffer window)
            (when (local-variable-p 'window-size-change-functions)
              (dolist (fn window-size-change-functions)
                (when (and (not (eq fn t)) (window-live-p window))
                  (with-demoted-errors "Tiling, a size told: %S"
                    (funcall fn window)))))))))
    (dolist (fn (default-value 'window-size-change-functions))
      (when (frame-live-p frame)
        (with-demoted-errors "Tiling, a size told: %S"
          (funcall fn frame))))))
