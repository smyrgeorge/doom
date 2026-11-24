;;; tests/unit/test-mermaid-tiling.el -*- lexical-binding: t; -*-
;; config/mermaid with config/tiling: the preview (mmdc's image: no WebKit)
;; in a pane of its own; closed, by SPC m p or q, its pane closes with it,
;; but for the tabs under it. mmdc is a stand-in (tests/helper-mermaid.el).

(+test-load "config/emacs" "config/tiling" "config/webkit" "config/mermaid")
(require 'mermaid-mode)
(load (expand-file-name "../helper-mermaid" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(defmacro +test-mermaid-tiling (&rest body)
  "BODY from one window, tiling (tall), in a GUI without WebKit (faked), the
stand-in mmdc drawing, panes shown by `display-buffer' itself (not as
`+test-mermaid--with-mmdc' fakes it)."
  (declare (indent 0))
  `(let* ((mmdc (+test-mermaid--make-mmdc))
          (+my/mermaid-mmdc mmdc)
          (+my/mermaid-cache-directory (file-name-as-directory (make-temp-file (+test-tmp-file "mermaid/cache-") t)))
          (+my/mermaid--waiting (make-hash-table :test #'equal))
          (+my/mermaid--queue nil)
          (+my/mermaid--running 0)
          (+my/mermaid--pruned t)
          (+my/mermaid--written nil)
          (+my/mermaid-preview-notice nil))
     (cl-letf (((symbol-function '+my/webkit-p) #'ignore)
               ((symbol-function 'display-graphic-p) (lambda (&rest _) t))
               ((symbol-function 'image-type-available-p) (lambda (&rest _) t)))
       (+test-mermaid--theme +test-mermaid--dark
         (+test-with-reset
           (unwind-protect
               (let ((this-command 'test)
                     (+my/tiling-strategy 'tall)
                     (+my/tiling-tall-ratio 0.5)
                     (+my/tiling-apps 'all)
                     (+my/focus-new-windows t))
                 ,@body)
             (dolist (process (process-list))
               (when (equal (process-name process) "mmdc") (delete-process process)))))))))

(defun +test-mermaid-tiling--file (name)
  "A Mermaid file NAME, visited in the selected window; its buffer."
  (let ((buffer (find-file-noselect (+test-file (concat "mermaid/tiling/" name) "flowchart TD\n"))))
    (switch-to-buffer buffer)
    buffer))

(ert-deftest mermaid-tiling/preview-closed-with-its-pane ()
  "SPC m p opens the preview in a pane of its own; SPC m p or q closes it
with its pane."
  (dolist (close '(toggle quit))
    (+test-mermaid-tiling
      (let ((mmd (+test-mermaid-tiling--file "flow.mmd")))
        (+my/mermaid-preview-toggle)
        (let ((preview (buffer-local-value '+my/mermaid-preview--buffer mmd)))
          (should (equal (mapcar #'window-buffer (+my/tiling--panes)) (list mmd preview)))
          (if (eq close 'toggle)
              (with-current-buffer mmd (+my/mermaid-preview-toggle))
            (with-selected-window (get-buffer-window preview) (+my/mermaid-preview-quit)))
          (should-not (buffer-live-p preview))
          (should (equal (mapcar #'window-buffer (+my/tiling--panes)) (list mmd))))))))

(ert-deftest mermaid-tiling/preview-closed-keeps-the-tabs-under-it ()
  "A file shown in the preview's pane, the preview a tab behind it; SPC m p
shows the preview there again, SPC m p again closes it: the pane stays,
showing the file."
  (+test-mermaid-tiling
    (let* ((mmd (+test-mermaid-tiling--file "tabs.mmd"))
           (other (find-file-noselect (+test-file "mermaid/tiling/other.txt" "other\n"))))
      (+my/mermaid-preview-toggle)
      (let* ((preview (buffer-local-value '+my/mermaid-preview--buffer mmd))
             (pane (get-buffer-window preview)))
        (set-window-buffer pane other)
        (with-current-buffer mmd (+my/mermaid-preview-toggle))
        (should (eq (window-buffer pane) preview))
        (with-current-buffer mmd (+my/mermaid-preview-toggle))
        (should-not (buffer-live-p preview))
        (should (window-live-p pane))
        (should (eq (window-buffer pane) other))
        (should (equal (mapcar #'window-buffer (+my/tiling--panes)) (list mmd other)))))))
