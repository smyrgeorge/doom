;;; tests/unit/test-lsp-kotlin.el -*- lexical-binding: t; -*-
;; config/lsp/kotlin.el: JetBrains' kotlin-lsp registered for Kotlin (its
;; intellij-server run), winning over kotlin-language-server, its own
;; notifications taken quietly.

(load (expand-file-name "../helper-lsp" (file-name-directory (or load-file-name buffer-file-name))) nil t)

;; ====== HELPERS ======

(defun +test-lsp--kotlin-client ()
  (gethash 'kotlin-lsp lsp-clients))

;; ====== CLIENT ======

(ert-deftest lsp-kotlin/registered-when-lsp-mode-loads ()
  "Registered in `after! lsp-mode': not before lsp-mode loads."
  (should-not (plist-get +test-lsp--after-config :clients))
  (should (+test-lsp--kotlin-client)))

(ert-deftest lsp-kotlin/client ()
  (let ((client (+test-lsp--kotlin-client)))
    (should (eq (lsp--client-server-id client) 'kotlin-lsp))
    (should (equal (lsp--client-major-modes client) '(kotlin-mode kotlin-ts-mode)))
    (should (eql (lsp--client-priority client) 1))
    (should-not (lsp--client-add-on? client))
    (should-not (lsp--client-remote? client))))

(ert-deftest lsp-kotlin/command-intellij-server ()
  "bin/intellij-server of the install `kotlin-lsp' links into; `kotlin-lsp'
itself when there's none."
  (let* ((install (+test-lsp--dir "kotlin-server"))
         (script (expand-file-name "kotlin-lsp.sh" install))
         (server (expand-file-name "bin/intellij-server" install))
         (link (expand-file-name "kotlin-lsp" (+test-lsp--dir "bin"))))
    (make-directory (file-name-directory server) t)
    (with-temp-file script)
    (make-symbolic-link script link)
    (cl-letf (((symbol-function 'executable-find)
               (lambda (name &rest _) (and (equal name "kotlin-lsp") link))))
      (should (equal (+my/kotlin-lsp-command) (list "kotlin-lsp" "--stdio"))) ; not executable yet
      (with-temp-file server)
      (set-file-modes server #o755)
      (should (equal (+my/kotlin-lsp-command) (list (file-truename server) "--stdio"))))
    (cl-letf (((symbol-function 'executable-find) #'ignore))
      (should (equal (+my/kotlin-lsp-command) '("kotlin-lsp" "--stdio"))))))

(ert-deftest lsp-kotlin/command-from-the-linux-zip ()
  "Linux's zip: its kotlin-lsp.sh on PATH (no `kotlin-lsp'), bin/intellij-server
beside it; without a server, the script."
  (let* ((install (+test-lsp--dir "kotlin-zip"))
         (script (expand-file-name "kotlin-lsp.sh" install))
         (server (expand-file-name "bin/intellij-server" install)))
    (make-directory (file-name-directory server) t)
    (with-temp-file script)
    (cl-letf (((symbol-function 'executable-find)
               (lambda (name &rest _) (and (equal name "kotlin-lsp.sh") script))))
      (should (equal (+my/kotlin-lsp-command) (list "kotlin-lsp.sh" "--stdio")))
      (should (funcall (plist-get (lsp--client-new-connection (+test-lsp--kotlin-client)) :test?)))
      (with-temp-file server)
      (set-file-modes server #o755)
      (should (equal (+my/kotlin-lsp-command) (list (file-truename server) "--stdio"))))))

(ert-deftest lsp-kotlin/notifications-taken-quietly ()
  "kotlin-lsp's intellij/... notifications: no warning, no handler run; others,
and other servers', as lsp-mode has them."
  (let ((kotlin (make-lsp--workspace :client (+test-lsp--kotlin-client)))
        (other (make-lsp--workspace :client (make-lsp--client :server-id 'other)))
        (warnings nil))
    (cl-letf (((symbol-function 'lsp-warn) (lambda (&rest args) (push (apply #'format args) warnings))))
      (lsp--on-notification kotlin (lsp-make-notification "intellij/workspaceImportStatus" nil))
      (lsp--on-notification kotlin (lsp-make-notification "intellij/ready-for-test" nil))
      (should-not warnings)
      (lsp--on-notification kotlin (lsp-make-notification "custom/unknown" nil))
      (lsp--on-notification other (lsp-make-notification "intellij/workspaceImportStatus" nil))
      (should (equal (reverse warnings)
                     '("Unknown notification: custom/unknown"
                       "Unknown notification: intellij/workspaceImportStatus"))))))

(ert-deftest lsp-kotlin/command ()
  "It would run kotlin-lsp's server with --stdio (the process start is mocked)."
  (let* ((connection (lsp--client-new-connection (+test-lsp--kotlin-client)))
         (started nil))
    (cl-letf (((symbol-function 'make-process)
               (lambda (&rest args) (setq started args) (throw '+test-lsp--started nil)))
              ((symbol-function 'lsp-json-rpc-connection)
               (lambda (_workspace command)
                 (setq started (list :command command)) (throw '+test-lsp--started nil))))
      (let ((default-directory (+test-lsp--dir "kt")))
        (catch '+test-lsp--started
          (funcall (plist-get connection :connect) #'ignore #'ignore "kotlin-lsp" nil nil))))
    (should (equal (plist-get started :command) (+my/kotlin-lsp-command)))
    (should (equal (cadr (plist-get started :command)) "--stdio"))
    (dolist (buffer (buffer-list))      ; the stderr buffer lsp-mode made first
      (when (string-match-p "kotlin-lsp" (buffer-name buffer))
        (kill-buffer buffer)))))

(ert-deftest lsp-kotlin/present-when-kotlin-lsp-is-installed ()
  "lsp-mode looks for the `kotlin-lsp' executable (brew's cask)."
  (let* ((connection (lsp--client-new-connection (+test-lsp--kotlin-client)))
         (looked nil))
    (cl-letf (((symbol-function 'executable-find)
               (lambda (name &rest _) (push name looked) nil)))
      (should-not (funcall (plist-get connection :test?))))
    (should (equal looked '("kotlin-lsp.sh" "kotlin-lsp")))
    (cl-letf (((symbol-function 'executable-find)
               (lambda (name &rest _) (and (equal name "kotlin-lsp") "/opt/homebrew/bin/kotlin-lsp"))))
      (should (funcall (plist-get connection :test?))))))

(ert-deftest lsp-kotlin/wins-over-kotlin-language-server ()
  "In a Kotlin buffer with both servers installed, lsp-mode picks kotlin-lsp."
  (require 'lsp-kotlin)
  (require 'kotlin-mode)
  (should (< (lsp--client-priority (gethash 'kotlin-ls lsp-clients))
             (lsp--client-priority (+test-lsp--kotlin-client))))
  (let ((buffer (+test-buffer "Main.kt")))
    (unwind-protect
        (with-current-buffer buffer
          (setq buffer-file-name (expand-file-name "Main.kt" (+test-lsp--dir "kt")))
          (delay-mode-hooks (kotlin-mode))
          (cl-letf (((symbol-function 'executable-find)
                     (lambda (name &rest _) (concat "/usr/local/bin/" name))))
            (let ((clients (lsp--find-clients)))
              (should (equal (mapcar #'lsp--client-server-id clients) '(kotlin-lsp)))))
          (setq buffer-file-name nil))
      (kill-buffer buffer))))

(ert-deftest lsp-kotlin/without-kotlin-lsp-falls-back ()
  "Only kotlin-language-server installed: that one is used."
  (require 'lsp-kotlin)
  (require 'kotlin-mode)
  (let ((buffer (+test-buffer "Other.kt")))
    (unwind-protect
        (with-current-buffer buffer
          (setq buffer-file-name (expand-file-name "Other.kt" (+test-lsp--dir "kt")))
          (delay-mode-hooks (kotlin-mode))
          (cl-letf (((symbol-function 'executable-find)
                     (lambda (name &rest _)
                       (and (string-suffix-p "kotlin-language-server" name)
                            "/usr/local/bin/kotlin-language-server"))))
            (should (equal (mapcar #'lsp--client-server-id (lsp--find-clients)) '(kotlin-ls))))
          (setq buffer-file-name nil))
      (kill-buffer buffer))))

(ert-deftest lsp-kotlin/not-for-other-modes ()
  (require 'kotlin-mode)
  (let ((buffer (+test-buffer "x.py")))
    (unwind-protect
        (with-current-buffer buffer
          (python-mode)
          (should-not (lsp--supports-buffer? (+test-lsp--kotlin-client))))
      (kill-buffer buffer))))
