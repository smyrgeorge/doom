;;; tests/e2e/test-image.el -*- lexical-binding: t; -*-
;; config/image.el in a GUI Emacs: real images in image-mode with the toolbar.
;; Zoom, fit, actual size, sharp pixels, rotating and flipping (sips on macOS,
;; ImageMagick on Linux; saved),
;; the folder's images, the toolbar's text and its narrow form, copying (the
;; clipboard not touched), git's HEAD beside the image, a file changed on disk.

(require 'image-mode)
(+test-load "config/emacs/childframe" "config/banner" "config/image")

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

;; Nothing goes outside Emacs: the clipboard (osascript on macOS; xclip,
;; wl-copy on Linux) is recorded instead; other apps (Preview, Finder, the
;; file manager) are, by tests/helper.el (`+test-os-runs').
(defvar +test-image--outside nil
  "(PROGRAM INFILE ARGS...) that would have run outside Emacs, the latest
first.")

(advice-add 'call-process :around
            (lambda (fn program &rest args)
              (if (member program '("osascript" "xclip" "wl-copy"))
                  (progn (push (append (list program (car args)) (nthcdr 3 args)) +test-image--outside) 0)
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
        (dolist (label (list "Fit" "1:1" "Crop" "Sharp" "Copy" "Diff"
                             (if (+my/macos-p) "Preview" "Open")))
          (should (string-match-p (regexp-quote label) toolbar)))
        (should-not (string-match-p "Save" toolbar))
        (should-not (string-match-p "…" toolbar))))))

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

(defun +test-image--copy ()
  "Copy the image (y): on Linux through xclip (X11), as if it were installed."
  (let ((process-environment (cons "WAYLAND_DISPLAY" process-environment))
        (find (symbol-function 'executable-find)))
    (cl-letf (((symbol-function 'executable-find)
               (lambda (name &rest args) (if (equal name "xclip") "/usr/bin/xclip" (apply find name args)))))
      (+my/image-copy))))

(defun +test-image--copied (call)
  "The file a recorded copy CALL gave: osascript's last argument, xclip's
input."
  (if (equal (car call) "osascript") (car (last call)) (nth 1 call)))

(ert-deftest e2e-image/copy-the-image ()
  (+test-with-reset
    (let ((file (expand-file-name "a.png" (+test-image--folder))))
      (+test-image--open file)
      (setq +test-image--outside nil)
      (+test-image--copy)
      (let ((call (car +test-image--outside)))
        (if (+my/macos-p)
            (progn (should (equal (car call) "osascript"))
                   (should (seq-some (lambda (arg) (and (stringp arg) (string-match-p "«class PNGf»" arg))) call)))
          (should (equal (car call) "xclip"))
          (should (member "image/png" call)))
        (should (equal (+test-image--copied call) file)))
      ;; Edited: its bytes as shown, not the file's.
      (+my/image-flip)
      (setq +test-image--outside nil)
      (cl-letf (((symbol-function 'delete-directory) #'ignore))
        (+test-image--copy))
      (let ((copied (+test-image--copied (car +test-image--outside))))
        (should-not (equal copied file))
        (should (equal (+test-image--bytes copied) (buffer-string))))
      (+my/image-copy-path)
      (should (equal (current-kill 0) file)))))

(ert-deftest e2e-image/preview-and-finder ()
  (+test-with-reset
    (let ((file (expand-file-name "a.png" (+test-image--folder))))
      (+test-image--open file)
      (setq +test-os-runs nil)
      (+my/image-open-in-preview)
      (+my/image-show-in-finder)
      (should (equal (reverse +test-os-runs)
                     (if (+my/macos-p)
                         `(("open" "-a" "Preview" ,file) ("open" "-R" ,file))
                       ;; The file manager on D-Bus (none here): its folder.
                       `(("xdg-open" ,file) ("xdg-open" ,(file-name-directory file)))))))))

;; ====== GIT'S HEAD ======

(defun +test-image--resize (file width height)
  "FILE made WIDTH×HEIGHT pixels, in place (sips on macOS, else ImageMagick)."
  (should (zerop (if (executable-find "sips")
                     (call-process "sips" nil nil nil "-z" (number-to-string height)
                                   (number-to-string width) file)
                   (call-process (+my/os-imagemagick) nil nil nil file
                                 "-resize" (format "%dx%d!" width height) file))))
  file)

(defun +test-image--repo (&optional size)
  "A git repository whose HEAD has a.png red, then a.png turned green; its
path. SIZE, (WIDTH . HEIGHT): both that big."
  (let* ((dir (+test-image--folder))
         (file (expand-file-name "a.png" dir))
         (default-directory dir)
         (process-environment (append '("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1"
                                        "GIT_AUTHOR_NAME=t" "GIT_AUTHOR_EMAIL=t@t"
                                        "GIT_COMMITTER_NAME=t" "GIT_COMMITTER_EMAIL=t@t")
                                      process-environment)))
    (when size (+test-image--resize file (car size) (cdr size)))
    (dolist (args '(("init" "-q") ("add" "a.png") ("commit" "-q" "-m" "a")))
      (should (zerop (apply #'call-process "git" nil nil nil args))))
    (+test-image--write file +test-image--green)
    (when size (+test-image--resize file (car size) (cdr size)))
    dir))

(defun +test-image--pane (cols)
  "The selected window made COLS columns wide, another pane on its right;
that pane."
  (let ((other (split-window nil nil 'right)))
    (set-window-buffer other (get-buffer-create "*other*"))
    (window-resize (selected-window) (- cols (window-total-width)) t)
    (redisplay t)
    other))

(defun +test-image--fitted-p (window)
  "Non-nil if WINDOW's image is fitted to it, as it opens: at its size if it
fits, else as big as it fits."
  (with-selected-window window
    (pcase-let* ((`(,width . ,height) (image-size (+my/image--spec) t))
                 (`(,left ,top ,right ,bottom) (window-inside-pixel-edges window)))
      (and (<= width (- right left)) (<= height (- bottom top))
           (or (equal (cons width height) (+my/image-size))
               (>= width (- right left 2)) (>= height (- bottom top 2)))))))

(defun +test-image--before (window)
  "The before-string of the image's overlay in WINDOW (center.el)."
  (with-current-buffer (window-buffer window)
    (when-let* ((overlay (cdr (assq window +my/image--centering))))
      (overlay-get overlay 'before-string))))

(defun +test-image--head-drawn (window)
  "HEAD's image drawn in WINDOW, before the image (diff.el), if it is."
  (let ((string (or (+test-image--before window) ""))
        (found nil))
    (dotimes (i (length string))
      (let ((display (get-text-property i 'display string)))
        (when (eq (car-safe display) 'image)
          (setq found display))))
    found))

(defun +test-image--scale (window)
  "How big WINDOW's image is shown (1.0: its size)."
  (with-selected-window window (+my/image-scale)))

(defun +test-image--head-scale (window)
  "How big HEAD is drawn in WINDOW (1.0: its size)."
  (let ((head (+test-image--head-drawn window)))
    (/ (float (car (image-size head t))) (car (+my/image--head-size (plist-get (cdr head) :data))))))

(defun +test-image--same-scale-p (window)
  (< (abs (- (+test-image--scale window) (+test-image--head-scale window))) 0.01))

(defun +test-image--diff-fitted-p (window)
  "Non-nil if WINDOW's diff (HEAD, the image, their captions) fits it, as
big as it fits: no room left on one side."
  (with-selected-window window
    (pcase-let ((`(,width . ,height) (+my/image--diff-size window))
                (body-width (window-body-width window t))
                (body-height (window-body-height window t)))
      (and (<= width body-width) (<= height body-height)
           (or (>= width (- body-width 4)) (>= height (- body-height 4)))))))

(defun +test-image--commit (dir)
  (string-trim (+my/image--git dir "rev-parse" "--short" "HEAD")))

(defun +test-image--diff-button-on-p ()
  "Non-nil if the toolbar's Diff button is on."
  (let* ((toolbar (format-mode-line header-line-format nil (selected-window)))
         (at (string-match "Diff" toolbar)))
    (and at (memq '+my/image-toolbar-on (ensure-list (get-text-property at 'face toolbar))))))

(ert-deftest e2e-image/head-beside-the-image-in-its-own-pane ()
  "SPC m g: git's HEAD drawn in the image's own buffer, pane and tab, on its
left, a caption over each: no new buffer, no new pane. Again: gone, the
image fitted to its whole pane; the image closed with it shown, nothing
left."
  (+test-with-reset
    (let* ((dir (+test-image--repo))
           (image (+test-image--open (expand-file-name "a.png" dir)))
           (window (selected-window))
           (buffers (length (buffer-list)))
           (windows (window-list)))
      (+my/image-diff)
      (redisplay t)
      (should (+my/image--head-shown-p))
      (should (= (length (buffer-list)) buffers))
      (should (equal (window-list) windows))
      (should (eq (window-buffer window) image))
      (should (eq (selected-window) window))
      (let ((head (+test-image--head-drawn window))
            (before (substring-no-properties (+test-image--before window))))
        (should head)
        (should (equal (plist-get (cdr head) :data) +test-image--red))
        (should (string-match-p (format "HEAD %s.*Working tree" (+test-image--commit dir)) before)))
      (should (+my/image--diff-side-p window))
      (should (+test-image--diff-button-on-p))
      (should (+test-image--same-scale-p window))
      ;; Again: closed, the image as before.
      (+my/image-diff)
      (redisplay t)
      (should-not (+my/image--head-shown-p))
      (should-not (+test-image--head-drawn window))
      (should-not (+test-image--diff-button-on-p))
      (should (+test-image--fitted-p window))
      ;; Closing the image with the diff shown: nothing left.
      (+my/image-diff)
      (kill-buffer image)
      (should (= (length (buffer-list)) (1- buffers))))))

(ert-deftest e2e-image/head-in-the-image-s-pane-of-any-width ()
  "The diff in a pane of any width: HEAD on the left (above, in a pane
narrower than twice `+my/image-diff-min-width'), the pair fitted to it at
one scale; the other pane untouched. Closed: the image fitted to its
whole pane again."
  (let ((dir (+test-image--repo '(800 . 400))))
    (dolist (cols '(120 60 40 30))
      (+test-with-reset
        (let* ((other (+test-image--pane cols))
               (other-width (window-total-width other))
               (window (selected-window))
               (windows (window-list)))
          (+test-image--open (expand-file-name "a.png" dir))
          (should (= (window-total-width window) cols))
          (+my/image-diff)
          (redisplay t)
          (ert-info ((format "%d columns: body %dx%d, diff %S, columns %S" cols
                             (window-body-width window t) (window-body-height window t)
                             (+my/image--diff-size window) (+my/image--diff-columns window)))
            (should (equal (window-list) windows))
            (should (= (window-total-width window) cols))
            (should (= (window-total-width other) other-width))
            (should (eq (+my/image--diff-side-p window) (>= cols (* 2 +my/image-diff-min-width))))
            ;; Side by side: both captions on one line; stacked: the
            ;; image's under HEAD.
            (should (eq (and (string-match-p "HEAD [^\n]*Working tree" (+test-image--before window)) t)
                        (+my/image--diff-side-p window)))
            (should (+test-image--diff-fitted-p window))
            (should (+test-image--same-scale-p window))
            (should (< (+test-image--scale window) 0.9))
            ;; Again: the image fitted to its whole pane.
            (+my/image-diff)
            (redisplay t)
            (should (= (window-total-width window) cols))
            (should (= (window-total-width other) other-width))
            (should (+test-image--fitted-p window))))))))

(ert-deftest e2e-image/head-and-the-image-zoomed-together ()
  "The diff at the image's zoom; zoom, Fit, 1:1 and Sharp change both."
  (let ((dir (+test-image--repo '(400 . 200))))
    (+test-with-reset
      (+test-image--open (expand-file-name "a.png" dir))
      (+my/image-zoom-in)
      (+my/image-diff)
      (redisplay t)
      (let ((window (selected-window)))
        (should (< (abs (- (+test-image--scale window) 1.25)) 0.02))
        (should (+test-image--same-scale-p window))
        (+my/image-zoom-in)
        (redisplay t)
        (should (< (abs (- (+test-image--scale window) 1.5625)) 0.02))
        (should (+test-image--same-scale-p window))
        (+my/image-actual-size)
        (redisplay t)
        (should (= (+test-image--scale window) 1.0))
        (should (+test-image--same-scale-p window))
        (+my/image-fit)
        (redisplay t)
        (should (+test-image--diff-fitted-p window))
        (should (+test-image--same-scale-p window))
        (let ((+my/image-sharp +my/image-sharp))
          (+my/image-toggle-sharp)
          (redisplay t)
          (should (equal (plist-member (cdr (+test-image--head-drawn window)) :transform-smoothing)
                         '(:transform-smoothing nil)))
          (+my/image-toggle-sharp)
          (redisplay t)
          (should (plist-get (cdr (+test-image--head-drawn window)) :transform-smoothing)))
        (should (+my/image--head-shown-p))))))

(ert-deftest e2e-image/q-closes-the-diff-the-image-refitted-at-once ()
  "q with the diff shown closes it as SPC m g does, the image fitted to its
whole pane at once; q again closes the image."
  (let ((dir (+test-image--repo '(800 . 400))))
    (+test-with-reset
      (let ((image (+test-image--open (expand-file-name "a.png" dir)))
            (window (selected-window))
            (q (keymap-lookup (evil-get-auxiliary-keymap +my/image-mode-map 'normal) "q")))
        (should (+test-image--fitted-p window))
        (+my/image-diff)
        (redisplay t)
        (should (< (+test-image--scale window) 0.9))
        (call-interactively q)
        (should (buffer-live-p image))
        (should-not (+my/image--head-shown-p))
        (should (+test-image--fitted-p window))
        (should (= (+test-image--scale window) 1.0))
        (call-interactively q)
        (should-not (buffer-live-p image))))))

(ert-deftest e2e-image/head-centered-in-each-pane ()
  "The diff smaller than its panes: centered in each (a split), from the
pair's size."
  (+test-with-reset
    (let ((dir (+test-image--repo)))
      (+test-image--open (expand-file-name "a.png" dir))
      (let ((top (selected-window))
            (bottom (split-window-below)))
        (+my/image-diff)
        (redisplay t)
        (dolist (window (list top bottom))
          (should (+test-image--head-drawn window))
          (pcase-let ((`(,left . ,_) (with-current-buffer (window-buffer window) (+my/image--room window)))
                      (`(,width . ,_) (+my/image--diff-size window)))
            (should (> left 0))
            (should (<= (abs (- left (/ (- (window-body-width window t) width) 2))) 1))))))))

(ert-deftest e2e-image/head-kept-on-a-revert-and-an-edit-not-on-j ()
  "The diff kept while the file changes on disk (the image shown anew beside
HEAD) and while rotating or flipping (its caption Edited); J: another
image, without it."
  (+test-with-reset
    (let* ((dir (+test-image--repo))
           (file (expand-file-name "a.png" dir)))
      (+test-image--open file)
      (+my/image-diff)
      (+test-image--write file +test-image--red)
      (auto-revert-handler)
      (redisplay t)
      (should (equal (buffer-string) +test-image--red))
      (should (+my/image--head-shown-p))
      (should (+test-image--head-drawn (selected-window)))
      (+my/image-flip)
      (redisplay t)
      (should (+my/image--head-shown-p))
      (should (string-match-p "Edited" (+test-image--before (selected-window))))
      (set-buffer-modified-p nil)
      (+my/image-next)
      (redisplay t)
      (should (equal buffer-file-name (expand-file-name "b.png" dir)))
      (should-not (+my/image--head-shown-p))
      (should-not (+test-image--head-drawn (selected-window))))))

(ert-deftest e2e-image/crop-closes-the-diff-first ()
  (require 'image-crop)
  (skip-unless (executable-find (car image-crop-crop-command)))
  (+test-with-reset
    (+test-image--open (expand-file-name "a.png" (+test-image--repo)))
    (+my/image-diff)
    (let ((shown 'unset))
      (cl-letf (((symbol-function 'image-crop)
                 (lambda (&rest _) (setq shown (+my/image--head-shown-p)))))
        (+my/image-crop))
      (should-not shown)
      (should-not (+my/image--head-shown-p)))))

(ert-deftest e2e-image/head-unchanged-or-not-in-git ()
  (+test-with-reset
    (let ((dir (+test-image--repo)))
      ;; As committed again: nothing to compare.
      (+test-image--write (expand-file-name "a.png" dir) +test-image--red)
      (+test-image--open (expand-file-name "a.png" dir))
      (should-error (+my/image-diff) :type 'user-error)
      (should-not (+my/image--head-shown-p))
      (should (one-window-p))
      (+test-image--open (expand-file-name "b.png" dir)) ; not committed
      (should-error (+my/image-diff) :type 'user-error)
      (should-not (+my/image--head-shown-p))
      ;; Not in a git repository.
      (+test-image--open (expand-file-name "a.png" (+test-image--folder)))
      (should-error (+my/image-diff) :type 'user-error))))

;; ====== THE TOOLBAR IN NARROW PANES ======

(defun +test-image--toolbar-width (window)
  "The width in pixels of WINDOW's toolbar: its text, without the space
pushing its right side to the window's edge."
  (let ((text (format-mode-line header-line-format nil window))
        (parts nil)
        (i 0))
    (while (< i (length text))
      (let ((next (next-single-property-change i 'display text (length text))))
        (unless (eq (car-safe (get-text-property i 'display text)) 'space)
          (push (substring text i next) parts))
        (setq i next)))
    (string-pixel-width (apply #'concat (nreverse parts)))))

(defun +test-image--fits (window)
  (redisplay t)
  (should (<= (+test-image--toolbar-width window) (window-body-width window t))))

(ert-deftest e2e-image/the-toolbar-fits-narrow-panes-copy-diff-and-save-last ()
  (let ((dir (+test-image--repo)))
    (dolist (cols '(60 40 25))
      (+test-with-reset
        (+test-image--pane cols)
        (let ((window (selected-window)))
          (+test-image--open (expand-file-name "a.png" dir))
          (ert-info ((format "%d columns" cols))
            (+test-image--fits window)
            (should (string-match-p "Copy" (+test-image--toolbar)))
            ;; What's left out in the … button's menu, with its keys.
            (should (string-match-p "…" (+test-image--toolbar)))
            (let ((menu (+my/image--menu (nth 2 (+my/image--toolbar-fit)))))
              (should (eq (lookup-key menu [+my/image-rotate]) #'+my/image-rotate))
              (should (eq (lookup-key menu [+my/image-open-in-preview]) #'+my/image-open-in-preview))
              (should (equal (assq '+my/image-diff (cdr menu))
                             '(+my/image-diff menu-item "The image as in git's HEAD, beside it (SPC m g)"
                                              +my/image-diff))))
            ;; HEAD shown: Diff kept.
            (+my/image-diff)
            (+test-image--fits window)
            (should (string-match-p "Diff" (+test-image--toolbar)))
            ;; Edited: Save kept as well.
            (+my/image-flip)
            (+test-image--fits window)
            (let ((toolbar (+test-image--toolbar)))
              (dolist (label '("Copy" "Diff" "Save"))
                (should (string-match-p label toolbar))))))))))

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
  (skip-unless (+my/os-imagemagick))
  (+test-with-reset
    (let ((file (expand-file-name "anim.gif" (+test-image--folder))))
      (should (zerop (call-process (+my/os-imagemagick) nil nil nil "-size" "20x10"
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
      (should (zerop (if (executable-find "sips")
                         (call-process "sips" nil nil nil "-z" "2000" "4000" buffer-file-name "--out" big)
                       (call-process (+my/os-imagemagick) nil nil nil buffer-file-name
                                     "-resize" "4000x2000!" big))))
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
