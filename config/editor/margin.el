;;; $DOOMDIR/config/editor/margin.el -*- lexical-binding: t; -*-
;; The right margin's line, at fill-column.
;; Loaded from config/editor.el.

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
