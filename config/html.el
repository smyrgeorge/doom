;;; $DOOMDIR/config/html.el -*- lexical-binding: t; -*-
;; HTML files: a notice offering to open them in the browser. Loaded from
;; config.el.

;; ====== VARIABLES ======

;; BROWSER NOTICE
;; An HTML file (.html, .htm, .xhtml) opens with a notice at the top
;; (config/banner.el): "Open in browser" opens it in the default browser
;; (`browse-url-of-file': the file as saved; changes not saved yet, it says
;; so). The notice stays until its ✕. Its modes: Doom's web-mode, Emacs's
;; HTML modes, and the long lines' mode (an HTML report with its data on one
;; line, config/editor/long-lines.el), its notice under that one's.
(defvar +my/html-browser-notice t
  "Offer to open an HTML file in the browser, in a notice (see above).")

(defvar +my/html-modes '(web-mode html-mode html-ts-mode so-long-mode)
  "The modes HTML files open in (see above): their hooks show the notice.")

;; ====== CODE ======

(defun +my/html-file-p ()
  "Non-nil if the buffer visits an HTML file."
  (and buffer-file-name
       (let ((case-fold-search t))
         (string-match-p "\\.x?html?\\'" buffer-file-name))))

(defun +my/html-open-in-browser ()
  "Open the buffer's HTML file in the default browser."
  (interactive)
  (unless (+my/html-file-p)
    (user-error "Not an HTML file"))
  (browse-url-of-file buffer-file-name))

(defun +my/html-browser-notice-h ()
  "Offer to open the buffer's HTML file in the browser (see above)."
  (when (and +my/html-browser-notice
             (+my/html-file-p)
             (fboundp '+my/banner-show))
    (+my/banner-show 'html-browser "Open this file in your browser."
                     :actions '(("Open in browser" . +my/html-open-in-browser)))))

(dolist (mode +my/html-modes)
  (add-hook (intern (format "%s-hook" mode)) #'+my/html-browser-notice-h))
