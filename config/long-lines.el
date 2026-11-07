;;; $DOOMDIR/config/long-lines.el -*- lexical-binding: t; -*-
;; Files with very long lines: opened plain and unwrapped, with a notice.
;; Loaded from config.el, after config/banner.el.

;; ====== VARIABLES ======

;; LONG LINES
;; Files with very long lines (e.g. an HTML report embedding its data as one
;; 50,000-character line) open in `so-long-mode', which still wraps them: one
;; line then fills screens of rows, and each scroll step over it lays it all out
;; again (~60 ms a step: the scroll stuttered). Don't wrap there (~13 ms): the
;; line takes one row; M-x toggle-truncate-lines to read it wrapped.
;; Lines over 5,000 characters count as very long (Doom keeps Emacs's 10,000
;; in native-comp builds): an HTML report with 7,000-character SVG lines stayed
;; in web-mode, where redisplay walks each such line character by character
;; (highlighting, ligatures), ~6 ms a line a pass: scrolling stalled for
;; seconds. A notice says so, with the way back (THE NOTICE, below).
(defvar +my/long-line-threshold 5000
  "Files with lines longer than this many characters open in `so-long-mode'.")

(after! so-long
  (setq so-long-threshold +my/long-line-threshold)
  (setf (alist-get 'truncate-lines so-long-variable-overrides) t))

;; ====== CODE ======

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
