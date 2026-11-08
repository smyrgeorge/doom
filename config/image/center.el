;;; $DOOMDIR/config/image/center.el -*- lexical-binding: t; -*-
;; The image in the middle of its window. Loaded from config/image.el.

;; CENTERED
;; image-mode draws the image at the window's top left. Smaller than the
;; window, it gets room before it, in each window showing it (a split's panes
;; apart): an overlay's before-string, a line as tall as the room above, then a
;; space as wide as the room on the left. Bigger, none: it scrolls as before.
;; Made again when the image is shown anew (zoom, fit, an edit, a revert) and
;; when its windows change size.
(defvar-local +my/image--centering nil
  "(WINDOW . OVERLAY): the room before the image in each window.")

(defun +my/image--room (window)
  "(LEFT . TOP): the room in pixels around the image in WINDOW, to center it."
  (when-let* ((spec (+my/image--spec)))
    (let ((size (image-display-size spec t (window-frame window))))
      (cons (max 0 (/ (- (window-body-width window t) (car size)) 2))
            (max 0 (/ (- (window-body-height window t) (cdr size)) 2))))))

(defun +my/image--room-string (left top window)
  "The before-string making LEFT and TOP pixels of room (see above): no line
above when TOP is less than one (a line can't be lower than its font)."
  (concat (when (> top (with-selected-window window (default-line-height)))
            (concat (propertize " " 'display `(space :width (0) :height (,top))) "\n"))
          (when (> left 0)
            (propertize " " 'display `(space :width (,left))))))

(defun +my/image-center ()
  "Center the image in each window showing it (see above)."
  (when +my/image-mode
    (let ((windows (get-buffer-window-list nil 'nomini t)))
      ;; Windows no longer showing it: their overlay gone.
      (setq +my/image--centering
            (seq-filter (lambda (entry)
                          (or (memq (car entry) windows)
                              (progn (delete-overlay (cdr entry)) nil)))
                        +my/image--centering))
      (dolist (window windows)
        (pcase-let* ((`(,left . ,top) (or (+my/image--room window) '(0 . 0)))
                     (overlay (or (cdr (assq window +my/image--centering))
                                  (let ((new (make-overlay (point-min) (point-min) nil t)))
                                    (overlay-put new 'window window)
                                    (push (cons window new) +my/image--centering)
                                    new))))
          (move-overlay overlay (point-min) (point-min))
          (overlay-put overlay 'before-string (+my/image--room-string left top window)))))))

(defun +my/image--uncenter ()
  (mapc (lambda (entry) (delete-overlay (cdr entry))) +my/image--centering)
  (setq +my/image--centering nil))

(defun +my/image--center-a (&rest _)
  "After image-mode shows the image anew (zoom, fit, its own refit on a
resize, a revert): centered again."
  (when (bound-and-true-p +my/image-mode)
    (+my/image-center)))

(advice-add 'image-toggle-display-image :after #'+my/image--center-a)

(defun +my/image--center-h (window-or-frame)
  "Its windows resized, shown elsewhere: centered again."
  (with-current-buffer (if (windowp window-or-frame) (window-buffer window-or-frame) (current-buffer))
    (+my/image-center)))
