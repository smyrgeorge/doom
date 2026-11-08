;;; $DOOMDIR/config/lsp/rust.el -*- lexical-binding: t; -*-
;; Rust: rust-analyzer (rustic, :lang rust). Loaded from config/lsp.el.

;; INLAY HINTS
;; Types (on by default), and also parameter names at call sites, types along
;; method chains, return types of closures with a block, lifetimes left out
;; (but trivial ones).
(setq lsp-rust-analyzer-display-parameter-hints t
      lsp-rust-analyzer-display-chaining-hints t
      ;; Not `lsp-rust-analyzer-display-closure-return-type-hints': lsp-mode
      ;; doesn't send that one.
      lsp-rust-analyzer-closure-return-type-hints "with_block"
      lsp-rust-analyzer-display-lifetime-elision-hints-enable "skip_trivial")

;; CODE LENSES
;; "▶ Run" and implementations (rust-analyzer's own), and reference counts for
;; methods, types, traits and enum variants. The "Debug" lens needs a debugger
;; set up (dap), so it's off.
(setq lsp-rust-analyzer-lens-references-method-enable t
      lsp-rust-analyzer-lens-references-adt-enable t
      lsp-rust-analyzer-lens-references-trait-enable t
      lsp-rust-analyzer-lens-references-enum-variant-enable t
      lsp-rust-analyzer-lens-debug-enable nil)

;; CHECKS
;; On save, clippy instead of cargo check: its lints too, as diagnostics
;; (rustup component add clippy).
(setq lsp-rust-analyzer-cargo-watch-command "clippy")
