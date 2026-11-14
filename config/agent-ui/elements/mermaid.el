;;; $DOOMDIR/config/agent-ui/elements/mermaid.el -*- lexical-binding: t; -*-
;; Agent UI's Mermaid diagrams: the mermaid type, and the markdown type's
;; ```mermaid blocks (elements/markdown.el). Loaded from
;; config/agent-ui/elements.el.
;;
;; In the GUI, the diagram drawn by config/mermaid.el's renderer (mmdc, in the
;; background, cached, in the theme's colours), at its size, at most the
;; canvas's width; until it's there, its source. An error: Mermaid's message
;; under its source. In a terminal, or without config/mermaid.el, its source,
;; coloured by mermaid-mode. A theme switch draws them again.

(require 'cl-lib)
(require 'subr-x)

(defvar agent-ui-mermaid--errors (make-hash-table :test #'equal)
  "The diagrams that failed, by theme and source: Mermaid's message (or what
to install), not drawn again.")

(defun agent-ui-mermaid--p ()
  "Non-nil if diagrams can be drawn: config/mermaid.el loaded."
  (fboundp '+my/mermaid-render))

(defun agent-ui-mermaid--highlight (diagram)
  "DIAGRAM coloured by mermaid-mode, if it's there."
  (if (not (fboundp 'mermaid-mode))
      diagram
    (with-temp-buffer
      (insert diagram)
      (delay-mode-hooks (mermaid-mode))
      (font-lock-ensure)
      (buffer-string))))

(defun agent-ui-mermaid--sized (svg ctx)
  "SVG (mmdc's, 100% wide) with its size in pixels: as wide as it is, at
most CTX's width. Sized in its data: a snapshot nests it as it's shown."
  (if (not (string-match "<svg\\b[^>]*>" svg))
      svg
    (let* ((root (match-string 0 svg))
           (start (match-beginning 0))
           (end (match-end 0))
           (box (and (string-match "viewBox=\"[-0-9.]+[ ,]+[-0-9.]+[ ,]+\\([0-9.]+\\)[ ,]+\\([0-9.]+\\)\"" root)
                     (cons (string-to-number (match-string 1 root)) (string-to-number (match-string 2 root))))))
      (if (not (and box (> (car box) 0)))
          svg
        (let* ((room (* (plist-get ctx :char-width) (max 1 (1- (plist-get ctx :width)))))
               (scale (min 1.0 (/ (float room) (car box))))
               (root (replace-regexp-in-string " \\(?:width\\|height\\)=\"[^\"]*\"" "" root t t))
               (root (replace-regexp-in-string "max-width: *[^;\"]*;? *" "" root t t)))
          (concat (substring svg 0 start)
                  (replace-regexp-in-string
                   "\\`<svg\\b" (format "<svg width=\"%d\" height=\"%d\""
                                        (round (* scale (car box))) (round (* scale (cdr box))))
                   root t t)
                  (substring svg end)))))))

(defun agent-ui-mermaid--image (file ctx)
  "FILE's SVG as an image (see `agent-ui-mermaid--sized')."
  (propertize "diagram" 'display
              (agent-ui-image (create-image (agent-ui-mermaid--sized
                                             (with-temp-buffer (insert-file-contents file) (buffer-string))
                                             ctx)
                                            'svg t :ascent 'center))))

(defun agent-ui-mermaid-draw (diagram ctx)
  "DIAGRAM (Mermaid) drawn for CTX: its image, or its source (see above)."
  (let* ((diagram (string-trim diagram))
         (width (plist-get ctx :width))
         ;; Its source wrapped, each line's rest under its indent (whole, a
         ;; line ran 190 columns past the width).
         (text (if width
                   (agent-ui-wrap-hanging (agent-ui-mermaid--highlight diagram) width)
                 (agent-ui-mermaid--highlight diagram))))
    (if (not (and (plist-get ctx :graphic) (plist-get ctx :char-width) (agent-ui-mermaid--p)))
        text
      (let* ((key (concat (+my/mermaid-theme-json) "\n" diagram))
             (failed (gethash key agent-ui-mermaid--errors))
             (file (and (not failed)
                        (+my/mermaid-render diagram
                                            (lambda (_file message)
                                              (when message (puthash key message agent-ui-mermaid--errors))
                                              (agent-ui-mermaid--redraw diagram))))))
        (cond (file (agent-ui-mermaid--image file ctx))
              (failed (concat text "\n" (propertize (agent-ui-wrap failed width) 'face 'agent-ui-error)))
              (t (concat text "\n" (propertize "drawing…" 'face 'agent-ui-muted))))))))

(defun agent-ui-mermaid--shows-p (element &optional diagram)
  "Non-nil if ELEMENT shows DIAGRAM (any, if nil): a mermaid element's, or a
markdown element's block."
  (pcase (plist-get element :type)
    ("mermaid" (or (null diagram) (equal (string-trim (or (plist-get element :diagram) "")) diagram)))
    ("markdown" (let ((markdown (or (plist-get element :markdown) "")))
                  (if diagram
                      (string-search diagram markdown)
                    (string-match-p "^[ \t]*\\(```\\|~~~\\)[ \t]*mermaid" markdown))))))

(defun agent-ui-mermaid--redraw (&optional diagram)
  "Redraw the elements showing DIAGRAM (any, if nil), everywhere."
  (dolist (canvas (agent-ui-canvases))
    (with-current-buffer canvas
      (agent-ui--dirty
       (cl-loop for id in agent-ui--order
                for element = (agent-ui--entry-element (gethash id agent-ui--entries))
                when (or (agent-ui-mermaid--shows-p element diagram)
                         (seq-some (lambda (child) (agent-ui-mermaid--shows-p child diagram))
                                   (agent-ui--descendants element)))
                collect id)))))

(defun agent-ui-mermaid-theme-h ()
  "A theme switch: each diagram drawn in its colours."
  (agent-ui-mermaid--redraw))

(add-hook '+my/mermaid-theme-hook #'agent-ui-mermaid-theme-h)

(defun agent-ui-mermaid--draw (props ctx)
  (agent-ui-mermaid-draw (plist-get props :diagram) ctx))

(agent-ui-define mermaid
  "A Mermaid diagram: DIAGRAM in Mermaid's syntax (flowchart, sequence,
state, class, ER, Gantt, mind map...). For a diagram that stays in view and
changes as work goes on: an update with a new diagram draws it anew. An
image in the GUI, in the theme's colours (mmdc, if installed); its source in
a terminal."
  :props ((diagram string "The diagram, in Mermaid's syntax: flowchart LR; build --> test" :required t))
  :example (:title "Release" :diagram "flowchart LR\n    build --> test --> deploy")
  :text #'agent-ui-mermaid--draw)
