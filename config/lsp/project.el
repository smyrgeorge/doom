;;; $DOOMDIR/config/lsp/project.el -*- lexical-binding: t; -*-
;; A server for the file's project, watching what git doesn't ignore.
;; Loaded from config/lsp.el.

;; PROJECT IMPORT
;; Start the language server in the file's project (its git repository, as
;; projectile sees it) without the "import project root?" prompt, like Zed or
;; VS Code. Only for files inside a project: elsewhere lsp-mode would fall back
;; to the file's folder (e.g. ~, which servers like pyright would scan), so
;; those still ask.
(defadvice! +my/lsp-auto-import-project-a (fn session file-name)
  :around #'lsp--calculate-root
  (let* ((default-directory (file-name-directory file-name)) ; guess from the file
         (lsp-auto-guess-root (and (doom-project-root) t)))
    (funcall fn session file-name)))

;; FILE WATCHERS
;; To tell the server about files changed outside Emacs, lsp-mode watches every
;; directory under the project root, skipping only those matching
;; `lsp-file-watch-ignored-directories' (node_modules, build dirs...); it
;; doesn't read .gitignore. A root that ignores big folders, e.g. pas-workspace
;; with the 17 repositories cloned inside it, then needs ~8000 watches instead
;; of ~30: hence the "watch N directories?" prompt and the lag (on macOS each
;; watch is an open file). Also skip the directories git ignores in the root.
(defun +my/lsp-gitignored-directories (root)
  "Regexps matching the directories under ROOT that git ignores."
  (let ((default-directory (file-name-as-directory (file-truename root))))
    (with-temp-buffer
      (when (eql 0 (ignore-errors
                     (call-process "git" nil t nil "ls-files" "-z" "--others"
                                   "--ignored" "--exclude-standard" "--directory")))
        (cl-loop for entry in (split-string (buffer-string) "\0" t)
                 when (string-suffix-p "/" entry) ; directories only
                 ;; Relative to the root, as git prints it: `concat', as
                 ;; `expand-file-name' takes a folder named ~ for home.
                 collect (concat "\\`"
                                 (regexp-quote (directory-file-name
                                                (concat default-directory entry)))
                                 "\\'"))))))

(defadvice! +my/lsp-watch-skip-gitignored-a (fn workspace-root)
  :around #'lsp--get-ignored-regexes-for-workspace-root
  (pcase-let ((`(,files ,dirs) (funcall fn workspace-root)))
    (list files (append dirs (+my/lsp-gitignored-directories workspace-root)))))
