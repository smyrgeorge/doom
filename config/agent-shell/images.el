;;; $DOOMDIR/config/agent-shell/images.el -*- lexical-binding: t; -*-
;; Images in Claude Code's replies. Loaded from config/agent-shell.el.

;; AS WIDE AS THE ROOM THEY HAVE
;; Images (and diagrams, config/agent-shell/mermaid.el) as wide as the window
;; at most, as config/agent-shell.el has them, are drawn after the 2 columns a
;; reply is indented by (agent-shell's line-prefix): as wide as the window,
;; they were cut by as much at its right edge. A share of the window
;; (`agent-shell-markdown-image-max-width' a fraction) is now at most the
;; width beside that indent; a size in pixels is left as it is.
(defun +my/agent-shell-image-max-width-a (width)
  "`agent-shell-markdown--image-max-width' (WIDTH, pixels): at most the window
beside a reply's indent, for a share of the window (see above)."
  (if (floatp agent-shell-markdown-image-max-width)
      (let ((window (or (get-buffer-window (current-buffer) t) (frame-first-window))))
        (max 1 (min width (- (window-body-width window t)
                             (string-pixel-width "  " (window-buffer window))))))
    width))

(advice-add 'agent-shell-markdown--image-max-width :filter-return #'+my/agent-shell-image-max-width-a)
