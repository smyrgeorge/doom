;;; tests/e2e/test-agent-ui.el -*- lexical-binding: t; -*-
;; config/agent-ui in a GUI Emacs: what needs real windows and redisplay. A
;; question left waiting at the turn's end, below what its canvas's pane
;; shows: the pane shown again, scrolled to it, the cursor on it, the focus
;; left in the session. No agent runs: the session is a buffer, its turn's end
;; agent-shell's event called by hand.

(+test-load "config/agent-ui")
(require 'agent-shell)

(ert-deftest e2e-agent-ui/a-question-waiting-brought-into-view ()
  (let* ((session (generate-new-buffer "Claude Agent @ e2e"))
         (agent-ui-display-function #'agent-ui-display-canvas)
         (on-event nil))
    (unwind-protect
        (cl-letf (((symbol-function 'agent-ui--sessions) (lambda () (list session)))
                  ((symbol-function 'agent-shell-subscribe-to)
                   (lambda (&rest args) (setq on-event (plist-get args :on-event)))))
          (with-current-buffer session
            (setq default-directory "/tmp/")
            (agent-ui--watch-questions-h))
          (delete-other-windows)
          (switch-to-buffer session)
          (let ((name (agent-ui--session-name session)))
            ;; More than its pane shows, then the question.
            (agent-ui-show (list :id "steps" :type "text"
                                 :text (mapconcat (lambda (i) (format "Step %d done" i)) (number-sequence 1 150) "\n"))
                           :canvas name)
            (agent-ui-show '(:id "fix" :type "choice" :question "Which fix?"
                             :options ("Change the test" "Revert the message"))
                           :canvas name)
            (let ((canvas (get-buffer (agent-ui-canvas-buffer-name name))))
              ;; Its pane closed, its top shown before.
              (with-current-buffer canvas (goto-char (point-min)))
              (delete-window (get-buffer-window canvas))
              (should-not (get-buffer-window canvas))
              (with-current-buffer session
                (funcall on-event '((:event . turn-complete))))
              (redisplay)
              (let ((window (get-buffer-window canvas)))
                (should window)
                ;; The focus where it was.
                (should (eq (window-buffer (selected-window)) session))
                ;; The cursor on the question, in view.
                (should (equal (get-text-property (window-point window) 'agent-ui-id canvas) "fix"))
                (should (pos-visible-in-window-p (window-point window) window))
                (should (> (window-start window) 1)))
              ;; The session's mode line says it.
              (with-current-buffer session
                (should (string-match-p "question waiting" (format-mode-line mode-line-format)))))))
      (kill-buffer session))))
