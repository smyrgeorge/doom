;;; tests/e2e/test-smooth.el -*- lexical-binding: t; -*-
;; config/editor/smooth.el in a GUI Emacs, with smooth scrolling on as in Doom:
;; the line you're on stays whole at a window's bottom, whose last row a
;; window's height rarely fits (typing there, a new line), while a scroll still
;; leaves it cut. At a buffer's end (Claude Code's prompt): above it, Emacs
;; scrolls by itself.

(+test-load "config/childframe" "config/stripe" "config/editor")
(require 'ultra-scroll)
(ultra-scroll-mode 1)

;; ====== HELPERS ======

(defun +test-smooth--last-row-line ()
  "The line on the window's last row, the cut one."
  (save-excursion
    (goto-char (window-start))
    (forward-line (/ (window-body-height nil t) (line-pixel-height)))
    (line-number-at-pos)))

(defun +test-smooth--cut-p ()
  "Non-nil if point's line is shown, cut by the window's bottom."
  (let ((visible (pos-visible-in-window-p (point) nil t)))
    (and visible (> (or (nth 3 visible) 0) 0))))

(defun +test-smooth--after (command)
  "Redisplay as Emacs does once COMMAND has run."
  (let ((this-command nil)
        (last-command command))
    (redisplay t)))

(defmacro +test-smooth--at-the-bottom (&rest body)
  "BODY in a buffer of lines, in the selected window, whose last line is on
the window's last row, cut (a sliver: rows made a little taller until so),
point at its end: Claude Code's prompt. Shown as after a scroll; scrolling as
in Doom."
  (declare (indent 0))
  `(+test-with-reset
     (switch-to-buffer
      (+test-buffer "*smooth-line*"
                    (mapconcat (lambda (i) (format "line %d" i)) (number-sequence 1 200) "\n")
                    #'text-mode))
     (let ((scroll-conservatively 10)
           (scroll-margin 0))
       (setq-local line-spacing
                   (cl-loop with body = (window-body-height nil t)
                            for spacing from 0 to 30
                            for row = (+ (default-line-height) spacing)
                            when (<= (/ row 4) (mod body row) (- row (/ row 4)))
                            return spacing))
       (should line-spacing)
       (set-window-start nil (point-min))
       (goto-char (point-min))
       (forward-line (+test-smooth--last-row-line))
       (delete-region (1- (point)) (point-max))
       (+test-smooth--after 'ultra-scroll)
       (should (+test-smooth--cut-p))
       ,@body)))

;; ====== TESTS ======

(ert-deftest e2e-smooth/the-setting ()
  "Smooth scrolling's own: asked of redisplay."
  (should (eq (default-value 'make-cursor-line-fully-visible)
              #'+my/smooth-cursor-line-whole-p)))

(ert-deftest e2e-smooth/typing-on-the-cut-row-shows-it-whole ()
  "Typing on the cut row: it's shown whole, the window scrolled one row."
  (+test-smooth--at-the-bottom
    (insert "x")
    (+test-smooth--after 'self-insert-command)
    (should (pos-visible-in-window-p (point)))
    (should-not (+test-smooth--cut-p))
    (should (= (line-number-at-pos (window-start)) 2))))

(ert-deftest e2e-smooth/a-new-line-is-shown-whole ()
  "A new line below the cut row: the window scrolls until it's whole, not only
into the sliver."
  (+test-smooth--at-the-bottom
    (insert "\nmore")
    (should-not (pos-visible-in-window-p (point) nil t))
    (+test-smooth--after 'newline)
    (should (pos-visible-in-window-p (point)))
    (should-not (+test-smooth--cut-p))))

(ert-deftest e2e-smooth/moving-onto-the-cut-row-shows-it-whole ()
  "Onto the cut row (j), at the end or in the middle of a buffer."
  (+test-smooth--at-the-bottom
    (forward-line -1)
    (+test-smooth--after 'evil-previous-line)
    (forward-line 1)
    (+test-smooth--after 'evil-next-line)
    (should-not (+test-smooth--cut-p))
    (should (pos-visible-in-window-p (point)))
    ;; In the middle.
    (save-excursion (insert "\nline\nline"))
    (set-window-start nil (point-min))
    (forward-line -1)
    (+test-smooth--after 'evil-previous-line)
    (forward-line 1)
    (+test-smooth--after 'evil-next-line)
    (should (pos-visible-in-window-p (point)))))

(ert-deftest e2e-smooth/a-scroll-leaves-it-cut ()
  "After a scroll (the wheel, C-e...), the cut row stays cut: no jump back."
  (+test-smooth--at-the-bottom
    (dolist (command '(ultra-scroll evil-scroll-line-down))
      (+test-smooth--after command)
      (should (+test-smooth--cut-p))
      (should (= (window-start) (point-min))))))

(ert-deftest e2e-smooth/other-windows-left-cut ()
  "A window not selected keeps its cut row (its point there after the wheel
scrolled it): what's typed elsewhere doesn't move it."
  (+test-smooth--at-the-bottom
    (let ((window (selected-window)))
      (select-window (split-window-right))
      (switch-to-buffer (+test-buffer "*smooth-other*" "x" #'text-mode))
      (insert "y")
      (+test-smooth--after 'self-insert-command)
      (should (= (window-start window) (point-min)))
      (with-selected-window window
        (should (+test-smooth--cut-p))))))
