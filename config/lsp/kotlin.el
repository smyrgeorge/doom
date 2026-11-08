;;; $DOOMDIR/config/lsp/kotlin.el -*- lexical-binding: t; -*-
;; Kotlin: JetBrains' kotlin-lsp. Loaded from config/lsp.el.

;; SERVER
;; JetBrains' kotlin-lsp (brew install --cask kotlin-lsp; Linux: the zip
;; of github.com/Kotlin/kotlin-lsp's releases, its kotlin-lsp.sh on PATH, or
;; linked as kotlin-lsp) instead of lsp-mode's default kotlin-language-server:
;; - its bin/intellij-server, which the `kotlin-lsp' command (a script that
;;   says it's deprecated) runs;
;; - it analyses files of a Gradle or Maven project (others get no diagnostics);
;; - its own notifications (intellij/workspaceImportStatus, ...: importing the
;;   project) are taken quietly, not warned about as unknown.
;; Inlay hints (types, parameter names, chained calls): on by default.

(defconst +my/kotlin-lsp-scripts '("kotlin-lsp" "kotlin-lsp.sh")
  "kotlin-lsp's command: brew's link (macOS), or the zip's script (Linux).")

(defun +my/kotlin-lsp--script ()
  "The first of `+my/kotlin-lsp-scripts' on PATH: its name and path."
  (seq-some (lambda (name) (when-let* ((path (executable-find name))) (cons name path)))
            +my/kotlin-lsp-scripts))

(defun +my/kotlin-lsp-command ()
  "kotlin-lsp's server: bin/intellij-server of the install the `kotlin-lsp'
command (a link to its deprecated kotlin-lsp.sh) or kotlin-lsp.sh itself is
in, else that command."
  (let* ((script (+my/kotlin-lsp--script))
         (server (and script
                      (expand-file-name "bin/intellij-server"
                                        (file-name-directory (file-truename (cdr script)))))))
    (list (cond ((and server (file-executable-p server)) server)
                (script (car script))
                (t "kotlin-lsp"))
          "--stdio")))

(after! lsp-mode
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection #'+my/kotlin-lsp-command
                                          (lambda () (+my/kotlin-lsp--script)))
    :major-modes '(kotlin-mode kotlin-ts-mode)
    :priority 1                         ; win over kotlin-ls (-1)
    :server-id 'kotlin-lsp)))

(defadvice! +my/kotlin-lsp-notifications-a (fn workspace notification)
  "kotlin-lsp's own notifications (intellij/...): taken, not warned about."
  :around #'lsp--on-notification
  (unless (and (eq (lsp--client-server-id (lsp--workspace-client workspace)) 'kotlin-lsp)
               (string-prefix-p "intellij/" (or (lsp-get notification :method) "")))
    (funcall fn workspace notification)))
