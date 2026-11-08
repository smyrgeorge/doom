;;; $DOOMDIR/config/image/commands.el -*- lexical-binding: t; -*-
;; Zoom, fit, smoothing, animation, copying, Preview and Finder. Loaded from
;; config/image.el.

(defvar image-transform-resize)
(defvar image--transform-smoothing)

(defun +my/image--redisplay ()
  "Show the image anew: its zoom, smoothing or bytes changed."
  (let ((inhibit-read-only t))
    (image-toggle-display-image))
  (force-mode-line-update))

;; ZOOM
(defvar-local +my/image--zoom-target nil
  "The zoom asked for, not shown yet (a wheel's events gathered).")

(defvar-local +my/image--zoom-timer nil)

(defun +my/image--zoom-apply (buffer)
  "Show BUFFER's image at the zoom asked for."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq +my/image--zoom-timer nil)
      (when-let* ((scale +my/image--zoom-target))
        (setq +my/image--zoom-target nil
              image-transform-resize scale)
        (+my/image--redisplay)))))

(defun +my/image--zoom-to (scale &optional later)
  "Zoom to SCALE (1.0: the image's actual size), within
`+my/image-zoom-limits'. LATER: once the events coming fast (a wheel, a
pinch) pause, not drawn at each."
  (let ((scale (min (cdr +my/image-zoom-limits) (max (car +my/image-zoom-limits) scale))))
    ;; Back at 100% exactly after zooming in and out again.
    (setq +my/image--zoom-target (if (< (abs (- scale 1.0)) 0.01) 1.0 scale)))
  (if later
      (unless (timerp +my/image--zoom-timer)
        (setq +my/image--zoom-timer
              (run-with-timer 0.05 nil #'+my/image--zoom-apply (current-buffer))))
    (+my/image--zoom-apply (current-buffer)))
  (force-mode-line-update))

(defun +my/image--zoom (factor &optional later)
  (+my/image--zoom-to (* (or +my/image--zoom-target (+my/image-scale) 1.0) factor) later))

(defun +my/image-zoom-in ()
  "+, Cmd+=: zoom in (by `+my/image-zoom-step')."
  (interactive)
  (+my/image--zoom +my/image-zoom-step))

(defun +my/image-zoom-out ()
  "-, Cmd+-: zoom out (by `+my/image-zoom-step')."
  (interactive)
  (+my/image--zoom (/ 1.0 +my/image-zoom-step)))

(defun +my/image--mouse-window (event)
  (let ((window (posn-window (event-start event))))
    (if (window-live-p window) window (selected-window))))

(defun +my/image-zoom-in-mouse (event)
  "Cmd+scroll (Ctrl+scroll): zoom in, the image under the pointer."
  (interactive "e")
  (with-selected-window (+my/image--mouse-window event)
    (+my/image--zoom 1.1 t)))

(defun +my/image-zoom-out-mouse (event)
  "Cmd+scroll (Ctrl+scroll): zoom out, the image under the pointer."
  (interactive "e")
  (with-selected-window (+my/image--mouse-window event)
    (+my/image--zoom (/ 1.0 1.1) t)))

(defvar-local +my/image--pinch-start nil
  "The zoom as the pinch began: its events' scale is from there.")

(defun +my/image-pinch (event)
  "A trackpad's pinch: zoom, the image under the fingers."
  (interactive "e")
  (with-selected-window (+my/image--mouse-window event)
    ;; Its first event moved nothing yet (as `text-scale-pinch' tells).
    (when (or (null +my/image--pinch-start)
              (and (zerop (nth 2 event)) (zerop (nth 3 event)) (zerop (nth 5 event))))
      (setq +my/image--pinch-start (or (+my/image-scale) 1.0)))
    (+my/image--zoom-to (* +my/image--pinch-start (nth 4 event)) t)))

(defun +my/image-fit ()
  "W: fit the window, scaled up or down."
  (interactive)
  (setq +my/image--zoom-target nil
        image-transform-resize 'fit-window)
  (+my/image--redisplay))

(defun +my/image-actual-size ()
  "0, Cmd+0: the image at its actual size (1:1)."
  (interactive)
  (setq +my/image--zoom-target nil
        image-transform-resize nil)
  (+my/image--redisplay))

;; SHARP PIXELS
(defun +my/image--sharp-p ()
  (equal image--transform-smoothing "none"))

(defun +my/image-toggle-sharp ()
  "SPC m s: no smoothing (pixels stay square zoomed in), or smoothing again;
the next images as this one."
  (interactive)
  (setq +my/image-sharp (not (+my/image--sharp-p))
        image--transform-smoothing (and +my/image-sharp "none"))
  (+my/image--redisplay)
  (message "Sharp pixels %s" (if +my/image-sharp "on" "off")))

;; ANIMATION
(defun +my/image-playing-p ()
  "Non-nil while the image's animation plays."
  (when-let* ((spec (+my/image--spec)))
    (image-animate-timer spec)))

(defun +my/image-toggle-animation ()
  "RET: play or pause the image's animation."
  (interactive)
  (unless image-multi-frame
    (user-error "Not an animation"))
  (image-toggle-animation)
  (force-mode-line-update))

;; COPYING
(defun +my/image--to-clipboard (file class)
  "FILE's bytes on macOS's clipboard as an image of CLASS (AppleScript's:
PNGf, JPEG)."
  (with-temp-buffer
    (unless (zerop (call-process
                    "osascript" nil t nil
                    "-e" "on run argv"
                    "-e" (format "set the clipboard to (read (POSIX file (item 1 of argv)) as «class %s»)"
                                 class)
                    "-e" "end run"
                    file))
      (user-error "Couldn't copy the image: %s" (string-trim (buffer-string))))))

(defun +my/image--png (from to)
  "Make PNG TO from image FROM: with macOS's sips, or ImageMagick for what
sips can't read (SVG)."
  (unless (or (and (zerop (call-process "sips" nil nil nil "-s" "format" "png" from "--out" to))
                   (file-exists-p to))
              (and (executable-find "magick")
                   (zerop (call-process "magick" nil nil nil from (concat "png:" to)))
                   (file-exists-p to)))
    (user-error "Couldn't make a PNG of the image to copy")))

(defun +my/image-copy ()
  "y, Cmd+C: the image itself to the clipboard, as shown (edited too), to
paste in other apps; a PNG unless it's one or a JPEG."
  (interactive)
  (unless (+my/image--spec)
    (user-error "No image shown"))
  (let ((dir (make-temp-file "image-copy-" t)))
    (unwind-protect
        (let ((file (+my/image--file dir)))
          (pcase image-type
            ('png (+my/image--to-clipboard file "PNGf"))
            ('jpeg (+my/image--to-clipboard file "JPEG"))
            (_ (let ((png (expand-file-name "copy.png" dir)))
                 (+my/image--png file png)
                 (+my/image--to-clipboard png "PNGf"))))
          (message "Copied the image"))
      (delete-directory dir t))))

(defun +my/image-copy-path ()
  "SPC m y: the image's path to the clipboard (the kill ring)."
  (interactive)
  (unless buffer-file-name
    (user-error "Not a file"))
  (kill-new buffer-file-name)
  (message "Copied %s" (abbreviate-file-name buffer-file-name)))

;; OTHER APPS
(defun +my/image--saved-file ()
  "The image's file, for other apps: they read what's saved."
  (unless buffer-file-name
    (user-error "Not a file"))
  (when (buffer-modified-p)
    (message "Not saved: the file as it was"))
  (expand-file-name buffer-file-name))

(defun +my/image-open-in-preview ()
  "SPC m p: the image in macOS's Preview (to annotate, export...)."
  (interactive)
  (call-process "open" nil 0 nil "-a" "Preview" (+my/image--saved-file)))

(defun +my/image-show-in-finder ()
  "SPC m f: the image selected in a Finder window."
  (interactive)
  (call-process "open" nil 0 nil "-R" (+my/image--saved-file)))
