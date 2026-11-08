;;; tests/unit/test-lsp-python.el -*- lexical-binding: t; -*-
;; config/lsp/python.el: basedpyright as Python's server, through lsp-pyright
;; (set before it loads: it names the server's command and settings after it).

(load (expand-file-name "../helper-lsp" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(defvar +test-lsp-python--before-lsp-pyright (featurep 'lsp-pyright)
  "Whether lsp-pyright had loaded when the config set its server.")

(require 'lsp-pyright)

(ert-deftest lsp-python/basedpyright ()
  "basedpyright, set before lsp-pyright loads."
  (should-not +test-lsp-python--before-lsp-pyright)
  (should (equal lsp-pyright-langserver-command "basedpyright"))
  (should (equal (+test-lsp--default 'lsp-pyright-langserver-command) "pyright")))

(ert-deftest lsp-python/runs-basedpyright-langserver ()
  "The server lsp-pyright looks for: basedpyright-langserver (uv's), else npm's
basedpyright."
  (let ((dependency (gethash 'pyright lsp--dependencies)))
    (should (member '(:system "basedpyright-langserver") dependency))
    (should (equal (plist-get (cdr (assq :npm dependency)) :package) "basedpyright"))))

(ert-deftest lsp-python/settings-named-after-basedpyright ()
  "Its settings, inlay hints among them, under basedpyright (as it asks)."
  (let* ((section (lsp--section-workspace-configuration "basedpyright"))
         (analysis (gethash "analysis" section)))
    (should analysis)
    (should (eq (gethash "variableTypes" (gethash "inlayHints" analysis)) t))
    (should (eq (gethash "callArgumentNames" (gethash "inlayHints" analysis)) t))
    (should (equal (gethash "typeCheckingMode" section) "standard"))))
