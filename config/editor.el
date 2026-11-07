;;; $DOOMDIR/config/editor.el -*- lexical-binding: t; -*-
;; Editing helpers. Loaded from config.el; getting around is
;; config/navigation.el.

;; ====== KEY BINDINGS ======

(map! :leader :desc "Cycle case style" "c ~" #'string-inflection-all-cycle)

;; ====== CODE ======

;; EDITING
;; SPC c ~: cycle the word at point through snake_case, UPPER_CASE,
;; PascalCase, camelCase and kebab-case.
(use-package! string-inflection
  :commands string-inflection-all-cycle)

;; RAINBOW BRACKETS
;; Color (), [] and {} by nesting depth in code, so matching pairs are easy
;; to spot.
(use-package! rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;; RIGHT MARGIN
;; A thin vertical line at the column lines shouldn't go past, in files of code, text and configuration: at `fill-column'
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

;; CURRENT LINE AND SELECTION ACROSS WRAPPED ROWS
;; A long line wraps onto rows indented like it (Doom's word wrap: e.g. two
;; spaces in a Markdown table), and the current line's highlight, and the
;; selection's, left that indentation out: Emacs draws a line's wrap prefix
;; (and line prefix) without the faces of the overlays on it, so a strip of
;; plain background stayed at the start of each continuation row. hl-line's
;; overlay now carries copies of the line's prefixes in its face (an overlay's
;; prefix wins over the text's); the selection, which spans lines with their
;; own prefixes, gets a small overlay per line on screen.
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
             ;; Only where the highlight is the whole line, across the window:
             ;; a mode that highlights part of it (Doom's dashboard: the menu
             ;; item, its line centred by a prefix) keeps that look.
             (whole (= (overlay-end overlay)
                       (save-excursion (goto-char pos)
                                       (line-beginning-position 2))))
             (face (overlay-get overlay 'face))
             (wrap (and whole (or (get-text-property pos 'wrap-prefix)
                                  wrap-prefix)))
             (line (and whole (or (get-text-property pos 'line-prefix)
                                  line-prefix)))
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

(defun +my/region-prefixes (window)
  "Give the selected lines on WINDOW's screen their prefixes in the
selection's face, each over its part of the selection (see above)."
  (let* ((region (window-parameter window 'internal-region-overlay))
         (buffer (window-buffer window))
         (active (and (overlayp region) (eq (overlay-buffer region) buffer)
                      (< (overlay-start region) (overlay-end region))))
         ;; Redone only when the selection, the scroll position or the text
         ;; (word wrap adds prefixes as lines are first shown) changed.
         (key (and active
                   (list (overlay-start region) (overlay-end region)
                         (overlay-get region 'face) (window-start window)
                         (window-body-height window)
                         (buffer-modified-tick buffer)))))
    (unless (equal key (window-parameter window '+my/region-prefixes-key))
      (set-window-parameter window '+my/region-prefixes-key key)
      (let ((spare (window-parameter window '+my/region-prefixes))
            (used nil))
        (when active
          (with-current-buffer buffer
            (save-excursion
              (let* ((face (overlay-get region 'face))
                     (beg (overlay-start region))
                     ;; No further than the screen: a line takes a row at
                     ;; least.
                     (end (min (overlay-end region)
                               (progn (goto-char (window-start window))
                                      (forward-line (window-body-height window))
                                      (point)))))
                (goto-char (max beg (window-start window)))
                (forward-line 0)
                (while (< (point) end)
                  (let* ((bol (point))
                         (wrap (or (get-text-property bol 'wrap-prefix)
                                   wrap-prefix))
                         (line (or (get-text-property bol 'line-prefix)
                                   line-prefix)))
                    (when (or wrap line)
                      (let ((ov (or (pop spare) (make-overlay 1 1))))
                        (move-overlay ov (max bol beg)
                                      (min (line-beginning-position 2)
                                           (overlay-end region))
                                      buffer)
                        (overlay-put ov 'window window)
                        ;; Above hl-line's, which carries its own copies.
                        (overlay-put ov 'priority '(nil . 110))
                        (overlay-put ov 'wrap-prefix
                                     (+my/hl-line--prefix wrap face))
                        (overlay-put ov 'line-prefix
                                     (+my/hl-line--prefix line face))
                        (push ov used))))
                  (forward-line 1))))))
        (mapc #'delete-overlay spare)
        (set-window-parameter window '+my/region-prefixes used)))))

(defadvice! +my/region-prefixes-a (window)
  :after #'redisplay--update-region-highlight
  (when (window-live-p window)
    (+my/region-prefixes window)))

;; HIGHLIGHTING AFTER THE FIRST DISPLAY
;; A file just opened shows right away, plain, and gets its colours a moment
;; later. Highlighting the screen (in Markdown: a tree-sitter parser per
;; paragraph, see config/tree-sitter.el) used to come first, everything that opening a file
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
