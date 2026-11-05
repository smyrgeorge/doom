;;; $DOOMDIR/config/lsp.el -*- lexical-binding: t; -*-
;; Language server setup. Loaded from config.el.

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

;; KOTLIN
;; Use JetBrains' kotlin-lsp (brew install --cask kotlin-lsp) instead of
;; lsp-mode's default kotlin-language-server.
(after! lsp-mode
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection '("kotlin-lsp" "--stdio"))
    :major-modes '(kotlin-mode kotlin-ts-mode)
    :priority 1                         ; win over kotlin-ls (-1)
    :server-id 'kotlin-lsp)))
