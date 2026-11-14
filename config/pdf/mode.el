;;; $DOOMDIR/config/pdf/mode.el -*- lexical-binding: t; -*-
;; The PDF mode, and which buffers get it. Loaded from config/pdf.el.

(defun +my/pdf-p ()
  "Non-nil if this buffer's PDF can show in WebKit: a local file that's there
\(not a new one, not written yet), in the GUI, in an Emacs with xwidgets."
  (and buffer-file-name (not (file-remote-p buffer-file-name))
       (file-readable-p buffer-file-name)
       (+my/webkit-p)))

(defvar +my/pdf--falling-back nil
  "Non-nil while doc-view picks another mode for a PDF it can't show.")

(defun +my/pdf-mode-maybe ()
  "PDFs' major mode: WebKit where it works, doc-view otherwise (see
config/pdf.el). Asked again by doc-view, falling back on another mode for a
PDF it can't show (a new file, empty): `fundamental-mode', where doc-view
alone ends, not doc-view over and over."
  (cond ((+my/pdf-p) (+my/pdf-mode))
        (+my/pdf--falling-back (fundamental-mode))
        (t (let ((+my/pdf--falling-back t))
             (doc-view-mode-maybe)))))

;; No "File is large, really open?" for PDFs, as with Doom's pdf module: only
;; WebKit reads them.
(defadvice! +my/pdf-no-large-file-prompt-a (fn size op-type filename &optional offer-raw)
  :around #'abort-if-file-too-large
  (unless (string-match-p "\\.[pP][dD][fF]\\'" filename)
    (funcall fn size op-type filename offer-raw)))

(define-derived-mode +my/pdf-mode +my/webkit-mode "PDF"
  "A PDF in WebKit, drawn by PDF.js (see config/pdf.el), a view per
window (config/webkit.el). The file's bytes stay in the buffer, unchanged:
WebKit is shown over them.

\\{+my/pdf-mode-map}"
  (setq-local font-lock-defaults '(nil t)  ; nothing to colour in a PDF's bytes
              revert-buffer-function #'+my/pdf--revert
              +my/webkit-url-function #'+my/pdf--url
              +my/webkit-watch-function #'+my/pdf--watch
              +my/webkit-selection-script
              "window.pdfx ? pdfx.selection() : String(window.getSelection())"
              ;; Each window's page (see WATCHING, watch.el).
              doom-modeline--pdf-pages '(:eval (+my/pdf--page)))
  (add-hook 'change-major-mode-hook #'+my/pdf--stop nil t)
  (add-hook 'kill-buffer-hook #'+my/pdf--stop nil t))
