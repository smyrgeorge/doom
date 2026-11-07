;;; $DOOMDIR/config/lsp/lenses.el -*- lexical-binding: t; -*-
;; Code lenses, placed cheaply. Loaded from config/lsp.el.

;; CODE LENSES, CHEAPER
;; Placing each lens, lsp-mode works out the indentation that lenses above the
;; line need, even with them at the end of the line (here): it finds where the
;; line starts on screen, which highlights that part of the file first. In
;; Markdown that means a tree-sitter parser per paragraph, ~10 ms each (see
;; config/tree-sitter.el, AVAILABLE GRAMMARS): opening a file froze for half a
;; second when its lenses arrived. At the end of the line, just put them there.
(defadvice! +my/lsp-lens-end-of-line-a (fn ov)
  :around #'lsp-lens--update
  (if (eq lsp-lens-place-position 'end-of-line)
      (let ((str (overlay-get ov 'lsp--lens-contents)))
        (overlay-put ov 'after-string (propertize (concat " " str) 'cursor t))
        (overlay-put ov 'lsp-original str))
    (funcall fn ov)))
