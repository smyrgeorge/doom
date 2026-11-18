;;; $DOOMDIR/config/image/edit.el -*- lexical-binding: t; -*-
;; Rotating, flipping, cropping: the image changed, as Preview does, saved as
;; any file. Loaded from config/image.el.

(defvar image-transform-rotation)
(defvar image-crop-crop-command)

(defconst +my/image--editable-types '(png jpeg gif tiff bmp heic)
  "Image types sips (macOS) and ImageMagick (Linux) write: what rotating,
flipping and cropping change.")

(defun +my/image--editable-kind-p ()
  "Non-nil if the image is one rotating, flipping and cropping change: one
sips or ImageMagick writes (not an SVG: text), not an animation (one frame
would be left), not read-only."
  (and (memq image-type +my/image--editable-types)
       (not image-multi-frame)
       (not buffer-read-only)))

(defun +my/image--editable-p ()
  "Non-nil if rotating, flipping and cropping can change the image now: one
they change (`+my/image--editable-kind-p'), not while git's HEAD is shown
in its place (TAB, diff.el)."
  (and (+my/image--editable-kind-p)
       (not (eq (+my/image--head-view) 'head))))

(defun +my/image--check-editable ()
  (unless (+my/image--editable-p)
    (user-error (cond ((eq (+my/image--head-view) 'head)
                       "Git's HEAD is shown: TAB for the image, to change it")
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

(defun +my/image--transform (transform)
  "Change the image by TRANSFORM (config/emacs/os.el's `+my/os-image-transform':
sips on macOS, ImageMagick on Linux), as done to a file (see
config/image.el)."
  (+my/image--check-editable)
  (let ((dir (make-temp-file "image-edit-" t)))
    (unwind-protect
        (let ((file (expand-file-name (concat "image." (+my/image--extension)) dir)))
          (+my/image--write file)
          (+my/os-image-transform file transform)
          (+my/image--replace file))
      (delete-directory dir t))))

(defun +my/image-rotate ()
  "r: rotate the image clockwise (changes it: see config/image.el)."
  (interactive)
  (+my/image--transform 'rotate-right))

(defun +my/image-rotate-left ()
  "R: rotate the image anticlockwise (changes it)."
  (interactive)
  (+my/image--transform 'rotate-left))

(defun +my/image-flip ()
  "f: flip the image horizontally (changes it)."
  (interactive)
  (+my/image--transform 'flip-horizontal))

(defun +my/image-flip-vertically ()
  "F: flip the image vertically (changes it)."
  (interactive)
  (+my/image--transform 'flip-vertical))

(defun +my/image-crop ()
  "c: crop the image, with Emacs's image-crop: drag a rectangle, RET crops, q
cancels (changes it). The diff (SPC m g) closed first: crop the image, not
HEAD beside it."
  (interactive)
  (+my/image--check-editable)
  (require 'image-crop)
  (unless (executable-find (car image-crop-crop-command))
    (user-error "Cropping needs ImageMagick's %s (%s)"
                (car image-crop-crop-command)
                (if (+my/macos-p) "brew install imagemagick" "your distribution's imagemagick package")))
  (+my/image--close-head)
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
