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
           (canvas (agent-ui-session-canvas nil "/tmp/proj/src")))
      (should (equal (buffer-name canvas) "Agent UI: Claude Agent @ proj"))
      (should (eq (buffer-local-value 'agent-ui--session-buffer canvas) session))
      (should (eq (agent-ui-session-canvas "Claude Agent @ proj" nil) canvas))
      ;; Killed with its session.
      (kill-buffer session)
      (should-not (buffer-live-p canvas)))))

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
           (canvas (agent-ui-session-canvas nil "/tmp/a/")))
      (with-current-buffer canvas (setq agent-ui--session-buffer (generate-new-buffer "other")))
      (kill-buffer first)
      (should (buffer-live-p canvas)))))
