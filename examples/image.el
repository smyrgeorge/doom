;;; $DOOMDIR/examples/image.el -*- lexical-binding: t; -*-
;; Example: the image viewer (config/image.el, docs/images.md). M-x
;; +my/example-image makes a Git repository in the temp folder with a picture,
;; landscape.png (mountains, a sun, a lake), committed by day and then changed
;; to a sunset, two smaller pictures beside it, and opens it with its version
;; in git's HEAD on the left (SPC m g): the toolbar above each, the pictures in
;; the middle of their panes. Try J / K for the folder's images, + / - to zoom,
;; r to rotate, y to copy it; SPC m g closes the diff. The repository is
;; deleted once the picture is closed.
;; The pictures are drawn here, a PNG written byte by byte (its deflate blocks
;; stored, not compressed): no image tool needed.

;; ====== VARIABLES ======

(defconst +my/example-image--scenes
  '((day
     :sky-top (62 128 214) :sky-bottom (204 228 248)
     :sun (255 247 214) :glow (255 252 232)
     :far (150 176 206) :mid (92 128 150) :near (46 88 72)
     :water (58 112 160))
    (sunset
     :sky-top (36 32 84) :sky-bottom (255 158 92)
     :sun (255 214 140) :glow (255 150 84)
     :far (156 104 132) :mid (98 62 104) :near (40 28 56)
     :water (92 56 92))
    (night
     :sky-top (6 10 28) :sky-bottom (36 48 92)
     :sun (238 238 222) :glow (70 84 132)
     :far (48 58 96) :mid (30 38 70) :near (14 18 36)
     :water (18 26 54) :stars t))
  "The pictures' colours, by scene: (R G B) each; :stars, a starry sky.")

;; ====== CODE ======

;; A PNG
(defconst +my/example-image--crc-table
  (let ((table (make-vector 256 0)))
    (dotimes (n 256)
      (let ((c n))
        (dotimes (_ 8)
          (setq c (if (= (logand c 1) 1) (logxor (ash c -1) #xedb88320) (ash c -1))))
        (aset table n c)))
    table)
  "CRC-32's table: a byte at a time, not a bit.")

(defun +my/example-image--crc (string)
  "PNG's CRC-32 of unibyte STRING."
  (let ((crc #xffffffff))
    (dotimes (i (length string))
      (setq crc (logxor (aref +my/example-image--crc-table
                              (logand (logxor crc (aref string i)) 255))
                        (ash crc -8))))
    (logxor crc #xffffffff)))

(defun +my/example-image--u32 (n)
  "N as 4 bytes, big-endian."
  (unibyte-string (logand (ash n -24) 255) (logand (ash n -16) 255)
                  (logand (ash n -8) 255) (logand n 255)))

(defun +my/example-image--chunk (type data)
  (concat (+my/example-image--u32 (length data)) type data
          (+my/example-image--u32 (+my/example-image--crc (concat type data)))))

(defun +my/example-image--zlib (data)
  "DATA as a zlib stream of stored (not compressed) deflate blocks."
  (let ((a 1) (b 0) (blocks nil) (start 0) (size (length data)))
    (dotimes (i size)
      (setq a (% (+ a (aref data i)) 65521)
            b (% (+ b a) 65521)))
    (while (progn
             (let* ((end (min size (+ start 65535)))
                    (len (- end start))
                    (final (if (= end size) 1 0)))
               (push (concat (unibyte-string final
                                             (logand len 255) (ash len -8)
                                             (logand (lognot len) 255)
                                             (logand (ash (lognot len) -8) 255))
                             (substring data start end))
                     blocks)
               (setq start end)
               (< start size))))
    (concat (unibyte-string #x78 #x01)
            (apply #'concat (nreverse blocks))
            (+my/example-image--u32 (logior (ash b 16) a)))))

(defun +my/example-image--png (width height pixel)
  "A PNG, WIDTH by HEIGHT, (PIXEL X Y) its (R G B) at each point: its bytes."
  (let ((rows (make-string (* height (1+ (* 3 width))) 0))
        (i 0))
    (setq rows (string-to-unibyte rows))
    (dotimes (y height)
      (aset rows i 0)                   ; no filter
      (setq i (1+ i))
      (dotimes (x width)
        (pcase-let ((`(,r ,g ,b) (funcall pixel x y)))
          (aset rows i r) (aset rows (+ i 1) g) (aset rows (+ i 2) b)
          (setq i (+ i 3)))))
    (concat (unibyte-string #x89 ?P ?N ?G #x0d #x0a #x1a #x0a)
            (+my/example-image--chunk "IHDR" (concat (+my/example-image--u32 width)
                                                     (+my/example-image--u32 height)
                                                     (unibyte-string 8 2 0 0 0)))
            (+my/example-image--chunk "IDAT" (+my/example-image--zlib rows))
            (+my/example-image--chunk "IEND" ""))))

;; THE PICTURE
;; Layers, back to front, each edge smoothed over a pixel (its coverage, not
;; in or out): the sky (a gradient, the sun's glow, stars at night), the sun,
;; three ridges, hazier the farther, then the lake, the sky's colours deeper,
;; the ridges mirrored in it, ripples and the sun's glittering path.
(defun +my/example-image--mix (a b f)
  "Colour A to B, F of the way (clamped to 0 to 1): floats."
  (let ((f (min 1.0 (max 0.0 f))))
    (list (+ (nth 0 a) (* f (- (nth 0 b) (nth 0 a))))
          (+ (nth 1 a) (* f (- (nth 1 b) (nth 1 a))))
          (+ (nth 2 a) (* f (- (nth 2 b) (nth 2 a)))))))

(defun +my/example-image--cover (inside)
  "How much of a pixel is covered: INSIDE, how far its centre is inside the
edge, in pixels (a pixel's width smoothed)."
  (min 1.0 (max 0.0 (+ inside 0.5))))

(defun +my/example-image--noise (x y)
  "A fixed pseudo-random number from 0 to 1 for X, Y (stars, glitter): the
pixel they're in (the lake mirrors the sky between pixels)."
  (let ((n (logand (+ (* (truncate x) 374761393) (* (truncate y) 668265263)) #xffffffff)))
    (setq n (logand (* (logxor n (ash n -13)) 1274126177) #xffffffff))
    (/ (float (logand (logxor n (ash n -16)) #xffff)) #xffff)))

(defun +my/example-image--ridges (width height)
  "Each column's ridges' heights: (FAR MID NEAR), vectors of y by x."
  (let ((far (make-vector width 0.0)) (mid (make-vector width 0.0)) (near (make-vector width 0.0)))
    (dotimes (x width)
      (let ((u (/ (float x) width)))
        (aset far x (* height (+ 0.44 (* 0.07 (sin (+ 0.6 (* u 8.5))))
                                 (* 0.035 (sin (+ 1.7 (* u 21)))) (* 0.012 (sin (* u 61))))))
        (aset mid x (* height (+ 0.53 (* 0.05 (sin (+ 2.1 (* u 5.3))))
                                 (* 0.025 (sin (+ 0.3 (* u 17)))) (* 0.01 (sin (+ 1.0 (* u 49)))))))
        (aset near x (* height (+ 0.615 (* 0.02 (sin (+ 4.0 (* u 9.6)))) (* 0.008 (sin (* u 43))))))))
    (list far mid near)))

(defun +my/example-image--landscape (scene width height)
  "SCENE's landscape (see `+my/example-image--scenes'): its PNG's bytes."
  (pcase-let* ((c (alist-get scene +my/example-image--scenes))
               (sky-top (plist-get c :sky-top)) (sky-bottom (plist-get c :sky-bottom))
               (sun (plist-get c :sun)) (glow (plist-get c :glow))
               (far-c (plist-get c :far)) (mid-c (plist-get c :mid)) (near-c (plist-get c :near))
               (water (plist-get c :water)) (stars (plist-get c :stars))
               (`(,far ,mid ,near) (+my/example-image--ridges width height))
               (horizon (* 0.66 height))
               (sun-x (* 0.7 width)) (sun-y (* 0.36 height)) (sun-r (* 0.07 width))
               (mix #'+my/example-image--mix) (cover #'+my/example-image--cover))
    (cl-labels
        ((sky (x y)
           (let* ((d (sqrt (+ (expt (- x sun-x) 2) (expt (- y sun-y) 2))))
                  (colour (funcall mix sky-top sky-bottom (expt (/ y horizon) 1.4)))
                  ;; The glow: brightest by the sun, gone a few radii away.
                  (colour (funcall mix colour glow (* 0.75 (exp (- (/ (max 0 (- d sun-r)) (* 2.2 sun-r))))))))
             (when (and stars (< y (* 0.55 height)))
               (let ((n (+my/example-image--noise x y)))
                 (when (> n 0.994)
                   (setq colour (funcall mix colour '(255 255 240) (* 3 (- n 0.994) 100 (- 1 (/ y height))))))))
             ;; The sun's disc, its edge smoothed.
             (funcall mix colour sun (funcall cover (- sun-r d)))))
         (land (x y colour)
           "Ridges over COLOUR at X, Y: each hazier toward its foot."
           (let* ((f (aref far x)) (m (aref mid x)) (n (aref near x))
                  (colour (funcall mix colour
                                   (funcall mix far-c sky-bottom (* 0.45 (/ (- y f) (- horizon f))))
                                   (funcall cover (- y f))))
                  (colour (funcall mix colour
                                   (funcall mix mid-c sky-bottom (* 0.25 (/ (- y m) (- horizon m))))
                                   (funcall cover (- y m)))))
             (funcall mix colour near-c (funcall cover (- y n)))))
         (lake (x y)
           (let* ((depth (/ (- y horizon) (- height horizon)))
                  ;; The point the lake mirrors, squashed: its reflection.
                  (mirror (- horizon (* 1.35 (- y horizon))))
                  (wobble (* 1.6 (sin (+ (* y 0.55) (* 2.0 (sin (* x 0.031)))))))
                  (mx (min (1- width) (max 0 (round (+ x wobble)))))
                  (reflected (if (> mirror 0) (land mx mirror (sky mx mirror)) sky-top))
                  (colour (funcall mix reflected water (+ 0.45 (* 0.4 depth))))
                  ;; Ripples: faint light and dark lines.
                  (ripple (sin (+ (* y 1.25) (* 1.5 (sin (+ (* x 0.045) (* y 0.11)))))))
                  (colour (funcall mix colour (if (> ripple 0) sky-bottom '(0 0 0))
                                   (* 0.06 (abs ripple))))
                  ;; The sun's path: wider nearer, glittering.
                  (path (* sun-r (+ 0.5 (* 1.4 depth))))
                  (dx (abs (- x sun-x))))
             (if (and (< dx path) (> ripple 0.25))
                 (funcall mix colour sun (* 0.85 (- 1 (/ dx path)) (- 1 (* 0.55 depth))
                                            (+ 0.6 (* 0.4 (+my/example-image--noise x y)))))
               colour))))
      (+my/example-image--png
       width height
       (lambda (x y)
         (let ((colour (if (< y horizon)
                           (land x y (sky x y))
                         (lake x y))))
           (mapcar (lambda (v) (min 255 (max 0 (round v)))) colour)))))))

(defun +my/example-image--write (file bytes)
  (let ((coding-system-for-write 'no-conversion))
    (with-temp-file file
      (set-buffer-multibyte nil)
      (insert bytes)))
  file)

(defun +my/example-image--git (&rest args)
  "Run git with ARGS in the current folder, as no one in particular (not
your name, hooks or signing): its exit status."
  (let ((process-environment (append '("GIT_EDITOR=true" "GIT_TERMINAL_PROMPT=0")
                                     process-environment)))
    (apply #'call-process "git" nil nil nil
           "-c" "user.name=Example" "-c" "user.email=example@example.invalid"
           "-c" "commit.gpgsign=false" "-c" "core.hooksPath=/dev/null"
           "-c" "init.defaultBranch=main"
           args)))

(defun +my/example-image--repo ()
  "A repository in the temp folder: landscape.png committed by day, then a
sunset; night.png and dawn.png beside it, smaller. Its folder: images/ in a
new temp folder, always that name (the screenshot shows the picture's path)."
  (let ((default-directory (file-name-as-directory
                            (expand-file-name "images" (+my/example-folder "image")))))
    (make-directory default-directory)
    (+my/example-image--git "init" "-q")
    (+my/example-image--write "landscape.png" (+my/example-image--landscape 'day 480 300))
    (unless (and (zerop (+my/example-image--git "add" "landscape.png"))
                 (zerop (+my/example-image--git "commit" "-qm" "A landscape")))
      (error "Example: git commit failed"))
    (+my/example-image--write "landscape.png" (+my/example-image--landscape 'sunset 480 300))
    (+my/example-image--write "night.png" (+my/example-image--landscape 'night 240 150))
    (+my/example-image--write "dawn.png" (+my/example-image--landscape 'day 240 150))
    default-directory))

(defun +my/example-image ()
  "Example: the image viewer, a picture changed since git's HEAD beside its
version there (deleted once closed). See examples/image.el."
  (interactive)
  (let ((repo (+my/example-image--repo)))
    (delete-other-windows)
    (find-file (expand-file-name "landscape.png" repo))
    (let ((buffer (current-buffer)))
      (when (bound-and-true-p +my/image-mode)
        (+my/image-diff))
      (+my/example-delete-when-closed
       (file-name-directory (directory-file-name repo)) (list buffer))
      (message "Image example: HEAD's version on the left; J / K the folder's images, + / - zoom, r rotates, y copies; SPC m g closes the diff")
      buffer)))

(defun +my/example-image-ready ()
  "Non-nil once the example's picture and its HEAD version are shown."
  (seq-some (lambda (buffer)
              (and (buffer-local-value '+my/example--closing buffer)
                   (buffer-local-value '+my/image-mode buffer)
                   (with-current-buffer buffer
                     (and (+my/image--spec)
                          (+my/image--head-shown-p)))))
            (buffer-list)))

;; Compiled once loaded: the pictures' 200,000 pixels drawn in a second, not
;; ten (an example's file is loaded as source).
(require 'bytecomp)
(dolist (function '(+my/example-image--crc +my/example-image--zlib +my/example-image--png
                    +my/example-image--mix +my/example-image--cover +my/example-image--noise
                    +my/example-image--ridges +my/example-image--landscape))
  (let ((byte-compile-warnings nil)
        (inhibit-message t))
    (byte-compile function)))

(provide 'example-image)
