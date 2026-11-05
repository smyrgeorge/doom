;;; $DOOMDIR/config/smooth.el -*- lexical-binding: t; -*-
;; Smooth mouse-wheel scrolling. Loaded from config.el.

;; ====== VARIABLES ======

;; SMOOTH SCROLL
;; Doom's smooth-scroll module (ultra-scroll) scrolls by the pixels each wheel
;; event reports, all at once: right for a trackpad's stream of small steps,
;; but a mouse wheel reports a few lines per notch (51 px here), so it still
;; moved in jumps. Bigger steps now glide over a few frames, fast at first
;; and slowing down (ease-out); notches in quick succession add up.
(defvar +my/smooth-scroll-min-step 20
  "Wheel steps bigger than this many pixels glide; smaller ones (trackpads) don't.")

(defvar +my/smooth-scroll-frame 0.012
  "Seconds between the frames of a glide.")

(defvar +my/smooth-scroll-fraction 0.3
  "How much of the remaining distance each frame of a glide covers.")

;; ====== CODE ======

(defvar +my/smooth--window nil "The window gliding.")

(defvar +my/smooth--remaining 0 "Pixels left to scroll (negative: down).")

(defvar +my/smooth--timer nil)

(defun +my/smooth--stop ()
  (when (timerp +my/smooth--timer)
    (cancel-timer +my/smooth--timer))
  (setq +my/smooth--timer nil
        +my/smooth--remaining 0))

(defun +my/smooth--frame ()
  "Scroll part of what's left of the glide."
  (let ((window +my/smooth--window))
    (if (or (not (window-live-p window))
            (zerop +my/smooth--remaining))
        (+my/smooth--stop)
      (let ((step (round (* +my/smooth--remaining +my/smooth-scroll-fraction))))
        (when (zerop step)
          (setq step (if (> +my/smooth--remaining 0) 1 -1)))
        (setq +my/smooth--remaining (- +my/smooth--remaining step))
        (condition-case nil
            (ultra-scroll--scroll step window)
          (error (+my/smooth--stop)))))))

;; SCROLL LIMIT
;; ultra-scroll lets a window scroll until its last line is at the top; past
;; that, each wheel notch went a bit further and bounced back. Like file windows
;; (config/stripe.el), all windows now stop with at most `+my/stripe-overscroll'
;; (a quarter of the window) empty below the last line, held before each frame.
;; Not in buffers that scroll within a line (images, PDFs) or manage their own
;; view (terminals).
(defun +my/smooth--limit-p (window)
  "Non-nil if WINDOW's scrolling past the end should be limited here."
  (with-current-buffer (window-buffer window)
    (not (or (bound-and-true-p +my/stripe-mode) ; the stripe does it
             (derived-mode-p 'image-mode 'pdf-view-mode 'doc-view-mode
                             'term-mode 'vterm-mode)
             (string-match-p "ghostel\\|xwidget" (symbol-name major-mode))))))

(defun +my/smooth--limit-h (window)
  (when (and (windowp window)
             (not (window-minibuffer-p window))
             (fboundp '+my/stripe--clamp-start))
    (let ((key (cons (window-start window) (window-vscroll window t))))
      ;; Only when it scrolled.
      (unless (equal key (window-parameter window '+my/smooth-limit))
        (when (+my/smooth--limit-p window)
          (with-current-buffer (window-buffer window)
            (+my/stripe--clamp-start window)))
        (set-window-parameter window '+my/smooth-limit
                              (cons (window-start window) (window-vscroll window t)))))))

(add-hook 'pre-redisplay-functions #'+my/smooth--limit-h)

;; THE MINIBUFFER
;; The echo area / minibuffer window always fits what it shows, so scrolling it
;; only made it jump and come back. The wheel leaves it alone; with a
;; completion list open (vertico), it moves through the candidates instead,
;; about one per line scrolled.
(defvar +my/smooth--minibuffer-pixels 0
  "Wheel pixels over the minibuffer not yet worth a candidate.")

(defun +my/smooth--minibuffer-wheel (event)
  "If wheel EVENT is over a minibuffer window, handle it there and return
non-nil (see above)."
  (let ((window (mwheel-event-window event)))
    (when (window-minibuffer-p window)
      (let* ((pixels (and (consp (nth 4 event)) (cdr (nth 4 event))))
             (delta (round (or pixels ; negative: down
                               (* (or (nth 3 event) 1) (frame-char-height)
                                  (if (memq (event-basic-type event) '(wheel-down mouse-5))
                                      -1 1))))))
        (when (and (eq window (active-minibuffer-window))
                   (memq (event-basic-type event) '(wheel-up wheel-down mouse-4 mouse-5))
                   (bound-and-true-p vertico-mode)
                   (buffer-local-value 'vertico--input (window-buffer window)))
          (setq +my/smooth--minibuffer-pixels (+ +my/smooth--minibuffer-pixels delta))
          (let ((lines (truncate +my/smooth--minibuffer-pixels (frame-char-height))))
            (unless (zerop lines)
              (setq +my/smooth--minibuffer-pixels
                    (- +my/smooth--minibuffer-pixels (* lines (frame-char-height))))
              (with-selected-window window
                (if (< lines 0)
                    (vertico-next (- lines))
                  (vertico-previous lines)))))))
      t)))

;; In an open minibuffer the wheel runs `mwheel-scroll' (elsewhere ultra-scroll).
(defadvice! +my/smooth-minibuffer-wheel-a (fn event &optional arg)
  :around #'mwheel-scroll
  (unless (+my/smooth--minibuffer-wheel event)
    (funcall fn event arg)))

(after! ultra-scroll
  ;; Doom's module pauses hl-todo during scrolls (`ultra-scroll-hide-functions'),
  ;; so TODO/NOTE/FIXME lost their highlight while scrolling and got it back
  ;; when it stopped: they flickered. Keep them on.
  (remove-hook 'ultra-scroll-hide-functions #'hl-todo-mode)

  (defadvice! +my/smooth-scroll-glide-a (fn event &optional arg)
    "Spread big wheel steps (mouse wheels) over a few frames; see above for the
minibuffer."
    :around #'ultra-scroll
    (let ((delta (and (consp (nth 4 event)) (round (cdr (nth 4 event))))))
      (cond
       ((+my/smooth--minibuffer-wheel event))
       ((not (and delta (> (abs delta) +my/smooth-scroll-min-step)))
        (funcall fn event arg))
       (t
        (let ((window (mwheel-event-window event)))
          ;; Another window, or the other way: drop the rest of the glide.
          (when (or (not (eq window +my/smooth--window))
                    (< (* delta +my/smooth--remaining) 0))
            (+my/smooth--stop))
          (ultra-scroll--prepare-to-scroll window)
          (setq +my/smooth--window window
                +my/smooth--remaining (+ +my/smooth--remaining delta))
          (unless +my/smooth--timer
            (+my/smooth--frame)         ; the first frame right away
            (setq +my/smooth--timer
                  (run-at-time +my/smooth-scroll-frame +my/smooth-scroll-frame
                               #'+my/smooth--frame)))))))))
