;;; $DOOMDIR/config/markdown/notice.el -*- lexical-binding: t; -*-
;; The notice offering the preview. Loaded from config/markdown.el.

;; PREVIEW NOTICE (see config/markdown.el)
(defun +my/markdown-preview-notice-h ()
  (when (and +my/markdown-preview-notice
             buffer-file-name
             (not (bound-and-true-p +md-preview-mode))
             (+my/markdown-preview-live-p))
    (+my/banner-show
     'markdown-preview
     "See this file rendered next to it, updated as you type (SPC m p)."
     :actions '(("Open preview" . +my/markdown-preview-show)))))

(add-hook 'markdown-mode-hook #'+my/markdown-preview-notice-h)

(add-hook 'markdown-ts-mode-hook #'+my/markdown-preview-notice-h)
