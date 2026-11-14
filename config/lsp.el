;;; $DOOMDIR/config/lsp.el -*- lexical-binding: t; -*-
;; Language servers: what's on for all of them, and lsp-ui's peek. Loaded from
;; config.el; its code, and each language's own settings, are in config/lsp/.

;; ====== VARIABLES ======

;; SERVERS
;; A server per language of init.el's +lsp modules, installed by
;; scripts/tools.sh; a language's own settings, where it has some, in
;; config/lsp/LANGUAGE.el:
;;   C/C++                  clangd
;;   Docker                 docker-langserver                  lsp/docker.el
;;   GDScript               Godot's editor (it serves while open)
;;   HTML, CSS, JSON        vscode-langservers-extracted
;;   Java                   Eclipse's jdtls (lsp-java downloads it)
;;   Kotlin                 JetBrains' kotlin-lsp              lsp/kotlin.el
;;   Lua                    lua-language-server
;;   Markdown               marksman
;;   Python                 basedpyright                       lsp/python.el
;;   Rust                   rust-analyzer                      lsp/rust.el
;;   Shell                  bash-language-server (shellcheck)
;;   TypeScript/JavaScript  TypeScript 7 (and ESLint)          lsp/typescript.el
;;   YAML                   yaml-language-server

;; FEATURES
;; Doom turns off the LSP features that can be slow or get in the way
;; (modules/tools/lsp/+lsp.el); these are back on, as an IDE has them:
;; - inlay hints: types and parameter names inline, in the comment colour (what
;;   each server shows: its language's file);
;; - semantic highlighting: the server colours symbols by what they are
;;   (a parameter, a mutable variable, a macro...), over tree-sitter's
;;   colours; it asks again when the server has indexed the project;
;; - colours: CSS and HTML colour values get a swatch.
;; Still off: breadcrumbs (the sticky header shows where you are, see
;; config/editor.el), LSP folding (tree-sitter folds), formatting as you type
;; (formatting is on save, see :editor format).
(setq lsp-inlay-hint-enable t
      lsp-semantic-tokens-enable t
      lsp-semantic-tokens-honor-refresh-requests t
      lsp-enable-text-document-color t)

;; CODE LENSES
;; lsp-mode shows the code lenses a server sends (which: its language's file)
;; at the end of the line, placed there without measuring the line.

;; PEEK
;; - colours: a soft selection and soft matches instead of bright blue boxes;
;; - the header says what's listed: "Usages of HOLD1 · 22 in 1 file";
;; - the footer shows the keys;
;; - the preview has line numbers, with the usage's line highlighted;
;; - the peek is only as tall as its list needs (up to `lsp-ui-peek-peek-height')
;;   and the window lets: it shows whole, below the declaration;
;; - it fits its pane's width: the list takes half of it (at most
;;   `lsp-ui-peek-list-width'), all of it in a pane narrower than
;;   `+my/peek-preview-min-width' (no preview); drawn again as the pane's size
;;   changes;
;; - each usage shows the function/class it's in, grouped: the name on the
;;   first of its usages, with how many there are;
;; - usages don't list the declaration itself (where you are).
(defvar +my/peek-min-height 10
  "The peek's height when it lists only a few usages.")

(defvar +my/peek-scope-width 24
  "Widest the function/class column of the list gets.")

(defvar +my/peek-preview-min-width 70
  "The narrowest pane the peek shows its preview in, in columns.")

(after! lsp-ui-peek
  (setq lsp-ui-peek-list-width 60))     ; the widest: room for the function column

(defface +my/peek-separator '((t :inherit lsp-ui-peek-header))
  "The rows above and below the peek.")

;; ====== CODE ======

;; In config/lsp/, in this order: each part can use what the ones before it
;; define.
(load! "lsp/capabilities")
(load! "lsp/project")
(load! "lsp/lenses")
(load! "lsp/peek")

;; Each language's settings (see SERVERS).
(load! "lsp/docker")
(load! "lsp/kotlin")
(load! "lsp/python")
(load! "lsp/rust")
(load! "lsp/typescript")
