;;; tests/unit/test-lsp-rust.el -*- lexical-binding: t; -*-
;; config/lsp/rust.el: rust-analyzer's inlay hints, code lenses (references,
;; no Debug), clippy on save; what it's sent when it starts.

(load (expand-file-name "../helper-lsp" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(require 'lsp-rust)

;; ====== INLAY HINTS ======

(ert-deftest lsp-rust/inlay-hints-sent ()
  "What rust-analyzer is sent when it starts: parameter, chaining, closure
return type (closures with a block) and lifetime hints."
  (require 'lsp-rust)
  (let ((hints (plist-get (lsp-rust-analyzer--make-init-options) :inlayHints)))
    (should (eq (plist-get (plist-get hints :parameterHints) :enable) t))
    (should (eq (plist-get (plist-get hints :chainingHints) :enable) t))
    (should (equal (plist-get (plist-get hints :closureReturnTypeHints) :enable) "with_block"))
    (should (equal (plist-get (plist-get hints :lifetimeElisionHints) :enable) "skip_trivial"))))

;; ====== CODE LENSES ======

(ert-deftest lsp-rust/lens-settings ()
  "Reference counts for methods, types, traits, enum variants; Debug off."
  (should (eq lsp-rust-analyzer-lens-references-method-enable t))
  (should (eq lsp-rust-analyzer-lens-references-adt-enable t))
  (should (eq lsp-rust-analyzer-lens-references-trait-enable t))
  (should (eq lsp-rust-analyzer-lens-references-enum-variant-enable t))
  (should (eq lsp-rust-analyzer-lens-debug-enable nil)))

(ert-deftest lsp-rust/settings-survive-the-package-loading ()
  "lsp-rust's defaults are the other way round; loading it keeps the config's."
  (should (eq (+test-lsp--default 'lsp-rust-analyzer-lens-references-method-enable) nil))
  (should (eq (+test-lsp--default 'lsp-rust-analyzer-lens-debug-enable) t))
  (should (eq (+test-lsp--default 'lsp-rust-analyzer-display-parameter-hints) nil))
  (should (equal (+test-lsp--default 'lsp-rust-analyzer-cargo-watch-command) "check"))
  (should (eq lsp-rust-analyzer-lens-references-method-enable t))
  (should (eq lsp-rust-analyzer-lens-debug-enable nil))
  (should (eq lsp-rust-analyzer-display-parameter-hints t))
  (should (equal lsp-rust-analyzer-cargo-watch-command "clippy")))

(ert-deftest lsp-rust/lens-settings-sent ()
  "What rust-analyzer is sent when it starts: references on, Debug off."
  (require 'lsp-rust)
  (let ((lens (plist-get (lsp-rust-analyzer--make-init-options) :lens)))
    (should (eq (plist-get (plist-get lens :debug) :enable) :json-false))
    (let ((references (plist-get lens :references)))
      (dolist (kind '(:adt :enumVariant :method :trait))
        (should (eq (plist-get (plist-get references kind) :enable) t))))))

;; ====== CHECKS ======

(ert-deftest lsp-rust/clippy-on-save ()
  "What rust-analyzer is sent when it starts: clippy checks on save."
  (let ((check (plist-get (lsp-rust-analyzer--make-init-options) :checkOnSave)))
    (should (equal (plist-get check :command) "clippy"))))
