;;; $DOOMDIR/config/treemacs/arrows.el -*- lexical-binding: t; -*-
;; Arrows in trees; LSP's panels selected. Loaded from config/treemacs.el.

(defun +my/treemacs--node ()
  "The node at point: (BUTTON STATE-NAME), BUTTON nil on a hidden one (the
invisible first line holding lsp-treemacs' lists)."
  (let ((button (ignore-errors (treemacs-current-button))))
    (when (and button (>= (or (treemacs-button-get button :depth) 0) 0))
      (list button (symbol-name (treemacs-button-get button :state))))))

(defun +my/treemacs--leaf-p (button)
  "Non-nil if BUTTON is an lsp-treemacs node without children (e.g. an error):
those say closed too."
  (let ((item (treemacs-button-get button :item)))
    (and (consp item) (keywordp (car item))
         (not (plist-get item :children))
         (not (plist-get item :children-async)))))

(defun +my/treemacs-left ()
  "← in treemacs (see the key bindings above)."
  (interactive)
  (pcase-let ((`(,button ,name) (+my/treemacs--node)))
    (cond ((null button))
          ;; A file: up, as ↑ (not to its folder).
          ((equal name "file-node-closed") (treemacs-previous-line 1))
          ;; treemacs' own nodes (the project view): collapse, or go to the
          ;; parent.
          ((string-match-p "\\`\\(root\\|dir\\|file\\|tag\\)-node" name)
           (treemacs-COLLAPSE-action))
          ;; Others (lsp-treemacs' lists) don't do either: close, or go up (not
          ;; to the hidden first line).
          ((string-suffix-p "-open" name) (treemacs-TAB-action))
          ((when-let* ((parent (treemacs-button-get button :parent)))
             (>= (or (treemacs-button-get parent :depth) 0) 0))
           (treemacs-goto-parent-node)))))

(defun +my/treemacs-right ()
  "→ in treemacs (see the key bindings above)."
  (interactive)
  (pcase-let ((`(,button ,name) (+my/treemacs--node)))
    (cond ((null button) (treemacs-next-line 1))
          ;; A file: down, as ↓ (RET or a double click opens it).
          ((equal name "file-node-closed") (treemacs-next-line 1))
          ((+my/treemacs--leaf-p button) (treemacs-RET-action)) ; go to the error
          ((string-suffix-p "-closed" name) (treemacs-TAB-action))
          ((and (string-suffix-p "-open" name) (not (equal name "file-node-open")))
           (treemacs-next-line 1))
          (t (treemacs-RET-action)))))

;; LSP PANELS
;; SPC c X (errors) and SPC c S (symbols) open their panel at the bottom; new
;; windows get the cursor (config/window.el) but these are side windows, so it
;; stayed in the code and the arrows moved there. Go to the panel.
(defadvice! +my/lsp-treemacs-select-panel-a (&rest _)
  :after '(lsp-treemacs-errors-list lsp-treemacs-symbols)
  (when-let* ((window (seq-find (lambda (w)
                                  (member (buffer-name (window-buffer w))
                                          '("*LSP Error List*" "*LSP Symbols List*")))
                                (window-list))))
    (select-window window)
    ;; The list opens with the cursor on its hidden first line, shown on the
    ;; first visible one: ↓ then skipped that one. Onto the first visible one.
    (with-current-buffer (window-buffer window)
      (when (and (bobp) (null (+my/treemacs--node)))
        (treemacs-next-line 1)
        (set-window-point window (point))))))
