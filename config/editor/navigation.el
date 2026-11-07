;;; $DOOMDIR/config/editor/navigation.el -*- lexical-binding: t; -*-
;; Getting around: Cmd+B, declaration or usages.
;; Loaded from config/editor.el.

;; GO TO DECLARATION OR USAGES
;; Where the symbol is declared comes from xref: the language server in LSP
;; buffers, Emacs itself in Emacs Lisp. The jump and the usages list are Doom's
;; lookup (`gd' / `gD'), with its fallbacks where there's no server. When the
;; language server knows no declaration to jump to, e.g. on a Markdown heading
;; (links point to it, marksman's lens counts them), it lists the usages too:
;; the jump fell back to searching the project for the word.
(defun +my/at-declaration-p ()
  "Non-nil if point is on the declaration of the symbol there, or (with a
language server) on one it knows no declaration of."
  (when-let* ((bounds (bounds-of-thing-at-point 'symbol))
              (backend (xref-find-backend))
              (id (xref-backend-identifier-at-point backend)))
    (let ((definitions (ignore-errors (xref-backend-definitions backend id))))
      (if (and (null definitions) (eq backend 'xref-lsp))
          t
        (+my/at-declaration--here-p bounds definitions)))))

(defun +my/at-declaration--here-p (bounds definitions)
  "Non-nil if one of DEFINITIONS (xref items) is the symbol at BOUNDS."
  (let ((here (line-number-at-pos)))
    (cl-some (lambda (item)
               (let* ((location (xref-item-location item))
                      (line (ignore-errors (xref-location-line location))))
                 ;; Only look closer at declarations in this file, on this
                 ;; line when the location says which (getting the position of
                 ;; others would open their files). Emacs Lisp's don't say:
                 ;; theirs is the start of the line that declares the symbol
                 ;; (and finding it moves point, so put it back).
                 ;; The same file, whatever links its path goes through (the
                 ;; buffer's is its true name, Doom's `find-file-visit-truename').
                 (and (ignore-errors (file-equal-p (xref-location-group location)
                                                   buffer-file-name))
                      (or (null line) (eql line here))
                      (when-let* ((marker (save-excursion
                                            (ignore-errors (xref-location-marker location)))))
                        (and (eq (marker-buffer marker) (current-buffer))
                             (if line
                                 (<= (car bounds) marker (cdr bounds))
                               (= (line-number-at-pos marker) here)))))))
             definitions)))

(defun +my/goto-declaration-or-usages ()
  "Jump to the declaration of the symbol at point; on the declaration itself,
list its usages instead."
  (interactive)
  (unless (thing-at-point 'symbol)
    (user-error "No symbol here"))
  (call-interactively (if (+my/at-declaration-p)
                          #'+lookup/references
                        #'+lookup/definition)))
