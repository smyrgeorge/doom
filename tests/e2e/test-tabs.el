;;; tests/e2e/test-tabs.el -*- lexical-binding: t; -*-
;; config/editor/tabs.el in a GUI Emacs: the tab line as drawn, in pixels. A
;; long current tab shown whole, its ✕ inside the window, in narrow panes
;; (its label shortened) and past the scroll arrows; short labels as they
;; are.

(+test-load "config/window" "config/editor")
(require 'tab-line)
;; Tabs' icons, as in Doom.
(require 'nerd-icons nil t)
(global-tab-line-mode 1)

;; As Doom: no scroll bars, a divider of a pixel between windows.
(scroll-bar-mode -1)
(setq window-divider-default-places t
      window-divider-default-right-width 1
      window-divider-default-bottom-width 1)
(window-divider-mode 1)

(defconst +test-tabs--long "AgreementControllerIntegrationTest.kt")

;; ====== HELPERS ======

(defun +test-tabs--files (&rest names)
  "Files NAMES (in a new folder) visited, each shown in turn in the selected
window (its tabs), the last one current; their buffers."
  (let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "tabs-") t)))
         (buffers (mapcar (lambda (name)
                            (with-temp-file (expand-file-name name dir) (insert name "\n"))
                            (find-file-noselect (expand-file-name name dir)))
                          names)))
    (dolist (buffer buffers)
      (with-current-buffer buffer (tab-line-mode 1))
      (switch-to-buffer buffer))
    buffers))

(defun +test-tabs--drawn (window buffer)
  "BUFFER's tab as drawn in WINDOW's tab line: (FIRST LAST LENGTH TEXT), the
first and last positions of its string seen across the tab line, its
string's length and text; nil if not shown."
  (let ((x 0) first last string done)
    (while (and (not done) (< x (window-pixel-width window)))
      (let* ((posn (posn-at-x-y x 3 window t))
             (at (and (eq (posn-area posn) 'tab-line) (posn-string posn))))
        (if (and at (eq (get-text-property (cdr at) 'tab (car at)) buffer))
            (setq string (car at)
                  first (min (or first (cdr at)) (cdr at))
                  last (max (or last 0) (cdr at)))
          ;; Past it.
          (setq done string)))
      (setq x (1+ x)))
    (and string (list first last (length string) (substring-no-properties string)))))

(defun +test-tabs--whole-p (window buffer)
  "Non-nil if BUFFER's tab is drawn whole in WINDOW's tab line: from its
first character (after the space between tabs) to its last, after its ✕."
  (pcase-let ((`(,first ,last ,length ,_) (+test-tabs--drawn window buffer)))
    (and first (<= first 1) (= last (1- length)))))

(defun +test-tabs--pane (columns)
  "The selected window COLUMNS wide (a window on its right), drawn; it."
  (delete-other-windows)
  (split-window-right columns)
  (redisplay t)
  (selected-window))

;; ====== A LONG CURRENT TAB ======

(ert-deftest e2e-tabs/a-long-current-tab-whole-in-a-narrow-pane ()
  "25, 30 and 40 columns: the long current tab in view, whole (its label
shortened where need be, its end kept); alone or among others."
  (+test-with-reset
    (let* ((buffers (+test-tabs--files "Makefile" "editor.el" "a.txt" +test-tabs--long))
           (long (car (last buffers))))
      (dolist (columns '(40 30 25))
        (let ((window (+test-tabs--pane columns)))
          (should (+test-tabs--whole-p window long))
          (should (string-search ".kt" (nth 3 (+test-tabs--drawn window long))))))
      ;; 25 columns: shortened.
      (should (string-search "…" (nth 3 (+test-tabs--drawn (selected-window) long))))
      ;; Its only tab.
      (set-window-prev-buffers nil nil)
      (set-window-parameter nil 'tab-line-buffers nil)
      (tab-line-force-update nil)
      (redisplay t)
      (should (equal (+my/tabs-window-buffers) (list long)))
      (should (+test-tabs--whole-p (selected-window) long)))))

(ert-deftest e2e-tabs/the-current-tab-whole-past-the-arrows ()
  "Tabs that don't all fit: scrolled to the current one with room for the
arrows before them, its ✕ inside the window; at the end or in the middle,
at any width (they cut it at some: 49 columns, macOS's font)."
  (+test-with-reset
    (let* ((buffers (apply #'+test-tabs--files
                           (append (mapcar (lambda (i) (format "file%02d.txt" i)) (number-sequence 1 9))
                                   (list +test-tabs--long))))
           (long (car (last buffers)))
           cut)
      (dolist (columns (number-sequence 40 130 3))
        (let ((window (+test-tabs--pane columns)))
          (should (window-parameter window 'tab-line-hscroll))
          (dolist (buffer (list (nth 4 buffers) (nth 6 buffers) long))
            (switch-to-buffer buffer)
            (redisplay t)
            (unless (+test-tabs--whole-p window buffer)
              (push (list columns (buffer-name buffer)) cut)))
          ;; Its whole label where there's room for it.
          (when (>= columns 70)
            (should (string-search +test-tabs--long (nth 3 (+test-tabs--drawn window long)))))))
      (should-not cut))))

(ert-deftest e2e-tabs/short-labels-as-they-are ()
  (+test-with-reset
    (let* ((buffers (+test-tabs--files "Makefile" "editor.el" +test-tabs--long))
           (window (+test-tabs--pane 100)))
      (should-not (window-parameter window 'tab-line-hscroll))
      (dolist (buffer buffers)
        (should (+test-tabs--whole-p window buffer))
        (should (string-search (buffer-name buffer) (nth 3 (+test-tabs--drawn window buffer))))
        (should-not (string-search "…" (nth 3 (+test-tabs--drawn window buffer))))))))
