;;; $DOOMDIR/config/lsp/typescript.el -*- lexical-binding: t; -*-
;; TypeScript/JavaScript: TypeScript 7's own language server, ESLint beside it,
;; Prettier where a project has it. Loaded from config/lsp.el.

;; SERVER
;; TypeScript 7, the native (Go) compiler, is also the language server
;; (`tsc --lsp --stdio'): the TypeScript team's own, fast, with inlay hints,
;; semantic highlighting, lenses, call hierarchy, rename that fixes imports when
;; a file moves. lsp-mode knows it as tsgo; which tsc runs it, in order:
;; - the project's own, if it's TypeScript 7 or later (node_modules/.bin/tsc):
;;   the errors are the ones its build gets;
;; - the one on PATH, if TypeScript 7 or later (scripts/lsp.sh installs it);
;; - else lsp-mode's own copy (a nightly build, @typescript/native-preview,
;;   installed on first use).
;; typescript-language-server (ts-ls) wraps tsserver, TypeScript 6 at most
;; (TypeScript 7 has none), and lsp-mode would prefer it when installed: off,
;; and the older theia one too.
(setq lsp-disabled-clients
      (append '(ts-ls jsts-ls) (bound-and-true-p lsp-disabled-clients)))

;; INLAY HINTS, CODE LENSES
;; Parameter names for literal arguments, return types, enum values; reference
;; counts on every function, implementations. TypeScript 7 reads its settings
;; from a `js/ts' section, as VS Code names them now: lsp-mode's are sent there
;; too (it ignores the old `typescript.inlayHints.include...' ones).
(setq lsp-javascript-display-parameter-name-hints "literals"
      lsp-javascript-display-return-type-hints t
      lsp-javascript-display-enum-member-value-hints t
      lsp-typescript-references-code-lens-enabled t
      lsp-typescript-implementations-code-lens-enabled t
      lsp-javascript-references-code-lens-enabled t)

;; ESLINT
;; ESLint runs alongside, for its diagnostics and fixes (in projects with an
;; ESLint config): vscode-eslint-language-server (vscode-langservers-extracted,
;; scripts/lsp.sh), not the VS Code extension lsp-mode would download. It
;; doesn't format: TypeScript or Prettier does (see FORMATTING).
(setq lsp-eslint-server-command '("vscode-eslint-language-server" "--stdio")
      lsp-eslint-format nil)

;; FORMATTING
;; With :editor (format +lsp) Doom formats with the language server when it
;; can: TypeScript 7 can, so a project's Prettier config would be ignored.
;; TypeScript/JavaScript files of a project with Prettier set up (a .prettierrc,
;; a prettier.config, a "prettier" key in package.json) are formatted by its
;; Prettier instead; others by the server.

;;; Which TypeScript serves

(defun +my/typescript-version (tsc)
  "The version of TypeScript whose tsc TSC is (a path, through node_modules/.bin
or a global install's link), as a string; nil if it isn't one."
  (when-let* ((tsc (and tsc (file-exists-p tsc) (file-truename tsc)))
              ;; .../node_modules/typescript/bin/tsc
              (package (expand-file-name "../package.json" (file-name-directory tsc)))
              ((file-exists-p package))
              (data (ignore-errors
                      (with-temp-buffer
                        (insert-file-contents package)
                        (json-parse-buffer :object-type 'plist))))
              ((equal (plist-get data :name) "typescript")))
    (plist-get data :version)))

(defun +my/typescript-native-p (tsc)
  "Non-nil if TSC is TypeScript 7 or later's tsc: the native one, which serves LSP."
  (when-let* ((version (+my/typescript-version tsc)))
    (>= (string-to-number version) 7)))

(defun +my/typescript-server ()
  "The tsc to serve TypeScript/JavaScript from `default-directory' (see
SERVER above): the project's TypeScript 7, else the one on
PATH, else `lsp-clients-tsgo-path' (and failing that lsp-mode's own copy)."
  (or (seq-find #'+my/typescript-native-p
                (list (when-let* ((dir (locate-dominating-file default-directory
                                                               "node_modules/.bin/tsc")))
                        (expand-file-name "node_modules/.bin/tsc" dir))
                      (executable-find "tsc")))
      lsp-clients-tsgo-path))

(defun +my/typescript-suppress-matching-names ()
  "TypeScript 7's suppressWhenArgumentMatchesName, the opposite of lsp-mode's setting."
  (not (bound-and-true-p lsp-javascript-display-parameter-name-hints-when-argument-matches-name)))

(after! lsp-javascript
  ;; lsp-mode's tsgo client runs what this finds (with --lsp --stdio).
  (lsp-dependency 'tsgo
                  '(:system +my/typescript-server)
                  '(:npm :package "@typescript/native-preview" :path "tsgo"))
  ;; TypeScript 7 asks for `js/ts' (and `typescript', `javascript', `editor').
  (lsp-register-custom-settings
   '(("js/ts.inlayHints.parameterNames.enabled" lsp-javascript-display-parameter-name-hints)
     ("js/ts.inlayHints.parameterNames.suppressWhenArgumentMatchesName"
      +my/typescript-suppress-matching-names t)
     ("js/ts.inlayHints.parameterTypes.enabled" lsp-javascript-display-parameter-type-hints t)
     ("js/ts.inlayHints.variableTypes.enabled" lsp-javascript-display-variable-type-hints t)
     ("js/ts.inlayHints.propertyDeclarationTypes.enabled"
      lsp-javascript-display-property-declaration-type-hints t)
     ("js/ts.inlayHints.functionLikeReturnTypes.enabled" lsp-javascript-display-return-type-hints t)
     ("js/ts.inlayHints.enumMemberValues.enabled" lsp-javascript-display-enum-member-value-hints t)
     ("js/ts.referencesCodeLens.enabled" lsp-typescript-references-code-lens-enabled t)
     ("js/ts.referencesCodeLens.showOnAllFunctions" lsp-typescript-references-code-lens-enabled t)
     ("js/ts.implementationsCodeLens.enabled" lsp-typescript-implementations-code-lens-enabled t))))

;;; Prettier where the project has it

(defconst +my/prettier-config-files
  '(".prettierrc" ".prettierrc.json" ".prettierrc.yml" ".prettierrc.yaml" ".prettierrc.json5"
    ".prettierrc.js" ".prettierrc.mjs" ".prettierrc.cjs" ".prettierrc.ts" ".prettierrc.toml"
    "prettier.config.js" "prettier.config.mjs" "prettier.config.cjs" "prettier.config.ts")
  "Files that set Prettier up (as Prettier looks for them).")

(defun +my/prettier-project-p (dir)
  "Non-nil if DIR is in a project with Prettier set up: a config file, or a
\"prettier\" key in the nearest package.json."
  (or (seq-some (lambda (file) (locate-dominating-file dir file)) +my/prettier-config-files)
      (when-let* ((root (locate-dominating-file dir "package.json")))
        (ignore-errors
          (with-temp-buffer
            (insert-file-contents (expand-file-name "package.json" root))
            (plist-member (json-parse-buffer :object-type 'plist) :prettier))))))

(defun +my/format-with-prettier-h ()
  "In a project with Prettier set up, format with it (Apheleia's formatter for
the mode), not with the language server: Doom then leaves `+format-with' as is."
  (when (and buffer-file-name
             (+my/prettier-project-p (file-name-directory buffer-file-name)))
    (when-let* (((require 'apheleia nil t))
                (formatter (alist-get major-mode apheleia-mode-alist)))
      (setq-local +format-with formatter))))

;; Before lsp-mode starts (Doom: from the mode's local-vars hook, later).
(add-hook 'js-base-mode-hook #'+my/format-with-prettier-h)
(add-hook 'typescript-ts-base-mode-hook #'+my/format-with-prettier-h)
