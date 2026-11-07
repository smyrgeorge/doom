;;; $DOOMDIR/config/sticky.el -*- lexical-binding: t; -*-
;; Sticky function header in code windows. Loaded from config.el.

;; ====== VARIABLES ======

;; STICKY HEADER
;; The header line of code windows shows the classes/functions the top visible
;; line is inside, once their first lines have scrolled out of view: e.g.
;; "class Foo › def bar(self):". Otherwise it
;; shows the file's path in the project. Nested scopes come from tree-sitter
;; where the major mode uses it; other modes get the enclosing defun only.
;; In Markdown (markdown-ts-mode) the scopes are the headings: "# Guide › ## Setup".
;; The header row is always there, so the text doesn't shift when it changes.
;; Only where scopes can be told (e.g. not in HTML: web-mode has no notion of
;; them): elsewhere there's no header row.
(defvar +my/sticky-separator " › "
  "Between the scopes in the header.")

(defvar +my/sticky-defun-types
  '((kotlin . "\\`\\(class\\|object\\|function\\)_declaration\\'\\|\\`companion_object\\'")
    (markdown . "\\`section\\'"))        ; a heading and what's under it
  "Tree-sitter node types of classes/functions, for languages whose mode doesn't
declare them (kotlin-ts-mode, markdown-ts-mode); the others come from the major
mode.")

;; ====== CODE ======

(defun +my/sticky--language ()
  "The tree-sitter language whose scopes to show at point: the buffer's own if
we know its scopes (in Markdown, not that of the text or code block at point),
else the one at point."
  (let ((host (and (bound-and-true-p treesit-primary-parser)
                   (treesit-parser-language treesit-primary-parser))))
    (if (and host (alist-get host +my/sticky-defun-types))
        host
      (treesit-language-at (point)))))

(defun +my/sticky--treesit-p ()
  "Non-nil if we know which tree-sitter nodes are defuns in this buffer."
  (and (fboundp 'treesit-parser-list)
       (treesit-parser-list)
       (let ((language (+my/sticky--language)))
         (or (alist-get language +my/sticky-defun-types)
             (bound-and-true-p treesit-defun-type-regexp) ; older ts modes
             (and (fboundp 'treesit-thing-defined-p)       ; Emacs 30+: `defun' thing
                  (treesit-thing-defined-p 'defun language))))))

(defun +my/sticky--defun-node-p (node)
  "Non-nil if tree-sitter NODE is a function/class/..."
  (let ((type (treesit-node-type node)))
    (if-let* ((re (alist-get (treesit-node-language node) +my/sticky-defun-types)))
        (string-match-p re type)
      (pcase (bound-and-true-p treesit-defun-type-regexp)
        ((and (pred stringp) re) (string-match-p re type))
        (`(,re . ,pred) (and (string-match-p re type) (funcall pred node)))
        (_ (treesit-node-match-p node 'defun t))))))

(defun +my/sticky--scope-starts (start)
  "Start positions of the scopes the line at START is inside, outermost first,
leaving out those that begin on that line or below."
  (save-excursion
    (goto-char start)
    (skip-chars-forward " \t")
    (let ((bol (line-beginning-position)))
      (if (+my/sticky--treesit-p)
          (let ((node (treesit-node-at (point) (+my/sticky--language))) starts)
            (while node
              (when (and (+my/sticky--defun-node-p node)
                         (< (treesit-node-start node) bol))
                (push (treesit-node-start node) starts))
              (setq node (treesit-node-parent node)))
            (delete-dups starts))
        ;; No tree-sitter: the defun around the line, if it starts above it.
        (let ((pos (point)))
          (when (and (ignore-errors (beginning-of-defun)) ; found one
                     (< (point) bol)
                     (not (looking-at-p "[ \t]*\\(\\s<\\|$\\)")) ; not a comment
                     (> (save-excursion (end-of-defun) (point)) pos))
            (list (point))))))))

(defun +my/sticky--line (pos)
  "The (fontified) text of the line at POS, without its indentation."
  (save-excursion
    (goto-char pos)
    (let ((beg (progn (back-to-indentation) (point)))
          (end (line-end-position)))
      (font-lock-ensure beg end)
      (string-trim-right (buffer-substring beg end)))))

(defvar-local +my/sticky--path-cache nil
  "(FILE . TEXT): the path shown for FILE (finding the project root on every
scroll step took ~6% of the time spent scrolling).")

(defun +my/sticky--path ()
  "The file's path in its project, as shown."
  (unless (equal (car +my/sticky--path-cache) buffer-file-name)
    (setq +my/sticky--path-cache
          (cons buffer-file-name
                (propertize (if-let* ((root (doom-project-root)))
                                (file-relative-name buffer-file-name root)
                              (abbreviate-file-name buffer-file-name))
                            'face 'shadow))))
  (cdr +my/sticky--path-cache))

(defun +my/sticky--compute (start)
  (if-let* ((starts (+my/sticky--scope-starts start)))
      (mapconcat #'+my/sticky--line starts
                 (propertize +my/sticky-separator 'face 'shadow))
    (+my/sticky--path)))

(defun +my/sticky--indent (window)
  "Spaces as wide as the line numbers in WINDOW, to line the header up with the
code. Worked out the way Emacs does (the widest number that can show: at least
`display-line-numbers-width' digits, plus 2), not with `line-number-display-width'
as `header-line-indent-mode' did: that lays the window out, which highlights it
first, on every scroll and before every redraw (~100 ms more to open a Markdown
file). Relative numbers aren't sized like that: those ask Emacs."
  (make-string
   (cond ((not display-line-numbers) 0)
         ((eq display-line-numbers t)
          (let ((last (+ (line-number-at-pos (window-start window) t)
                         (window-body-height window) -1)))
            (+ 2 (max (or display-line-numbers-width 0)
                      (length (number-to-string (max 1 last)))))))
         (t (with-selected-window window
              (truncate (line-number-display-width 'columns)))))
   ?\s))

(defun +my/sticky-header ()
  "The header line text of the window being displayed (cached per scroll position)."
  (let* ((window (selected-window))      ; the window whose header is drawn
         (key (list (current-buffer) (window-start window) (buffer-chars-modified-tick)
                    (window-body-height window) display-line-numbers))
         (cache (window-parameter window '+my/sticky)))
    (if (equal (car cache) key)
        (cdr cache)
      (let ((text (concat (+my/sticky--indent window)
                          (or (ignore-errors (+my/sticky--compute (window-start window))) ""))))
        (set-window-parameter window '+my/sticky (cons key text))
        text))))

(define-minor-mode +my/sticky-header-mode
  "Show the scopes of the top visible line in the header line."
  :lighter nil
  (if +my/sticky-header-mode
      (setq-local header-line-format
                  ;; The header line starts at the window's edge, the text after
                  ;; the fringe: skip to where the text starts; the line
                  ;; numbers are skipped by the header's own text (see above).
                  '("" (:propertize " " display (space :align-to 0))
                    (:eval (+my/sticky-header))))
    (kill-local-variable 'header-line-format)))

(defun +my/sticky--supported-p ()
  "Non-nil if the scopes of this buffer's lines can be told."
  (or (+my/sticky--treesit-p)
      beginning-of-defun-function       ; the mode says how to find its defuns
      (derived-mode-p 'lisp-data-mode))) ; or they're the usual "(" in column 0

(defun +my/sticky-header-maybe-h ()
  (when (and buffer-file-name (+my/sticky--supported-p))
    (+my/sticky-header-mode 1)))

(add-hook 'prog-mode-hook #'+my/sticky-header-maybe-h)

(add-hook 'markdown-ts-mode-hook #'+my/sticky-header-maybe-h)
