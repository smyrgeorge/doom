;;; $DOOMDIR/config/banner/header.el -*- lexical-binding: t; -*-
;; Room for the notices in the header line. Loaded from config/banner.el.

;;; Room in the header line

(defun +my/banner--row-height (&optional window)
  "The height of a notice's row in WINDOW: a line of the header line's font."
  (or (ignore-errors (window-font-height window 'header-line))
      (frame-char-height (window-frame window))))

(defun +my/banner--descent (&optional window)
  "The descent of the header line's font in WINDOW."
  (or (ignore-errors
        (aref (font-info (face-font 'header-line (window-frame window) ?a)
                         (window-frame window))
              9))
      0))

(defvar +my/banner--spacers (make-hash-table :test #'equal))

(defun +my/banner--spacer (rows alone)
  "An invisible image, a pixel wide and tall enough for ROWS notice rows above
the header line's text (none if ALONE), sitting on its baseline: it makes the
header line that much taller, its text in the bottom row."
  (let* ((row (+my/banner--row-height))
         (height (if alone
                     (max 1 (- (* rows row) (+my/banner--descent)))
                   (+ (* rows row) (- row (+my/banner--descent))))))
    (or (gethash height +my/banner--spacers)
        (puthash height
                 (propertize
                  " " 'display
                  (create-image
                   (concat "/* XPM */ static char *s[] = {\"1 " (number-to-string height)
                           " 1 1\", \". c None\","
                           (mapconcat (lambda (_) "\".\"") (number-sequence 1 height) ",")
                           "};")
                   'xpm t :ascent 100))
                 +my/banner--spacers))))

(defun +my/banner--header-line ()
  "Before the header line's own content: room for the notices (in a terminal,
the first one, which takes the whole row)."
  (when +my/banner--list
    (if (display-graphic-p)
        (+my/banner--spacer (length +my/banner--list) (null +my/banner--saved-header))
      (+my/banner--row (car +my/banner--list) (current-buffer) t
                       (length (cdr +my/banner--list))
                       (window-body-width (selected-window))))))
