;;; tests/helper-lsp.el -*- lexical-binding: t; -*-
;; What the LSP tests (tests/unit/test-lsp*.el) share: config/lsp.el loaded as
;; Doom loads it (before lsp-mode), lsp-mode then, and helpers. Loaded by each
;; of them, after tests/helper.el. No language server is ever started: process
;; starts are mocked.

(defvar doom-disabled-packages nil)     ; `use-package!' reads it (Doom's)

;; Mocking a primitive (`call-process', `make-process') mustn't natively
;; compile a trampoline for it: that runs another Emacs.
(setq native-comp-enable-subr-trampolines nil)

;; What lsp-mode sees before it loads (the config sets its variables first).
(defvar +test-lsp--before-lsp-mode
  (list :lsp-mode (featurep 'lsp-mode)
        :clients (boundp 'lsp-clients)))

(+test-load "config/lsp")

(defvar +test-lsp--after-config
  (list :lsp-mode (featurep 'lsp-mode)
        :clients (boundp 'lsp-clients)))

(require 'projectile)                   ; Doom loads it at startup
(require 'lsp-mode)
(require 'lsp-lens)

;; ====== HELPERS ======

(defun +test-lsp--dir (name)
  "A new empty folder NAME-XXXX in the temp folder (with a slash)."
  (file-name-as-directory (make-temp-file (+test-tmp-file (concat "lsp/" name "-")) t)))

(defun +test-lsp--project (&rest files)
  "A new git project (a .git folder) with FILES (relative paths, made empty);
return its folder."
  (let ((root (+test-lsp--dir "proj")))
    (make-directory (expand-file-name ".git" root))
    (dolist (file files)
      (let ((path (expand-file-name file root)))
        (make-directory (file-name-directory path) t)
        (unless (string-suffix-p "/" file)
          (with-temp-file path))))
    root))

(defmacro +test-lsp--without-advice (symbol advice &rest body)
  "BODY with ADVICE taken off SYMBOL (put back after)."
  (declare (indent 2))
  `(progn
     (advice-remove ,symbol ,advice)
     (unwind-protect (progn ,@body)
       (advice-add ,symbol :around ,advice))))

(defun +test-lsp--default (var)
  "VAR's default value, as its package defines it."
  (eval (car (get var 'standard-value)) t))

(provide 'helper-lsp)
