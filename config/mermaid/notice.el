;;; $DOOMDIR/config/mermaid/notice.el -*- lexical-binding: t; -*-
;; The notice offering the preview. Loaded from config/mermaid.el.

;; PREVIEW NOTICE (see config/mermaid.el)
(defun +my/mermaid-preview-notice-h ()
  (when (and +my/mermaid-preview-notice
             buffer-file-name
             (not (bound-and-true-p +my/mermaid-preview-mode))
             (+my/mermaid-preview-live-p))
    (+my/banner-show
     'mermaid-preview
     "See this diagram rendered next to it, updated as you type (SPC m p)."
     :actions '(("Open preview" . +my/mermaid-preview-show)))))

(add-hook 'mermaid-mode-hook #'+my/mermaid-preview-notice-h)
