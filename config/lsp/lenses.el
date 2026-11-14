;;; $DOOMDIR/config/lsp/lenses.el -*- lexical-binding: t; -*-
;; Code lenses, placed cheaply. Loaded from config/lsp.el.

;; CODE LENSES, CHEAPER
;; Placing each lens, lsp-mode works out the indentation that lenses above the
;; line need, even with them at the end of the line (here): it finds where the
;; line starts on screen, which highlights that part of the file first. In
;; Markdown that means a tree-sitter parser per paragraph, ~10 ms each (see
;; config/editor/tree-sitter.el, AVAILABLE GRAMMARS): opening a file froze for
;; half a second when its lenses arrived. At the end of the line, just put them
;; there.
;; Not when the line and its lens don't fit the pane: the lens was cut, or
;; hidden (truncated lines), or went on to more rows, pushing the code down
;; (wrapped ones). Such a line's lens goes above it, at its indentation, on as
;; many rows as it needs (broken between its lenses). Lengths are counted in
;; characters, not measured on screen (see above).
(defun +my/lsp-lens--above (ov str width)
  "Lens STR of OV's line (point there) as rows above it, at its
indentation, broken between its lenses to fit WIDTH columns."
  (let* ((indent (make-string (current-indentation) ?\s))
         (room (- width (length indent) 1))
         (separator (propertize "|" 'face 'lsp-lens-face))
         (rows nil)
         (row nil))
    (dolist (title (or (overlay-get ov 'lsp--metadata) (list str)))
      (if (and row (> (+ (string-width row) 1 (string-width title)) room))
          (setq rows (cons row rows)
                row title)
        (setq row (if row (concat row separator title) title))))
    (mapconcat (lambda (row) (concat indent row "\n")) (nreverse (cons row rows)) "")))

(defadvice! +my/lsp-lens-end-of-line-a (fn ov)
  "Lenses at the end of the line placed without measuring it (see above)."
  :around #'lsp-lens--update
  (if (eq lsp-lens-place-position 'end-of-line)
      (let ((str (overlay-get ov 'lsp--lens-contents))
            (window (get-buffer-window (current-buffer))))
        (save-excursion
          (goto-char (overlay-start ov))
          (let ((bol (line-beginning-position))
                (eol (line-end-position)))
            (if (or (null window)
                    (< (+ (- eol bol) 1 (string-width str)) (window-text-width window)))
                (progn
                  (move-overlay ov eol eol)
                  (overlay-put ov 'before-string nil)
                  (overlay-put ov 'after-string (propertize (concat " " str) 'cursor t)))
              (move-overlay ov bol bol)
              (overlay-put ov 'after-string nil)
              (overlay-put ov 'before-string
                           (+my/lsp-lens--above ov str (window-text-width window))))))
        (overlay-put ov 'lsp-original str))
    (funcall fn ov)))
