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
  "Jump to the part of the file at the clicked cell of the stripe (terminal):
to its mark's line if it shows one, else to the middle of its lines."
  (interactive "e")
  (let* ((posn (event-start event))
         (window (posn-window posn))
         (geometry (and (window-live-p window)
                        (window-parameter window '+my/stripe-geometry))))
    (pcase geometry
      (`(cells ,rows ,lines . ,rest)
       (when-let* ((row (if-let* ((string (posn-string posn)))
                            (get-text-property (or (cdr string) 0) '+my/stripe-row (car string))
                          ;; Reported in the text (see `+my/stripe--on-tty-strip').
                          (and (+my/stripe--tty-strip-click-p event) (cdr (posn-col-row posn)))))
                   ((< -1 row rows)))
         (+my/stripe--goto-line window
                                (or (and (vectorp (car rest)) (< row (length (car rest)))
                                         (aref (car rest) row))
                                    (+my/stripe--row-to-line row lines rows))))))))

;; A press on a mark goes to its line. The strip maps many lines to a pixel
;; (or a cell): the line under the pressed pixel could be far enough from the
;; mark's for it to stay off screen (a 9 row window, 3000 lines: an error on
;; line 2000 drawn on pixels 83-84, the press on 83 went to line 1978); and
;; drawn over the band, the press grabbed the band.
(defun +my/stripe--mark-at (y line spans)
  "The line a press at pixel Y (on LINE's place) goes to if a mark is drawn
there: the nearest to LINE of the most important marks drawn there. SPANS:
the marks as drawn (see `+my/stripe--pixels')."
  (let (best best-priority best-distance)
    (pcase-dolist (`(,top ,bottom ,priority ,first ,last) spans)
      (when (and (<= top y) (< y bottom))
        (let* ((target (max first (min last line)))
               (distance (abs (- target line))))
          (when (or (null best)
                    (> priority best-priority)
                    (and (= priority best-priority) (< distance best-distance)))
            (setq best target best-priority priority best-distance distance)))))
    best))

(defun +my/stripe--tty-strip-click-p (event)
  "Non-nil if mouse EVENT is on the strip of a terminal window, reported as
in its text: past the end of its text's columns (see `+my/stripe-tty-click-map')."
  (when-let* (((consp event))
              (posn (event-start event))
              (window (posn-window posn))
              ((window-live-p window))
              ((null (posn-area posn)))
              ((eq (car-safe (window-parameter window '+my/stripe-geometry)) 'cells)))
    (>= (car (posn-col-row posn)) (window-body-width window))))

(defun +my/stripe--on-tty-strip (command)
  "COMMAND if the mouse event being read is on a terminal window's strip,
reported as in its text (a filter of `+my/stripe-tty-click-map')."
  (and (+my/stripe--tty-strip-click-p last-input-event) command))

;; Before Evil's keys (and general's): first among the emulation keymaps.
;; Evil puts its own first the first time it's on in a buffer, so it's
;; checked again as the stripe comes on in one.
(defvar +my/stripe--emulation-alist nil
  "The stripe's emulation keymaps (see `+my/stripe-tty-click-map').")

(setq +my/stripe--emulation-alist `((+my/stripe-mode . ,+my/stripe-tty-click-map)))

(defun +my/stripe--keys-first ()
  "The stripe's terminal clicks first among `emulation-mode-map-alists'."
  (unless (eq (car emulation-mode-map-alists) '+my/stripe--emulation-alist)
    (setq emulation-mode-map-alists
          (cons '+my/stripe--emulation-alist
                (delq '+my/stripe--emulation-alist emulation-mode-map-alists)))))

(+my/stripe--keys-first)

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

(defun +my/stripe--pointer-y (window)
  "The mouse's height in pixels, from a top that stays put while the band is
dragged: the screen's; on Wayland (pgtk), which doesn't give the mouse's
place on the screen, WINDOW's frame's (the strip's frame, a child of it, is
placed in it). Nil if the mouse is over another frame."
  (if (not (eq (framep (window-frame window)) 'pgtk))
      (cdr (mouse-absolute-pixel-position))
    (let ((parent (window-frame window)))
      (pcase (mouse-pixel-position)
        (`(,frame ,_ . ,(and y (pred integerp)))
         (cond ((eq frame parent) y)
               ((eq (frame-parent frame) parent) (+ y (cdr (frame-position frame))))))))))

(defun +my/stripe-press (event)
  "A press on the strip: on a mark, jump to its line; on the band, hold it
\(dragging scrolls); elsewhere, jump there (the line in the middle of the
window, `C-o' going back)."
  (interactive "e")
  (when-let* ((window (+my/stripe--window-of event)))
    ;; The keyboard stays with the file's frame, not the strip's.
    (select-frame-set-input-focus (window-frame window))
    (select-window window)
    (pcase (window-parameter window '+my/stripe-geometry)
      (`(pixels ,scale ,lines ,thumb . ,rest)
       (let* ((posn (event-start event))
              (y (or (cdr (posn-object-x-y posn)) 0))
              (line (max 1 (min lines (1+ (floor (/ y scale))))))
              (mark (+my/stripe--mark-at y line (car rest)))
              (grab (and (not mark) thumb (<= (car thumb) y) (< y (cdr thumb)) (- y (car thumb)))))
         (if (not grab)
             (+my/stripe--goto-line window (or mark line))
           ;; Where the strip's top is on the screen: the mouse there now,
           ;; less how far down the strip it is.
           (let ((origin (- (or (+my/stripe--pointer-y window) y) y))
                 (next nil))
             (track-mouse
               (while (progn (setq next (read-event))
                             (mouse-movement-p next))
                 (when-let* ((pointer (+my/stripe--pointer-y window)))
                   (+my/stripe--scroll-band-to window (- pointer origin grab) scale)
                   (redisplay))))
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
