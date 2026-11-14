;;; $DOOMDIR/config/search/everywhere.el -*- lexical-binding: t; -*-
;; The list: Classes, Files, Symbols and Actions at once.
;; Loaded from config/search.el.

(defun +my/search-everywhere ()
  "Search classes, files, symbols and actions at once."
  (interactive)
  (require 'consult)
  (let* ((root (doom-project-root))
         ;; The servers that search their workspace's symbols: a server
         ;; without it raised an error at each key typed.
         (workspaces (and (bound-and-true-p lsp-mode)
                          (require 'consult-lsp nil t)
                          (lsp-feature? "workspace/symbol")))
         ;; Classes, Files and Symbols show all in their rows, not in
         ;; annotations (Files not marginalia's either: their own category):
         ;; marginalia aligns the Actions' docs after the longest row it
         ;; annotated, off a narrow frame after a file's long path.
         (symbols (lambda (name key classes token)
                    (when workspaces
                      (list :name name :narrow key :category 'consult-lsp-symbols
                            :async (+my/search-everywhere--lsp-async workspaces token classes)
                            :annotate #'ignore
                            :run #'+my/search-everywhere--goto-symbol))))
         (selected
          (let ((completion-ignore-case t) ; "servic" finds UserService.kt
                ;; The input as typed: with a language server's sources,
                ;; consult otherwise starts it with "#" (its async split),
                ;; and then c SPC didn't narrow (only a lone character
                ;; does), nor DEL widen.
                (consult-async-split-style 'none))
            (consult--multi
             (list (funcall symbols "Classes" ?c t :+my/search-everywhere-classes)
                   (when root
                     (list :name "Files" :narrow ?f :category '+my/search-everywhere-file
                           :face 'consult-file :annotate #'ignore
                           :items (lambda ()
                                    (+my/search-everywhere--file-items
                                     (+my/search-everywhere--files root)))
                           :run (lambda (file) (find-file (expand-file-name file root)))))
                   (funcall symbols "Symbols" ?s nil :+my/search-everywhere-symbols)
                   (list :name "Actions" :narrow ?a :category 'command
                         :items #'+my/search-everywhere--commands
                         :run #'+my/search-everywhere--run-command))
             :prompt "Search everywhere: "
             :require-match t
             :sort nil))))
    ;; What's picked runs once read (its source's :run: consult runs an
    ;; :action with the settings above still on), as from M-x: in the
    ;; buffer's own folder (a cd sticks, a shell starts there), with the
    ;; user's own `completion-ignore-case'.
    (when-let* ((run (plist-get (cdr selected) :run)))
      (funcall run (car selected)))))
