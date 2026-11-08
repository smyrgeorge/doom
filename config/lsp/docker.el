;;; $DOOMDIR/config/lsp/docker.el -*- lexical-binding: t; -*-
;; Docker: docker-langserver (:tools (docker +lsp)). Loaded from config/lsp.el.

;; THE SERVER IN DOCKERFILE-TS-MODE
;; Doom's docker module starts LSP from `dockerfile-mode''s hook only (once
;; dockerfile-mode has loaded). With +tree-sitter Dockerfiles open in
;; `dockerfile-ts-mode', which isn't derived from it: they got no server. Its
;; own hook too, as Doom's other modules have for their tree-sitter modes
;; (lsp-mode knows the mode: language "dockerfile").
(when (modulep! :tools docker +lsp)
  (add-hook 'dockerfile-ts-mode-local-vars-hook #'lsp! 'append))
