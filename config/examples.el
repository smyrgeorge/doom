;;; $DOOMDIR/config/examples.el -*- lexical-binding: t; -*-
;; Examples of the features that need something set up to be seen. Loaded from
;; config.el; the examples themselves only when run.

;; ====== VARIABLES ======

;; EXAMPLES
;; examples/NAME.el shows a feature on files of its own, in the temp folder:
;; M-x +my/example picks one, or M-x +my/example-NAME runs it. Each opens the
;; feature as you'd come to it and leaves nothing behind (its files deleted
;; once you're done with it). So far:
;;   merge   conflicts resolved in three panes (config/merge.el): a temp
;;           repository merging a branch, in conflict every way
(defvar +my/examples-dir (expand-file-name "examples/" doom-user-dir)
  "Where the examples are (see above).")

;; ====== CODE ======

(defun +my/examples ()
  "The examples' names (examples/NAME.el)."
  (and (file-directory-p +my/examples-dir)
       (mapcar #'file-name-sans-extension
               (directory-files +my/examples-dir nil "\\`[^.].*\\.el\\'"))))

(defun +my/example (name)
  "Run example NAME (see above), picked in the minibuffer."
  (interactive (list (completing-read "Example: " (+my/examples) nil t)))
  (unless (member name (+my/examples))
    (user-error "No example %s in %s" name +my/examples-dir))
  (call-interactively (intern (format "+my/example-%s" name))))

;; M-x +my/example-NAME: each loads its file when first run.
(dolist (name (+my/examples))
  (autoload (intern (format "+my/example-%s" name))
            (expand-file-name name +my/examples-dir)
            (format "Example: %s (see examples/%s.el)." name name)
            t))
