;;; $DOOMDIR/config/stripe/overscroll.el -*- lexical-binding: t; -*-
;; How far past the end a window may scroll. Loaded from config/stripe.el.

;;; Scrolling past the end

(defun +my/stripe--text-rows-wanted (window)
  "How many of WINDOW's rows must show text: all but the allowed overscroll."
  (let ((rows (window-body-height window)))
    (max 1 (- rows (if (floatp +my/stripe-overscroll)
                       (floor (* rows +my/stripe-overscroll))
                     +my/stripe-overscroll)))))

;; Measured in pixels, not rows: a row showing an image (e.g. a screenshot in
;; an agent-shell reply) is as tall as many lines. Counted as one, the limit
;; came out far above the end: scrolling down to an image near the end,
;; ultra-scroll went on past it (within the image) and the limit then
;; snapped the window back up, by screens.
(defun +my/stripe--end-pixels-wanted (window)
  "How far below the top of WINDOW the end of its buffer must at least be, in
pixels: `+my/stripe--text-rows-wanted' rows, the empty line after a final
newline counting as one."
  (let ((lh (window-default-line-height window)))
    (- (* (+my/stripe--text-rows-wanted window) lh)
       (if (and (> (point-max) (point-min)) (eq (char-before (point-max)) ?\n))
           lh
         0))))

(defun +my/stripe--end-limit (window)
  "(START . VSCROLL): as far as WINDOW may scroll toward the end, the row the
allowed distance above it and how much of that row goes above the window's top
\(as ultra-scroll scrolls). Measured up from the end, as far as needed."
  (pcase-let* ((wanted (+my/stripe--end-pixels-wanted window))
               (`(,_ ,height ,start)
                (window-text-pixel-size window (cons (point-max) (- wanted))
                                        (point-max))))
    (and start (cons start (max 0 (- height wanted))))))

(defun +my/stripe--clamp-start (window)
  "Scroll WINDOW back so it doesn't show more empty space past the end than allowed."
  (unless (eq +my/stripe-overscroll t)
    (let ((start (window-start window))
          (vscroll (window-vscroll window t)))
      (when (or (> start (point-min)) (> vscroll 0))
        (pcase (+my/stripe--end-limit window)
          ((and `(,limit . ,limit-vscroll)
                (guard (or (> start limit)
                           (and (= start limit) (> vscroll limit-vscroll)))))
           (set-window-start window limit t)
           (set-window-vscroll window limit-vscroll t t)))))))

;; Redraw right before a window is displayed whenever what it shows changed
;; (scroll position, size, buffer, diagnostics, git highlights, lines added or
;; removed): every kind of scrolling and editing is caught before a stale
;; stripe can be drawn. Also limits scrolling past the end (`+my/stripe-overscroll').
(defun +my/stripe--pre-redisplay (window)
  (when (and (bound-and-true-p +my/stripe-mode) (windowp window))
    (let ((old (window-parameter window '+my/stripe-key)))
      ;; `eq' per part: the error list is compared by identity.
      (unless (and old (cl-every #'eq old (+my/stripe--key window)))
        ;; Scrolled (or edited...): hold the window within the limit before
        ;; this frame is drawn, then redraw the strip.
        (+my/stripe--clamp-start window)
        (+my/stripe--render window)))))

(defun +my/stripe--after-scroll (window start)
  "When redisplay itself scrolled WINDOW (e.g. to follow the cursor), maybe past
the end, check it right after."
  (when (and (not (eq +my/stripe-overscroll t))
             (window-live-p window)
             (<= (count-lines start (point-max)) (window-body-height window)))
    (run-at-time 0 nil (lambda ()
                         (when (window-live-p window)
                           (with-current-buffer (window-buffer window)
                             (when (bound-and-true-p +my/stripe-mode)
                               (+my/stripe--clamp-start window)
                               ;; Redraw before the next frame.
                               (set-window-parameter window '+my/stripe-key nil))))))))

(add-hook 'pre-redisplay-functions #'+my/stripe--pre-redisplay)
