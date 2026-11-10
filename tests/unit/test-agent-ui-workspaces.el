;;; tests/unit/test-agent-ui-workspaces.el -*- lexical-binding: t; -*-
;; config/agent-ui/workspaces.el: a session's canvas in its session's
;; workspace. Real persp-mode (Doom's workspaces), nothing saved; no agent
;; runs: sessions are buffers the tests make. A canvas shown is recorded, and
;; given a window of its own (batch Emacs's frame is too small to split for
;; `display-buffer').

(+test-load "config/agent-ui")
(require 'agent-shell)
(require 'persp-mode)

;; ====== HELPERS ======

(defvar +test-auw-sessions nil "The sessions `agent-ui--sessions' gives.")

(defvar +test-auw-shown nil "The canvases shown, the latest first.")

(defmacro +test-auw (&rest body)
  "BODY with persp-mode on (its workspaces A and B, A current) and only
`+test-auw-sessions' as agent-shell's sessions; persp-mode off, the buffers
it made killed and one window after."
  (declare (indent 0))
  `(let ((+test-auw-sessions nil)
         (+test-auw-shown nil)
         (before (buffer-list))
         (persp-auto-save-opt 0)
         (persp-auto-resume-time -1)
         (persp-save-dir (file-name-as-directory (+test-tmp-file "persp"))))
     (cl-letf (((symbol-function 'agent-ui--sessions) (lambda () +test-auw-sessions))
               ((symbol-function 'agent-shell-cwd) (lambda () default-directory))
               ((symbol-function 'agent-ui-display-canvas)
                (lambda (buffer)
                  (push buffer +test-auw-shown)
                  (set-window-buffer (split-window (frame-root-window) nil 'right) buffer))))
       (delete-other-windows)
       (persp-mode 1)
       (persp-add-new "A")
       (persp-add-new "B")
       (persp-frame-switch "A")
       (unwind-protect (progn ,@body)
         (persp-mode -1)
         (dolist (b (buffer-list))
           (unless (memq b before) (kill-buffer b)))
         (delete-other-windows)))))

(defun +test-auw-session (name workspace)
  "A session's buffer NAME, in WORKSPACE (added there, the current one kept)."
  (let ((buffer (generate-new-buffer name)))
    (with-current-buffer buffer (setq default-directory "/tmp/"))
    (push buffer +test-auw-sessions)
    (persp-add-buffer buffer (persp-get-by-name workspace) nil nil)
    (agent-ui--session-name buffer)))

(defun +test-auw-canvas (session)
  (get-buffer (agent-ui-canvas-buffer-name session)))

;; ====== TESTS ======

(ert-deftest agent-ui-workspaces/wired ()
  (should (eq agent-ui-display-function #'agent-ui-workspace-display-canvas))
  (should (memq #'agent-ui--workspace-shown-h persp-activated-functions)))

(ert-deftest agent-ui-workspaces/another-workspace-s-session-waits-there ()
  "The session in B, you in A: its elements open no pane in A; the canvas
joins B, and its pane opens when you switch there; back in A, none."
  (+test-auw
    (let* ((session (+test-auw-session "Claude Agent @ pas" "B")))
      (agent-ui-show '(:id "a" :type "text" :text "one") :canvas session)
      (agent-ui-show '(:id "b" :type "text" :text "two") :canvas session)
      (let ((canvas (+test-auw-canvas session)))
        (should-not +test-auw-shown)
        (should-not (get-buffer-window canvas t))
        (should (persp-contain-buffer-p canvas (persp-get-by-name "B")))
        (should (equal (safe-persp-name (get-current-persp)) "A"))
        ;; In B: shown, its elements there.
        (persp-frame-switch "B")
        (should (equal +test-auw-shown (list canvas)))
        (should (get-buffer-window canvas))
        (should (string-match-p "one\\(.\\|\n\\)*two" (with-current-buffer canvas (buffer-string))))
        ;; Back in A: A's panes, not the canvas.
        (persp-frame-switch "A")
        (should-not (get-buffer-window canvas))
        ;; Once shown, not again by a switch.
        (persp-frame-switch "B")
        (should (= (length +test-auw-shown) 1))))))

(ert-deftest agent-ui-workspaces/the-current-workspace-s-session-shows-it ()
  (+test-auw
    (let ((session (+test-auw-session "Claude Agent @ doom" "A")))
      (agent-ui-show '(:id "a" :type "text" :text "here") :canvas session)
      (let ((canvas (+test-auw-canvas session)))
        (should (equal +test-auw-shown (list canvas)))
        (should (get-buffer-window canvas))
        (should-not (buffer-local-value 'agent-ui--waiting canvas))))))

(ert-deftest agent-ui-workspaces/no-session-or-no-workspaces-shown-here ()
  "A canvas without a session, a session in no workspace, persp-mode off:
shown where you are, as before."
  (+test-auw
    (agent-ui-show '(:id "a" :type "text" :text "x") :canvas "plain")
    (should (equal +test-auw-shown (list (get-buffer "Agent UI: plain"))))
    (let ((session (generate-new-buffer "Claude Agent @ none")))
      (push session +test-auw-sessions)
      (agent-ui--session-name session)
      ;; persp-mode puts a new buffer in the current workspace: out of it.
      (dolist (persp (persp--buffer-in-persps session))
        (persp--remove-buffer-2 persp session))
      (agent-ui-show '(:id "a" :type "text" :text "y") :canvas "Claude Agent @ none")
      (should (eq (car +test-auw-shown) (get-buffer "Agent UI: Claude Agent @ none"))))
    (let ((session (+test-auw-session "Claude Agent @ off" "B")))
      (persp-mode -1)
      (agent-ui-show '(:id "a" :type "text" :text "z") :canvas session)
      (should (eq (car +test-auw-shown) (+test-auw-canvas session))))))
