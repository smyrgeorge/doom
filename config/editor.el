;;; $DOOMDIR/config/editor.el -*- lexical-binding: t; -*-
;; General editing helpers. Loaded from config.el.

;; ====== KEY BINDINGS ======

(map! :leader :desc "Cycle case style" "c ~" #'string-inflection-all-cycle)

;; GO TO DECLARATION OR USAGES
;; Cmd+B on a symbol, like IntelliJ: on a use, jump to its declaration; on the
;; declaration itself, list its usages (Enter opens one). Cmd+[ goes back.
(map! "s-b" #'+my/goto-declaration-or-usages)

;; ====== CODE ======

;; EDITING
;; SPC c ~: cycle the word at point through snake_case, UPPER_CASE,
;; PascalCase, camelCase and kebab-case.
(use-package! string-inflection
  :commands string-inflection-all-cycle)

;; RAINBOW BRACKETS
;; Color (), [] and {} by nesting depth in code, like IntelliJ's Rainbow
;; Brackets plugin, so matching pairs are easy to spot.
(use-package! rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

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
  (cl-some (lambda (item)
             (let ((location (xref-item-location item)))
               ;; Only look closer at declarations on this line of this file
               ;; (getting the position of others would open their files).
               (and (equal (ignore-errors (expand-file-name (xref-location-group location)))
                           buffer-file-name)
                    (eql (ignore-errors (xref-location-line location))
                         (line-number-at-pos))
                    (when-let* ((marker (ignore-errors (xref-location-marker location))))
                      (and (eq (marker-buffer marker) (current-buffer))
                           (<= (car bounds) marker (cdr bounds)))))))
           definitions))

(defun +my/goto-declaration-or-usages ()
  "Jump to the declaration of the symbol at point; on the declaration itself,
list its usages instead (IntelliJ's Go to Declaration or Usages)."
  (interactive)
  (unless (thing-at-point 'symbol)
    (user-error "No symbol here"))
  (call-interactively (if (+my/at-declaration-p)
                          #'+lookup/references
                        #'+lookup/definition)))
