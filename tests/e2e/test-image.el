;;; tests/e2e/test-image.el -*- lexical-binding: t; -*-
;; config/image.el in a GUI Emacs: real images in image-mode with the toolbar.
;; Zoom, fit, actual size, sharp pixels, rotating and flipping (sips, saved),
;; the folder's images, the toolbar's text and its narrow form, copying (the
;; clipboard not touched), git's HEAD beside the image, a file changed on disk.

(require 'image-mode)
(+test-load "config/childframe" "config/banner" "config/image")

;; ====== SETUP ======

;; 40×20 PNGs: red then blue, green then blue.
(defconst +test-image--red
  (base64-decode-string "iVBORw0KGgoAAAANSUhEUgAAACgAAAAUCAIAAABwJOjsAAAAJklEQVR4nGP4z8CAB+GVpAyNWjxq8ajFoxaPWjxq8ajFoxaPHIsB0l8dDopnYIMAAAAASUVORK5CYII="))

(defconst +test-image--green
  (base64-decode-string "iVBORw0KGgoAAAANSUhEUgAAACgAAAAUCAIAAABwJOjsAAAAJ0lEQVR4nGNg+M+ADxGQph0atXjU4lGLRy0etXjU4lGLRy0eRhYDAAsnHQ5AYdIWAAAAAElFTkSuQmCC"))

(defun +test-image--write (file bytes)
  (make-directory (file-name-directory file) t)
  (let ((coding-system-for-write 'no-conversion))
    (with-temp-file file
      (set-buffer-multibyte nil)
      (insert bytes)))
  file)

(defun +test-image--bytes (file)
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (buffer-string)))

(defun +test-image--folder ()
  "A new folder of images: a.png (red), b.png (green); its path."
  (let ((dir (file-name-as-directory (make-temp-file (expand-file-name "images-" +test-tmp) t))))
    (+test-image--write (expand-file-name "a.png" dir) +test-image--red)
    (+test-image--write (expand-file-name "b.png" dir) +test-image--green)
    dir))

(defun +test-image--open (file)
  "FILE in the selected window, shown."
  (find-file file)
  (redisplay t)
  (current-buffer))

(defun +test-image--toolbar ()
  (substring-no-properties (format-mode-line header-line-format nil (selected-window))))

;; Nothing goes outside Emacs: the clipboard (osascript) and Preview, Finder
;; (open) are recorded instead.
(defvar +test-image--outside nil
  "(PROGRAM ARGS...) that would have run outside Emacs, the latest first.")

(advice-add 'call-process :around
            (lambda (fn program &rest args)
              (if (member program '("osascript" "open"))
                  (progn (push (cons program (nthcdr 3 args)) +test-image--outside) 0)
                (apply fn program args)))
            '((name . +test-image-no-outside)))

;; ====== OPENING ======

(ert-deftest e2e-image/opens-with-the-toolbar ()
  (+test-with-reset
    (let ((+my/image-toolbar t))
      (+test-image--open (expand-file-name "a.png" (+test-image--folder)))
      (should (derived-mode-p 'image-mode))
      (should +my/image-mode)
      (should (bound-and-true-p auto-revert-mode))
      (should (equal (+my/image-size) '(40 . 20)))
      (let ((toolbar (+test-image--toolbar)))
        (should (string-match-p "1/2" toolbar))
        (should (string-match-p "100%" toolbar)) ; smaller than the window: as is
        (should (string-match-p "40×20 · PNG · " toolbar))
        (dolist (label '("Fit" "1:1" "Crop" "Sharp" "Copy" "Diff" "Preview"))
          (should (string-match-p (regexp-quote label) toolbar)))
        (should-not (string-match-p "Save" toolbar))))))

(ert-deftest e2e-image/a-narrow-window-s-toolbar ()
  (+test-with-reset
    (+test-image--open (expand-file-name "a.png" (+test-image--folder)))
    (let ((wide (+test-image--toolbar)))
      (should (string-match-p "40×20" wide))
      (split-window-right (- (window-total-width) 50))
      (redisplay t)
      (let ((narrow (+test-image--toolbar)))
        (should-not (string-match-p "40×20" narrow))
        (should (string-match-p "Copy" narrow))))))

;; ====== ZOOM ======

(ert-deftest e2e-image/zoom-fit-and-actual-size ()
  (+test-with-reset
    (+test-image--open (expand-file-name "a.png" (+test-image--folder)))
    (should (= (+my/image-scale) 1.0))
    (+my/image-zoom-in)
    (should (< (abs (- (+my/image-scale) 1.25)) 0.03))
    (should (string-match-p "125%" (+test-image--toolbar)))
    (+my/image-zoom-out)
    (should (< (abs (- (+my/image-scale) 1.0)) 0.03))
    ;; Fitted: the 40 pixels wide image as wide as the window, or as high.
    (+my/image-fit)
    (should (> (+my/image-scale) 5))
    (should (eq image-transform-resize 'fit-window))
    (+my/image-actual-size)
    (should (= (+my/image-scale) 1.0))))

(ert-deftest e2e-image/the-wheel-s-zoom-drawn-once-it-pauses ()
  (+test-with-reset
    (+test-image--open (expand-file-name "a.png" (+test-image--folder)))
    (let ((event `(wheel-up (,(selected-window) 1 (0 . 0) 0))))
      (+my/image-zoom-in-mouse event)
      (+my/image-zoom-in-mouse event)
      (should (= (+my/image-scale) 1.0))  ; not drawn yet
      (should (+test-wait-for (lambda () (> (+my/image-scale) 1.15)) 2)))))

(ert-deftest e2e-image/sharp-pixels-for-the-next-images-too ()
  (+test-with-reset
    (let ((+my/image-sharp nil)
          (dir (+test-image--folder)))
      (+test-image--open (expand-file-name "a.png" dir))
      (+my/image-toggle-sharp)
      (should (equal image--transform-smoothing "none"))
      (+my/image-zoom-in)
      (should (eq (plist-get (cdr (+my/image--spec)) :transform-smoothing) nil))
      (should (plist-member (cdr (+my/image--spec)) :transform-smoothing))
      (+test-image--open (expand-file-name "b.png" dir))
      (should (+my/image--sharp-p))
      (+my/image-toggle-sharp)
      (should-not +my/image-sharp))))

;; ====== THE FOLDER ======

(ert-deftest e2e-image/next-and-previous-in-the-same-tab ()
  (+test-with-reset
    (let ((dir (+test-image--folder)))
      (+test-image--open (expand-file-name "a.png" dir))
      (let ((window (selected-window)))
        (+my/image-next)
        (should (equal (file-name-nondirectory buffer-file-name) "b.png"))
        (should (eq (selected-window) window))
        (should +my/image-mode)
        (should-not (get-file-buffer (expand-file-name "a.png" dir)))
        (+my/image-next)                ; after the last, the first
        (should (equal (file-name-nondirectory buffer-file-name) "a.png"))))))

;; ====== EDITS ======

(ert-deftest e2e-image/rotate-and-save ()
  (+test-with-reset
    (let ((file (expand-file-name "a.png" (+test-image--folder))))
      (+test-image--open file)
      (+my/image-rotate)
      (should (equal (+my/image-size) '(20 . 40)))
      (should (buffer-modified-p))
      (should (string-match-p "Save" (+test-image--toolbar)))
      ;; The file as it was until saved.
      (should (equal (+test-image--bytes file) +test-image--red))
      (save-buffer)
      (should-not (buffer-modified-p))
      (should (equal (cdr (image-size (create-image file nil nil :scale 1) t)) 40))
      (+my/image-rotate-left)
      (should (equal (+my/image-size) '(40 . 20))))))

(ert-deftest e2e-image/flip-and-revert ()
  (+test-with-reset
    (let ((file (expand-file-name "a.png" (+test-image--folder))))
      (+test-image--open file)
      (+my/image-flip)
      (should (buffer-modified-p))
      (should (equal (+my/image-size) '(40 . 20)))
      (should-not (equal (buffer-string) +test-image--red))
      (revert-buffer t t t)
      (should-not (buffer-modified-p))
      (should +my/image-mode)
      (should (equal (+my/image-size) '(40 . 20))))))

;; ====== COPYING, OTHER APPS ======

(ert-deftest e2e-image/copy-the-image ()
  (+test-with-reset
    (let ((file (expand-file-name "a.png" (+test-image--folder))))
      (+test-image--open file)
      (setq +test-image--outside nil)
      (+my/image-copy)
      (let ((call (car +test-image--outside)))
        (should (equal (car call) "osascript"))
        (should (seq-some (lambda (arg) (string-match-p "«class PNGf»" arg)) call))
        (should (equal (car (last call)) file)))
      ;; Edited: its bytes as shown, not the file's.
      (+my/image-flip)
      (setq +test-image--outside nil)
      (cl-letf (((symbol-function 'delete-directory) #'ignore))
        (+my/image-copy))
      (let ((copied (car (last (car +test-image--outside)))))
        (should-not (equal copied file))
        (should (equal (+test-image--bytes copied) (buffer-string))))
      (+my/image-copy-path)
      (should (equal (current-kill 0) file)))))

(ert-deftest e2e-image/preview-and-finder ()
  (+test-with-reset
    (let ((file (expand-file-name "a.png" (+test-image--folder))))
      (+test-image--open file)
      (setq +test-image--outside nil)
      (+my/image-open-in-preview)
      (+my/image-show-in-finder)
      (should (equal (reverse +test-image--outside)
                     `(("open" "-a" "Preview" ,file) ("open" "-R" ,file)))))))

;; ====== GIT'S HEAD ======

(defun +test-image--repo ()
  "A git repository whose HEAD has a.png red, then a.png turned green; its
path."
  (let* ((dir (+test-image--folder))
         (default-directory dir)
         (process-environment (append '("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1"
                                        "GIT_AUTHOR_NAME=t" "GIT_AUTHOR_EMAIL=t@t"
                                        "GIT_COMMITTER_NAME=t" "GIT_COMMITTER_EMAIL=t@t")
                                      process-environment)))
    (dolist (args '(("init" "-q") ("add" "a.png") ("commit" "-q" "-m" "a")))
      (should (zerop (apply #'call-process "git" nil nil nil args))))
    (+test-image--write (expand-file-name "a.png" dir) +test-image--green)
    dir))

(ert-deftest e2e-image/head-beside-the-image ()
  (+test-with-reset
    (let* ((dir (+test-image--repo))
           (image (+test-image--open (expand-file-name "a.png" dir)))
           (window (selected-window)))
      (+my/image-diff)
      (let* ((head +my/image--head-buffer)
             (head-window (get-buffer-window head)))
        (should head-window)
        (should (eq (window-in-direction 'left window) head-window))
        (should (eq (selected-window) window))
        (with-current-buffer head
          (should (equal (buffer-string) +test-image--red))
          (should +my/image-mode)
          (should-not (+my/image--editable-p))
          (with-selected-window head-window
            (should (string-match-p "HEAD [0-9a-f]+" (+test-image--toolbar)))
            (should-not (string-match-p "Diff" (+test-image--toolbar)))))
        ;; Again: closed, its pane too.
        (+my/image-diff)
        (should-not (buffer-live-p head))
        (should (one-window-p))
        ;; Closing the image closes it.
        (+my/image-diff)
        (setq head +my/image--head-buffer)
        (kill-buffer image)
        (should-not (buffer-live-p head))))))

(ert-deftest e2e-image/head-unchanged-or-not-in-git ()
  (+test-with-reset
    (let ((dir (+test-image--repo)))
      ;; As committed again: nothing to compare.
      (+test-image--write (expand-file-name "a.png" dir) +test-image--red)
      (+test-image--open (expand-file-name "a.png" dir))
      (should-error (+my/image-diff) :type 'user-error)
      (should (one-window-p))
      (+test-image--open (expand-file-name "b.png" dir)) ; not committed
      (should-error (+my/image-diff) :type 'user-error))))

;; ====== CHANGED ON DISK ======

(ert-deftest e2e-image/changed-on-disk-shown-anew-zoom-kept ()
  (+test-with-reset
    (let ((file (expand-file-name "a.png" (+test-image--folder))))
      (+test-image--open file)
      (+my/image-zoom-in)
      (+test-image--write file +test-image--green)
      (auto-revert-handler)
      (redisplay t)
      (should (equal (buffer-string) +test-image--green))
      (should +my/image-mode)
      (should (< (abs (- (+my/image-scale) 1.25)) 0.03)))))

;; ====== ANIMATIONS ======

(ert-deftest e2e-image/an-animation-plays-and-pauses-not-edited ()
  (skip-unless (executable-find "magick"))
  (+test-with-reset
    (let ((file (expand-file-name "anim.gif" (+test-image--folder))))
      (should (zerop (call-process "magick" nil nil nil "-size" "20x10"
                                   "xc:red" "xc:blue" "-loop" "0" file)))
      (+test-image--open file)
      (should image-multi-frame)
      (let ((toolbar (+test-image--toolbar)))
        (should (string-match-p "2 frames" toolbar))
        (should-not (string-match-p "Crop" toolbar)))
      (should-error (+my/image-rotate) :type 'user-error)
      (let ((playing (+my/image-playing-p)))
        (+my/image-toggle-animation)
        (should (eq (not (+my/image-playing-p)) (and playing t)))
        (+my/image-toggle-animation)
        (should (eq (and (+my/image-playing-p) t) (and playing t)))))))

;; ====== CENTERED, NO CURSOR ======

(defun +test-image--room (window)
  "(LEFT . TOP): the room before the image in WINDOW, as its overlay makes it."
  (let* ((overlay (cdr (assq window +my/image--centering)))
         (string (and overlay (overlay-get overlay 'before-string)))
         (left 0) (top 0))
    (dotimes (i (length (or string "")))
      (pcase (get-text-property i 'display string)
        (`(space :width (0) :height (,height)) (setq top height))
        (`(space :width (,width)) (setq left width))))
    (cons left top)))

(ert-deftest e2e-image/centered-in-each-window ()
  (+test-with-reset
    (+test-image--open (expand-file-name "a.png" (+test-image--folder)))
    (let* ((window (selected-window))
           (room (+test-image--room window)))
      ;; 40×20 at 100%: in the middle.
      (should (= (car room) (/ (- (window-body-width window t) 40) 2)))
      (should (= (cdr room) (/ (- (window-body-height window t) 20) 2)))
      (should (eq (overlay-get (cdr (assq window +my/image--centering)) 'window) window))
      ;; A split: each pane its own room, made again as they resize.
      (let ((other (split-window-right)))
        (redisplay t)
        (should (= (car (+test-image--room window))
                   (/ (- (window-body-width window t) 40) 2)))
        (should (= (car (+test-image--room other))
                   (/ (- (window-body-width other t) 40) 2)))
        (delete-window other)
        (redisplay t)
        (should-not (assq other +my/image--centering))
        (should (= (car (+test-image--room window)) (car room)))))))

(ert-deftest e2e-image/fitted-no-room-on-the-side-it-fills ()
  (+test-with-reset
    (+test-image--open (expand-file-name "a.png" (+test-image--folder)))
    (+my/image-fit)
    (let ((room (+test-image--room (selected-window))))
      ;; 2:1 fills the width or the height: no room there.
      (should (or (< (car room) 2) (< (cdr room) 2))))
    ;; Bigger than the window: no room, it scrolls.
    (let ((big (expand-file-name "big.png" default-directory)))
      (should (zerop (call-process "sips" nil nil nil "-z" "2000" "4000"
                                   buffer-file-name "--out" big)))
      (+test-image--open big)
      (+my/image-actual-size)
      (should (equal (+my/image-size) '(4000 . 2000)))
      (should (equal (+test-image--room (selected-window)) '(0 . 0))))))

(ert-deftest e2e-image/no-cursor-box-around-the-image ()
  (+test-with-reset
    (+test-image--open (expand-file-name "a.png" (+test-image--folder)))
    (should (equal evil-normal-state-cursor '(nil)))
    (should (local-variable-p 'cursor-in-non-selected-windows))
    (should-not cursor-in-non-selected-windows)
    (should-not cursor-type)))
