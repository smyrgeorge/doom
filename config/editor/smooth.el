;;; $DOOMDIR/config/editor/smooth.el -*- lexical-binding: t; -*-
;; Smooth mouse-wheel scrolling, and the line you're on kept whole.
;; Loaded from config/editor.el.

(defvar +my/smooth--window nil "The window gliding.")

(defvar +my/smooth--remaining 0 "Pixels left to scroll (negative: down).")

(defvar +my/smooth--last 0 "When the last frame was (`float-time').")

(defvar +my/smooth--timer nil)

(defun +my/smooth--stop ()
  (when (timerp +my/smooth--timer)
    (cancel-timer +my/smooth--timer))
  (setq +my/smooth--timer nil
        +my/smooth--remaining 0))

(defun +my/smooth--frame ()
  "Scroll the share of what's left that's due since the last frame."
  (let ((window +my/smooth--window))
    (if (or (not (window-live-p window))
            (zerop +my/smooth--remaining))
        (+my/smooth--stop)
      (let* ((now (float-time))
             (share (- 1 (exp (/ (- +my/smooth--last now)
                                 +my/smooth-scroll-time-constant))))
             (step (round (* +my/smooth--remaining share))))
        (setq +my/smooth--last now)
        ;; The last few pixels in one go (no crawl at the end), and at least
        ;; one each frame.
        (when (< (abs (- +my/smooth--remaining step)) 4)
          (setq step +my/smooth--remaining))
        (when (zerop step)
          (setq step (if (> +my/smooth--remaining 0) 1 -1)))
        (setq +my/smooth--remaining (- +my/smooth--remaining step))
        (condition-case nil
            (ultra-scroll--scroll step window)
          (error (+my/smooth--stop)))))))

(defun +my/smooth--glide (window delta)
  "Add DELTA pixels to WINDOW's glide, or start one."
  ;; Another window, or the other way: drop the rest of the glide.
  (when (or (not (eq window +my/smooth--window))
            (< (* delta +my/smooth--remaining) 0))
    (+my/smooth--stop))
  (ultra-scroll--prepare-to-scroll window)
  (setq +my/smooth--window window
        +my/smooth--remaining (+ +my/smooth--remaining delta))
  (unless +my/smooth--timer
    ;; From rest: the first frame right away, as if one had just passed.
    (setq +my/smooth--last (- (float-time) +my/smooth-scroll-frame))
    (+my/smooth--frame)
    (setq +my/smooth--timer
          (run-at-time +my/smooth-scroll-frame +my/smooth-scroll-frame
                       #'+my/smooth--frame))))

;; NOTHING HEAVY MID-GLIDE
;; A glide runs from a timer, so meanwhile Emacs counts as idle: gcmh's garbage
;; collection when idle (~80 ms with this heap) or treemacs' refresh after a
;; git change (~130 ms) could start in the middle of one and freeze it for a
;; few frames. They wait until the glide ends.
(defun +my/smooth--after-glide-a (fn &rest args)
  "Run FN now, or once the glide in progress ends."
  (if (timerp +my/smooth--timer)
      (run-at-time 0.1 nil (lambda () (apply #'+my/smooth--after-glide-a fn args)))
    (apply fn args)))

(advice-add 'gcmh-idle-garbage-collect :around #'+my/smooth--after-glide-a)
(advice-add '+my/treemacs-refresh-all :around #'+my/smooth--after-glide-a)

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

;; THE LINE YOU'RE ON, WHOLE
;; Smooth scrolling (ultra-scroll, through pixel-scroll-precision-mode) turns
;; `make-cursor-line-fully-visible' off everywhere: otherwise redisplay undoes a
;; scroll that leaves the cursor's line cut by the window's edge (Emacs's
;; bug#65214), and slows down while scrolling (ultra-scroll's #32). But then a
;; cut line counts as shown: typing at a window's bottom (Claude Code's prompt
;; is always there) went on in the sliver of a row the window doesn't fit, and
;; Emacs scrolled only as far as that sliver, line after line. Now redisplay
;; shows the cursor's line whole again in the selected window after anything
;; but a scroll; a scroll (the wheel, the trackpad, a glide, C-d, C-e...)
;; still leaves it cut, and other windows aren't moved under it.
(defun +my/smooth--scroll-command-p (command)
  "Non-nil if COMMAND scrolls: the wheel, the trackpad, C-d, C-e..."
  (and command (symbolp command)
       (string-match-p "scroll" (symbol-name command))))

(defun +my/smooth-cursor-line-whole-p (window)
  "Non-nil if redisplay should scroll WINDOW to show the cursor's line whole
\(`make-cursor-line-fully-visible'): the selected window, after anything but a
scroll (see above). Between commands (a timer, a process's output), the last
command decides."
  (and (eq window (selected-window))
       (not (+my/smooth--scroll-command-p (or this-command last-command)))))

(defun +my/smooth-cursor-line-whole-h (&rest _)
  "Once smooth scrolling has turned `make-cursor-line-fully-visible' off."
  (when (or (bound-and-true-p ultra-scroll-mode)
            (bound-and-true-p pixel-scroll-precision-mode))
    (setq-default make-cursor-line-fully-visible #'+my/smooth-cursor-line-whole-p)))

;; ultra-scroll turns it off after pixel-scroll-precision-mode's hook. Already
;; on: the config loaded again.
(add-hook 'pixel-scroll-precision-mode-hook #'+my/smooth-cursor-line-whole-h)
(add-hook 'ultra-scroll-mode-hook #'+my/smooth-cursor-line-whole-h)
(+my/smooth-cursor-line-whole-h)

;; GOOD-SCROLL, ONLY WHEN SCROLLING
;; good-scroll (Doom's +interpolate: it animates keyboard scrolling, C-d, C-v...)
;; runs a timer every 20 ms forever, even with nothing to scroll. Each tick made
;; Emacs redraw, ~50 times a second, and on macOS that took time from
;; everything else (opening a file too); Doom's own docs warn about it. Its
;; timer now runs only while a scroll is animating.
(defun +my/good-scroll-stop-timer ()
  (when (timerp (bound-and-true-p good-scroll--timer))
    (cancel-timer good-scroll--timer))
  (setq good-scroll--timer nil))

(after! good-scroll
  (add-hook 'good-scroll-mode-hook
            (defun +my/good-scroll-idle-h ()
              (when good-scroll-mode (+my/good-scroll-stop-timer))))
  (when good-scroll-mode (+my/good-scroll-stop-timer))

  (defadvice! +my/good-scroll-start-timer-a (&rest _)
    :after #'good-scroll-move
    (when (and good-scroll-mode (not (timerp good-scroll--timer)))
      (setq good-scroll--timer
            (run-at-time 0 good-scroll-render-rate #'good-scroll--render))))

  (defadvice! +my/good-scroll-stop-when-done-a (&rest _)
    :after #'good-scroll--render
    (when (zerop good-scroll-destination)
      (+my/good-scroll-stop-timer))))

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
        (+my/smooth--glide (mwheel-event-window event) delta))))))
