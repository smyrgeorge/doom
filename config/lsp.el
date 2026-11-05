;;; $DOOMDIR/config/lsp.el -*- lexical-binding: t; -*-
;; Language server setup. Loaded from config.el.

;; ====== VARIABLES ======

;; CODE LENSES
;; lsp-mode shows the code lenses a server sends, at the end of the line:
;; rust-analyzer's "▶ Run" and implementations, and now also reference counts
;; (IntelliJ's usages) for Rust and TypeScript/JavaScript. Pyright sends none.
;; rust-analyzer's "Debug" lens needs a debugger set up (dap), so it's off.
(setq lsp-rust-analyzer-lens-references-method-enable t
      lsp-rust-analyzer-lens-references-adt-enable t
      lsp-rust-analyzer-lens-references-trait-enable t
      lsp-rust-analyzer-lens-references-enum-variant-enable t
      lsp-rust-analyzer-lens-debug-enable nil
      lsp-typescript-references-code-lens-enabled t
      lsp-typescript-implementations-code-lens-enabled t
      lsp-javascript-references-code-lens-enabled t)

;; ====== CODE ======

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
                 collect (concat "\\`"
                                 (regexp-quote (directory-file-name
                                                (expand-file-name entry)))
                                 "\\'"))))))

(defadvice! +my/lsp-watch-skip-gitignored-a (fn workspace-root)
  :around #'lsp--get-ignored-regexes-for-workspace-root
  (pcase-let ((`(,files ,dirs) (funcall fn workspace-root)))
    (list files (append dirs (+my/lsp-gitignored-directories workspace-root)))))

;; CODE LENSES, CHEAPER
;; Placing each lens, lsp-mode works out the indentation that lenses above the
;; line need, even with them at the end of the line (here): it finds where the
;; line starts on screen, which highlights that part of the file first. In
;; Markdown that means a tree-sitter parser per paragraph, ~10 ms each (see
;; config/editor.el, TREE-SITTER): opening a file froze for half a second when
;; its lenses arrived. At the end of the line, just put them there.
(defadvice! +my/lsp-lens-end-of-line-a (fn ov)
  :around #'lsp-lens--update
  (if (eq lsp-lens-place-position 'end-of-line)
      (let ((str (overlay-get ov 'lsp--lens-contents)))
        (overlay-put ov 'after-string (propertize (concat " " str) 'cursor t))
        (overlay-put ov 'lsp-original str))
    (funcall fn ov)))

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
