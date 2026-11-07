;;; $DOOMDIR/config/stripe/mode.el -*- lexical-binding: t; -*-
;; The stripe's mode, on in file buffers. Loaded from config/stripe.el.

;;; Modes

(define-minor-mode +my/stripe-mode
  "A stripe of git changes and diagnostics at the right edge."
  :keymap +my/stripe-mode-map
  (if +my/stripe-mode
      (progn
        ;; The strip's room: its frame lies over it (a terminal: the cells).
        (setq-local right-margin-width 1)
        ;; Scrolls that redisplay itself decides on (point left the window);
        ;; everything else is caught by `+my/stripe--pre-redisplay'.
        (add-hook 'window-scroll-functions #'+my/stripe--scrolled nil t)
        (add-hook 'window-scroll-functions #'+my/stripe--after-scroll nil t)
        (add-hook 'before-change-functions #'+my/stripe--note-line-edit nil t)
        (add-hook 'after-change-functions #'+my/stripe--note-line-edit nil t)
        ;; The stripe at the very edge, the fringe (line truncation arrows)
        ;; between it and the text. Doom's vc-gutter puts fringes outside the
        ;; margins, for the git gutter's sake (at the left edge); without a
        ;; left margin, as in file windows, that changes nothing on the left.
        (setq-local fringes-outside-margins nil)
        (+my/stripe--pad)
        (dolist (window (get-buffer-window-list nil nil t))
          (set-window-margins window (car (window-margins window)) 1)
          (+my/stripe--set-fringes window)
          (+my/stripe--render window)))
    (remove-overlays (point-min) (point-max) '+my/stripe t)
    (setq +my/stripe--cache nil)
    (remove-hook 'window-scroll-functions #'+my/stripe--scrolled t)
    (remove-hook 'window-scroll-functions #'+my/stripe--after-scroll t)
    (remove-hook 'before-change-functions #'+my/stripe--note-line-edit t)
    (remove-hook 'after-change-functions #'+my/stripe--note-line-edit t)
    (kill-local-variable 'right-margin-width)
    (kill-local-variable 'fringes-outside-margins)
    (kill-local-variable 'left-fringe-width)
    (kill-local-variable 'right-fringe-width)
    (dolist (window (get-buffer-window-list nil nil t))
      (set-window-margins window (car (window-margins window)) nil)
      (+my/stripe--set-fringes window)))
  ;; The strips' frames: shown, hidden.
  (+my/stripe--sync-soon))

(defun +my/stripe--set-fringes (window)
  "Apply the buffer's fringe settings (`fringes-outside-margins', widths) to
WINDOW, which shows it already (windows take them when they start showing a
buffer)."
  (set-window-fringes window left-fringe-width right-fringe-width
                      fringes-outside-margins))

(defun +my/stripe--pad (&optional frame)
  "Widen the current buffer's fringes by `+my/stripe-padding' columns, as
measured in FRAME or else any graphical frame. With none yet (a terminal
session), it's done when a graphical window first shows the buffer."
  (when-let* ((columns +my/stripe-padding)
              (frame (or frame
                         (seq-find (lambda (f) (and (display-graphic-p f)
                                                    (not (frame-parent f))))
                                   (cons (selected-frame) (frame-list))))))
    (let ((pad (* columns (frame-char-width frame))))
      ;; The right one may be padded already (config/window.el, FRINGES).
      (setq-local left-fringe-width (+ (or (frame-parameter frame 'left-fringe) 8) pad)
                  right-fringe-width (max (or (frame-parameter frame 'right-fringe) 8)
                                          (+ 8 pad))))))

(defun +my/stripe--maybe-enable ()
  ;; `so-long-mode' (files with very long lines) replaces their mode and isn't
  ;; derived from any of these.
  (when (and buffer-file-name
             (derived-mode-p 'prog-mode 'text-mode 'conf-mode 'so-long-mode))
    (+my/stripe-mode 1)))

(define-globalized-minor-mode +my/stripe-global-mode +my/stripe-mode
  +my/stripe--maybe-enable)

(+my/stripe-global-mode 1)
