;;; $DOOMDIR/config/search/everywhere.el -*- lexical-binding: t; -*-
;; The list: Classes, Files, Symbols and Actions at once.
;; Loaded from config/search.el.

(defun +my/search-everywhere ()
  "Search classes, files, symbols and actions at once."
  (interactive)
  (require 'consult)
  (let* ((root (doom-project-root))
         (default-directory (or root default-directory)) ; file annotations
         (completion-ignore-case t)     ; "servic" finds UserService.kt
         (workspaces (and (bound-and-true-p lsp-mode)
                          (require 'consult-lsp nil t)
                          (lsp-workspaces)))
         (symbols (lambda (name key classes token)
                    (when workspaces
                      (list :name name :narrow key :category 'consult-lsp-symbols
                            :async (+my/search-everywhere--lsp-async workspaces token classes)
                            :annotate #'+my/search-everywhere--annotate-symbol
                            :action #'+my/search-everywhere--goto-symbol)))))
    (consult--multi
     (list (funcall symbols "Classes" ?c t :+my/search-everywhere-classes)
           (when root
             (list :name "Files" :narrow ?f :category 'file :face 'consult-file
                   :items (lambda () (+my/search-everywhere--files root))
                   :action (lambda (file) (find-file (expand-file-name file root)))))
           (funcall symbols "Symbols" ?s nil :+my/search-everywhere-symbols)
           (list :name "Actions" :narrow ?a :category 'command
                 :items #'+my/search-everywhere--commands
                 :action #'+my/search-everywhere--run-command))
     :prompt "Search everywhere: "
     :require-match t
     :sort nil)))
