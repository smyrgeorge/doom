;;; $DOOMDIR/config/lsp/docker.el -*- lexical-binding: t; -*-
;; Docker: docker-langserver (:tools (docker +lsp)), without its semantic
;; highlighting. Loaded from config/lsp.el.

;; THE SERVER IN DOCKERFILE-TS-MODE
;; Doom's docker module starts LSP from `dockerfile-mode''s hook only (once
;; dockerfile-mode has loaded). With +tree-sitter Dockerfiles open in
;; `dockerfile-ts-mode', which isn't derived from it: they got no server. Its
;; own hook too, as Doom's other modules have for their tree-sitter modes
;; (lsp-mode knows the mode: language "dockerfile").
(when (modulep! :tools docker +lsp)
  (add-hook 'dockerfile-ts-mode-local-vars-hook #'lsp! 'append))

;; NO SEMANTIC HIGHLIGHTING
;; docker-langserver's semantic tokens call every word of a RUN's shell
;; command a "parameter" (it doesn't parse the shell): commands, packages and
;; flags all one colour. Off in Dockerfiles: tree-sitter's colours (the
;; instructions, strings, variables, comments), the commands plain. The
;; server's other features stay (completion, diagnostics, hover, the image's
;; link to Docker Hub).
(defun +my/docker-no-semantic-tokens-h ()
  "No LSP semantic highlighting in this Dockerfile (see above)."
  (setq-local lsp-semantic-tokens-enable nil))

(add-hook 'dockerfile-ts-mode-hook #'+my/docker-no-semantic-tokens-h)
(add-hook 'dockerfile-mode-hook #'+my/docker-no-semantic-tokens-h)
