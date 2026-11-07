;;; $DOOMDIR/config/editor/fontify.el -*- lexical-binding: t; -*-
;; Highlighting after a file's first display.
;; Loaded from config/editor.el.

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
