;;; $DOOMDIR/config/sticky.el -*- lexical-binding: t; -*-
;; Sticky function header in code windows. Loaded from config.el.

;; ====== VARIABLES ======

;; STICKY HEADER
;; The header line of code windows shows the classes/functions the top visible
;; line is inside, once their first lines have scrolled out of view, like
;; IntelliJ's sticky lines: e.g. "class Foo › def bar(self):". Otherwise it
;; shows the file's path in the project. Nested scopes come from tree-sitter
;; where the major mode uses it; other modes get the enclosing defun only.
;; The header row is always there, so the text doesn't shift when it changes.
(defvar +my/sticky-separator " › "
  "Between the scopes in the header.")

(defvar +my/sticky-defun-types
  '((kotlin . "\\`\\(class\\|object\\|function\\)_declaration\\'\\|\\`companion_object\\'"))
  "Tree-sitter node types of classes/functions, for languages whose mode doesn't
declare them (kotlin-ts-mode); the others come from the major mode.")

;; ====== CODE ======

(defun +my/sticky--treesit-p ()
  "Non-nil if we know which tree-sitter nodes are defuns in this buffer."
  (and (fboundp 'treesit-parser-list)
       (treesit-parser-list)
       (let ((language (treesit-language-at (point))))
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
          (let ((node (treesit-node-at (point))) starts)
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

(defun +my/sticky--compute (start)
  (if-let* ((starts (+my/sticky--scope-starts start)))
      (mapconcat #'+my/sticky--line starts
                 (propertize +my/sticky-separator 'face 'shadow))
    (propertize (if-let* ((root (doom-project-root)))
                    (file-relative-name buffer-file-name root)
                  (abbreviate-file-name buffer-file-name))
                'face 'shadow)))

(defun +my/sticky-header ()
  "The header line text of the window being displayed (cached per scroll position)."
  (let* ((window (selected-window))      ; the window whose header is drawn
         (key (list (current-buffer) (window-start window) (buffer-chars-modified-tick)))
         (cache (window-parameter window '+my/sticky)))
    (if (equal (car cache) key)
        (cdr cache)
      (let ((text (or (ignore-errors (+my/sticky--compute (window-start window))) "")))
        (set-window-parameter window '+my/sticky (cons key text))
        text))))

(define-minor-mode +my/sticky-header-mode
  "Show the scopes of the top visible line in the header line."
  :lighter nil
  (if +my/sticky-header-mode
      (progn
        (header-line-indent-mode 1)       ; line the text up with the code
        (setq-local header-line-format
                    '("" header-line-indent (:eval (+my/sticky-header)))))
    (header-line-indent-mode -1)
    (kill-local-variable 'header-line-format)))

(defun +my/sticky-header-maybe-h ()
  (when buffer-file-name
    (+my/sticky-header-mode 1)))

(add-hook 'prog-mode-hook #'+my/sticky-header-maybe-h)
