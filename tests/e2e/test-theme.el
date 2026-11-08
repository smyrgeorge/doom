;;; tests/e2e/test-theme.el -*- lexical-binding: t; -*-
;; A real theme change in a GUI Emacs: doom-one, then doom-one-light (as SPC h
;; t loads them). The parts of the config with colours of their own follow
;; it: the merge's tints, the banner's rows (an open notice too), the
;; stripe's marks and band (an open strip too), the image toolbar's buttons.
;; (The WebKit pages: their own files' THE THEME tests.)

(setq-default truncate-lines t)          ; as Doom
(+test-load "config/window" "config/editor" "config/childframe" "config/banner"
            "config/stripe" "config/merge" "config/image")
(require 'doom-themes)
(add-to-list 'custom-theme-load-path (file-name-directory (locate-library "doom-themes")))

;; Doom's `doom-enable-theme-h' (lisp/doom-emacs.el): a theme enabled runs
;; `doom-load-theme-hook', from a temp buffer.
(defun +test-theme--enabled (_theme)
  (with-temp-buffer
    (run-hooks 'doom-load-theme-hook)))
(add-hook 'enable-theme-functions #'+test-theme--enabled -90)

;; ====== HELPERS ======

(defun +test-theme--load (theme)
  "THEME, the only one, as `consult-theme' (SPC h t) loads it."
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme theme t)
  (should (eq (car custom-enabled-themes) theme)))

(defun +test-theme--colours ()
  "The colours the config gives its parts, by name."
  `((merge-added . ,(face-background '+my/merge-added nil t))
    (merge-conflict . ,(face-background '+my/merge-conflict nil t))
    (merge-filler . ,(face-background '+my/merge-filler nil t))
    (banner-info . ,(face-background '+my/banner-info nil t))
    (banner-error . ,(face-background '+my/banner-error nil t))
    (stripe-todo . ,(face-foreground '+my/stripe-todo nil t))
    (stripe-suggestion . ,(face-foreground '+my/stripe-suggestion nil t))
    (stripe-band . ,(+my/stripe--thumb-color))
    (image-button . ,(face-background '+my/image-toolbar-button nil t))
    (image-on . ,(face-foreground '+my/image-toolbar-on nil t))))

(defun +test-theme--dark-p (colour)
  (color-dark-p (color-name-to-rgb colour)))

(defun +test-theme--strip-data (window)
  "The image WINDOW's strip frame shows (its XPM)."
  (let ((frame (nth 1 (assq window +my/stripe--frames))))
    (and (frame-live-p frame)
         (with-current-buffer (window-buffer (frame-root-window frame))
           (plist-get (cdr (get-text-property (point-min) 'display)) :data)))))

;; ====== THE THEME, CHANGED ======

(ert-deftest e2e-theme/every-part-follows-a-real-theme-change ()
  (unwind-protect
      (+test-with-reset
        (+test-theme--load 'doom-one)
        ;; A file with its strip, a notice above it: on screen as it changes.
        (find-file (+test-file "theme/file.el"
                               (mapconcat (lambda (i) (format ";; line %d" i))
                                          (number-sequence 1 300) "\n")))
        (emacs-lisp-mode)
        (+my/stripe-mode 1)
        (+my/banner-show 'theme "A notice" :type 'error)
        (let ((window (selected-window)))
          (should (+test-wait-for (lambda () (+test-theme--strip-data window)) 5))
          (should (+test-wait-for
                   (lambda () (frame-live-p (nth 1 (assq window +my/banner--frames))))
                   5))
          (let ((dark (+test-theme--colours)))
            ;; Each a colour, a dark theme's.
            (pcase-dolist (`(,part . ,colour) dark)
              (should (stringp colour))
              (should (color-defined-p colour))
              (ignore part))
            (should (+test-theme--dark-p (alist-get 'banner-info dark)))
            (should (+test-theme--dark-p (alist-get 'merge-added dark)))
            (should (+test-theme--dark-p (alist-get 'stripe-band dark)))
            (+test-theme--load 'doom-one-light)
            (let ((light (+test-theme--colours)))
              ;; Each one changed, a light theme's where it's a background.
              (pcase-dolist (`(,part . ,colour) light)
                (should (equal (list part (equal colour (alist-get part dark)))
                               (list part nil))))
              (dolist (part '(merge-added merge-conflict merge-filler banner-info
                              banner-error stripe-band image-button))
                (should (equal (list part (+test-theme--dark-p (alist-get part light)))
                               (list part nil))))
              ;; The tints, the theme's own colours blended in.
              (should (equal (alist-get 'merge-added light)
                             (doom-blend (doom-color 'green) (doom-color 'bg) 0.25)))
              (should (equal (alist-get 'banner-info light)
                             (doom-blend (doom-color 'blue) (face-background 'default nil t) 0.2)))
              ;; The open strip drawn again in the new band colour, its frame
              ;; in the new background.
              (should (+test-wait-for
                       (lambda ()
                         (string-search (alist-get 'stripe-band light)
                                        (or (+test-theme--strip-data window) "")))
                       3))
              (should (equal (frame-parameter (nth 1 (assq window +my/stripe--frames))
                                              'background-color)
                             (face-background 'default nil t)))
              ;; The open notice: its frame in the new tint.
              (should (+test-wait-for
                       (lambda ()
                         (equal (frame-parameter (nth 1 (assq window +my/banner--frames))
                                                 'background-color)
                                (alist-get 'banner-error light)))
                       3))))))
    (mapc #'disable-theme custom-enabled-themes)
    (with-temp-buffer
      (run-hooks 'doom-load-theme-hook))))
