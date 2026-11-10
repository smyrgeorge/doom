;;; $DOOMDIR/config/editor/large-files.el -*- lexical-binding: t; -*-
;; Large files, and files with very long lines, opened light at once.
;; Loaded from config/editor.el, after long-lines.el.

;; DECIDED BEFORE THE FILE'S MODE
;; so-long (Doom's `doom-so-long-p') turned a file with very long lines into
;; `so-long-mode', and one with many lines `so-long-minor-mode', but after its
;; own mode and that mode's hooks had run on all of it, and only once it was
;; shown: a 3.4 MB agent-shell transcript ran markdown-ts-mode, the language
;; server, the sticky header, the stripe... froze Emacs, then switched (with a
;; treesit-parser-p error left behind). Now the file's text is looked at before
;; its mode is applied (the mode it would get looked up, not run), and a file
;; of code, text or config (`so-long-target-modes') opens light at once:
;; - very long lines (over `so-long-threshold'): `so-long-mode', its own mode
;;   never run (long-lines.el's notice; Open normally runs it);
;; - large (more lines than Doom's `doom-file-lines-threshold-alist' says, or
;;   over `+my/large-file-size'): its own mode, without the language server
;;   (Doom's MODE-local-vars-hook not run), `so-long-minor-mode' at once
;;   (spelling, syntax checking... off), no sticky header nor error stripe; a
;;   notice says so, with Open normally (asked first over
;;   `+my/large-file-ask-size'). Its mode's scan of the whole buffer while it
;;   sets up is skipped too: markdown-mode runs `syntax-propertize' to its end
;;   first (14 s on 60,000 lines); done as it's needed then, for what's shown.
;; Doom's and so-long's, bound below (dynamically: special here too).
(defvar doom-inhibit-local-var-hooks)
(defvar so-long-enabled)

(defvar-local +my/large-file nil
  "In a file opened light for its size: (SIZE . LINES).")
(put '+my/large-file 'permanent-local t)

(defvar-local +my/large-files--normally nil
  "Non-nil once the file was opened normally: not light again.")
(put '+my/large-files--normally 'permanent-local t)

(defvar +my/large-files--light nil
  "Non-nil while a large file's mode sets up (see above).")

(defvar +my/large-files--looking nil
  "While a file's mode is looked up, not applied: a cons, its car the mode.")

(defvar +my/large-files-modes-off '(+my/sticky-header-mode +my/stripe-mode)
  "Modes of this config a large file opens without (see above).")

(defun +my/large-files--max-lines ()
  "How many lines make this file large (Doom's threshold for it, else 20,000)."
  (or (and (boundp 'doom-file-lines-threshold-alist)
           (assoc-default buffer-file-name doom-file-lines-threshold-alist #'string-match-p))
      20000))

(defun +my/large-files--kind ()
  "This buffer's, a file's just read: `long' (a line over `so-long-threshold'),
`large' (see above), or nil."
  (when (and buffer-file-name
             (not +my/large-files--normally)
             (not (string-prefix-p " " (buffer-name))))
    (require 'so-long)
    (let ((stats (buffer-line-statistics)))
      (cond ((> (cadr stats) so-long-threshold) 'long)
            ((or (> (car stats) (+my/large-files--max-lines))
                 (> (buffer-size) +my/large-file-size))
             'large)))))

(defun +my/large-files--target-p (mode)
  "Whether MODE (a major mode) is one so-long acts on: code, text, config;
its file loaded first if it's only autoloaded, to know what it derives from."
  (when (and mode (symbolp mode))
    (let ((function (major-mode-remap mode)))
      (when (autoloadp (symbol-function function))
        (ignore-errors (autoload-do-load (symbol-function function) function)))
      (and (fboundp function)
           (or (eq so-long-target-modes t)
               (apply #'provided-mode-derived-p function so-long-target-modes))))))

(defun +my/large-files-look-up-a (fn mode &optional keep-mode-if-same)
  "`set-auto-mode-0': while the mode is looked up, MODE noted, not applied."
  (if +my/large-files--looking
      (progn (unless (car +my/large-files--looking)
               (setcar +my/large-files--looking mode))
             mode)
    (funcall fn mode keep-mode-if-same)))

(defun +my/large-files--long (mode)
  "`so-long-mode' at once, MODE (never run) kept as the file's own, which
Open normally (`so-long-mode-revert') runs."
  ;; What so-long remembers as the mode it replaced.
  (setq major-mode mode)
  (so-long 'so-long-mode))

(defun +my/large-files--large (fn args)
  "FN, `set-auto-mode', with ARGS: the file's mode light (see above)."
  (setq +my/large-file (cons (buffer-size) (car (buffer-line-statistics))))
  (let ((doom-inhibit-local-var-hooks t)
        (so-long-enabled nil)
        (+my/large-files--light t))
    (apply fn args))
  (if (not (+my/large-files--target-p major-mode))
      (setq +my/large-file nil)
    (so-long 'so-long-minor-mode)
    (dolist (mode +my/large-files-modes-off)
      (when (and (boundp mode) (symbol-value mode))
        (funcall mode -1)))
    (+my/large-files-notice)))

(defun +my/large-files-set-auto-mode-a (fn &rest args)
  "`set-auto-mode': a large file, or one with very long lines, light at once
\(see above)."
  (pcase (+my/large-files--kind)
    ('long
     (let ((looked (list nil)))
       (let ((+my/large-files--looking looked)
             (so-long-enabled nil))
         (apply fn args))
       (let ((mode (car looked)))
         (cond ((+my/large-files--target-p mode)
                (+my/large-files--long (major-mode-remap mode)))
               (mode (set-auto-mode-0 mode (car args)))))))
    ('large (+my/large-files--large fn args))
    (_ (apply fn args))))

(defun +my/large-files-no-scan-a (fn &rest args)
  "`syntax-propertize': not while a large file's mode sets up (see above)."
  (unless +my/large-files--light
    (apply fn args)))

;; Outside so-long's own (added later, when the first file opens).
(advice-add 'set-auto-mode :around #'+my/large-files-set-auto-mode-a '((depth . -90)))
(advice-add 'set-auto-mode-0 :around #'+my/large-files-look-up-a)
(advice-add 'syntax-propertize :around #'+my/large-files-no-scan-a)

;; THE NOTICE (config/banner.el's), a warning, as long-lines.el's: what a large
;; file opened without, with the way back.
(defun +my/large-files--size (bytes)
  "BYTES said: \"3.4 MB\", \"812 KB\"."
  (if (>= bytes (* 1024 1024))
      (format "%.1f MB" (/ bytes 1048576.0))
    (format "%d KB" (max 1 (round bytes 1024)))))

(defun +my/large-files-notice ()
  "In a large file opened light, say what it's without (see above)."
  (when-let* ((large +my/large-file))
    (+my/banner-show
     'large-file
     (format "This file is large (%s, %s lines): opened without the language server, spelling, syntax checking, the sticky header and the error stripe, to keep Emacs responsive."
             (+my/large-files--size (car large)) (+my/long-lines--group-digits (cdr large)))
     :type 'warning
     :actions '(("Open normally" . +my/large-files-open-normally)))))

(defun +my/large-files-open-normally ()
  "The large file in its own mode with everything (asked first over
`+my/large-file-ask-size')."
  (interactive)
  (when (or (<= (buffer-size) +my/large-file-ask-size)
            (y-or-n-p (format "Open this %s file with everything on (Emacs may be slow while it's open)? "
                              (+my/large-files--size (buffer-size)))))
    (setq +my/large-files--normally t
          +my/large-file nil)
    (+my/banner-close 'large-file)
    (let ((so-long-enabled nil))
      (when (bound-and-true-p so-long--active)
        (so-long-revert))
      (normal-mode))))
