;;; $DOOMDIR/config/editor/long-lines.el -*- lexical-binding: t; -*-
;; The notice on files with very long lines, opened plain and unwrapped.
;; Loaded from config/editor.el.

;; THE NOTICE (config/banner.el's), a warning: very long lines aren't wrapped
;; nor highlighted; its actions wrap them, or open the file normally.
(defun +my/long-lines--group-digits (n)
  "N with thousands separators: 51997 -> \"51,997\"."
  (let ((s (number-to-string n)))
    (while (string-match "\\([0-9]\\)\\([0-9]\\{3\\}\\)\\(,\\|\\'\\)" s)
      (setq s (replace-match "\\1,\\2\\3" t nil s)))
    s))

(defun +my/long-lines-notice-h ()
  "In `so-long-mode' (very long lines), say the file is shown plain and unwrapped."
  (when (derived-mode-p 'so-long-mode)
    (+my/banner-show
     'long-lines
     (format "This file has very long lines (up to %s characters): shown without highlighting%s, to keep scrolling smooth."
             (+my/long-lines--group-digits (cadr (buffer-line-statistics)))
             (if truncate-lines " and unwrapped" ""))
     :type 'warning
     :actions `(,@(and truncate-lines '(("Wrap lines" . +my/long-lines--wrap)))
                ("Open normally" . +my/long-lines--open-normally)))))

(defun +my/long-lines--wrap ()
  (setq-local truncate-lines nil)
  ;; Same notice, without the part about wrapping.
  (+my/long-lines-notice-h))

(defun +my/long-lines--open-normally ()
  ;; Back to the file's own mode. Not `so-long-revert': Doom's action keeps
  ;; what to undo in a buffer-local variable that entering `so-long-mode'
  ;; wipes, so it did nothing.
  (so-long-mode-revert))

(add-hook 'so-long-hook #'+my/long-lines-notice-h)
