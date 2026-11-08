;;; $DOOMDIR/config/lsp/python.el -*- lexical-binding: t; -*-
;; Python: basedpyright, through lsp-pyright (:lang (python +pyright)).
;; Loaded from config/lsp.el.

;; SERVER
;; basedpyright, Pyright's community fork (uv tool install basedpyright,
;; scripts/tools.sh): the same checks, and also inlay hints (variable and return
;; types, argument names), semantic highlighting, and Pylance's features
;; Pyright leaves out. lsp-pyright knows it; its type checking mode stays
;; lsp-pyright's ("standard"), a project's pyproject.toml or
;; pyrightconfig.json overriding it.
;; Set before lsp-pyright loads: it names the server's settings after it.
(setq lsp-pyright-langserver-command "basedpyright")
