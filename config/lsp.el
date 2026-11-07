;;; $DOOMDIR/config/lsp.el -*- lexical-binding: t; -*-
;; Language server setup, and lsp-ui's peek. Loaded from config.el; its code is
;; in config/lsp/.

;; ====== VARIABLES ======

;; CODE LENSES
;; lsp-mode shows the code lenses a server sends, at the end of the line:
;; rust-analyzer's "▶ Run" and implementations, and now also reference counts
;; for Rust and TypeScript/JavaScript. Pyright sends none.
;; rust-analyzer's "Debug" lens needs a debugger set up (dap), so it's off.
(setq lsp-rust-analyzer-lens-references-method-enable t
      lsp-rust-analyzer-lens-references-adt-enable t
      lsp-rust-analyzer-lens-references-trait-enable t
      lsp-rust-analyzer-lens-references-enum-variant-enable t
      lsp-rust-analyzer-lens-debug-enable nil
      lsp-typescript-references-code-lens-enabled t
      lsp-typescript-implementations-code-lens-enabled t
      lsp-javascript-references-code-lens-enabled t)

;; PEEK
;; - colours: a soft selection and soft matches instead of bright blue boxes;
;; - the header says what's listed: "Usages of HOLD1 · 22 in 1 file";
;; - the footer shows the keys;
;; - the preview has line numbers, with the usage's line highlighted;
;; - the peek is only as tall as its list needs (up to `lsp-ui-peek-peek-height');
;; - each usage shows the function/class it's in, grouped: the name on the
;;   first of its usages, with how many there are;
;; - usages don't list the declaration itself (where you are).
(defvar +my/peek-min-height 10
  "The peek's height when it lists only a few usages.")

(defvar +my/peek-scope-width 24
  "Widest the function/class column of the list gets.")

(after! lsp-ui-peek
  (setq lsp-ui-peek-list-width 60))     ; room for the function column

(defface +my/peek-separator '((t :inherit lsp-ui-peek-header))
  "The rows above and below the peek.")

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

;; ====== CODE ======

;; In config/lsp/, in this order: each part can use what the ones before it
;; define.
(load! "lsp/project")
(load! "lsp/lenses")
(load! "lsp/peek")
