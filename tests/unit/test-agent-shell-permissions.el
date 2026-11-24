;;; tests/unit/test-agent-shell-permissions.el -*- lexical-binding: t; -*-
;; config/agent-shell/permissions.el's RULES FOR AN AGENT THAT HAS NONE OF ITS
;; OWN: a session's tools and deny (Claude Code's syntax) answering its
;; agent's permission requests, matched against their kind and what they act
;; on. No agent: agent-shell's tool calls and requests, stood in for.

;; Doom's `use-package!' reads it (Doom's package manager defines it).
(defvar doom-disabled-packages nil)

(+test-load "config/agent-shell")
(require 'agent-shell)

(defun +test-asp--call (kind &rest more)
  "A tool call of KIND (ACP's), MORE its other keys (:title, :raw-input,
:locations)."
  (append (list (cons :kind kind))
          (cl-loop for (key value) on more by #'cddr collect (cons key value))))

(ert-deftest agent-shell-permissions/a-rule-by-kind ()
  "A tool alone matches its kinds: Read reads, Grep and Glob search, Edit
edits, deletes and moves, Write edits, Bash executes, WebFetch fetches."
  (dolist (case '(("Read" "read" t) ("Read" "edit" nil) ("Grep" "search" t) ("Glob" "search" t)
                  ("Edit" "edit" t) ("Edit" "delete" t) ("Edit" "move" t) ("Write" "edit" t)
                  ("Bash" "execute" t) ("Bash" "read" nil) ("WebFetch" "fetch" t) ("WebSearch" "fetch" t)
                  ("mcp__agent-ui" "other" nil) ("Unknown" "read" nil)))
    (ert-info ((format "%S" case))
      (should (eq (and (+my/agent-shell-rule-matches-p (nth 0 case) (+test-asp--call (nth 1 case))) t)
                  (nth 2 case))))))

(ert-deftest agent-shell-permissions/a-command ()
  "Bash(prefix:*): the command, its raw input's (a string or a list), else
its title, starting with it (a word); Bash(glob): * anything, the whole."
  (let ((push (+test-asp--call "execute" :raw-input '((command . "git push origin main")))))
    (should (+my/agent-shell-rule-matches-p "Bash(git push:*)" push))
    (should-not (+my/agent-shell-rule-matches-p "Bash(git pu:*)" push))
    (should (+my/agent-shell-rule-matches-p "Bash(git * main)" push))
    (should-not (+my/agent-shell-rule-matches-p "Bash(git push)" push)))
  (should (+my/agent-shell-rule-matches-p
           "Bash(git -C * push)" (+test-asp--call "execute" :raw-input '((command . ["git" "-C" "/p" "push"])))))
  (should (+my/agent-shell-rule-matches-p "Bash(npm install:*)" (+test-asp--call "execute" :title "`npm install`")))
  (should (+my/agent-shell-rule-matches-p "Bash(npm install:*)" (+test-asp--call "execute" :title "npm install"))))

(ert-deftest agent-shell-permissions/a-path ()
  "Edit(glob): a path it acts on (its raw input's, its locations'), relative
to the session's folder (/x from there too; //x absolute); ** any folders,
* within one."
  (let ((doc (+test-asp--call "edit" :raw-input '((file_path . "/p/docs/a/b.md"))))
        (code (+test-asp--call "edit" :locations [((path . "/p/src/a.el"))])))
    (should (+my/agent-shell-rule-matches-p "Edit(docs/**)" doc "/p/"))
    (should (+my/agent-shell-rule-matches-p "Edit(**/*.md)" doc "/p/"))
    (should-not (+my/agent-shell-rule-matches-p "Edit(docs/*.md)" doc "/p/"))
    (should (+my/agent-shell-rule-matches-p "Edit(/docs/**)" doc "/p"))
    (should (+my/agent-shell-rule-matches-p "Edit(//p/docs/**)" doc "/elsewhere/"))
    (should-not (+my/agent-shell-rule-matches-p "Edit(docs/**)" code "/p/"))
    (should (+my/agent-shell-rule-matches-p "Edit(src/*.el)" code "/p/"))
    ;; None to match: no path, nothing matched.
    (should-not (+my/agent-shell-rule-matches-p "Edit(docs/**)" (+test-asp--call "edit") "/p/"))))

(ert-deftest agent-shell-permissions/deny-first-then-tools ()
  "A deny rule matching: reject; else a tools one: allow; else nil (asked)."
  (let ((rules '(:tools ("Read" "Bash(git:*)") :deny ("Bash(git push:*)"))))
    (should (eq (+my/agent-shell-permission-by-rules rules (+test-asp--call "read")) 'allow))
    (should (eq (+my/agent-shell-permission-by-rules
                 rules (+test-asp--call "execute" :raw-input '((command . "git status")))) 'allow))
    (should (eq (+my/agent-shell-permission-by-rules
                 rules (+test-asp--call "execute" :raw-input '((command . "git push")))) 'reject))
    (should-not (+my/agent-shell-permission-by-rules rules (+test-asp--call "edit")))))

(ert-deftest agent-shell-permissions/the-responder ()
  "The session's rules answer its request, as an option of their kind (once,
else always); none for it, or none decides: the responder before ours, else
nil (agent-shell asks)."
  (should (eq agent-shell-permission-responder-function #'+my/agent-shell-permission-responder))
  (let ((session (generate-new-buffer " *test session*"))
        (answered nil))
    (unwind-protect
        (cl-letf (((symbol-function 'agent-shell-cwd) (lambda () "/p/")))
          (with-current-buffer session
            (setq-local +my/agent-shell-permission-rules '(:tools ("Read") :deny ("Bash"))))
          (cl-flet ((ask (kind options)
                      (setq answered nil)
                      (let ((+my/agent-shell--requesting (list (cons :buffer session))))
                        (+my/agent-shell-permission-responder
                         (list (cons :tool-call (+test-asp--call kind))
                               (cons :options (mapcar (lambda (option)
                                                        (list (cons :kind (car option)) (cons :option-id (cdr option))))
                                                      options))
                               (cons :respond (lambda (id) (setq answered id) t)))))))
            (should (ask "execute" '(("allow_once" . "a") ("reject_once" . "r"))))
            (should (equal answered "r"))
            (should (ask "read" '(("allow_always" . "aa") ("reject_once" . "r"))))
            (should (equal answered "aa"))
            ;; Nothing decides: asked.
            (should-not (ask "edit" '(("allow_once" . "a") ("reject_once" . "r"))))
            (should-not answered)
            ;; The responder before ours, then.
            (let ((+my/agent-shell-permission-responder-next (lambda (_) 'next)))
              (should (eq (ask "edit" '(("allow_once" . "a"))) 'next)))
            ;; A session without rules (Claude Code's): asked.
            (with-current-buffer session (setq-local +my/agent-shell-permission-rules nil))
            (should-not (ask "execute" '(("allow_once" . "a") ("reject_once" . "r"))))))
      (kill-buffer session))))
