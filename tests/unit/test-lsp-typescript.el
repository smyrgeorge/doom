;;; tests/unit/test-lsp-typescript.el -*- lexical-binding: t; -*-
;; config/lsp/typescript.el: TypeScript 7 as the TypeScript/JavaScript server
;; (which tsc, the other servers off), its inlay hints and lenses (in the
;; js/ts section it reads, and the old one), ESLint beside it, Prettier where a
;; project has it.

(load (expand-file-name "../helper-lsp" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(require 'lsp-javascript)

;; ====== HELPERS ======

(defun +test-lsp--typescript (root version &optional name)
  "A TypeScript VERSION install in ROOT's node_modules (package NAME, default
typescript), its tsc linked from node_modules/.bin as npm does; the link."
  (let* ((package (expand-file-name (concat "node_modules/" (or name "typescript") "/") root))
         (bin (expand-file-name "node_modules/.bin/" root))
         (link (expand-file-name "tsc" bin)))
    (make-directory (expand-file-name "bin" package) t)
    (make-directory bin t)
    (with-temp-file (expand-file-name "package.json" package)
      (insert (format "{\"name\": \"%s\", \"version\": \"%s\"}" (or name "typescript") version)))
    (with-temp-file (expand-file-name "bin/tsc" package))
    (make-symbolic-link (expand-file-name "bin/tsc" package) link t)
    link))

;; ====== SERVER ======

(ert-deftest lsp-typescript/other-servers-off ()
  "typescript-language-server (tsserver: TypeScript 6 at most) and theia's
older one are off: lsp-mode would prefer them to TypeScript 7's."
  (should (memq 'ts-ls lsp-disabled-clients))
  (should (memq 'jsts-ls lsp-disabled-clients))
  (should-not (memq 'tsgo lsp-disabled-clients)))

(ert-deftest lsp-typescript/version ()
  "A tsc's TypeScript version, through node_modules/.bin's link; nil for
something else."
  (let ((root (+test-lsp--dir "ts")))
    (should (equal (+my/typescript-version (+test-lsp--typescript root "7.0.2")) "7.0.2"))
    (should (+my/typescript-native-p (expand-file-name "node_modules/.bin/tsc" root))))
  (let ((root (+test-lsp--dir "ts")))
    (should (equal (+my/typescript-version (+test-lsp--typescript root "5.9.3")) "5.9.3"))
    (should-not (+my/typescript-native-p (expand-file-name "node_modules/.bin/tsc" root))))
  (let ((root (+test-lsp--dir "ts")))
    (should-not (+my/typescript-version (+test-lsp--typescript root "7.0.0" "not-typescript"))))
  (should-not (+my/typescript-version nil))
  (should-not (+my/typescript-version "/no/such/tsc")))

(ert-deftest lsp-typescript/server-the-project-s-first ()
  "The project's TypeScript 7, else the one on PATH if 7, else tsgo (lsp-mode's)."
  (require 'lsp-javascript)
  (let* ((global (+test-lsp--dir "global"))
         (global-7 (+test-lsp--typescript global "7.1.0"))
         (project (+test-lsp--project "src/"))
         (on-path global-7))
    (cl-letf (((symbol-function 'executable-find)
               (lambda (name &rest _) (and (equal name "tsc") on-path))))
      (let ((default-directory (expand-file-name "src/" project)))
        ;; None in the project: PATH's.
        (should (equal (+my/typescript-server) global-7))
        ;; The project's 5: still PATH's 7.
        (+test-lsp--typescript project "5.9.3")
        (should (equal (+my/typescript-server) global-7))
        ;; PATH's isn't 7 either: tsgo.
        (setq on-path (+test-lsp--typescript (+test-lsp--dir "old") "5.0.0"))
        (should (equal (+my/typescript-server) lsp-clients-tsgo-path))
        (setq on-path nil)
        (should (equal (+my/typescript-server) lsp-clients-tsgo-path))
        ;; The project's 7 wins.
        (delete-directory (expand-file-name "node_modules" project) t)
        (let ((local (+test-lsp--typescript project "7.0.2")))
          (should (equal (+my/typescript-server) local))
          ;; What lsp-mode's tsgo client runs.
          (should (equal (lsp-package-path 'tsgo) local)))))))

;; ====== INLAY HINTS, CODE LENSES ======

(ert-deftest lsp-typescript/settings ()
  "Parameter names for literals, return types, enum values; references (and
implementations) for TypeScript and JavaScript."
  (should (equal lsp-javascript-display-parameter-name-hints "literals"))
  (should (eq lsp-javascript-display-return-type-hints t))
  (should (eq lsp-javascript-display-enum-member-value-hints t))
  (should (eq lsp-typescript-references-code-lens-enabled t))
  (should (eq lsp-typescript-implementations-code-lens-enabled t))
  (should (eq lsp-javascript-references-code-lens-enabled t)))

(ert-deftest lsp-typescript/settings-survive-the-package-loading ()
  "lsp-javascript's defaults are the other way round; loading it keeps the
config's."
  (should (eq (+test-lsp--default 'lsp-typescript-references-code-lens-enabled) nil))
  (should (eq (+test-lsp--default 'lsp-typescript-implementations-code-lens-enabled) nil))
  (should (eq (+test-lsp--default 'lsp-javascript-references-code-lens-enabled) nil))
  (should (equal (+test-lsp--default 'lsp-javascript-display-parameter-name-hints) "none"))
  (should (eq lsp-typescript-references-code-lens-enabled t))
  (should (equal lsp-javascript-display-parameter-name-hints "literals")))

(ert-deftest lsp-typescript/settings-in-js-ts ()
  "TypeScript 7's settings, in the `js/ts' section it asks for: lsp-mode's
inlay hint and lens settings (the old `typescript' ones stay, for others)."
  (require 'lsp-javascript)
  (let* ((section (lsp--section-workspace-configuration "js/ts"))
         (get (lambda (&rest keys)
                (let ((value section))
                  (dolist (key keys value) (setq value (gethash key value)))))))
    (should (equal (funcall get "inlayHints" "parameterNames" "enabled") "literals"))
    (should (eq (funcall get "inlayHints" "parameterNames" "suppressWhenArgumentMatchesName") t))
    (should (eq (funcall get "inlayHints" "functionLikeReturnTypes" "enabled") t))
    (should (eq (funcall get "inlayHints" "enumMemberValues" "enabled") t))
    (should (eq (funcall get "inlayHints" "variableTypes" "enabled") :json-false))
    (should (eq (funcall get "inlayHints" "parameterTypes" "enabled") :json-false))
    (should (eq (funcall get "inlayHints" "propertyDeclarationTypes" "enabled") :json-false))
    (should (eq (funcall get "referencesCodeLens" "enabled") t))
    (should (eq (funcall get "referencesCodeLens" "showOnAllFunctions") t))
    (should (eq (funcall get "implementationsCodeLens" "enabled") t))
    (let ((lsp-javascript-display-parameter-name-hints-when-argument-matches-name t))
      (should (eq (gethash "suppressWhenArgumentMatchesName"
                           (gethash "parameterNames"
                                    (gethash "inlayHints" (lsp--section-workspace-configuration "js/ts"))))
                  :json-false)))))

(ert-deftest lsp-typescript/inlay-hints-in-the-old-sections ()
  "In the old typescript/javascript sections too (other servers read them) (workspace/configuration): parameter
names for literals, return types, enum values; for JavaScript too."
  (require 'lsp-javascript)
  (dolist (section '("typescript" "javascript"))
    (let ((hints (gethash "inlayHints" (gethash section (lsp-configuration-section section)))))
      (should (equal (gethash "includeInlayParameterNameHints" hints) "literals"))
      (should (eq (gethash "includeInlayFunctionLikeReturnTypeHints" hints) t))
      (should (eq (gethash "includeInlayEnumMemberValueHints" hints) t)))))

(ert-deftest lsp-typescript/lenses-in-the-old-sections ()
  "In the old typescript/javascript sections too."
  (require 'lsp-javascript)
  (let ((setting (lambda (section key)
                   (gethash "enabled"
                            (gethash key (gethash section (lsp-configuration-section section)))))))
    (should (eq (funcall setting "typescript" "referencesCodeLens") t))
    (should (eq (funcall setting "typescript" "implementationsCodeLens") t))
    (should (eq (funcall setting "javascript" "referencesCodeLens") t))))

;; ====== ESLINT, FORMATTING ======

(ert-deftest lsp-typescript/eslint ()
  "ESLint from vscode-langservers-extracted's server, never formatting."
  (should (equal lsp-eslint-server-command '("vscode-eslint-language-server" "--stdio")))
  (should (eq lsp-eslint-format nil)))

(ert-deftest lsp-typescript/prettier-project ()
  "A Prettier config file, or a \"prettier\" key in package.json, up from the
file: a Prettier project."
  (let ((root (+test-lsp--project "src/a.ts" ".prettierrc")))
    (should (+my/prettier-project-p (expand-file-name "src/" root))))
  (let ((root (+test-lsp--project "src/a.ts" "prettier.config.mjs")))
    (should (+my/prettier-project-p (expand-file-name "src/" root))))
  (let ((root (+test-lsp--project "src/a.ts")))
    (with-temp-file (expand-file-name "package.json" root)
      (insert "{\"name\": \"p\", \"prettier\": {\"semi\": false}}"))
    (should (+my/prettier-project-p (expand-file-name "src/" root))))
  (let ((root (+test-lsp--project "src/a.ts")))
    (with-temp-file (expand-file-name "package.json" root)
      (insert "{\"name\": \"p\"}"))
    (should-not (+my/prettier-project-p (expand-file-name "src/" root))))
  (let ((root (+test-lsp--project "src/a.ts")))
    (with-temp-file (expand-file-name "package.json" root) (insert "not json"))
    (should-not (+my/prettier-project-p (expand-file-name "src/" root)))))

(ert-deftest lsp-typescript/prettier-formats-its-projects ()
  "In a Prettier project the mode's Apheleia formatter (the project's
Prettier), so Doom doesn't switch the buffer to the server's; elsewhere left
to Doom."
  (skip-unless (require 'apheleia nil t))
  (should (memq #'+my/format-with-prettier-h typescript-ts-base-mode-hook))
  (should (memq #'+my/format-with-prettier-h js-base-mode-hook))
  (dolist (case '((".prettierrc" . prettier-typescript) (nil . nil)))
    (let ((root (+test-lsp--project "src/a.ts")))
      (when (car case)
        (with-temp-file (expand-file-name (car case) root)))
      (with-temp-buffer
        (setq buffer-file-name (expand-file-name "src/a.ts" root)
              major-mode 'typescript-ts-mode)
        (setq-local +format-with nil)
        (+my/format-with-prettier-h)
        (should (eq +format-with (cdr case)))
        (setq buffer-file-name nil)))))
