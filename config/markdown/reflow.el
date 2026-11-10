;;; $DOOMDIR/config/markdown/reflow.el -*- lexical-binding: t; -*-
;; Markdown reflowed on screen: a paragraph's lines shown as one line, wrapped
;; at the pane's edge. Loaded from config/markdown.el.
;;
;; A file filled at 120 columns in a narrower pane wrapped raggedly: each
;; source line soft-wrapped on its own, a short tail row after it. Here,
;; inside a paragraph (a list item's, a block quote's too: tree-sitter's
;; `paragraph' nodes), each line break with the next line's indentation (and
;; its "> ") is shown as one space: a `display' property, put by jit-lock as
;; the text is shown, kept apart by `+md-reflow'. visual-line-mode then wraps
;; the whole paragraph, adaptive-wrap lining its rows up under the item's
;; text. The file's text doesn't change. Left as they are: hard line breaks
;; (two trailing spaces, a backslash), code blocks, tables, headings, HTML,
;; front matter (none of them paragraphs). Only while lines wrap (a pane
;; truncating its lines would show a paragraph as one long line).

(defun +md-reflow--wrapping-p ()
  "Whether this buffer's lines wrap at the pane's edge, by words."
  (and word-wrap (not truncate-lines)))

(defun +md-reflow--paragraphs (beg end)
  "The paragraph nodes touching BEG..END (not a setext heading's)."
  (seq-remove (lambda (node)
                (equal (treesit-node-type (treesit-node-parent node)) "setext_heading"))
              (mapcar #'cdr (treesit-query-capture 'markdown '((paragraph) @p) beg end))))

(defun +md-reflow--clear (beg end)
  "This part's display properties in BEG..END removed."
  (let ((pos beg))
    (while (setq pos (text-property-any pos end '+md-reflow t))
      (let ((stop (or (text-property-not-all pos end '+md-reflow t) end)))
        (remove-text-properties pos stop '(display nil +md-reflow nil))
        (setq pos stop)))))

(defun +md-reflow--join (node)
  "NODE's (a paragraph's) line breaks shown as a space each, with the next
line's indentation and \"> \": not a hard one (two spaces, a backslash
before it), nor its last."
  (let ((end (treesit-node-end node)))
    (save-excursion
      (goto-char (treesit-node-start node))
      (while (search-forward "\n" end t)
        (let ((break (1- (point))))
          (when (and (looking-at "[ \t]*\\(?:>[ \t]*\\)*")
                     ;; Text after it, in the paragraph.
                     (< (match-end 0) end)
                     (not (memql (char-after (match-end 0)) '(?\n nil)))
                     ;; A hard break kept.
                     (not (save-excursion
                            (goto-char break)
                            (or (looking-back "  " (- break 2)) (eq (char-before) ?\\)))))
            (put-text-property break (match-end 0) 'display " ")
            (put-text-property break (match-end 0) '+md-reflow t)))))))

(defun +md-reflow--fontify (beg end)
  "jit-lock: BEG..END's paragraphs, whole, reflowed (or not, lines not
wrapping)."
  (when (treesit-parser-list nil 'markdown)
    (let* ((nodes (+md-reflow--paragraphs beg end))
           (from (apply #'min beg (mapcar #'treesit-node-start nodes)))
           (to (apply #'max end (mapcar #'treesit-node-end nodes))))
      (with-silent-modifications
        (+md-reflow--clear from to)
        (when (+md-reflow--wrapping-p)
          (mapc #'+md-reflow--join nodes)))
      `(jit-lock-bounds ,from . ,to))))

(define-minor-mode +md-reflow-mode
  "Show a Markdown paragraph's lines as one line, wrapped at the pane's edge
\(see config/markdown/reflow.el); the file's text unchanged."
  :lighter nil
  (if +md-reflow-mode
      (jit-lock-register #'+md-reflow--fontify)
    (jit-lock-unregister #'+md-reflow--fontify)
    (with-silent-modifications
      (+md-reflow--clear (point-min) (point-max)))))

(defun +md-reflow--refontify-h ()
  "Lines wrapping or not, again (visual-line-mode turned on or off): this
part's properties drawn again."
  (when +md-reflow-mode
    (jit-lock-refontify)))

(add-hook 'visual-line-mode-hook #'+md-reflow--refontify-h)

(defun +md-reflow-maybe-h ()
  "A Markdown buffer (markdown-ts-mode's): reflowed, if `+my/markdown-reflow'."
  (when (and +my/markdown-reflow (treesit-parser-list nil 'markdown))
    (+md-reflow-mode 1)))

(add-hook 'markdown-ts-mode-hook #'+md-reflow-maybe-h)
