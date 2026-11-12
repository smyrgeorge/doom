;;; $DOOMDIR/config/agent-shell/mermaid.el -*- lexical-binding: t; -*-
;; ```mermaid blocks drawn as diagrams in Claude Code's replies
;; (config/mermaid.el). Loaded from config/agent-shell.el.

;; DIAGRAMS IN REPLIES (see config/agent-shell.el)
;; A renderer on `agent-shell-markdown-render-functions' (agent-shell's hook
;; for renderers of its own: LaTeX math...). A block, once closed, is claimed:
;; its source in its place, highlighted (frozen: agent-shell's passes leave it
;; alone), the block's Markdown kept on it (`agent-shell-markdown-source':
;; copying as Markdown gives the block back), the diagram shown over it once
;; drawn (in the background, mermaid/render.el). An error, or no mmdc: the
;; source, the message under it. Still streaming, the block stays as it is.
;; Each diagram is a region carrying its source (`+my/agent-shell-mermaid'),
;; found again in any buffer (the shell's, its viewport's) once drawn.

(defun +my/agent-shell-mermaid-p ()
  "Non-nil if diagrams are drawn: config/mermaid.el there, the GUI."
  (and (fboundp '+my/mermaid-render) (display-graphic-p)))

(defun +my/agent-shell-mermaid--image (file)
  "FILE's image, as agent-shell sizes its images (resized with them)."
  (let ((image (create-image file nil nil :max-width (agent-shell-markdown--image-max-width))))
    (image-flush image t)
    image))

(defun +my/agent-shell-mermaid--show (start end file message)
  "The diagram START..END (a region of the current buffer) as FILE's image;
or its source with MESSAGE under it."
  (let ((inhibit-read-only t)
        (buffer-undo-list t)
        (modified (buffer-modified-p)))
    (if file
        (add-text-properties
         start end
         (list 'display (+my/agent-shell-mermaid--image file)
               'agent-shell-markdown-image-width-ratio 'default
               'agent-shell-markdown-image-window-width (agent-shell-markdown--displayed-window-width)))
      (remove-list-of-text-properties start end '(agent-shell-markdown-image-width-ratio
                                                  agent-shell-markdown-image-window-width))
      (let ((source (buffer-substring start end)))
        (remove-list-of-text-properties 0 (length source) '(display) source)
        (put-text-property start end 'display
                           (concat source "\n" (propertize message 'face 'error)))))
    (set-buffer-modified-p modified)))

(defun +my/agent-shell-mermaid--regions (&optional buffer)
  "BUFFER's diagrams (default: the current one's): ((START END . SOURCE)...)."
  (with-current-buffer (or buffer (current-buffer))
    (save-restriction
      (widen)
      (let ((pos (point-min)) regions)
        (while (setq pos (text-property-not-all pos (point-max) '+my/agent-shell-mermaid nil))
          (let ((end (next-single-property-change pos '+my/agent-shell-mermaid nil (point-max))))
            (push (cons pos (cons end (get-text-property pos '+my/agent-shell-mermaid))) regions)
            (setq pos end)))
        (nreverse regions)))))

(defun +my/agent-shell-mermaid--drawn (source file message)
  "SOURCE drawn (FILE) or not (MESSAGE): each region showing it, in any
buffer, shows that."
  (dolist (buffer (buffer-list))
    (pcase-dolist (`(,start ,end . ,text) (+my/agent-shell-mermaid--regions buffer))
      (when (equal text source)
        (with-current-buffer buffer
          (save-restriction
            (widen)
            (+my/agent-shell-mermaid--show start end file message)))))))

(defun +my/agent-shell-mermaid--shown-p (source)
  "Non-nil if a buffer shows SOURCE's diagram (a region of it)."
  (seq-some (lambda (buffer)
              (seq-some (lambda (region) (equal (cddr region) source))
                        (+my/agent-shell-mermaid--regions buffer)))
            (buffer-list)))

(defun +my/agent-shell-mermaid--draw (source)
  "Draw SOURCE: its regions show it now if it's drawn already, else once it
is. None left (a reply's buffer gone, Agent UI's markdown drawing its own):
nothing drawn."
  (when (+my/agent-shell-mermaid--shown-p source)
    (if-let* ((file (+my/mermaid-render source (lambda (file message)
                                                 (+my/agent-shell-mermaid--drawn source file message)))))
        (+my/agent-shell-mermaid--drawn source file nil))))

(defun +my/agent-shell-mermaid--claim (start end body)
  "The block START..END (closed, its source BODY): its source in its place,
highlighted, frozen, the block's Markdown on it; drawn (see above)."
  (let* ((markdown (buffer-substring-no-properties start end))
         (text (agent-shell-markdown--highlight-code body "mermaid")))
    (add-face-text-property 0 (length text) 'agent-shell-markdown-source-block t text)
    (goto-char start)
    (delete-region start end)
    (insert (propertize text
                        'agent-shell-markdown-source markdown
                        'agent-shell-markdown-frozen t
                        '+my/agent-shell-mermaid body
                        'rear-nonsticky '(agent-shell-markdown-frozen agent-shell-markdown-source
                                          +my/agent-shell-mermaid display))
            ;; The line's end: not drawn over (what follows starts a line).
            (propertize "\n"
                        'agent-shell-markdown-source ""
                        'agent-shell-markdown-frozen t
                        'rear-nonsticky '(agent-shell-markdown-frozen agent-shell-markdown-source)))
    ;; Once agent-shell's passes are done with the rest.
    (run-at-time 0 nil #'+my/agent-shell-mermaid--draw body)))

(defun +my/agent-shell-mermaid-render (context)
  "Claim each closed ```mermaid block of CONTEXT's (see above); one still
streaming is left as it is. For `agent-shell-markdown-render-functions'."
  (when (+my/agent-shell-mermaid-p)
    (dolist (block (map-elt context :source-blocks))
      (let* ((range (map-elt block :block))
             (start (map-elt range :start))
             (end (map-elt range :end)))
        (when (and (equal (map-elt block :language) "mermaid")
                   (map-elt block :complete)
                   (not (get-text-property start 'agent-shell-markdown-frozen)))
          (+my/agent-shell-mermaid--claim (marker-position start) (marker-position end)
                                          (string-trim-right (or (map-elt block :body) ""))))))
    nil))

(add-hook 'agent-shell-markdown-render-functions #'+my/agent-shell-mermaid-render)

;; A theme switch: each diagram drawn again, in the new theme's colours.
(defun +my/agent-shell-mermaid-theme-h ()
  "Each diagram shown, in any buffer, drawn in the theme's colours."
  (let (sources)
    (dolist (buffer (buffer-list))
      (dolist (region (+my/agent-shell-mermaid--regions buffer))
        (cl-pushnew (cddr region) sources :test #'equal)))
    (mapc #'+my/agent-shell-mermaid--draw sources)))

(add-hook '+my/mermaid-theme-hook #'+my/agent-shell-mermaid-theme-h)

;; What Claude is told (see `+my/agent-shell-mermaid-context').
(defun +my/agent-shell-mermaid-context ()
  "That Mermaid blocks are drawn, where they are; else nil."
  (when (fboundp '+my/mermaid-render)
    +my/agent-shell-mermaid-context))

(add-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-mermaid-context t)
