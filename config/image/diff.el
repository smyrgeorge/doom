;;; $DOOMDIR/config/image/diff.el -*- lexical-binding: t; -*-
;; The image as it is in git's HEAD, beside it in its own buffer. Loaded from
;; config/image.el.

(defvar image-transform-resize)
(defvar image-transform-rotation)

(defface +my/image-diff-caption '((t :inherit shadow))
  "The caption over the image in the diff (SPC m g).")

(defface +my/image-diff-caption-head '((t :inherit font-lock-keyword-face))
  "The caption over git's HEAD in the diff (SPC m g).")

(defconst +my/image--diff-gap 16
  "The room between HEAD and the image side by side, in pixels.")

(defvar-local +my/image--head nil
  "Git's HEAD of the image while the diff (SPC m g) is shown: a plist, :bytes
its bytes, :commit HEAD's commit (short), :size its size in pixels, :spec its
image as drawn now.")

(defun +my/image--git (dir &rest args)
  "git ARGS's output in DIR, as bytes; nil if it failed."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (let ((default-directory dir)
          (coding-system-for-read 'binary))
      (and (zerop (apply #'call-process "git" nil '(t nil) nil args))
           (buffer-string)))))

(defun +my/image--head-shown-p ()
  "Non-nil while the diff (SPC m g) is shown: git's HEAD beside the image."
  (and +my/image--head t))

;; BESIDE THE IMAGE
;; image-mode shows one image, the buffer's text: HEAD's is drawn before it,
;; in the overlay that centers the image in each of its windows (center.el),
;; a caption over each: HEAD on the left, a gap, the image (in a pane
;; narrower than twice `+my/image-diff-min-width', HEAD above it). Both at
;; one scale, so their pixels compare one to one: the image's zoom (1:1, a
;; zoom), or fitted, the scale fitting the bigger of the two into half the
;; pane. image-mode fits its image to the whole window: the image's own
;; drawn again at that scale, after it (and on a resize, image-mode's refit
;; then leaves it alone: nothing to compare with its :max-width).
(defun +my/image--diff-side-p (window)
  "Non-nil if HEAD is beside the image in WINDOW; nil: above it (see
above)."
  (>= (window-total-width window) (* 2 +my/image-diff-min-width)))

(defun +my/image--turned (size)
  "SIZE, (WIDTH . HEIGHT), as drawn by the image's rotation (a JPEG's
orientation): its sides swapped turned a quarter."
  (if (= 90 (mod (round image-transform-rotation) 180))
      (cons (cdr size) (car size))
    size))

(defun +my/image--diff-fit (window)
  "The scale fitting HEAD and the image, both at it, with their captions,
into WINDOW (see BESIDE THE IMAGE)."
  (let* ((head (+my/image--turned (plist-get +my/image--head :size)))
         (own (+my/image--turned (+my/image-size)))
         (width (max (car head) (car own) 1))
         (height (max (cdr head) (cdr own) 1))
         (line (with-selected-window window (default-line-height)))
         (box-width (window-body-width window t))
         (box-height (window-body-height window t)))
    (if (+my/image--diff-side-p window)
        (setq box-width (/ (- box-width +my/image--diff-gap) 2)
              box-height (- box-height line))
      (setq box-height (/ (- box-height (* 2 line)) 2)))
    ;; A pixel less: Emacs rounds a scaled size up.
    (max 0.01 (min (/ (float (1- box-width)) width) (/ (float (1- box-height)) height)))))

(defun +my/image--diff-scale (window)
  "The scale of HEAD and the image in WINDOW: the image's zoom, or fitted
(see BESIDE THE IMAGE)."
  (pcase image-transform-resize
    ((pred numberp) image-transform-resize)
    ('nil 1.0)
    ;; Fitted if bigger: the window's.
    ('t (min 1.0 (+my/image--diff-fit window)))
    (_ (+my/image--diff-fit window))))

(defun +my/image--respec (spec scale)
  "SPEC, an image, drawn at SCALE: its sizes left out."
  `(image ,@(cl-loop for (key value) on (cdr spec) by #'cddr
                     unless (memq key '(:width :height :max-width :max-height :scale))
                     append (list key value))
          :scale ,scale))

(defun +my/image--set-spec (spec)
  "The buffer's image drawn as SPEC, the buffer not modified by it."
  (let ((inhibit-read-only t)
        (buffer-undo-list t)
        (create-lockfiles nil)
        (modified (buffer-modified-p)))
    (put-text-property (point-min) (point-max) 'display spec)
    (restore-buffer-modified-p modified)))

(defun +my/image--diff-layout ()
  "HEAD and the image at one scale (see BESIDE THE IMAGE), for the first
window showing them."
  (when-let* ((window (get-buffer-window nil 'visible))
              (own (+my/image--spec)))
    (let ((scale (+my/image--diff-scale window)))
      ;; Fitted: the image's own at the pair's scale; a zoom's is right.
      (unless (or (null image-transform-resize) (numberp image-transform-resize))
        (let ((new (+my/image--respec own scale)))
          (unless (equal new own)
            (+my/image--set-spec new)
            (setq own new))))
      (let ((head (apply #'create-image (plist-get +my/image--head :bytes) nil t
                         :scale scale
                         ;; As the image's: smoothing (Sharp), rotation.
                         (cl-loop for key in '(:transform-smoothing :rotation)
                                  when (plist-member (cdr own) key)
                                  append (list key (plist-get (cdr own) key))))))
        (unless (equal head (plist-get +my/image--head :spec))
          (setq +my/image--head (plist-put +my/image--head :spec head)))))))

(defun +my/image--diff-captions ()
  "(HEAD-CAPTION . IMAGE-CAPTION): what's over each (see BESIDE THE IMAGE)."
  (cons (propertize (format "HEAD %s" (plist-get +my/image--head :commit))
                    'face '+my/image-diff-caption-head)
        (propertize (if (buffer-modified-p) "Edited" "Working tree")
                    'face '+my/image-diff-caption)))

(defun +my/image--diff-columns (window)
  "(HEAD IMAGE HEAD-CAPTION IMAGE-CAPTION LINE): the sizes in WINDOW of the
two images, (WIDTH . HEIGHT) in pixels, their captions' widths and a line's
height."
  (let ((frame (window-frame window))
        (captions (+my/image--diff-captions)))
    (list (image-display-size (plist-get +my/image--head :spec) t frame)
          (image-display-size (+my/image--spec) t frame)
          (string-pixel-width (car captions))
          (string-pixel-width (cdr captions))
          (with-selected-window window (default-line-height)))))

(defun +my/image--diff-size (window)
  "(WIDTH . HEIGHT): the diff's size in WINDOW in pixels: HEAD, the image
and their captions."
  (pcase-let* ((`(,head ,own ,head-caption ,own-caption ,line) (+my/image--diff-columns window))
               (left (max (car head) head-caption))
               (right (max (car own) own-caption)))
    (if (+my/image--diff-side-p window)
        (cons (+ left +my/image--diff-gap right) (+ line (max (cdr head) (cdr own))))
      (cons (max left right) (+ line (cdr head) line (cdr own))))))

(defun +my/image--space (width)
  "A space WIDTH pixels wide (none if less than one)."
  (if (> width 0) (propertize " " 'display `(space :width (,width))) ""))

(defun +my/image--diff-string (window left top)
  "The overlay's before-string drawing the diff in WINDOW: LEFT and TOP
pixels of room (center.el), the captions, HEAD, then room up to where the
buffer's image goes (see BESIDE THE IMAGE)."
  (pcase-let* ((`(,head ,_ ,head-caption ,_ ,_) (+my/image--diff-columns window))
               (`(,head-text . ,own-text) (+my/image--diff-captions))
               (column (+ (max (car head) head-caption) +my/image--diff-gap))
               (image (propertize " " 'display (plist-get +my/image--head :spec)))
               (indent (+my/image--space left)))
    (concat (+my/image--room-string 0 top window)
            (if (+my/image--diff-side-p window)
                (concat indent head-text (+my/image--space (- column head-caption)) own-text "\n"
                        indent image (+my/image--space (- column (car head))))
              (concat indent head-text "\n"
                      indent image "\n"
                      indent own-text "\n"
                      indent)))))

;; OPENED, CLOSED
(defun +my/image--close-head ()
  "Close the diff: HEAD gone, the image as before, fitted to its whole pane
at once."
  (when +my/image--head
    (setq +my/image--head nil)
    (when (+my/image--spec)
      (+my/image--redisplay))
    (force-mode-line-update t)))

(defun +my/image-quit ()
  "q: close the diff (SPC m g) if it's shown, else the image."
  (interactive)
  (if (+my/image--head-shown-p)
      (+my/image--close-head)
    (kill-current-buffer)))

(defun +my/image--same-bytes-p (bytes)
  "Non-nil if BYTES are the image's, as saved."
  (and (not (buffer-modified-p))
       (let ((file buffer-file-name))
         (with-temp-buffer
           (set-buffer-multibyte nil)
           (insert-file-contents-literally file)
           (string= (buffer-string) bytes)))))

(defun +my/image--head-size (bytes)
  "The size in pixels of the image BYTES are."
  (let ((spec (create-image bytes nil t :scale 1)))
    (prog1 (image-size spec t)
      ;; Not kept: decoded at its full size, besides as shown.
      (image-flush spec))))

(defun +my/image-diff ()
  "SPC m g: the image as it is in git's HEAD beside it, in its own pane, at
its zoom, to compare; again, closed (see config/image.el)."
  (interactive)
  (unless buffer-file-name
    (user-error "Not a file"))
  (if (+my/image--head-shown-p)
      (+my/image--close-head)
    (let* ((file buffer-file-name)
           (root (when-let* ((out (+my/image--git (file-name-directory file)
                                                  "rev-parse" "--show-toplevel")))
                   (file-name-as-directory (file-truename (string-trim out)))))
           (path (and root (file-relative-name (file-truename file) root)))
           (bytes (and path (+my/image--git root "show" (concat "HEAD:" path))))
           (commit (and bytes (string-trim (+my/image--git root "rev-parse" "--short" "HEAD")))))
      (cond ((not root) (user-error "Not in a git repository"))
            ((not bytes) (user-error "%s isn't in git's HEAD" path))
            ((+my/image--same-bytes-p bytes) (user-error "No change since HEAD (%s)" commit)))
      (setq +my/image--head (list :bytes bytes :commit commit :size (+my/image--head-size bytes)))
      ;; A wheel's zoom not drawn yet: drawn with it.
      (when +my/image--zoom-target
        (setq image-transform-resize +my/image--zoom-target
              +my/image--zoom-target nil))
      (+my/image--redisplay)
      (force-mode-line-update t))))
