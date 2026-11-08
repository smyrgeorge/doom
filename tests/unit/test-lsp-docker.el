;;; tests/unit/test-lsp-docker.el -*- lexical-binding: t; -*-
;; config/lsp/docker.el: Dockerfiles in dockerfile-ts-mode (init.el's
;; :tools (docker +lsp +tree-sitter)) start their server too, as in
;; dockerfile-mode (Doom's module hooks only that one).

(load (expand-file-name "../helper-lsp" (file-name-directory (or load-file-name buffer-file-name))) nil t)

(require 'lsp-dockerfile)

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
