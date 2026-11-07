;;; $DOOMDIR/config/pdf/places.el -*- lexical-binding: t; -*-
;; Each PDF's place, kept between sessions. Loaded from config/pdf.el.

;; PLACES
;; Each PDF's place (page, position on it, zoom) when it's closed or Emacs
;; quits, in `+my/pdf-places-file', for the next time it opens.
(defvar +my/pdf--places 'unread
  "The places kept: ((FILE . PLACE)...), the latest first.")

(defun +my/pdf--read-places ()
  "The places kept (see above), read from their file the first time."
  (when (eq +my/pdf--places 'unread)
    (setq +my/pdf--places
          (and (file-readable-p +my/pdf-places-file)
               (ignore-errors
                 (with-temp-buffer
                   (insert-file-contents +my/pdf-places-file)
                   (read (current-buffer)))))))
  +my/pdf--places)

(defun +my/pdf--kept-place ()
  "This PDF's place, from when it was last closed."
  (when buffer-file-name
    (cdr (assoc (abbreviate-file-name buffer-file-name) (+my/pdf--read-places)))))

(defun +my/pdf--keep-place (place)
  "Keep PLACE as this PDF's (see above)."
  (when (and place buffer-file-name)
    (let ((file (abbreviate-file-name buffer-file-name)))
      (setq +my/pdf--places
            (seq-take (cons (cons file place)
                            (seq-remove (lambda (entry) (equal (car entry) file))
                                        (+my/pdf--read-places)))
                      +my/pdf-places-max))
      (ignore-errors
        (make-directory (file-name-directory +my/pdf-places-file) t)
        (let ((print-length nil)
              (print-level nil))
          (with-temp-file +my/pdf-places-file
            (prin1 +my/pdf--places (current-buffer))))))))

(defun +my/pdf--forget-place (file)
  "Forget FILE's place (an example's PDF, deleted once closed)."
  (let ((file (abbreviate-file-name file)))
    (when (assoc file (+my/pdf--read-places))
      (setq +my/pdf--places (seq-remove (lambda (entry) (equal (car entry) file)) +my/pdf--places))
      (ignore-errors
        (let ((print-length nil)
              (print-level nil))
          (with-temp-file +my/pdf-places-file
            (prin1 +my/pdf--places (current-buffer))))))))

(defun +my/pdf--remember ()
  "Keep this page's settings for the next PDF, and its place (see above)."
  (when-let* ((state (+my/pdf--state)))
    (setq +my/pdf-dark-pages (plist-get state :dark)
          +my/pdf-toolbar (plist-get state :toolbar)
          +my/pdf-outline-sidebar (plist-get state :sidebar))
    (+my/pdf--keep-place (plist-get state :place))))
