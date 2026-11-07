;;; $DOOMDIR/config/stripe/draw.el -*- lexical-binding: t; -*-
;; Drawing a window's stripe. Loaded from config/stripe.el.

;;; Drawing

(defun +my/stripe--render (window &optional start)
  "Redraw the stripe of WINDOW, whose text starts at START."
  (when (window-live-p window)
    (with-current-buffer (window-buffer window)
      ;; Runs from redisplay hooks: never let an error escape into them.
      (with-demoted-errors "Stripe: %S"
        (when (bound-and-true-p +my/stripe-mode)
          (set-window-parameter window '+my/stripe-key (+my/stripe--key window start))
          (pcase-let ((`(,lines . ,marks) (+my/stripe--marks))
                      (start (or start (window-start window))))
            (if (display-graphic-p (window-frame window))
                ;; Not in windows of child frames (a strip's own, a popup's).
                (unless (frame-parent (window-frame window))
                  (when (and +my/stripe-padding (null left-fringe-width))
                    (+my/stripe--pad (window-frame window))
                    (+my/stripe--set-fringes window))
                  (+my/stripe--draw-image window start lines marks))
              (+my/stripe--draw-cells window start lines marks))))))))

(defun +my/stripe--scrolled (window start)
  "Redisplay scrolled WINDOW to START (e.g. to follow the cursor): redraw the
stripe there. Not when the window was just given the buffer
(`set-window-buffer' runs this too, before e.g. the saved place moves point):
the redraw right before it's displayed does it, at its final position. In a
graphical frame right after this redisplay: the strip's frame may be drawn
already."
  (when (eq (car-safe (window-parameter window '+my/stripe-key)) (window-buffer window))
    (if (display-graphic-p (window-frame window))
        (run-at-time 0 nil #'+my/stripe--render window)
      (+my/stripe--render window start))))

(defun +my/stripe--note-line-edit (beg end &rest _)
  "Before/after a change: count it if BEG..END holds a line break, i.e. lines
are being removed (before) or added (after)."
  (when (and (< beg end)
             (save-excursion (goto-char beg) (search-forward "\n" end t)))
    (cl-incf +my/stripe--line-edits)))

(defun +my/stripe--render-all ()
  "Redraw the stripe in every window (e.g. after a theme change: the strips'
frames take its background)."
  (dolist (entry +my/stripe--frames)
    (when (frame-live-p (nth 1 entry))
      (set-frame-parameter (nth 1 entry) 'background-color (face-background 'default nil t))))
  (dolist (window (window-list-1 nil 'nomini t))
    (+my/stripe--render window)))

(add-hook 'doom-load-theme-hook #'+my/stripe--render-all)
