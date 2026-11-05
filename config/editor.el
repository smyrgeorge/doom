;;; $DOOMDIR/config/editor.el -*- lexical-binding: t; -*-
;; Editing and navigation helpers. Loaded from config.el.

;; ====== KEY BINDINGS ======

(map! :leader :desc "Cycle case style" "c ~" #'string-inflection-all-cycle)

;; GO TO DECLARATION OR USAGES
;; Cmd+B on a symbol, like IntelliJ: on a use, jump to its declaration; on the
;; declaration itself, list its usages (Enter opens one). Cmd+[ goes back.
(map! "s-b" #'+my/goto-declaration-or-usages)

;; BACK / FORWARD
;; Cmd+[ / Cmd+]: back / forward through the places the cursor jumped from and
;; to (better-jumper), like IntelliJ's Back / Forward.
(map! "s-[" #'better-jumper-jump-backward)

(map! "s-]" #'better-jumper-jump-forward)

;; PREVIOUS / NEXT BUFFER
;; M-[ / M-], GUI only: in a terminal, M-[ / M-] are ESC [ / ESC ], the
;; prefixes of escape sequences (mouse, focus, OSC), so binding them flips
;; buffers. (Defined here: the bindings call it as this file loads.)
(defun +my/gui-only (cmd)
  `(menu-item "" ,cmd :filter ,(lambda (c) (when (display-graphic-p) c))))

(map! "M-[" (+my/gui-only #'previous-buffer)
      "M-]" (+my/gui-only #'next-buffer))

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

;; RIGHT MARGIN
;; A thin vertical line at the column lines shouldn't go past, like IntelliJ's
;; right margin, in files of code, text and configuration: at `fill-column'
;; (set in config.el; also where gq and M-q wrap text). A project's
;; .editorconfig moves it with max_line_length (e.g. 100 in a ktfmt Kotlin
;; project), or removes it with max_line_length = off (e.g. for *.md). Commit
;; messages: 72.
;; As faint as the line numbers. Drawn on the lines that end before it; a
;; longer line covers it.
(defun +my/right-margin-h ()
  (when buffer-file-name
    (display-fill-column-indicator-mode 1)))

(add-hook! '(prog-mode-hook text-mode-hook conf-mode-hook) #'+my/right-margin-h)

;; .editorconfig is applied after the major mode (its column is just
;; `fill-column', which the line follows).
(after! editorconfig
  (add-hook 'editorconfig-after-apply-functions
            (defun +my/right-margin-editorconfig-h (props)
              (let ((length (gethash 'max_line_length props)))
                (when (and (stringp length)
                           (string-equal-ignore-case length "off"))
                  (display-fill-column-indicator-mode -1))))))

(defun +my/right-margin-face-h ()
  (set-face-attribute 'fill-column-indicator nil
                      :foreground (face-foreground 'line-number nil t)))

(+my/right-margin-face-h)

(add-hook 'doom-load-theme-hook #'+my/right-margin-face-h)

;; CURRENT LINE ACROSS WRAPPED ROWS
;; A long line wraps onto rows indented like it (Doom's word wrap: e.g. two
;; spaces in a Markdown table), and the current line's highlight left that
;; indentation out: Emacs draws a line's wrap prefix (and line prefix) without
;; the faces of the overlays on it, so a strip of plain background stayed at
;; the start of each continuation row. hl-line's overlay now carries copies of
;; the line's prefixes in its face (an overlay's prefix wins over the text's).
(defun +my/hl-line--prefix (prefix face)
  "PREFIX (a `wrap-prefix' or `line-prefix' value) drawn in FACE too."
  (cond ((null prefix) nil)
        ((stringp prefix)
         (let ((copy (copy-sequence prefix)))
           (add-face-text-property 0 (length copy) face nil copy)
           copy))
        ;; A display spec, e.g. (space :width 4).
        (t (propertize " " 'display prefix 'face face))))

(defun +my/hl-line-prefixes (overlay)
  "Give hl-line's OVERLAY its line's prefixes, in its face (see above)."
  (when (and (overlayp overlay) (overlay-buffer overlay))
    (with-current-buffer (overlay-buffer overlay)
      (let* ((pos (overlay-start overlay))
             (face (overlay-get overlay 'face))
             (wrap (or (get-text-property pos 'wrap-prefix) wrap-prefix))
             (line (or (get-text-property pos 'line-prefix) line-prefix))
             (key (overlay-get overlay '+my/prefixes)))
        ;; Only when the line, its prefixes or the face changed (this runs
        ;; before every redisplay).
        (unless (and key (eq (nth 0 key) wrap) (eq (nth 1 key) line)
                     (equal (nth 2 key) face) (eql (nth 3 key) pos))
          (overlay-put overlay '+my/prefixes (list wrap line face pos))
          (overlay-put overlay 'wrap-prefix
                       (+my/hl-line--prefix wrap face))
          (overlay-put overlay 'line-prefix
                       (+my/hl-line--prefix line face)))))))

;; `global-hl-line-sticky-flag' `window' (Doom's): an overlay per window, kept
;; in a window parameter; otherwise one moved by `hl-line-move'.
(defadvice! +my/hl-line-window-prefixes-a (window)
  :after #'global-hl-line-window-redisplay
  (+my/hl-line-prefixes (window-parameter window 'hl-line-overlay)))

(defadvice! +my/hl-line-move-prefixes-a (overlay)
  :after #'hl-line-move
  (+my/hl-line-prefixes overlay))

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

;; TREE-SITTER
;; Every check that a grammar is available, and every parser made, loads its
;; library again (dlopen), and with this many libraries loaded (each natively
;; compiled package is one) that takes ~10 ms on macOS. Opening a Markdown file
;; checked its grammars ~9 times (a missing one: 36 paths tried each time).
;; Remember the answers (cleared when a grammar gets installed).
(defvar +my/treesit--available (make-hash-table :test #'equal)
  "LANGUAGE -> its `treesit-language-available-p' answer with DETAIL.")

(defadvice! +my/treesit-remember-available-a (fn language &optional detail)
  :around #'treesit-language-available-p
  (let ((answer (or (gethash language +my/treesit--available)
                    (puthash language (funcall fn language t) +my/treesit--available))))
    (if detail answer (car answer))))

(defadvice! +my/treesit-forget-available-a (&rest _)
  :after #'treesit-install-language-grammar
  (clrhash +my/treesit--available))


;; HIGHLIGHTING AFTER THE FIRST DISPLAY
;; A file just opened shows right away, plain, and gets its colours a moment
;; later. Highlighting the screen (in Markdown: a tree-sitter parser per
;; paragraph, see above) used to come first, everything that opening a file
;; does measured the screen (restoring the saved place and centring it, the
;; stripe...) and so highlighted it, while the previous file stayed on screen.
;; Like jit-lock's own deferral (`jit-lock-defer-time'), but only until a file
;; just opened is first displayed: scrolling isn't deferred, so no plain text
;; flashes by. Not when a file shown already is reverted (changed on disk).
(defvar-local +my/defer-fontification nil
  "Non-nil while highlighting waits for this buffer's first display.")

(defadvice! +my/jit-lock-defer-first-a (fn start)
  :around #'jit-lock-function
  (if (not +my/defer-fontification)
      (funcall fn start)
    ;; As jit-lock's deferral does: redisplay takes it as done, for now.
    (with-silent-modifications
      (put-text-property start
                         (next-single-property-change
                          start 'fontified nil
                          (min (point-max) (+ start jit-lock-chunk-size)))
                         'fontified 'defer))))

(defun +my/defer-fontification-h ()
  (when (and (bound-and-true-p jit-lock-mode)
             (not (get-buffer-window (current-buffer) t)))
    (setq +my/defer-fontification t)
    (add-hook 'pre-redisplay-functions #'+my/defer-fontification-shown-h nil t)))

(defun +my/defer-fontification-shown-h (_window)
  "A window is drawing the buffer, plain: highlight it right after."
  (remove-hook 'pre-redisplay-functions #'+my/defer-fontification-shown-h t)
  (let ((buffer (current-buffer)))
    ;; Not an idle timer: opening a file can wait for input on the way
    ;; (Emacs is "idle" then), before anything was displayed.
    (run-at-time 0 nil (lambda ()
                         (when (buffer-live-p buffer)
                           (with-current-buffer buffer
                             (setq +my/defer-fontification nil)
                             (jit-lock-refontify)))))))

;; Before saveplace (and Doom's centring after it) measures the screen.
(add-hook 'find-file-hook #'+my/defer-fontification-h -90)
