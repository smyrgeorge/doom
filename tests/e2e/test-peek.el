;;; tests/e2e/test-peek.el -*- lexical-binding: t; -*-
;; config/lsp/peek.el in a GUI Emacs: lsp-ui's peek of a declaration's usages
;; (gD, Cmd+B) as it shows in panes short and narrow, measured on screen. The
;; language server is mocked (`lsp-request').

;; `use-package!' (config/editor.el...) reads it.
(defvar doom-disabled-packages nil)

(+test-load "config/editor" "config/lsp")

(require 'python)
(require 'hl-line)
(require 'doom-themes)

(set-face-attribute 'default nil :background "#282c34" :foreground "#bbc2cf")
(cl-letf (((symbol-function 'doom-color)
           (lambda (name &optional _type) (pcase name ('blue "#51afef") ('yellow "#ecbe7b")))))
  (require 'lsp-ui))

;; Doom's.
(setq-default truncate-lines t)
(setq truncate-partial-width-windows nil)

;; ====== HELPERS ======

(defconst +test-peek--long
  (concat (mapconcat (lambda (i) (format "# filler line %d" i)) (number-sequence 1 60) "\n")
          "\n\ndef target_function(a, b):\n    return a + b\n\n"
          (mapconcat (lambda (i) (format "def caller_%d():\n    return target_function(%d, 2)\n" i i))
                     (number-sequence 1 30) "\n"))
  "A file: a declaration (line 62), 30 calls of it after it.")

(defun +test-peek--loc (file line col end-line end-col)
  "An LSP Location in FILE (0-based lines and columns)."
  (lsp-make-location
   :uri (lsp--path-to-uri file)
   :range (lsp-make-range :start (lsp-make-position :line line :character col)
                          :end (lsp-make-position :line end-line :character end-col))))

(defun +test-peek--pane (rows)
  "The selected window made ROWS rows tall (of text), another below it."
  (delete-other-windows)
  (let ((window (selected-window)))
    (split-window window (+ rows (- (window-total-height window) (window-body-height window))) 'below)
    (dotimes (_ 5)
      (let ((delta (- rows (window-body-height window))))
        (unless (zerop delta) (ignore-errors (window-resize window delta nil)))))
    (should (= (window-body-height window) rows))
    window))

(defmacro +test-peek-with-long (setup row usages &rest body)
  "SETUP (forms), then long.py open, its declaration on the window's ROW
\(0-based), and its first USAGES calls peeked (gD); BODY, then the peek
closed."
  (declare (indent 3))
  `(+test-with-reset
     (let ((file (file-truename (+test-file "peek/long.py" +test-peek--long))))
       (cl-letf (((symbol-function 'lsp-request)
                  (lambda (_method _params)
                    (vconcat (cl-loop for i from 1 to ,usages
                                      for line = (+ 65 (* 3 (1- i))) ; "return target_function"
                                      collect (+test-peek--loc file line 11 line 26)))))
                 ((symbol-function 'lsp-workspace-root)
                  (lambda (&rest _) (file-name-directory file))))
         ,setup
         (let ((vc-handled-backends nil)) (find-file file))
         (setq-local truncate-lines t)
         (goto-char (point-min))
         (search-forward "def target_fu")
         (recenter ,row)
         (redisplay t)
         (unwind-protect
             (progn (lsp-ui-peek-find-references)
                    (redisplay t)
                    ,@body)
           (lsp-ui-peek--disable)
           (cancel-function-timers #'lsp-ui-peek--disable))))))

(defun +test-peek--row (pos)
  "The window row POS is shown on (0-based), or nil when it isn't shown."
  (when-let* ((visible (pos-visible-in-window-p pos nil t)))
    ;; Its y counts from above the header line (the sticky header).
    (/ (- (cadr visible) (window-header-line-height) (window-tab-line-height))
       (frame-char-height))))

(defun +test-peek--peek-rows ()
  "How many rows the peek takes (its own, the separators and the footer)."
  (cl-count ?\n (overlay-get lsp-ui-peek--overlay 'after-string)))

(defun +test-peek--pane-wide (columns)
  "The selected window made COLUMNS columns wide (of text), another beside
it."
  (delete-other-windows)
  (let ((window (selected-window)))
    (split-window window (+ columns (- (window-total-width window) (window-body-width window))) 'right)
    (dotimes (_ 5)
      (let ((delta (- columns (window-body-width window))))
        (unless (zerop delta) (ignore-errors (window-resize window delta t)))))
    (should (= (window-body-width window) columns))
    window))

(defun +test-peek--row-widths ()
  "The peek's rows, each laid out in its window as it shows there (lines
not wrapped): ((TEXT . PIXEL-WIDTH)...), TEXT with what's shown as a space
as a space."
  (let* ((window (selected-window))
         (shown (overlay-get lsp-ui-peek--overlay 'after-string))
         (old (window-buffer window))
         (start (window-start window))
         (point (window-point window))
         (rows nil))
    (with-current-buffer (get-buffer-create " *test-peek-rows*")
      (erase-buffer)
      (setq-local truncate-lines t)
      (insert shown)
      (set-window-buffer window (current-buffer))
      (set-window-start window (point-min))
      (redisplay t)
      (goto-char (point-min))
      (while (not (eobp))
        (let ((bol (point)) (eol (line-end-position)))
          (push (cons (mapconcat (lambda (pos)
                                   (if (eq (car-safe (get-text-property pos 'display)) 'space)
                                       " "
                                     (char-to-string (char-after pos))))
                                 (number-sequence bol (1- eol)) "")
                      (car (window-text-pixel-size window bol eol 100000)))
                rows))
        (forward-line 1)))
    (set-window-buffer window old)
    (set-window-start window start)
    (set-window-point window point)
    (redisplay t)
    (nreverse rows)))

(defun +test-peek--fits-the-pane ()
  "Each row of the peek no wider than its window; its rows."
  (let ((rows (+test-peek--row-widths)))
    (dolist (row rows)
      (should (<= (cdr row) (window-body-width nil t))))
    (mapcar #'car rows)))

;; ====== HEIGHT ======

(ert-deftest e2e-peek/whole-in-short-panes ()
  "In panes 12, 16 and 24 rows tall, the declaration on row 3, 8 or 12: its
line and every row of the peek, the footer too, on screen (lsp-ui put the
declaration on row 15, the peek off screen)."
  (dolist (rows '(12 16 24))
    (dolist (start '(3 8 12))
      (when (< start rows)
        (+test-peek-with-long (+test-peek--pane rows) start 3
          (let ((row (+test-peek--row (point))))
            (should row)
            (should (<= (+ row 1 (+test-peek--peek-rows)) rows))))))))

(ert-deftest e2e-peek/many-usages-in-a-short-pane ()
  "30 usages in a 16-row pane: a shorter peek, whole on screen, the list
scrolling; in a tall pane as tall as lsp-ui's (20 rows)."
  (+test-peek-with-long (+test-peek--pane 16) 8 30
    (should (< lsp-ui-peek-peek-height 20))
    (should (<= (+ (+test-peek--row (point)) 1 (+test-peek--peek-rows)) 16))
    (dotimes (_ 25) (lsp-ui-peek--select-next))
    (redisplay t)
    (should (> lsp-ui-peek--offset 0)))
  (+test-peek-with-long (+test-peek--pane 40) 3 30
    (should (= lsp-ui-peek-peek-height 20))
    (should (= (+test-peek--row (point)) 3))))

;; ====== WIDTH ======

(ert-deftest e2e-peek/fits-narrow-panes ()
  "At 100, 60, 40 and 25 columns no row of the peek wider than its pane: the
title with its counts, the footer, at 40 the usage's code (15 characters at
least)."
  (dolist (columns '(100 60 40 25))
    (+test-peek-with-long (+test-peek--pane-wide columns) 3 3
      (let ((rows (+test-peek--fits-the-pane)))
        (should (string-match-p "3 in 1 file\\'" (string-trim-right (nth 1 rows))))
        (should (string-match-p "j/k  next/previous" (nth (- (length rows) 2) rows)))
        (when (= columns 40)
          (should (seq-find (lambda (row) (string-match-p "return target_f" row)) rows)))))))

(ert-deftest e2e-peek/its-own-rows-in-a-wrapping-buffer ()
  "In a buffer that wraps (visual-line-mode, Markdown...), the peek takes
its own rows, none wrapped."
  (dolist (columns '(50 35))
    (+test-peek-with-long (+test-peek--pane-wide columns) 3 3
      (setq-local truncate-lines nil)
      (visual-line-mode 1)
      (lsp-ui-peek--select-next)
      (lsp-ui-peek--select-prev)
      (redisplay t)
      (let ((point-row (+test-peek--row (line-beginning-position)))
            (after-row (+test-peek--row (overlay-start lsp-ui-peek--overlay))))
        (should (= (- after-row point-row 1) (+test-peek--peek-rows)))))))

(ert-deftest e2e-peek/drawn-again-when-its-pane-is-resized ()
  "Opened at 100 columns, the pane then 60 (a pane opened beside it): its
rows laid out for 60, no key pressed. Closed, it no longer follows; its
buffer killed while open, no error."
  (+test-peek-with-long (+test-peek--pane-wide 100) 3 3
    (let ((window (selected-window)))
      (should (memq #'+my/peek-redraw-h window-size-change-functions))
      (window-resize window (- 60 (window-body-width window)) t)
      (redisplay t)
      (should (= (window-body-width window) 60))
      (+test-peek--fits-the-pane)
      (lsp-ui-peek--disable)
      (should-not (memq #'+my/peek-redraw-h window-size-change-functions))))
  (+test-peek-with-long (+test-peek--pane-wide 100) 3 3
    (let ((window (selected-window))
          (errors (+test-messages "^Error")))
      (kill-buffer (current-buffer))
      (window-resize window (- 60 (window-body-width window)) t)
      (redisplay t)
      (should (= (+test-messages "^Error") errors)))))

;;; test-peek.el ends here
