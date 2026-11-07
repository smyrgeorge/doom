;;; $DOOMDIR/config/stripe/mouse.el -*- lexical-binding: t; -*-
;; Clicks, drags and the wheel on the stripe. Loaded from config/stripe.el.

;;; Clicks, drags, the wheel

(defun +my/stripe--goto-line (window line)
  "Jump to LINE in WINDOW: in the middle of it, `C-o' going back."
  (select-window window)
  (when (fboundp 'better-jumper-set-jump)
    (better-jumper-set-jump))
  (goto-char (point-min))
  (forward-line (1- line))
  (recenter))

(defun +my/stripe-jump (event)
  "Jump to the part of the file at the clicked cell of the stripe (terminal)."
  (interactive "e")
  (let* ((posn (event-start event))
         (window (posn-window posn))
         (geometry (and (window-live-p window)
                        (window-parameter window '+my/stripe-geometry))))
    (pcase geometry
      (`(cells ,rows ,lines)
       (when-let* ((string (posn-string posn))
                   (row (get-text-property (or (cdr string) 0) '+my/stripe-row (car string))))
         (+my/stripe--goto-line window (+my/stripe--row-to-line row lines rows)))))))

(defun +my/stripe--window-of (event)
  "The window whose strip EVENT happened on."
  (let ((window (frame-parameter (window-frame (posn-window (event-start event)))
                                 '+my/stripe-window)))
    (and (window-live-p window) window)))

(defun +my/stripe--scroll-band-to (window top scale)
  "Scroll WINDOW so the band's top is at TOP pixels of the strip, SCALE pixels
a line."
  (with-current-buffer (window-buffer window)
    (let ((line (max 1 (1+ (floor (/ (max 0 top) scale))))))
      (set-window-start window (save-excursion
                                 (goto-char (point-min))
                                 (forward-line (1- line))
                                 (point))))))

(defun +my/stripe-press (event)
  "A press on the strip: on the band, hold it (dragging scrolls); elsewhere,
jump there (the line in the middle of the window, `C-o' going back)."
  (interactive "e")
  (when-let* ((window (+my/stripe--window-of event)))
    ;; The keyboard stays with the file's frame, not the strip's.
    (select-frame-set-input-focus (window-frame window))
    (select-window window)
    (pcase (window-parameter window '+my/stripe-geometry)
      (`(pixels ,scale ,lines ,thumb)
       (let* ((posn (event-start event))
              (y (or (cdr (posn-object-x-y posn)) 0))
              (grab (and thumb (<= (car thumb) y (cdr thumb)) (- y (car thumb)))))
         (if (not grab)
             (+my/stripe--goto-line window (max 1 (min lines (1+ (floor (/ y scale))))))
           ;; Where the strip's top is on the screen: the mouse there now,
           ;; less how far down the strip it is.
           (let ((origin (- (cdr (mouse-absolute-pixel-position)) y))
                 (next nil))
             (track-mouse
               (while (progn (setq next (read-event))
                             (mouse-movement-p next))
                 (+my/stripe--scroll-band-to
                  window (- (cdr (mouse-absolute-pixel-position)) origin grab) scale)
                 (redisplay)))
             ;; Anything but the button's release goes on as input.
             (unless (memq (event-basic-type next) '(mouse-1))
               (push next unread-command-events)))))))))

(defun +my/stripe-wheel (event)
  "The wheel over the strip: it scrolls the file's window, as over its text."
  (interactive "e")
  (when-let* ((window (+my/stripe--window-of event))
              (command (with-selected-window window
                         (key-binding (vector (car event)) t))))
    (when (commandp command)
      (funcall command (append (list (car event) (posn-at-point (window-start window) window))
                               (nthcdr 2 event))))))
