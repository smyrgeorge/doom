;;; $DOOMDIR/config/image/files.el -*- lexical-binding: t; -*-
;; The folder's images, the image's size, its bytes. Loaded from
;; config/image.el.

(defvar image-type)
(defvar image-multi-frame)

;; THE IMAGE SHOWN
(defun +my/image--spec ()
  "The image the buffer shows (image-mode's), if it shows one."
  (let ((spec (and (derived-mode-p 'image-mode) (image-get-display-property))))
    (and (eq (car-safe spec) 'image) spec)))

(defvar-local +my/image--size nil
  "(TICK . (WIDTH . HEIGHT)): the image's size, measured at TICK.")

(defun +my/image-size ()
  "The image's size in pixels: its own, not as shown. Measured once per change
of its bytes (the toolbar asks at each redisplay)."
  (when-let* ((spec (+my/image--spec)))
    (let ((tick (buffer-chars-modified-tick)))
      (unless (eql (car +my/image--size) tick)
        (let* ((plist (cdr spec))
               (natural `(image :type ,(plist-get plist :type)
                                ,@(if (plist-get plist :file)
                                      (list :file (plist-get plist :file))
                                    (list :data (plist-get plist :data)))
                                :scale 1)))
          (setq +my/image--size (cons tick (image-size natural t)))
          ;; Not kept: a big photo decoded at its full size, besides as shown.
          (image-flush natural)))
      (cdr +my/image--size))))

(defun +my/image-scale ()
  "How big the image is shown: 1.0 at its actual size."
  (when-let* ((spec (+my/image--spec))
              (size (+my/image-size))
              ((> (car size) 0)))
    (let ((shown (car (image-size spec t)))
          (sideways (= 90 (mod (round (or (image-property spec :rotation) 0)) 180))))
      (/ (float shown) (if sideways (cdr size) (car size))))))

(defun +my/image--bytes ()
  "The image's size in bytes: its file's, or the buffer's once edited."
  (if (and buffer-file-name (not (buffer-modified-p)) (file-exists-p buffer-file-name))
      (file-attribute-size (file-attributes buffer-file-name))
    (buffer-size)))

(defun +my/image-info ()
  "The image's size in pixels, type (frames) and file size, as the toolbar
shows them: \"1600×900 · PNG · 412 kB\"."
  (let ((size (+my/image-size))
        (frames (and image-multi-frame (car-safe (image-multi-frame-p (+my/image--spec))))))
    (string-join (delq nil (list (and size (format "%d×%d" (car size) (cdr size)))
                                 (and image-type (upcase (symbol-name image-type)))
                                 (and frames (format "%d frames" frames))
                                 (file-size-human-readable (+my/image--bytes) 'si " " "B")))
                 " · ")))

;; ITS BYTES
(defun +my/image--extension ()
  "The image's file name extension, by its type."
  (pcase image-type
    ('jpeg "jpg")
    ('nil (or (and buffer-file-name (file-name-extension buffer-file-name)) "png"))
    (type (symbol-name type))))

(defun +my/image--write (file)
  "Write the buffer's bytes (the image, edited or not) to FILE."
  (let ((coding-system-for-write (if enable-multibyte-characters
                                     buffer-file-coding-system
                                   'no-conversion)))
    (write-region (point-min) (point-max) file nil 'silent)))

(defun +my/image--file (dir)
  "A file of the image as shown: its own, unless edited (or not a file: git's
HEAD), then its bytes written to DIR."
  (if (and buffer-file-name (not (buffer-modified-p)) (file-readable-p buffer-file-name))
      buffer-file-name
    (let ((file (expand-file-name (concat "image." (+my/image--extension)) dir)))
      (+my/image--write file)
      file)))

;; THE FOLDER'S IMAGES
(defvar-local +my/image--files nil
  "(FOLDER-MTIME . FILES): the folder's images, as listed at FOLDER-MTIME.")

(defun +my/image--folder-images ()
  "The images in the image's folder, by name as people count (img2 before
img10), it among them. Listed again only once the folder changed (the toolbar
asks at each redisplay)."
  (when buffer-file-name
    (let* ((dir (file-name-directory buffer-file-name))
           (mtime (file-attribute-modification-time (file-attributes dir))))
      (unless (and +my/image--files (equal (car +my/image--files) mtime))
        (let ((regexp (image-file-name-regexp))
              (case-fold-search t))
          (setq +my/image--files
                (cons mtime
                      (sort (seq-filter (lambda (file)
                                          (and (string-match-p regexp file)
                                               (file-regular-p file)))
                                        (directory-files dir t "\\`[^.]"))
                            #'string-version-lessp)))))
      (let ((files (cdr +my/image--files)))
        (if (member buffer-file-name files)
            files
          (sort (cons buffer-file-name (copy-sequence files)) #'string-version-lessp))))))

(defun +my/image--position ()
  "(INDEX . COUNT): the image's place among its folder's (from 0)."
  (let ((files (+my/image--folder-images)))
    (cons (or (seq-position files buffer-file-name #'string=) 0) (length files))))

(defun +my/image-next (&optional n)
  "J: the next image in the folder (the Nth), after the last the first, in
the same tab (see config/image.el)."
  (interactive "p")
  (unless buffer-file-name
    (user-error "Not a file"))
  (let* ((files (+my/image--folder-images))
         (count (length files)))
    (when (< count 2)
      (user-error "No other image in %s"
                  (abbreviate-file-name (file-name-directory buffer-file-name))))
    (find-alternate-file
     (nth (mod (+ (car (+my/image--position)) (or n 1)) count) files))))

(defun +my/image-previous (&optional n)
  "K: the previous image in the folder (the Nth), before the first the last."
  (interactive "p")
  (+my/image-next (- (or n 1))))
