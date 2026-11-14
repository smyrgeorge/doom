;;; tests/unit/test-agent-ui-tiling.el -*- lexical-binding: t; -*-
;; config/agent-ui with config/tiling: where a canvas's pane opens, as the
;; tiling strategy has it. No agent runs: the session is a buffer.

(+test-load "config/window" "config/tiling" "config/agent-ui")

;; ====== HELPERS ======

(defmacro +test-auti (strategy &rest body)
  "BODY from one window on a session's buffer (`session', its canvas's name
`name'), tiling's STRATEGY, nothing hidden before or after; its canvases
killed after."
  (declare (indent 1))
  `(+test-with-reset
     (set-frame-parameter nil '+my/tiling-hidden nil)
     (let* ((+my/tiling-strategy ,strategy)
            (agent-ui-display-function #'agent-ui-display-canvas)
            (agent-ui-focus-questions nil)
            (agent-ui-close-finished nil)
            (session (+test-buffer "Claude Agent @ tiling"))
            (sessions (list session)))
       (cl-letf (((symbol-function 'agent-ui--sessions) (lambda () sessions))
                 ((symbol-function 'message) #'ignore))
         (switch-to-buffer session)
         (let ((name (agent-ui--session-name session)))
           (unwind-protect (progn ,@body)
             (set-frame-parameter nil '+my/tiling-hidden nil)
             (dolist (canvas (agent-ui-canvases)) (kill-buffer canvas))))))))

(defun +test-auti-slots ()
  "The panes in order (fullscreen): each one's buffer name, the one on the
screen with a *."
  (mapcar (lambda (slot)
            (if (eq slot :shown)
                (concat "*" (buffer-name (window-buffer (car (+my/tiling--panes)))))
              (buffer-name (plist-get slot :buffer))))
          (or (+my/tiling--slots) (list :shown))))

;; ====== FULLSCREEN ======

(ert-deftest agent-ui-tiling/fullscreen-the-canvas-behind-the-session ()
  "Fullscreen: the agent's first element (no command running: a request to
the server) opens its canvas behind the session, which stays on the screen,
selected (the canvas took the frame and the keys); its next ones leave it
there; SPC w w brings it up. A question taking the focus brings it up too,
as C-c C-q does."
  (+test-auti 'fullscreen
    (let ((this-command nil)
          (canvas-name (agent-ui-canvas-buffer-name name)))
      (agent-ui-show '(:id "build" :type "progress" :max 4) :canvas name)
      (should (equal (+test-auti-slots) (list (concat "*" (buffer-name session)) canvas-name)))
      (should (eq (window-buffer (selected-window)) session))
      (agent-ui-show '(:id "tests" :type "text" :text "running") :canvas name)
      (should (equal (+test-auti-slots) (list (concat "*" (buffer-name session)) canvas-name)))
      (let ((this-command '+my/tiling-next-pane))
        (+my/tiling-next-pane))
      (should (eq (window-buffer (selected-window)) (get-buffer canvas-name)))
      (let ((this-command '+my/tiling-next-pane))
        (+my/tiling-next-pane))
      (should (eq (window-buffer (selected-window)) session))
      ;; A question taking the focus: in front, selected.
      (let ((agent-ui-focus-questions t)
            (idle nil))
        (cl-letf (((symbol-function 'run-with-idle-timer)
                   (lambda (_secs _repeat f &rest args) (push (lambda () (apply f args)) idle))))
          (agent-ui-show '(:id "fix" :type "choice" :question "Which?" :options ("A" "B")) :canvas name)
          (should (eq (window-buffer (selected-window)) session))
          (funcall (car idle))
          (should (eq (window-buffer (selected-window)) (get-buffer canvas-name)))
          (should (equal (get-text-property (point) 'agent-ui-id) "fix")))))))
