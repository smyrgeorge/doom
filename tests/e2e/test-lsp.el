;;; tests/e2e/test-lsp.el -*- lexical-binding: t; -*-
;; config/lsp/lenses.el in a GUI Emacs: a code lens in panes narrow and wide,
;; lines truncated or wrapped, measured on screen.

;; `use-package!' (config/editor.el...) reads it.
(defvar doom-disabled-packages nil)

(+test-load "config/editor" "config/lsp")

(require 'lsp-lens)

;; ====== HELPERS ======

(defconst +test-lsp--code
  "    pub fn compute_total(items: &[Item]) -> u64 {\n        0\n    }\n"
  "A 49-character line, then a short one.")

(defun +test-lsp--pane-wide (columns)
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

(defun +test-lsp--with-lens (columns wrap)
  "The code in a pane COLUMNS wide, its lines wrapped if WRAP, the first one
with a lens of three (as lsp-mode shows them); the lens's overlay."
  (+test-lsp--pane-wide columns)
  (switch-to-buffer (+test-buffer "lens.rs" +test-lsp--code))
  (setq-local truncate-lines (not wrap))
  (when wrap (visual-line-mode 1))
  (let* ((lsp-lens-place-position 'end-of-line)
         (titles (mapcar (lambda (title) (propertize title 'face 'lsp-lens-face))
                         '("▶ Run" "3 implementations" "12 references")))
         (ov (save-excursion (goto-char (point-min))
                             (make-overlay (line-end-position) (line-end-position) nil t t))))
    (overlay-put ov 'lsp-lens t)
    (overlay-put ov 'lsp--metadata titles)
    (overlay-put ov 'lsp--lens-contents (string-join titles "|"))
    (lsp-lens--update ov)
    (set-window-start nil (point-min))
    (redisplay t)
    ov))

(defun +test-lsp--row (pos)
  "The window row POS shows on (0-based)."
  (/ (- (cadr (pos-visible-in-window-p pos nil t)) (window-header-line-height))
     (frame-char-height)))

(defun +test-lsp--widths (string)
  "The pixel width of each row of STRING laid out in the selected window."
  (let ((window (selected-window))
        (old (window-buffer))
        (widths nil))
    (with-current-buffer (get-buffer-create " *test-lsp-rows*")
      (erase-buffer)
      (setq-local truncate-lines t)
      (insert string)
      (set-window-buffer window (current-buffer))
      (redisplay t)
      (goto-char (point-min))
      (while (not (eobp))
        (push (car (window-text-pixel-size window (point) (line-end-position) 100000)) widths)
        (forward-line 1)))
    (set-window-buffer window old)
    (redisplay t)
    (nreverse widths)))

;; ====== CODE LENSES ======

(ert-deftest e2e-lsp/lens-whole-in-a-narrow-pane ()
  "At 40 columns, lines truncated or wrapped: the lens above its line, on
rows the pane shows whole, the code right under it (it was cut off, or
hidden, or ran on into the code's rows)."
  (dolist (wrap '(nil t))
    (+test-with-reset
      (let* ((ov (+test-lsp--with-lens 40 wrap))
             (above (overlay-get ov 'before-string))
             (rows (cl-count ?\n above)))
        (should above)
        (should-not (overlay-get ov 'after-string))
        (should (= rows 2))
        (dolist (width (+test-lsp--widths above))
          (should (<= width (window-body-width nil t))))
        (should (= (+test-lsp--row (point-min)) rows))))))

(ert-deftest e2e-lsp/lens-at-the-end-of-a-line-that-fits ()
  "At 100 columns the lens stays at the end of its line, the next line under
it."
  (+test-with-reset
    (let ((ov (+test-lsp--with-lens 100 nil)))
      (should (overlay-get ov 'after-string))
      (should-not (overlay-get ov 'before-string))
      (should (= (+test-lsp--row (point-min)) 0))
      (should (= (+test-lsp--row (save-excursion (goto-char (point-min)) (line-beginning-position 2))) 1))
      ;; The line and its lens, whole.
      (should (<= (car (window-text-pixel-size nil (point-min) (overlay-start ov) 100000))
                  (window-body-width nil t))))))

;;; test-lsp.el ends here
