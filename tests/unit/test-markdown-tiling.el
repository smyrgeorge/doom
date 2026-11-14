;;; tests/unit/test-markdown-tiling.el -*- lexical-binding: t; -*-
;; config/markdown with config/tiling: the live preview in a pane of its own;
;; closed, by SPC m p or q, its pane closes with it, but for the tabs under
;; it. WebKit is said to work (`+my/markdown-preview-live-p'), its views
;; never started (no redisplay in batch); pandoc not run.

(require 'markdown-mode)
(+test-load "config/window" "config/tiling" "config/webkit" "config/markdown")

(defmacro +test-md-tiling (&rest body)
  "BODY from one window, tiling (tall), the live preview working, its temp
files in the test's folder."
  (declare (indent 0))
  `(let ((temporary-file-directory
          (file-name-as-directory (make-temp-file (+test-tmp-file "md-tiling-") t)))
         (+my/markdown-preview-notice nil))
     (cl-letf (((symbol-function '+my/markdown-preview-live-p) (lambda () t))
               ((symbol-function '+my/webkit-p) (lambda () t))
               ((symbol-function '+md-preview--fragment) (lambda () "<p>x</p>")))
       (+test-with-reset
         (let ((this-command 'test)
               (+my/tiling-strategy 'tall)
               (+my/tiling-tall-ratio 0.5)
               (+my/tiling-apps 'all)
               (+my/focus-new-windows t))
           ,@body)))))

(defun +test-md-tiling--file (name)
  "A Markdown file NAME, visited in the selected window; its buffer."
  (let ((buffer (find-file-noselect (+test-file (concat "md-tiling/" name) "# Title\n"))))
    (switch-to-buffer buffer)
    (markdown-mode)
    buffer))

(ert-deftest markdown-tiling/preview-closed-with-its-pane ()
  "SPC m p opens the preview in a pane of its own; SPC m p or q closes it
with its pane."
  (dolist (close '(toggle quit))
    (+test-md-tiling
      (let ((md (+test-md-tiling--file "README.md")))
        (+my/markdown-preview-toggle)
        (let ((preview (buffer-local-value '+md-preview--buffer md)))
          (should (equal (mapcar #'window-buffer (+my/tiling--panes)) (list md preview)))
          (should (eq (window-buffer (selected-window)) md))
          (if (eq close 'toggle)
              (with-current-buffer md (+my/markdown-preview-toggle))
            (with-selected-window (get-buffer-window preview) (+my/markdown-preview-quit)))
          (should-not (buffer-live-p preview))
          (should-not (buffer-local-value '+md-preview-mode md))
          (should (equal (mapcar #'window-buffer (+my/tiling--panes)) (list md))))))))

(ert-deftest markdown-tiling/preview-closed-keeps-the-tabs-under-it ()
  "A file shown in the preview's pane, the preview a tab behind it; SPC m p
shows the preview there again, SPC m p again closes it: the pane stays,
showing the file."
  (+test-md-tiling
    (let* ((md (+test-md-tiling--file "tabs.md"))
           (other (find-file-noselect (+test-file "md-tiling/other.txt" "other\n"))))
      (+my/markdown-preview-toggle)
      (let* ((preview (buffer-local-value '+md-preview--buffer md))
             (pane (get-buffer-window preview)))
        (set-window-buffer pane other)
        (with-current-buffer md (+my/markdown-preview-toggle))
        (should (eq (window-buffer pane) preview))
        (with-current-buffer md (+my/markdown-preview-toggle))
        (should-not (buffer-live-p preview))
        (should (window-live-p pane))
        (should (eq (window-buffer pane) other))
        (should (equal (mapcar #'window-buffer (+my/tiling--panes)) (list md other)))))))
