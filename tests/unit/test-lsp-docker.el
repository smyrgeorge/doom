;;; tests/unit/test-lsp-docker.el -*- lexical-binding: t; -*-
;; config/lsp/docker.el: Dockerfiles in dockerfile-ts-mode (init.el's
;; :tools (docker +lsp +tree-sitter)) start their server too, as in
;; dockerfile-mode (Doom's module hooks only that one); without the server's
;; semantic highlighting (every word of a RUN one colour), tree-sitter's.

(load (expand-file-name "../helper-lsp" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(require 'lsp-dockerfile)
(require 'lsp-semantic-tokens)

(ert-deftest lsp-docker/server-in-dockerfile-ts-mode ()
  "LSP on dockerfile-ts-mode's local-vars hook (Doom runs a buffer's own
mode's only), last."
  (should (memq 'lsp! (default-value 'dockerfile-ts-mode-local-vars-hook)))
  (should (eq (car (last (default-value 'dockerfile-ts-mode-local-vars-hook))) 'lsp!)))

(ert-deftest lsp-docker/the-server-takes-dockerfile-ts-mode ()
  "lsp-mode's Dockerfile client (docker-langserver) activates in a
dockerfile-ts-mode buffer: its language is \"dockerfile\"."
  (let ((client (gethash 'dockerfile-ls lsp-clients)))
    (should client)
    (should (equal (alist-get 'dockerfile-ts-mode lsp-language-id-configuration) "dockerfile"))
    (with-temp-buffer
      (setq major-mode 'dockerfile-ts-mode
            buffer-file-name (+test-tmp-file "docker/Dockerfile"))
      (should (funcall (lsp--client-activation-fn client) buffer-file-name major-mode))
      (set-buffer-modified-p nil))))

(ert-deftest lsp-docker/only-with-docker-s-lsp ()
  "Without :tools docker's +lsp flag, no hook."
  (let ((dockerfile-ts-mode-local-vars-hook nil))
    (cl-letf (((symbol-function '+test-module-p)
               (lambda (group module &rest flags)
                 (not (and (eq group :tools) (eq module 'docker) (memq '+lsp flags))))))
      (+test-load "config/lsp/docker"))
    (should-not (memq 'lsp! dockerfile-ts-mode-local-vars-hook))))

(ert-deftest lsp-docker/no-semantic-highlighting ()
  "In Dockerfiles (both modes) semantic highlighting stays off when the
server connects; elsewhere it's on (config/lsp.el)."
  (should (memq '+my/docker-no-semantic-tokens-h dockerfile-ts-mode-hook))
  (should (memq '+my/docker-no-semantic-tokens-h dockerfile-mode-hook))
  (should (default-value 'lsp-semantic-tokens-enable))
  (with-temp-buffer
    (+my/docker-no-semantic-tokens-h)
    (should (local-variable-p 'lsp-semantic-tokens-enable))
    (should-not lsp-semantic-tokens-enable)
    ;; As lsp-mode configures the buffer: the server has semantic tokens.
    (cl-letf (((symbol-function 'lsp-feature?) (lambda (&rest _) t))
              ((symbol-function 'lsp-semantic-tokens-mode) (lambda (&rest _) (error "Turned on"))))
      (lsp-semantic-tokens--enable)))
  (with-temp-buffer
    (should lsp-semantic-tokens-enable)))
