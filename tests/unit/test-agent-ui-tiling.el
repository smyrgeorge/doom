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

;; ====== A SESSION'S CANVASES, ONE PANE ======

(ert-deftest agent-ui-tiling/a-sessions-canvases-tabs-of-one-pane ()
  "Tall: the session's canvas in a pane of its own; its other canvases (tests,
logs, ask) tabs of that pane, each in front when it opens, the ones before
kept as its tabs (each took a stack pane: five canvases, five panes of a
few lines). A question answered, its canvas gone: the tab before it in
front again. Coming back with the session: behind the one shown."
  (+test-auti 'tall
    (agent-ui-show '(:id "build" :type "progress" :max 4) :canvas name)
    (let* ((main (get-buffer (agent-ui-canvas-buffer-name name)))
           (pane (get-buffer-window main)))
      (should pane)
      (should (= (length (+my/tiling--panes)) 2))
      (dolist (part '("tests" "logs"))
        (agent-ui-show '(:id "t" :type "text" :text "x") :canvas (agent-ui-sub-canvas name part)))
      (should (= (length (+my/tiling--panes)) 2))
      (should (eq (window-buffer pane) (get-buffer (agent-ui-canvas-buffer-name (concat name " / logs")))))
      (should (equal (mapcar (lambda (b) (buffer-name b)) (mapcar #'car (window-prev-buffers pane)))
                     (list (agent-ui-canvas-buffer-name (concat name " / tests")) (buffer-name main))))
      ;; Selected still: the session.
      (should (eq (window-buffer (selected-window)) session))
      ;; A question: a tab too; answered, gone: the one before in front.
      (let ((agent-ui-action-function #'ignore)
            (ask (agent-ui-sub-canvas name "ask")))
        (agent-ui-show '(:id "go" :type "confirm" :question "Deploy?") :canvas ask)
        (should (= (length (+my/tiling--panes)) 2))
        (let ((canvas (get-buffer (agent-ui-canvas-buffer-name ask))))
          (should (eq (window-buffer pane) canvas))
          (with-current-buffer canvas
            (agent-ui--flush)
            (goto-char (point-min))
            (search-forward "⏵ Proceed")
            (goto-char (match-beginning 0))
            (agent-ui-button-press))
          (let ((end (+ (float-time) 0.2)))
            (while (< (float-time) end) (accept-process-output nil 0.02)))
          (should-not (buffer-live-p canvas))
          (should (eq (window-buffer pane) (get-buffer (agent-ui-canvas-buffer-name (concat name " / logs")))))
          (should (= (length (+my/tiling--panes)) 2))))
      ;; Coming back with its session: a tab behind the one shown.
      (let ((agent-ui--restoring t))
        (agent-ui-show '(:id "x" :type "text" :text "x") :canvas (agent-ui-sub-canvas name "later")))
      (should (eq (window-buffer pane) (get-buffer (agent-ui-canvas-buffer-name (concat name " / logs")))))
      (should (assq (get-buffer (agent-ui-canvas-buffer-name (concat name " / later"))) (window-prev-buffers pane))))))

(ert-deftest agent-ui-tiling/a-questions-answer-in-view ()
  "A question taking the focus in a short pane: its pane grown to show it
all, its first line at the top, Answer in view (5 lines showed its first
lines, the cursor on the first, Answer below)."
  (+test-auti 'tall
    (agent-ui-show '(:id "build" :type "progress" :max 4) :canvas name)
    (let* ((main (get-buffer (agent-ui-canvas-buffer-name name)))
           (pane (get-buffer-window main)))
      ;; Short: the stack's other panes taking the room.
      (dolist (other '("x1" "x2" "x3"))
        (let ((this-command 'test))
          (set-window-buffer (+my/tiling-split) (+test-buffer other))))
      (select-window (get-buffer-window session))
      (should (< (window-body-height pane) 6))
      (agent-ui-show (list :id "fix" :type "choice" :question "Which fix?"
                           :options '("One" "Two" "Three" "Four" "Five" "Six")
                           :title "Pick")
                     :canvas name)
      (let ((agent-ui-focus-questions t))
        (agent-ui--focus-question main "fix"))
      (should (eq (selected-window) pane))
      (with-current-buffer main
        (let* ((start (agent-ui--element-start main "fix"))
               (end (agent-ui--element-end "fix" start)))
          (should (equal (get-text-property (window-point pane) 'agent-ui-id) "fix"))
          (should (= (window-start pane) (save-excursion (goto-char start) (line-beginning-position))))
          (should (>= (window-body-height pane) (count-lines (window-start pane) end)))
          (should (save-excursion (goto-char start) (search-forward "⏵ Answer" end t))))))))
