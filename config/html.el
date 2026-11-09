;;; $DOOMDIR/config/html.el -*- lexical-binding: t; -*-
;; HTML files: a notice offering to open them in the browser; a page in
;; Emacs, in WebKit. Loaded from config.el.

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

;; A PAGE IN EMACS
;; `+my/html-open-in-emacs' shows an HTML file or a URL as a page in WebKit
;; (config/webkit.el), in a buffer of its own, "Page: NAME", opened in a tiled
;; pane (one of tiling's applications); links out of it go to the browser. Where
;; WebKit can't (a terminal, an Emacs without xwidgets): the browser. Agent
;; UI's page cards open so (config/agent-ui.el).
(defvar-local +my/html-page-url nil
  "In a page's buffer (see A PAGE IN EMACS above): the URL it shows.")

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

;; A PAGE IN EMACS (see above)
(define-derived-mode +my/html-page-mode +my/webkit-mode "Page"
  "An HTML file or a web page, in WebKit (see A PAGE IN EMACS in
config/html.el)."
  (setq-local +my/webkit-url-function (lambda (_window) +my/html-page-url)))

(defun +my/html--url-p (page)
  (string-match-p "\\`[a-z]+://" page))

(defun +my/html-open-in-emacs (page)
  "Show PAGE, an HTML file or a URL, in WebKit in a pane (see A PAGE IN
EMACS above); where WebKit can't, in the browser. Returns its buffer, if
it's Emacs's."
  (interactive (list (read-file-name "Page: " nil nil t)))
  (let ((url-p (+my/html--url-p page)))
    (if (not (and (display-graphic-p) (featurep 'xwidget-internal) (fboundp '+my/webkit-file-url)))
        (progn (if url-p (browse-url page) (browse-url-of-file page))
               nil)
      (let* ((url (if url-p page (+my/webkit-file-url page)))
             (name (format "Page: %s" (if url-p page (file-name-nondirectory page))))
             (old (get-buffer name)))
        ;; Another page so named: replaced.
        (when (and old (not (equal (buffer-local-value '+my/html-page-url old) url)))
          (kill-buffer old))
        (let ((buffer (get-buffer-create name)))
          (with-current-buffer buffer
            (unless (derived-mode-p '+my/html-page-mode)
              (+my/html-page-mode))
            ;; After the mode (which clears the buffer's variables), before
            ;; a window shows it (which starts its view).
            (setq +my/html-page-url url))
          (pop-to-buffer buffer)
          buffer)))))
