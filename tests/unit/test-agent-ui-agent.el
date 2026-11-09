;;; tests/unit/test-agent-ui-agent.el -*- lexical-binding: t; -*-
;; config/agent-ui/agent.el: agent-shell's sessions and their canvases. The
;; agent started with AGENT_UI_SESSION; a request finding its session by it,
;; else by its directory; the canvas named after the session, killed with it.
;; No agent runs: sessions are buffers the tests make.

(+test-load "config/agent-ui")
(require 'agent-shell)

;; ====== HELPERS ======

(defvar +test-aua-sessions nil "The sessions `agent-ui--sessions' gives, most recent first.")

(defmacro +test-aua (&rest body)
  "BODY with no window shown and only `+test-aua-sessions' as agent-shell's
sessions (each's directory its `default-directory'); the buffers it makes,
killed after."
  (declare (indent 0))
  `(let ((agent-ui-display-function #'ignore)
         (+test-aua-sessions nil)
         (before (buffer-list)))
     (cl-letf (((symbol-function 'agent-ui--sessions) (lambda () +test-aua-sessions))
               ((symbol-function 'agent-shell-cwd) (lambda () default-directory)))
       (unwind-protect (progn ,@body)
         (dolist (b (buffer-list))
           (unless (memq b before) (kill-buffer b)))))))

(defun +test-aua-session (name dir)
  "A session's buffer NAME working in DIR, the most recent."
  (let ((buffer (generate-new-buffer name)))
    (with-current-buffer buffer (setq default-directory (file-name-as-directory dir)))
    (push buffer +test-aua-sessions)
    buffer))

;; ====== THE AGENT'S ENVIRONMENT ======

(ert-deftest agent-ui-agent/the-session-in-the-agents-environment ()
  (+test-aua
    (should (advice-member-p 'agent-ui-session-environment 'agent-shell--make-acp-client))
    (let* ((session (+test-aua-session "Claude Agent @ proj" "/tmp/"))
           (client (agent-shell--make-acp-client :command "true"
                                                 :environment-variables '("A=1")
                                                 :context-buffer session)))
      (should (equal (map-elt client :environment-variables)
                     '("AGENT_UI_SESSION=Claude Agent @ proj" "A=1")))
      ;; Its name kept: renamed, and through a change of major mode.
      (with-current-buffer session
        (rename-buffer "Renamed")
        (fundamental-mode)
        (should (equal agent-ui-session "Claude Agent @ proj")))
      (should (equal (map-elt (agent-shell--make-acp-client :command "true" :context-buffer session)
                              :environment-variables)
                     '("AGENT_UI_SESSION=Claude Agent @ proj"))))
    ;; No session buffer: nothing added.
    (should (equal (map-elt (agent-shell--make-acp-client :command "true"
                                                          :environment-variables '("A=1"))
                            :environment-variables)
                   '("A=1")))))

;; ====== FINDING THE SESSION ======

(ert-deftest agent-ui-agent/the-session-by-name ()
  (+test-aua
    (let ((a (+test-aua-session "A" "/tmp/x/"))
          (b (+test-aua-session "B" "/tmp/x/")))
      (with-current-buffer a (setq agent-ui-session "sa"))
      (with-current-buffer b (setq agent-ui-session "sb"))
      (should (eq (agent-ui--session-buffer "sa" "/tmp/x/") a))
      (should (eq (agent-ui--session-buffer "sb" nil) b)))))

(ert-deftest agent-ui-agent/the-session-by-directory ()
  (+test-aua
    (let* ((root (+test-aua-session "root" "/tmp/proj/"))
           (deep (+test-aua-session "deep" "/tmp/proj/sub/"))
           (other (+test-aua-session "other" "/tmp/elsewhere/")))
      (ignore other)
      ;; The deepest working at or above it.
      (should (eq (agent-ui--session-buffer nil "/tmp/proj/sub/dir") deep))
      (should (eq (agent-ui--session-buffer nil "/tmp/proj/sub") deep))
      (should (eq (agent-ui--session-buffer nil "/tmp/proj/lib") root))
      (should (eq (agent-ui--session-buffer nil "/tmp/proj") root))
      (should-not (agent-ui--session-buffer nil "/tmp/pro"))
      (should-not (agent-ui--session-buffer nil nil))
      ;; Two as deep: the most recently used.
      (let ((recent (+test-aua-session "recent" "/tmp/proj/")))
        (should (eq (agent-ui--session-buffer nil "/tmp/proj/lib") recent)))
      ;; A name no session has: by its directory.
      (should (eq (agent-ui--session-buffer "gone" "/tmp/proj/sub") deep)))))

;; ====== THE SESSION'S CANVAS ======

(ert-deftest agent-ui-agent/the-sessions-canvas ()
  (+test-aua
    (should (eq agent-ui-canvas-function #'agent-ui-session-canvas))
    (let* ((session (+test-aua-session "Claude Agent @ proj" "/tmp/proj/"))
           (name (agent-ui-session-canvas nil "/tmp/proj/src")))
      ;; Its name, the session's; no canvas made just for asking.
      (should (equal name "Claude Agent @ proj"))
      (should (equal (agent-ui-session-canvas "Claude Agent @ proj" nil) name))
      (should-not (get-buffer "Agent UI: Claude Agent @ proj"))
      ;; Made by the first element shown: tied to its session.
      (agent-ui-show '(:id "a" :type "text" :text "x") :canvas name)
      (let ((canvas (get-buffer "Agent UI: Claude Agent @ proj")))
        (should (eq (buffer-local-value 'agent-ui--session-buffer canvas) session))
        ;; Killed with its session.
        (kill-buffer session)
        (should-not (buffer-live-p canvas))))))

(ert-deftest agent-ui-agent/no-session ()
  (+test-aua
    ;; By the name given, else the default.
    (should (equal (agent-ui-session-canvas "named" "/tmp/") "named"))
    (should (equal (agent-ui-session-canvas nil "/tmp/") agent-ui-default-canvas))
    (should (equal (agent-ui-session-canvas "" nil) agent-ui-default-canvas))))

(ert-deftest agent-ui-agent/a-canvas-another-session-took-kept ()
  (+test-aua
    ;; Two sessions named alike in turn: killing the first leaves the
    ;; second's canvas.
    (let* ((first (+test-aua-session "S" "/tmp/a/"))
           (name (agent-ui-session-canvas nil "/tmp/a/"))
           (canvas (agent-ui-canvas name)))
      (with-current-buffer canvas (setq agent-ui--session-buffer (generate-new-buffer "other")))
      (kill-buffer first)
      (should (buffer-live-p canvas)))))

(ert-deftest agent-ui-agent/a-canvas-without-its-session ()
  (+test-aua
    ;; A canvas named after no session: tied to none.
    (let ((canvas (agent-ui-canvas (make-temp-name "nobody-"))))
      (should-not (buffer-local-value 'agent-ui--session-buffer canvas)))))

;; ====== WHAT THE AGENT IS TOLD ======

(ert-deftest agent-ui-agent/told-in-its-system-prompt ()
  (should (memq #'agent-ui-agent-context +my/agent-shell-claude-context-functions))
  (should (file-executable-p agent-ui-command))
  (should (equal agent-ui-command (expand-file-name "cmd/agent-ui" +test-root)))
  (should (equal agent-ui-skill (expand-file-name "skills/agent-ui/SKILL.md" +test-root)))
  (should (file-exists-p agent-ui-skill))
  ;; Without a server, nothing: the command couldn't reach Emacs.
  (cl-letf (((symbol-function 'server-running-p) #'ignore))
    (should-not (agent-ui-agent-context)))
  (cl-letf (((symbol-function 'server-running-p) (lambda (&rest _) t)))
    (let ((text (agent-ui-agent-context)))
      (should (string-prefix-p "Agent UI: beside this session" text))
      ;; Where the command and the skill are.
      (should (string-search (concat (abbreviate-file-name agent-ui-command) " show '{\"id\":\"build\"")
                             text))
      (should (string-search (concat "then " (abbreviate-file-name agent-ui-command)
                                     " update build '{\"value\":5}'")
                             text))
      (should (string-search (concat "read " (abbreviate-file-name agent-ui-skill)) text))
      ;; Its example is right.
      (string-match "show '\\([^']+\\)'" text)
      (should (agent-ui-check "progress" (agent-ui-parse-json (match-string 1 text)))))))

(defun +test-aua-skill ()
  (with-temp-buffer
    (insert-file-contents agent-ui-skill)
    (buffer-string)))

(ert-deftest agent-ui-agent/the-skill ()
  (let ((skill (+test-aua-skill)))
    (should (string-prefix-p "---\nname: agent-ui\ndescription: >-\n" skill))
    ;; Each type has its section; each section a type.
    (should (equal (let ((pos 0) names)
                     (while (string-match "^### `\\([a-z-]+\\)`$" skill pos)
                       (push (intern (match-string 1 skill)) names)
                       (setq pos (match-end 0)))
                     (sort names (lambda (a b) (string< (symbol-name a) (symbol-name b)))))
                   (agent-ui-types)))
    ;; Each operation it names, the command's.
    (dolist (op agent-ui-operations)
      (should (string-match-p (concat "^agent-ui " op "\\b") skill)))))

(ert-deftest agent-ui-agent/the-skills-examples-right ()
  "Each `agent-ui show/update/append ... '{...}'' in the skill: its JSON is
right, and does what it says on a canvas, in order."
  (+test-aua
    (let ((agent-ui-default-canvas (make-temp-name "skill-"))
          (skill (+test-aua-skill))
          (pos 0)
          (count 0))
      (while (string-match "^agent-ui \\(show\\|update\\|append\\) \\(?:\\([a-z]+\\) \\)?'\\({.*}\\)'$"
                           skill pos)
        (let ((op (match-string 1 skill))
              (id (match-string 2 skill))
              (json (agent-ui-parse-json (match-string 3 skill))))
          (setq pos (match-end 0))
          (cl-incf count)
          (pcase op
            ("show" (should (agent-ui-show json)))
            ("update" (should (agent-ui-update id json)))
            ("append" (should (agent-ui-append id json))))))
      (should (>= count 12))
      ;; Drawn without an error.
      (with-current-buffer (agent-ui-canvas)
        (agent-ui--flush)
        (should-not (string-search "⚠" (buffer-string)))))))

;; ====== ACTIONS ======

(ert-deftest agent-ui-agent/an-action-into-the-sessions-prompt ()
  (+test-aua
    (should (eq agent-ui-action-function #'agent-ui--act))
    (let* ((session (+test-aua-session "Claude Agent @ act" "/tmp/act/"))
           (name (agent-ui--session-name session))
           (inserted nil))
      (agent-ui-show '(:id "t" :type "text" :text "2 failed"
                       :actions ((:label "Retry" :prompt "Run the 2 failing tests again" :submit t)))
                     :canvas name)
      ;; Wrong actions: refused with the element.
      (should (string-match-p "action 1's prompt"
                              (agent-ui-error-message
                               (should-error (agent-ui-show '(:id "u" :type "text" :text "x" :actions ((:label "a")))
                                                            :canvas name)
                                             :type 'agent-ui-error))))
      (cl-letf (((symbol-function 'agent-shell-insert) (lambda (&rest args) (push args inserted))))
        (with-current-buffer (agent-ui-canvas-buffer-name name)
          (agent-ui--flush)
          (goto-char (point-min))
          (search-forward "⏵ Retry")
          (goto-char (match-beginning 0))
          (agent-ui-button-press)))
      (should (equal (car inserted) (list :text "Run the 2 failing tests again" :submit t :shell-buffer session)))
      ;; A canvas of no session: said.
      (let ((agent-ui-default-canvas (make-temp-name "lonely-")))
        (agent-ui-show '(:id "t" :type "text" :text "x" :actions ((:label "Go" :prompt "go"))))
        (with-current-buffer (agent-ui-canvas)
          (goto-char (point-min))
          (search-forward "⏵ Go")
          (goto-char (match-beginning 0))
          (should (string-match-p "no agent-shell session"
                                  (cadr (should-error (agent-ui-button-press) :type 'user-error)))))))))

