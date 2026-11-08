;;; $DOOMDIR/config/image/edit.el -*- lexical-binding: t; -*-
;; Rotating, flipping, cropping: the image changed, as Preview does, saved as
;; any file. Loaded from config/image.el.

(defvar image-transform-rotation)
(defvar image-crop-crop-command)

(defconst +my/image--editable-types '(png jpeg gif tiff bmp heic)
  "Image types sips can write: what rotating, flipping and cropping change.")

(defvar-local +my/image--head-of nil
  "In the image as it is in git's HEAD (config/image/diff.el): the image's
file.")

(defun +my/image--editable-p ()
  "Non-nil if rotating, flipping and cropping can change the image: one sips
writes (not an SVG: text), not an animation (one frame would be left), not
git's HEAD."
  (and (memq image-type +my/image--editable-types)
       (not image-multi-frame)
       (not buffer-read-only)
       (not +my/image--head-of)))

(defun +my/image--check-editable ()
  (unless (+my/image--editable-p)
    (user-error (cond (+my/image--head-of "Git's HEAD: not to edit")
                      (image-multi-frame "Not an animation: one frame would be left")
                      (buffer-read-only "Read-only")
                      (t (format "Can't change a%s %s image"
                                 (if (memq image-type '(svg xpm)) "n" "")
                                 (upcase (symbol-name (or image-type 'unknown)))))))))

(defun +my/image--replace (file)
  "The buffer's bytes FILE's, the image shown anew: modified, to save."
  (let ((inhibit-read-only t)
        ;; Reverting undoes an edit: the undo list doesn't keep the bytes.
        (buffer-undo-list t))
    (erase-buffer)
    (insert-file-contents-literally file))
  ;; Read again from the new bytes (a JPEG's orientation).
  (setq image-transform-rotation 0.0)
  (+my/image--redisplay))

(defun +my/image--sips (&rest args)
  "Change the image as macOS's sips with ARGS does to a file (see
config/image.el)."
  (+my/image--check-editable)
  (let ((dir (make-temp-file "image-edit-" t)))
    (unwind-protect
        (let ((file (expand-file-name (concat "image." (+my/image--extension)) dir)))
          (+my/image--write file)
          (with-temp-buffer
            (unless (zerop (apply #'call-process "sips" nil t nil (append args (list file))))
              (user-error "sips couldn't change the image: %s" (string-trim (buffer-string)))))
          (+my/image--replace file))
      (delete-directory dir t))))

(defun +my/image-rotate ()
  "r: rotate the image clockwise (changes it: see config/image.el)."
  (interactive)
  (+my/image--sips "-r" "90"))

(defun +my/image-rotate-left ()
  "R: rotate the image anticlockwise (changes it)."
  (interactive)
  (+my/image--sips "-r" "270"))

(defun +my/image-flip ()
  "f: flip the image horizontally (changes it)."
  (interactive)
  (+my/image--sips "-f" "horizontal"))

(defun +my/image-flip-vertically ()
  "F: flip the image vertically (changes it)."
  (interactive)
  (+my/image--sips "-f" "vertical"))

(defun +my/image-crop ()
  "c: crop the image, with Emacs's image-crop: drag a rectangle, RET crops, q
cancels (changes it)."
  (interactive)
  (+my/image--check-editable)
  (require 'image-crop)
  (unless (executable-find (car image-crop-crop-command))
    (user-error "Cropping needs ImageMagick's %s (brew install imagemagick)"
                (car image-crop-crop-command)))
  (let ((tick (buffer-chars-modified-tick)))
    (goto-char (point-min))
    (image-crop)
    ;; The cropped image's bytes are the buffer's (image-mode's
    ;; `image-crop-buffer-text-function'), shown as image-crop has it: as
    ;; image-mode does instead (fitted, zoomed).
    (unless (= tick (buffer-chars-modified-tick))
      (setq image-transform-rotation 0.0)
      (+my/image--redisplay))))

(defun +my/image-save ()
  "The toolbar's Save: the edited image to its file."
  (interactive)
  (save-buffer))
