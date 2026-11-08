;;; tests/assets.el -*- lexical-binding: t; -*-
;; PDF.js and Excalidraw downloaded into Doom's data folder (.local/etc), each
;; file's SHA-256 checked, as opening a PDF or a drawing does: the end-to-end
;; tests that need them (they copy them from there) run instead of skipping.
;; GitHub Actions runs it before the tests (.github/workflows/tests.yml); by
;; hand:
;;
;;   emacs --batch -l tests/helper.el -l tests/assets.el
;;
;; DOOM_EMACS_DIR (default ~/.config/emacs) is Doom's folder.

(+test-load "config/childframe" "config/banner" "config/window" "config/editor" "config/webkit"
            "config/pdf" "config/excalidraw")

(let ((etc (expand-file-name ".local/etc/" +test-doom-emacs-dir)))
  (let ((+my/pdf-js-dir (expand-file-name (concat "pdfjs-" +my/pdf-js-version "/") etc)))
    (unless (+my/pdf-js-installed-p)
      (+my/pdf-js-install))
    (princ (format "PDF.js %s: %s\n" +my/pdf-js-version +my/pdf-js-dir)))
  (let ((+my/excalidraw-dir (expand-file-name (concat "excalidraw-" +my/excalidraw-version "/") etc)))
    (unless (+my/excalidraw-installed-p)
      (+my/excalidraw-install))
    (princ (format "Excalidraw %s: %s\n" +my/excalidraw-version +my/excalidraw-dir))))
