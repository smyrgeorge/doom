;;; $DOOMDIR/config/image/difference.el -*- lexical-binding: t; -*-
;; The pixels changed since git's HEAD, highlighted (D). Loaded from
;; config/image.el, after diff.el.

(defvar image-type)

;; THE CHANGED PIXELS
;; D, with the diff shown or not, shows one image in the image's place (as
;; TAB shows HEAD there, diff.el's IN ITS PLACE): the pixels changed since
;; HEAD in red over a faded copy of the image, at its zoom; the toolbar says
;; how many. Made by ImageMagick, in the background (compare draws it, and a
;; difference of the two, each pixel changed or not, counts them: compare's
;; own count weighs the colour channels), once per HEAD commit and change of
;; the image: the result's bytes kept in the buffer, its files removed at
;; once. Two images of different sizes are both extended to the bigger
;; (transparent), the room added counting as changed; an animation's first
;; frames are compared, an SVG as ImageMagick draws it.
(defvar-local +my/image--difference nil
  "The changed pixels, as last compared (see THE CHANGED PIXELS): a plist,
:key what was compared (HEAD's commit, the image's change, the fuzz),
:process while comparing, :dir its files, :bytes the difference image,
:count the pixels changed, :total all of them, :sizes (IMAGE . HEAD) when
they differ, :error what failed.")

(defun +my/image--compare-programs ()
  "(CONVERT COMPARE): ImageMagick's commands, as lists: magick and magick
compare (7), else convert and compare (6); nil without it."
  (let ((magick (executable-find "magick")))
    (cond (magick (list (list magick) (list magick "compare")))
          ((and (executable-find "convert") (executable-find "compare"))
           (list (list (executable-find "convert")) (list (executable-find "compare")))))))

(defun +my/image--difference-key ()
  (list (plist-get +my/image--head :commit) (buffer-chars-modified-tick) +my/image-diff-fuzz))

(defun +my/image--difference-stop ()
  "Stop comparing: forgotten first (its sentinel, run as it's killed, then
keeps nothing), its process killed, its files removed. Done, kept."
  (let ((process (plist-get +my/image--difference :process))
        (dir (plist-get +my/image--difference :dir)))
    (when (or process dir)
      (setq +my/image--difference nil)
      (when (process-live-p process)
        (delete-process process))
      (when dir
        (ignore-errors (delete-directory dir t))))))

(defun +my/image--lowlight ()
  "The unchanged pixels' veil: the theme's background, mostly opaque."
  (pcase-let ((`(,r ,g ,b) (or (color-name-to-rgb (or (face-background 'default nil t) "black"))
                               '(0 0 0))))
    (format "rgba(%d,%d,%d,0.8)" (round (* 255 r)) (round (* 255 g)) (round (* 255 b)))))

(defun +my/image--compare-script (head own size)
  "The shell commands comparing files HEAD and OWN (their first frames),
both extended to SIZE (WIDTH . HEIGHT) first if given: compare's drawing to
diff.png, then the count of the pixels changed on stdout."
  (pcase-let* ((`(,convert ,compare) (+my/image--compare-programs))
               (q (lambda (args) (mapconcat #'shell-quote-argument args " ")))
               (fuzz (format "%s%%" +my/image-diff-fuzz))
               (a (concat head "[0]"))
               (b (concat own "[0]")))
    (concat
     (when size
       (let ((extent (format "%dx%d" (car size) (cdr size))))
         (prog1 (concat (funcall q `(,@convert ,a "-background" "none" "-gravity" "NorthWest"
                                              "-extent" ,extent "head-x.png"))
                        " && "
                        (funcall q `(,@convert ,b "-background" "none" "-gravity" "NorthWest"
                                              "-extent" ,extent "own-x.png"))
                        " && ")
           (setq a "head-x.png" b "own-x.png"))))
     ;; compare: 0 the same, 1 different, 2 failed.
     "{ " (funcall q `(,@compare "-metric" "AE" "-fuzz" ,fuzz "-highlight-color" "red"
                                 "-lowlight-color" ,(+my/image--lowlight) ,a ,b "diff.png"))
     " 2>/dev/null; [ $? -le 1 ]; } && "
     (funcall q `(,@convert ,a ,b "-compose" "difference" "-composite" "-alpha" "off"
                            "-colorspace" "gray" "-threshold" ,fuzz "-precision" "15"
                            "-format" "%[fx:round(mean*w*h)] %[fx:w*h]" "info:")))))

(defun +my/image--head-extension ()
  "The file name extension of HEAD's image, by its bytes."
  (pcase (image-type-from-data (plist-get +my/image--head :bytes))
    ('jpeg "jpg")
    ('nil (+my/image--extension))
    (type (symbol-name type))))

(defun +my/image--difference-start ()
  "Compare the image with HEAD in the background, unless done (or being
done) for them as they are now (see THE CHANGED PIXELS)."
  (let ((key (+my/image--difference-key)))
    (unless (equal (plist-get +my/image--difference :key) key)
      (+my/image--difference-stop)
      (let* ((buffer (current-buffer))
             (dir (make-temp-file "image-difference-" t))
             (head (expand-file-name (concat "head." (+my/image--head-extension)) dir))
             (own (let ((file (+my/image--file dir)))
                    ;; Its own file: copied, read beside HEAD by name.
                    (if (file-in-directory-p file dir)
                        file
                      (let ((copy (expand-file-name (concat "image." (+my/image--extension)) dir)))
                        (copy-file file copy t)
                        copy))))
             (own-size (+my/image-size))
             (head-size (plist-get +my/image--head :size))
             (size (unless (equal own-size head-size)
                     (cons (max (car own-size) (car head-size))
                           (max (cdr own-size) (cdr head-size))))))
        (let ((coding-system-for-write 'no-conversion)
              (bytes (plist-get +my/image--head :bytes)))
          (with-temp-file head
            (set-buffer-multibyte nil)
            (insert bytes)))
        (let* ((default-directory dir)
               (output (generate-new-buffer " *image-difference*"))
               (process
                (make-process
                 :name "image-difference" :buffer output :noquery t
                 :connection-type 'pipe
                 :command (list "sh" "-c"
                                (+my/image--compare-script (file-name-nondirectory head)
                                                           (file-name-nondirectory own) size))
                 :sentinel (lambda (process _event)
                             (unless (process-live-p process)
                               (+my/image--difference-done buffer process dir))))))
          (setq +my/image--difference
                (list :key key :process process :dir dir
                      :sizes (and size (cons own-size head-size)))))))))

(defun +my/image--difference-done (buffer process dir)
  "PROCESS, comparing in DIR for BUFFER's image, ended: its result kept,
its files removed, the image's place drawn anew."
  (let ((output (process-buffer process)))
    (unwind-protect
        (when (and (buffer-live-p buffer)
                   (eq (plist-get (buffer-local-value '+my/image--difference buffer) :process) process))
          (with-current-buffer buffer
            (let* ((text (with-current-buffer output (buffer-string)))
                   (numbers (and (zerop (process-exit-status process))
                                 (string-match "\\`\\([0-9]+\\) \\([0-9]+\\)" text)
                                 (cons (string-to-number (match-string 1 text))
                                       (string-to-number (match-string 2 text)))))
                   (file (expand-file-name "diff.png" dir)))
              (setq +my/image--difference
                    (plist-put (plist-put +my/image--difference :process nil) :dir nil))
              (if (and numbers (file-exists-p file))
                  (setq +my/image--difference
                        (plist-put (plist-put (plist-put +my/image--difference :count (car numbers))
                                              :total (cdr numbers))
                                   :bytes (with-temp-buffer
                                            (set-buffer-multibyte nil)
                                            (insert-file-contents-literally file)
                                            (buffer-string))))
                (setq +my/image--difference
                      (plist-put +my/image--difference :error
                                 (let ((line (car (split-string (string-trim text) "\n"))))
                                   (if (string-empty-p line) "ImageMagick failed" line)))))
              (when (eq (+my/image--head-view) 'difference)
                (+my/image-center))
              (force-mode-line-update t))))
      (ignore-errors (delete-directory dir t))
      (when (buffer-live-p output)
        (kill-buffer output)))))

(defun +my/image--difference-spec (scale)
  "The difference image at SCALE, once compared; nil until then, or when
nothing changed."
  (when-let* ((bytes (plist-get +my/image--difference :bytes)))
    (and (equal (plist-get +my/image--difference :key) (+my/image--difference-key))
         (> (plist-get +my/image--difference :count) 0)
         (create-image bytes 'png t :scale scale))))

(defun +my/image--difference-text ()
  "What the toolbar says of the changed pixels (see THE CHANGED PIXELS)."
  (let* ((difference +my/image--difference)
         (ready (equal (plist-get difference :key) (+my/image--difference-key)))
         (sizes (plist-get difference :sizes))
         (count (plist-get difference :count))
         (total (plist-get difference :total)))
    (cond ((not ready) "Comparing…")
          ((plist-get difference :process) "Comparing…")
          ((plist-get difference :error) (format "Couldn't compare: %s" (plist-get difference :error)))
          (t (concat (when sizes
                       (format "Sizes differ: %d×%d · HEAD %d×%d · "
                               (car (car sizes)) (cdr (car sizes)) (car (cdr sizes)) (cdr (cdr sizes))))
                     (if (zerop count)
                         "Same pixels as HEAD"
                       (let ((percent (/ (* 100.0 count) (max 1 total))))
                         (format "%d px changed (%s%%)" count
                                 (if (< percent 0.1) (format "%.2f" percent) (format "%.1f" percent))))))))))

(defun +my/image-difference ()
  "D: the pixels changed since git's HEAD, highlighted in the image's place
\(see THE CHANGED PIXELS); again, back to what was shown before (the diff
side by side, or flipping), or the image."
  (interactive)
  (unless (+my/image--compare-programs)
    (user-error "The changed pixels need ImageMagick (%s)"
                (if (+my/macos-p) "brew install imagemagick" "your distribution's imagemagick package")))
  (cond ((eq (+my/image--head-view) 'difference)
         (let ((before (plist-get +my/image--head :before)))
           (if before
               (+my/image--show-view before)
             (+my/image--close-head))))
        ((+my/image--head-shown-p)
         (setq +my/image--head (plist-put +my/image--head :before (+my/image--head-view)))
         (+my/image--show-view 'difference))
        (t (+my/image--open-head 'difference)
           (+my/image--show-view 'difference))))
