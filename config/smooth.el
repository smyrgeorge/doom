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

(after! ultra-scroll
  ;; Doom's module pauses hl-todo during scrolls (`ultra-scroll-hide-functions'),
  ;; so TODO/NOTE/FIXME lost their highlight while scrolling and got it back
  ;; when it stopped: they flickered. Keep them on.
  (remove-hook 'ultra-scroll-hide-functions #'hl-todo-mode)

  (defadvice! +my/smooth-scroll-glide-a (fn event &optional arg)
    "Spread big wheel steps (mouse wheels) over a few frames."
    :around #'ultra-scroll
    (let ((delta (and (consp (nth 4 event)) (round (cdr (nth 4 event))))))
      (if (not (and delta (> (abs delta) +my/smooth-scroll-min-step)))
          (funcall fn event arg)
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
                               #'+my/smooth--frame))))))))
