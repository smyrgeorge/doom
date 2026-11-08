;;; $DOOMDIR/config/lsp/kotlin.el -*- lexical-binding: t; -*-
;; Kotlin: JetBrains' kotlin-lsp. Loaded from config/lsp.el.

;; SERVER
;; JetBrains' kotlin-lsp (brew install --cask kotlin-lsp) instead of
;; lsp-mode's default kotlin-language-server:
;; - its bin/intellij-server, which the `kotlin-lsp' command (a script that
;;   says it's deprecated) runs;
;; - it analyses files of a Gradle or Maven project (others get no diagnostics);
;; - its own notifications (intellij/workspaceImportStatus, ...: importing the
;;   project) are taken quietly, not warned about as unknown.
;; Inlay hints (types, parameter names, chained calls): on by default.

(defun +my/kotlin-lsp-command ()
  "kotlin-lsp's server: bin/intellij-server of the install the `kotlin-lsp'
command (a link to its deprecated kotlin-lsp.sh) is in, else that command."
  (let* ((script (executable-find "kotlin-lsp"))
         (server (and script
                      (expand-file-name "bin/intellij-server"
                                        (file-name-directory (file-truename script))))))
    (list (if (and server (file-executable-p server)) server "kotlin-lsp")
          "--stdio")))

(after! lsp-mode
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection #'+my/kotlin-lsp-command
                                          (lambda () (executable-find "kotlin-lsp")))
    :major-modes '(kotlin-mode kotlin-ts-mode)
    :priority 1                         ; win over kotlin-ls (-1)
    :server-id 'kotlin-lsp)))

(defadvice! +my/kotlin-lsp-notifications-a (fn workspace notification)
  "kotlin-lsp's own notifications (intellij/...): taken, not warned about."
  :around #'lsp--on-notification
  (unless (and (eq (lsp--client-server-id (lsp--workspace-client workspace)) 'kotlin-lsp)
               (string-prefix-p "intellij/" (or (lsp-get notification :method) "")))
    (funcall fn workspace notification)))
