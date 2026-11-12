;;; $DOOMDIR/examples/mermaid.el -*- lexical-binding: t; -*-
;; Example: a Mermaid file and its preview (config/mermaid.el,
;; docs/mermaid.md). M-x +my/example-mermaid writes a diagram to the temp
;; folder (the fruit shop's week, from the delivery to the report: a decision,
;; a loop, a group) and opens it with its preview beside it (SPC m p): drawn
;; in the theme's colours, redrawn as you type. Try changing a label, adding a
;; node, breaking a line (Mermaid's message under the last drawing), SPC m c
;; (the SVG next to the file). The file is deleted once it's closed (its
;; preview with it).

;; ====== VARIABLES ======

(defconst +my/example-mermaid--text "%% The fruit shop's week, from the delivery to the report.
flowchart TD
    delivery([Monday's delivery]) --> stock{In stock?}
    stock -->|no| farm[Order from the farm]
    farm --> delivery
    stock -->|yes| shelves[Put on the shelves]
    shelves --> sales
    subgraph report [The weekly report]
        sales[(This week's sales)] --> summary[A line per fruit]
    end
"
  "The diagram.")

;; ====== CODE ======

(defun +my/example-mermaid ()
  "Example: a Mermaid file and its preview (deleted once closed). See
examples/mermaid.el."
  (interactive)
  (let* ((dir (+my/example-folder "mermaid"))
         (file (+my/example-write dir "week.mmd" +my/example-mermaid--text)))
    (delete-other-windows)
    (find-file file)
    (let ((buffer (current-buffer)))
      (if (+my/mermaid-preview-live-p)
          (+my/mermaid-preview-toggle)
        (message "No preview here (it needs the GUI): SPC m o opens the diagram in Mermaid's Live Editor"))
      (when (window-live-p (get-buffer-window buffer))
        (select-window (get-buffer-window buffer)))
      (+my/example-delete-when-closed dir (list buffer))
      (when (+my/mermaid-preview-live-p)
        (message "Mermaid example: change a label, add a node, break a line; SPC m p closes the preview"))
      buffer)))

(defun +my/example-mermaid-ready ()
  "Non-nil once the example's preview has drawn its diagram."
  (when-let* ((source (seq-find (lambda (buffer)
                                  (and (buffer-local-value '+my/example--closing buffer)
                                       (buffer-local-value '+my/mermaid-preview--buffer buffer)))
                                (buffer-list)))
              (preview (buffer-local-value '+my/mermaid-preview--buffer source))
              ((buffer-live-p preview))
              (window (get-buffer-window preview t)))
    (with-current-buffer preview
      (if (derived-mode-p '+my/mermaid-preview-page-mode)
          (when-let* ((xwidget (+my/webkit-xwidget window)))
            (equal (xwidget-webkit-title xwidget) "mmd drawn"))
        (and +my/mermaid-preview--svg t)))))

(provide 'example-mermaid)
