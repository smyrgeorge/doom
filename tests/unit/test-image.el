;;; tests/unit/test-image.el -*- lexical-binding: t; -*-
;; config/image.el: images in image-mode with a toolbar. What doesn't need an
;; image shown (batch Emacs shows none): the folder's images and moving among
;; them, the info's text, what can be edited, the toolbar in the header line
;; (with notices), the keys. Shown images: tests/e2e/test-image.el.

(require 'image-mode)
(+test-load "config/emacs/childframe" "config/banner" "config/image")

;; ====== HELPERS ======

(defun +test-image--folder (&rest names)
  "A new folder with files NAMES (empty); its path."
  (let ((dir (file-name-as-directory (make-temp-file (expand-file-name "images-" +test-tmp) t))))
    (dolist (name names)
      (with-temp-file (expand-file-name name dir)))
    dir))

(defmacro +test-image--in (file &rest body)
  "BODY in a buffer visiting FILE's name (its text not an image)."
  (declare (indent 1))
  `(with-temp-buffer
     (setq buffer-file-name ,file)
     ,@body))

;; ====== THE FOLDER'S IMAGES ======

(ert-deftest image/folder-images-by-name-as-people-count ()
  (let ((dir (+test-image--folder "img10.png" "img2.png" "b.JPG" "notes.txt" ".hidden.png")))
    (+test-image--in (expand-file-name "img2.png" dir)
      (should (equal (mapcar #'file-name-nondirectory (+my/image--folder-images))
                     '("b.JPG" "img2.png" "img10.png")))
      (should (equal (+my/image--position) '(1 . 3))))))

(ert-deftest image/folder-images-listed-again-once-the-folder-changes ()
  (let ((dir (+test-image--folder "a.png" "b.png")))
    (+test-image--in (expand-file-name "a.png" dir)
      (should (= (length (+my/image--folder-images)) 2))
      ;; The folder's mtime moves on: a file added later in the same second
      ;; wouldn't change it.
      (with-temp-file (expand-file-name "c.png" dir))
      (set-file-times dir (time-add (current-time) 5))
      (should (= (length (+my/image--folder-images)) 3)))))

(ert-deftest image/the-image-among-its-folder-s-even-if-not-an-image-name ()
  (let ((dir (+test-image--folder "a.png" "z.png" "drawing.data")))
    (+test-image--in (expand-file-name "drawing.data" dir)
      (should (member buffer-file-name (+my/image--folder-images)))
      (should (= (cdr (+my/image--position)) 3)))))

(ert-deftest image/next-and-previous-wrap-around ()
  (let ((dir (+test-image--folder "a.png" "b.png" "c.png"))
        visited)
    (cl-letf (((symbol-function 'find-alternate-file)
               (lambda (file) (push (file-name-nondirectory file) visited))))
      (+test-image--in (expand-file-name "c.png" dir)
        (+my/image-next)
        (+my/image-previous)
        (+my/image-next 2))
      (+test-image--in (expand-file-name "a.png" dir)
        (+my/image-previous)))
    (should (equal (reverse visited) '("a.png" "b.png" "b.png" "c.png")))))

(ert-deftest image/next-without-another-image ()
  (let ((dir (+test-image--folder "only.png" "notes.txt")))
    (+test-image--in (expand-file-name "only.png" dir)
      (should-error (+my/image-next) :type 'user-error))
    (with-temp-buffer
      (should-error (+my/image-next) :type 'user-error))))

;; ====== INFO ======

(ert-deftest image/info-size-type-and-file-size ()
  (let ((file (+test-file "images/info.png" (make-string 2048 ?x))))
    (+test-image--in file
      (setq-local image-type 'png)
      (cl-letf (((symbol-function '+my/image-size) (lambda () '(1600 . 900))))
        (should (equal (+my/image-info) "1600×900 · PNG · 2 kB"))
        ;; Edited: the buffer's bytes, not the file's.
        (insert (make-string 5000 ?y))
        (should (equal (+my/image-info) "1600×900 · PNG · 5 kB"))))))

(ert-deftest image/extension-by-type ()
  (with-temp-buffer
    (setq-local image-type 'jpeg)
    (should (equal (+my/image--extension) "jpg"))
    (setq-local image-type 'png)
    (should (equal (+my/image--extension) "png"))
    (setq-local image-type nil)
    (setq buffer-file-name "/tmp/x.webp")
    (should (equal (+my/image--extension) "webp"))
    (setq buffer-file-name nil)))

;; ====== EDITS ======

(ert-deftest image/what-can-be-edited ()
  (with-temp-buffer
    (setq-local image-type 'png)
    (should (+my/image--editable-p))
    (setq-local image-type 'svg)        ; text: not sips's
    (should-not (+my/image--editable-p))
    (should-error (+my/image-rotate) :type 'user-error)
    (setq-local image-type 'gif)
    (should (+my/image--editable-p))
    (setq-local image-multi-frame t)    ; an animation: one frame would be left
    (should-not (+my/image--editable-p))
    (setq-local image-multi-frame nil)
    ;; The diff with git's HEAD shown: the image still changes (crop closes
    ;; the diff first).
    (setq-local +my/image--head '(:commit "abc1234"))
    (should (+my/image--editable-p))
    (setq-local buffer-read-only t)
    (should-not (+my/image--editable-p))
    (should-error (+my/image-crop) :type 'user-error)))

;; ====== THE TOOLBAR IN THE HEADER LINE ======

(ert-deftest image/toolbar-on-and-off-in-the-header-line ()
  (with-temp-buffer
    (+my/image--show-toolbar t)
    (should (equal header-line-format +my/image--header))
    (+my/image--show-toolbar nil)
    (should-not header-line-format)))

(ert-deftest image/toolbar-under-the-notices ()
  (with-temp-buffer
    (+my/image--show-toolbar t)
    (+my/banner--install)
    (should (equal header-line-format (list +my/banner--header +my/image--header)))
    ;; Off and on with notices shown: their room kept, the toolbar after it.
    (+my/image--show-toolbar nil)
    (should (equal header-line-format (list +my/banner--header nil)))
    (+my/image--show-toolbar t)
    (should (equal header-line-format (list +my/banner--header +my/image--header)))
    ;; The notices closed: the toolbar alone.
    (+my/banner--uninstall)
    (should (equal header-line-format +my/image--header))))

(ert-deftest image/toggling-the-toolbar-in-every-image ()
  (let ((+my/image-toolbar t)
        (a (generate-new-buffer "a.png"))
        (b (generate-new-buffer "b.png")))
    (unwind-protect
        (progn
          (dolist (buffer (list a b))
            (with-current-buffer buffer (+my/image-mode 1)))
          (with-current-buffer a (+my/image-toggle-toolbar))
          (should-not +my/image-toolbar)
          (should-not (buffer-local-value 'header-line-format b))
          (with-current-buffer b (+my/image-toggle-toolbar))
          (should (equal (buffer-local-value 'header-line-format a) +my/image--header)))
      (kill-buffer a)
      (kill-buffer b))))

(ert-deftest image/the-mode-off-takes-the-toolbar-away ()
  (with-temp-buffer
    (let ((+my/image-toolbar t))
      (+my/image-mode 1)
      (should header-line-format)
      (+my/image-mode -1)
      (should-not header-line-format))))

(ert-deftest image/buttons-click-in-their-window ()
  (let* ((ran nil)
         (map (+my/image--click-map (lambda () (interactive) (setq ran (selected-window)))))
         (command (lookup-key map [header-line mouse-1])))
    (should (eq (lookup-key map [header-line down-mouse-1]) #'ignore))
    (funcall command `(mouse-1 (,(selected-window) header-line (0 . 0) 0)))
    (should (eq ran (selected-window)))))

(ert-deftest image/buttons-highlighted-one-at-a-time ()
  ;; Side by side, their mouse-faces not `eq': hovering one highlights it
  ;; only (Emacs highlights a run of the same mouse-face as one).
  (let* ((bar (concat (+my/image--button 'zoom-in "Zoom in" #'ignore)
                      (+my/image--button 'fit "Fit" #'ignore)))
         (first (get-text-property 0 'mouse-face bar))
         (end (next-single-property-change 0 'mouse-face bar)))
    (should first)
    (should (= end (length (+my/image--button 'zoom-in "Zoom in" #'ignore))))
    (should-not (eq first (get-text-property end 'mouse-face bar)))))

(ert-deftest image/buttons-off-don-t-click ()
  (let ((on (+my/image--button 'copy "Copy" #'ignore))
        (off (+my/image--button 'previous "Previous" #'ignore 'off)))
    (should (get-text-property 1 'local-map on))
    (should-not (get-text-property 1 'local-map off))
    (should (equal (get-text-property 1 'help-echo off) "Previous"))))

;; ====== KEYS ======

(ert-deftest image/keys ()
  (let ((normal (evil-get-auxiliary-keymap +my/image-mode-map 'normal)))
    (pcase-dolist (`(,key . ,command)
                   '(("J" . +my/image-next) ("K" . +my/image-previous)
                     ("+" . +my/image-zoom-in) ("-" . +my/image-zoom-out)
                     ("W" . +my/image-fit) ("0" . +my/image-actual-size)
                     ("r" . +my/image-rotate) ("R" . +my/image-rotate-left)
                     ("f" . +my/image-flip) ("F" . +my/image-flip-vertically)
                     ("c" . +my/image-crop) ("y" . +my/image-copy)
                     ("RET" . +my/image-toggle-animation) ("q" . +my/image-quit)
                     ("SPC m t" . +my/image-toggle-toolbar) ("SPC m g" . +my/image-diff)
                     ("SPC m s" . +my/image-toggle-sharp) ("SPC m p" . +my/image-open-in-preview)
                     ("SPC m f" . +my/image-show-in-finder) ("SPC m y" . +my/image-copy-path)
                     ("TAB" . +my/image-toggle-head) ("<tab>" . +my/image-toggle-head)
                     ("SPC m h" . +my/image-toggle-head)
                     ("D" . +my/image-difference) ("SPC m d" . +my/image-difference)))
      (should (eq (keymap-lookup normal key) command))))
  (pcase-dolist (`(,key . ,command)
                 '(("s-=" . +my/image-zoom-in) ("s--" . +my/image-zoom-out)
                   ("s-0" . +my/image-actual-size) ("s-c" . +my/image-copy)
                   ("C-<wheel-up>" . +my/image-zoom-in-mouse)))
    (should (eq (keymap-lookup +my/image-mode-map key) command))))

;; ====== GIT'S HEAD ======

(ert-deftest image/q-closes-the-diff-then-the-image ()
  "q with the diff (SPC m g) shown: the diff closed, the image shown anew
\(fitted to its whole pane); q again: the image closed."
  (+test-with-reset
    (let ((image (+test-buffer "a.png"))
          (redrawn 0)
          (killed nil))
      (cl-letf (((symbol-function '+my/image--redisplay) (lambda () (cl-incf redrawn)))
                ((symbol-function '+my/image--spec) (lambda () '(image :type png)))
                ((symbol-function 'kill-current-buffer)
                 (lambda () (push (current-buffer) killed))))
        (with-current-buffer image
          (setq-local +my/image--head (list :commit "abc1234"))
          (should (+my/image--head-shown-p))
          (+my/image-quit)
          (should-not (+my/image--head-shown-p))
          (should (= redrawn 1))
          (should-not killed)
          (+my/image-quit)
          (should (equal killed (list image)))
          (should (= redrawn 1)))))))

(ert-deftest image/the-diff-menu ()
  "The toolbar's Diff menu: beside HEAD and in its place, their keys, the
one shown ticked, and closing once one is."
  (with-temp-buffer
    (should (equal (mapcar #'cadr (+my/image--diff-menu-items))
                   '(+my/image-diff +my/image-toggle-head +my/image-difference)))
    (should-not (delq nil (mapcar #'caddr (+my/image--diff-menu-items))))
    (setq-local +my/image--head (list :commit "abc1234" :view 'head))
    (let ((items (+my/image--diff-menu-items)))
      (should (equal (mapcar #'cadr items)
                     '(+my/image-diff +my/image-toggle-head +my/image-difference +my/image-quit)))
      (should (equal (mapcar #'caddr items) '(nil on nil nil)))
      (should (string-match-p "(D)" (car (nth 2 items))))
      (should (string-match-p "(TAB)" (car (nth 1 items))))
      (should (string-match-p "(SPC m g)" (car (nth 0 items)))))))

(ert-deftest image/the-changed-pixels-said ()
  "What the toolbar says of the changed pixels: comparing, how many, the
same pixels, sizes that differ, a failure; never a silent 0."
  (with-temp-buffer
    (setq-local +my/image--head (list :commit "abc1234" :view 'difference))
    (let ((key (+my/image--difference-key)))
      (should (equal (+my/image--difference-text) "Comparing…"))
      (setq-local +my/image--difference (list :key key :process t))
      (should (equal (+my/image--difference-text) "Comparing…"))
      (setq-local +my/image--difference (list :key key :count 412 :total 144000))
      (should (equal (+my/image--difference-text) "412 px changed (0.3%)"))
      (setq-local +my/image--difference (list :key key :count 2 :total 1440000))
      (should (equal (+my/image--difference-text) "2 px changed (0.00%)"))
      (setq-local +my/image--difference (list :key key :count 0 :total 800))
      (should (equal (+my/image--difference-text) "Same pixels as HEAD"))
      (setq-local +my/image--difference (list :key key :count 2400 :total 3200
                                              :sizes '((80 . 40) . (40 . 20))))
      (should (equal (+my/image--difference-text)
                     "Sizes differ: 80×40 · HEAD 40×20 · 2400 px changed (75.0%)"))
      (setq-local +my/image--difference (list :key key :error "no decode delegate"))
      (should (equal (+my/image--difference-text) "Couldn't compare: no decode delegate"))
      ;; The image changed since: compared again.
      (setq-local +my/image--difference (list :key (list "abc1234" -1 0) :count 3 :total 9))
      (should (equal (+my/image--difference-text) "Comparing…")))))

(ert-deftest image/the-changed-pixels-need-imagemagick ()
  (with-temp-buffer
    (cl-letf (((symbol-function '+my/image--compare-programs) #'ignore))
      (should-error (+my/image-difference) :type 'user-error)
      (should-not +my/image--head))))

(ert-deftest image/diff-scale-the-image-s-zoom-or-fitted ()
  "HEAD and the image at one scale: a zoom's, 1:1's, or fitted (scaled up
too with Fit; only down as it opens, fitted if bigger)."
  (with-temp-buffer
    (cl-letf (((symbol-function '+my/image--diff-fit) (lambda (_) 0.5)))
      (setq-local image-transform-resize 1.5625)
      (should (= (+my/image--diff-scale nil) 1.5625))
      (setq-local image-transform-resize nil)
      (should (= (+my/image--diff-scale nil) 1.0))
      (setq-local image-transform-resize t)
      (should (= (+my/image--diff-scale nil) 0.5))
      (setq-local image-transform-resize 'fit-window)
      (should (= (+my/image--diff-scale nil) 0.5)))
    (cl-letf (((symbol-function '+my/image--diff-fit) (lambda (_) 2.0)))
      (setq-local image-transform-resize t)
      (should (= (+my/image--diff-scale nil) 1.0))
      (setq-local image-transform-resize 'fit-window)
      (should (= (+my/image--diff-scale nil) 2.0)))))

(ert-deftest image/diff-respec-at-one-scale ()
  "The image drawn at the pair's scale: image-mode's sizes left out, the
rest kept."
  (should (equal (+my/image--respec '(image :type png :data "x" :max-width 800 :max-height 600
                                            :width 800 :scale 1 :transform-smoothing nil)
                                    0.25)
                 '(image :type png :data "x" :transform-smoothing nil :scale 0.25))))

(ert-deftest image/diff-side-by-side-or-stacked ()
  "HEAD beside the image in a pane at least twice `+my/image-diff-min-width'
wide, above it in a narrower one."
  (let ((+my/image-diff-min-width 30))
    (cl-letf (((symbol-function 'window-total-width) (lambda (&rest _) 60)))
      (should (+my/image--diff-side-p nil)))
    (cl-letf (((symbol-function 'window-total-width) (lambda (&rest _) 59)))
      (should-not (+my/image--diff-side-p nil)))))

(ert-deftest image/the-mode-in-image-mode-only ()
  (should (memq #'+my/image-mode-maybe-h image-mode-hook))
  (with-temp-buffer
    (+my/image-mode-maybe-h)            ; fundamental-mode: an image as text
    (should-not +my/image-mode)))
