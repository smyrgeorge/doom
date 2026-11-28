;;; tests/unit/test-agent-ui-tiling.el -*- lexical-binding: t; -*-
;; config/agent-ui with config/tiling: a session's Agent UI in its session's
;; pane, which tiling lays out as one pane, its views' windows taken out
;; before and put back after (config/tiling.el, WINDOWS ATTACHED TO A PANE).
;; No agent runs: the session is a buffer. A batch Emacs doesn't run window
;; change functions: the tests run them where Emacs would.

(+test-load "config/emacs" "config/tiling" "config/agent-ui")
;; Its parts, loaded with agent-shell or when first used (no session here).
(require 'agent-ui-parts)

;; ====== HELPERS ======

(defmacro +test-auti (strategy &rest body)
  "BODY from one window on notes.txt, a session's buffer (`session', its
canvas's name `name') in a pane of its own beside it, tiling's STRATEGY,
nothing hidden before or after; its canvases killed after."
  (declare (indent 1))
  `(+test-with-reset
     (set-frame-parameter nil '+my/tiling-hidden nil)
     (let* ((+my/tiling-strategy ,strategy)
            (+my/tiling-tall-ratio 0.5)
            (agent-ui-focus-questions nil)
            (agent-ui-close-finished nil)
            (this-command 'test)
            (notes (+test-buffer "notes.txt" "Notes.\n"))
            (session (+test-buffer "Claude Agent @ tiling" "The conversation.\n"))
            (sessions (list session)))
       (cl-letf (((symbol-function 'agent-ui--sessions) (lambda () sessions))
                 ((symbol-function 'message) #'ignore))
         (switch-to-buffer notes)
         (pop-to-buffer session '(+my/tiling-display-buffer))
         (let ((name (agent-ui--session-name session)))
           (unwind-protect (progn ,@body)
             (set-frame-parameter nil '+my/tiling-hidden nil)
             (dolist (canvas (agent-ui-canvases)) (kill-buffer canvas))
             (kill-buffer session)))))))

(defun +test-auti-in-place-p (session)
  "Non-nil if SESSION's views are under its window, in its pane."
  (when-let* ((window (agent-ui--pane-session-window session))
              (cells (agent-ui--pane-cells (selected-frame) session)))
    (agent-ui--pane-in-place-p window cells)))

(defun +test-auti-slots ()
  "The panes in order (fullscreen): each one's buffer name, the one on the
screen with a *."
  (mapcar (lambda (slot)
            (if (eq slot :shown)
                (concat "*" (buffer-name (window-buffer (car (+my/tiling--panes)))))
              (buffer-name (plist-get slot :buffer))))
          (or (+my/tiling--slots) (list :shown))))

;; ====== ONE PANE ======

(ert-deftest agent-ui-tiling/agent-ui-not-a-pane ()
  "Tall: the session's first element opens Agent UI in its pane, not a new
pane; its windows aren't panes (tiling's count, SPC w w's turns)."
  (+test-auti 'tall
    (should (= (length (+my/tiling--panes)) 2))
    (agent-ui-show '(:id "build" :type "progress" :max 4) :canvas name)
    (agent-ui-show '(:id "t" :type "text" :text "x") :canvas (agent-ui-sub-canvas name "tests"))
    (should (= (length (agent-ui--pane-cells (selected-frame))) 2))
    (should (= (length (+my/tiling--panes)) 2))
    (should (equal (mapcar #'window-buffer (+my/tiling--panes)) (list notes session)))
    (should (+test-auti-in-place-p session))
    (should (eq (window-buffer (selected-window)) session))))

(ert-deftest agent-ui-tiling/tiling-takes-it-along ()
  "SPC w a, SPC w SPC (another pane), SPC w RET (the session to the main
pane), SPC w } (the pane bigger), a strategy chosen: Agent UI stays in the
session's pane each time, the panes as tiling has them."
  (+test-auti 'tall
    (agent-ui-show '(:id "build" :type "progress" :max 4) :canvas name)
    (+my/tiling-arrange)
    (should (+test-auti-in-place-p session))
    (should (= (length (+my/tiling--panes)) 2))
    ;; Another pane, from notes.txt: three panes, Agent UI still the session's.
    (select-window (get-buffer-window notes))
    (+my/tiling-split)
    (should (= (length (+my/tiling--panes)) 3))
    (should (+test-auti-in-place-p session))
    ;; The session to the main pane: its Agent UI with it.
    (select-window (agent-ui--pane-session-window session))
    (+my/tiling-swap-main)
    (should (eq (window-buffer (car (+my/tiling--ordered-panes))) session))
    (should (+test-auti-in-place-p session))
    ;; Resized, then another strategy.
    (select-window (get-buffer-window notes))
    (+my/tiling-pane-bigger)
    (should (+test-auti-in-place-p session))
    (+my/tiling--set-strategy 'wide)
    (should (+test-auti-in-place-p session))
    (should (= (length (+my/tiling--panes)) 3))))

(ert-deftest agent-ui-tiling/from-a-view-as-from-its-session ()
  "SPC w a from one of Agent UI's views: as from its session's pane, the
view selected again after."
  (+test-auti 'tall
    (agent-ui-show '(:id "build" :type "progress" :max 4) :canvas name)
    (let ((canvas (get-buffer (agent-ui-canvas-buffer-name name))))
      (select-window (get-buffer-window canvas))
      (+my/tiling-arrange)
      (should (eq (window-buffer (selected-window)) canvas))
      (should (agent-ui-pane-window-p (selected-window)))
      (should (+test-auti-in-place-p session)))))

(ert-deftest agent-ui-tiling/a-pane-closed ()
  "Another pane closed: the stack laid out again (tiling's :closed), Agent
UI still in the session's pane."
  (+test-auti 'tall
    (agent-ui-show '(:id "build" :type "progress" :max 4) :canvas name)
    (pop-to-buffer (+test-buffer "x.txt") '(+my/tiling-display-buffer))
    (should (= (length (+my/tiling--panes)) 3))
    (+my/tiling--closed-h (selected-frame)) ; seen: 3 panes
    (delete-window (get-buffer-window "x.txt"))
    (+my/tiling--closed-h (selected-frame))
    (should (= (length (+my/tiling--panes)) 2))
    (should (+test-auti-in-place-p session))))

(ert-deftest agent-ui-tiling/the-sessions-pane-closed ()
  "The session's pane closed (SPC w d): Agent UI's windows go with it, the
other pane alone."
  (+test-auti 'tall
    (agent-ui-show '(:id "build" :type "progress" :max 4) :canvas name)
    (+my/tiling--closed-h (selected-frame))
    (delete-window (agent-ui--pane-session-window session))
    (+my/tiling--closed-h (selected-frame))
    (should-not (agent-ui--pane-cells (selected-frame)))
    (should (equal (window-list nil 'nomini) (list (get-buffer-window notes))))))

;; ====== FULLSCREEN ======

(ert-deftest agent-ui-tiling/fullscreen-on-the-screen-with-its-session ()
  "Fullscreen, the session on the screen: Agent UI shown in its pane, not
behind it. Another pane brought up (SPC w w): it's gone; the session back:
back with it. An element shown while the session is hidden opens nothing."
  (+test-auti 'fullscreen
    (+my/tiling--lay-out)
    (should (equal (+test-auti-slots) (list "notes.txt" (concat "*" (buffer-name session)))))
    (let ((this-command nil))
      (agent-ui-show '(:id "build" :type "progress" :max 4) :canvas name))
    (should (equal (+test-auti-slots) (list "notes.txt" (concat "*" (buffer-name session)))))
    (should (+test-auti-in-place-p session))
    (should (= (length (+my/tiling--panes)) 1))
    (let ((this-command '+my/tiling-next-pane))
      (+my/tiling-next-pane))
    (agent-ui--pane-sync)
    (should (eq (window-buffer (car (+my/tiling--panes))) notes))
    (should-not (agent-ui--pane-cells (selected-frame)))
    (let ((this-command nil))
      (agent-ui-show '(:id "tests" :type "text" :text "running") :canvas name))
    (should (equal (+test-auti-slots) (list "*notes.txt" (buffer-name session))))
    (let ((this-command '+my/tiling-next-pane))
      (+my/tiling-next-pane))
    (agent-ui--pane-sync)
    (should (+test-auti-in-place-p session))))

;; ====== QUESTIONS ======

(ert-deftest agent-ui-tiling/a-question-its-view-selected ()
  "A question taking the focus: its view selected, the cursor on it, all of
it in view, Answer too (its view grown if it must)."
  (+test-auti 'tall
    (agent-ui-show '(:id "build" :type "progress" :max 4) :canvas name)
    ;; Another pane in the stack: the session's pane shorter, its view too.
    (pop-to-buffer (+test-buffer "x1") '(+my/tiling-display-buffer))
    (select-window (agent-ui--pane-session-window session))
    (let ((main (get-buffer (agent-ui-canvas-buffer-name name))))
      (agent-ui-show (list :id "fix" :type "choice" :question "Which fix?"
                           :options '("One" "Two" "Three" "Four" "Five" "Six")
                           :title "Pick")
                     :canvas name)
      (let ((agent-ui-focus-questions t))
        (agent-ui--focus-question main "fix"))
      (let ((view (selected-window)))
        (should (eq (window-buffer view) main))
        (should (agent-ui-pane-window-p view))
        (with-current-buffer main
          (let* ((start (agent-ui--component-start main "fix"))
                 (end (agent-ui--component-end "fix" start)))
            (should (equal (get-text-property (window-point view) 'agent-ui-id) "fix"))
            (should (= (window-start view) (save-excursion (goto-char start) (line-beginning-position))))
            (should (save-excursion (goto-char start) (search-forward "⏵ Answer" end t)))))))))

(ert-deftest agent-ui-tiling/a-question-shows-a-hidden-session ()
  "A question while the session is in no window (notes.txt in its pane):
the session shown (as C-c C-q), Agent UI with it, the question selected."
  (+test-auti 'tall
    (agent-ui-show '(:id "build" :type "progress" :max 4) :canvas name)
    (let ((pane (agent-ui--pane-session-window session)))
      (with-selected-window pane
        (switch-to-buffer notes))
      (agent-ui--pane-sync)
      (should-not (agent-ui--pane-cells (selected-frame)))
      (agent-ui-show '(:id "fix" :type "choice" :question "Which?" :options ("A" "B")) :canvas name)
      (let ((this-command 'agent-ui-goto-question))
        (agent-ui-goto-question))
      (should (agent-ui--pane-session-window session))
      (should (+test-auti-in-place-p session))
      (should (eq (window-buffer (selected-window)) (get-buffer (agent-ui-canvas-buffer-name name)))))))
