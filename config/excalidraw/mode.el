;;; $DOOMDIR/config/excalidraw/mode.el -*- lexical-binding: t; -*-
;; The drawing mode, and which buffers get it. Loaded from config/excalidraw.el.

(defun +my/excalidraw-mode-maybe ()
  "Drawings' major mode: Excalidraw in WebKit where it works, else the file's
own (see config/excalidraw.el)."
  (if (and (+my/webkit-p) (+my/excalidraw-ensure))
      (+my/excalidraw-mode)
    (+my/excalidraw--fallback-mode)))

(defun +my/excalidraw--json-p ()
  "Non-nil if the buffer's drawing is Excalidraw's JSON (.excalidraw), not an
SVG."
  (and buffer-file-name
       (let ((case-fold-search t))
         (string-match-p "\\.excalidraw\\'" buffer-file-name))))

(defun +my/excalidraw--fallback-mode ()
  "The drawing's file in its own mode: the SVG as an image (as XML where
images don't show: a terminal), the JSON as JSON."
  (cond ((+my/excalidraw--json-p)
         (if (fboundp 'json-mode) (json-mode) (js-json-mode)))
        ((display-images-p) (image-mode))
        (t (nxml-mode))))

;; THE MODE
(define-derived-mode +my/excalidraw-mode +my/webkit-mode "Drawing"
  "A drawing in Excalidraw, in WebKit (see config/excalidraw.el), a view per
window (config/webkit.el). The buffer has the file's text, under the views:
the page's export of the drawing after each change, saved as any file.

\\{+my/excalidraw-mode-map}"
  (setq-local font-lock-defaults '(nil t)
              revert-buffer-function #'+my/excalidraw--revert
              +my/webkit-url-function #'+my/excalidraw--url
              +my/webkit-watch-function #'+my/excalidraw--watch
              +my/webkit-background #'+my/excalidraw--background
              ;; libraries.excalidraw.com in Emacs (see libraries.el).
              +my/webkit-link-function #'+my/excalidraw--link-out
              ;; Saved as the page made it (and the buffer is read-only).
              require-final-newline nil)
  (setq buffer-file-coding-system
        (coding-system-change-text-conversion buffer-file-coding-system 'utf-8))
  ;; Undo is Excalidraw's: the buffer's text is replaced at each change.
  (buffer-disable-undo)
  (add-hook '+my/webkit-load-functions #'+my/excalidraw--loaded nil t)
  ;; First: other hooks see the drawing as saved.
  (add-hook 'before-save-hook #'+my/excalidraw--before-save -90 t)
  (add-hook 'change-major-mode-hook #'+my/excalidraw--stop nil t)
  (add-hook 'kill-buffer-hook #'+my/excalidraw--stop nil t))
