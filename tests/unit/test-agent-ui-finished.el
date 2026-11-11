;;; tests/unit/test-agent-ui-finished.el -*- lexical-binding: t; -*-
;; config/agent-ui/finished.el: a finished element closes itself. steps, todo
;; and progress finished well count down (a line under them, Keep) and close;
;; one that failed stays; a change restarts or stops it; Keep stops it until
;; it changes; :close and `agent-ui-close-finished' decide; counting only
;; while the canvas is in a window; never in a project panel. The countdown's
;; ticks are called here, not waited for.

(+test-load "config/agent-ui")

;; ====== HELPERS ======

(defmacro +test-auf (&rest body)
  "BODY with a canvas of its own, `canvas', shown in the selected window
\(killed after); finished elements closing after 10 seconds."
  (declare (indent 0))
  `(let ((agent-ui-default-canvas (make-temp-name "test-"))
         (agent-ui-display-function #'switch-to-buffer)
         (agent-ui-close-finished 10))
     (save-window-excursion
       (delete-other-windows)
       (let ((canvas (agent-ui-canvas)))
         (switch-to-buffer canvas)
         (unwind-protect (progn ,@body)
           (kill-buffer canvas))))))

(defun +test-auf-text ()
  (with-current-buffer (agent-ui-canvas)
    (agent-ui--flush)
    (buffer-substring-no-properties (point-min) (point-max))))

(defun +test-auf-tick (&optional n)
  "N seconds of the canvas's countdowns (default 1), as its timer ticks."
  (let ((canvas (agent-ui-canvas)))
    (dotimes (_ (or n 1))
      (when (buffer-live-p canvas)
        (agent-ui--closing-tick canvas (buffer-local-value 'agent-ui--closing-timer canvas))))))

(defun +test-auf-left (id)
  "The seconds element ID has left, if it counts down."
  (with-current-buffer (agent-ui-canvas)
    (cdr (and agent-ui--closing (gethash id agent-ui--closing)))))

(defun +test-auf-there-p (id)
  "Whether element ID is on the canvas."
  (member id (buffer-local-value 'agent-ui--order (agent-ui-canvas))))

(defconst +test-auf-done
  '(:id "plan" :type "steps" :steps ((:name "Test" :status "done") (:name "Build" :status "skipped")))
  "A plan finished well.")

;; ====== WHEN ONE'S FINISHED ======

(ert-deftest agent-ui-finished/what-finished-means ()
  "steps: all done or skipped (one failed: failed); todo: all ticked, the
user's changes sent; progress: done, or at its max (failed: failed). Others
don't finish."
  (cl-flet ((finished (element) (agent-ui-finished element)))
    (should (eq (finished +test-auf-done) 'done))
    (should (eq (finished '(:type "steps" :steps ((:name "A" :status "done")
                                                  (:name "B" :status "running"
                                                   :steps ((:name "b" :status "failed"))))))
                'failed))
    (should-not (finished '(:type "steps" :steps ((:name "A" :status "done") "B"))))
    (should-not (finished '(:type "steps" :steps ())))
    ;; A plan to approve isn't, even all done.
    (should-not (finished '(:type "steps" :approve t :steps ((:name "A" :status "done")))))
    (should (eq (finished '(:type "todo" :items ((:label "A" :done t) (:label "B" :done t)))) 'done))
    (should-not (finished '(:type "todo" :items ((:label "A" :done t) "B"))))
    (should-not (finished '(:type "todo" :items ((:label "A" :done t))
                            :changes ((:label "A" :change "done")))))
    (should (eq (finished '(:type "progress" :value 12 :max 12)) 'done))
    (should (eq (finished '(:type "progress" :value 3 :status "done")) 'done))
    (should (eq (finished '(:type "progress" :value 12 :max 12 :status "failed")) 'failed))
    (should-not (finished '(:type "progress" :value 3 :max 12)))
    (should-not (finished '(:type "progress" :value 3)))
    (should-not (finished '(:type "text" :text "done")))))

(ert-deftest agent-ui-finished/close-is-checked ()
  "close: seconds, true or false, on a type that finishes."
  (+test-auf
    (should (agent-ui-show (append '(:close 3) +test-auf-done)))
    (should (agent-ui-show (append '(:close :false) +test-auf-done)))
    (should (string-match-p "close: a text doesn't finish"
                            (agent-ui-error-message
                             (should-error (agent-ui-show '(:id "t" :type "text" :text "x" :close 5))
                                           :type 'agent-ui-error))))
    (should (string-match-p "close: seconds after it finished"
                            (agent-ui-error-message
                             (should-error (agent-ui-show (append '(:close "soon") +test-auf-done))
                                           :type 'agent-ui-error))))))

;; ====== THE COUNTDOWN ======

(ert-deftest agent-ui-finished/a-plan-done-counts-down-and-closes ()
  "Not finished: no countdown. All done: a line under it counts 10 seconds
down, with Keep; at 0 it's removed, its pane closing with it (its last)."
  (+test-auf
    (agent-ui-show '(:id "plan" :type "steps" :steps ("Test" "Build")))
    (should-not (+test-auf-left "plan"))
    (should-not (string-search "closing in" (+test-auf-text)))
    (agent-ui-append "plan" '(:steps ((:name "Test" :status "done") (:name "Build" :status "done"))))
    (should (= (+test-auf-left "plan") 10))
    (should (string-match-p "✓ All done, closing in 10s +⏵ Keep" (+test-auf-text)))
    (should (timerp (buffer-local-value 'agent-ui--closing-timer canvas)))
    (+test-auf-tick 9)
    (should (string-search "closing in 1s" (+test-auf-text)))
    (should (get-buffer-window canvas))
    (+test-auf-tick)
    (should-not (+test-auf-there-p "plan"))
    (should-not (get-buffer-window canvas))
    (should-not (buffer-local-value 'agent-ui--closing-timer canvas))))

(ert-deftest agent-ui-finished/failed-stays ()
  "A step failed: no countdown, never closed; done after all (a retry): it
counts down then."
  (+test-auf
    (agent-ui-show '(:id "plan" :type "steps" :steps ((:name "Test" :status "failed") (:name "Build" :status "done"))))
    (should-not (+test-auf-left "plan"))
    (+test-auf-tick 20)
    (should (+test-auf-there-p "plan"))
    (agent-ui-append "plan" '(:steps ((:name "Test" :status "done"))))
    (should (= (+test-auf-left "plan") 10))))

(ert-deftest agent-ui-finished/a-change-restarts-or-stops-it ()
  "Counting down: changed and still done, it starts again; a step added
\(pending), it stops, the line gone; done again, it starts again."
  (+test-auf
    (agent-ui-show +test-auf-done)
    (+test-auf-tick 4)
    (should (= (+test-auf-left "plan") 6))
    (agent-ui-append "plan" '(:steps ((:name "Test" :status "done" :detail "412 passed"))))
    (should (= (+test-auf-left "plan") 10))
    (agent-ui-append "plan" '(:steps ("Publish")))
    (should-not (+test-auf-left "plan"))
    (should-not (string-search "closing in" (+test-auf-text)))
    (+test-auf-tick 20)
    (should (+test-auf-there-p "plan"))
    (agent-ui-append "plan" '(:steps ((:name "Publish" :status "done"))))
    (should (= (+test-auf-left "plan") 10))))

(ert-deftest agent-ui-finished/keep ()
  "Keep (its button): the countdown stops, the line goes, it stays; changed
and finished again, it counts down again."
  (+test-auf
    (agent-ui-show +test-auf-done)
    (with-current-buffer canvas
      (agent-ui--flush)
      (goto-char (point-min))
      (search-forward "⏵ Keep")
      (backward-char 1)
      (agent-ui-button-press))
    (should-not (+test-auf-left "plan"))
    (should-not (string-search "closing in" (+test-auf-text)))
    (+test-auf-tick 20)
    (should (+test-auf-there-p "plan"))
    (agent-ui-append "plan" '(:steps ((:name "Test" :status "done" :detail "again"))))
    (should (= (+test-auf-left "plan") 10))))

(ert-deftest agent-ui-finished/close-decides ()
  "The element's close: false keeps it; seconds its own; the default off
\(`agent-ui-close-finished' nil): only one whose close gives seconds."
  (+test-auf
    (agent-ui-show (append '(:close :false) +test-auf-done))
    (should-not (+test-auf-left "plan"))
    (agent-ui-update "plan" '(:close 3))
    (should (= (+test-auf-left "plan") 3))
    (should (string-search "closing in 3s" (+test-auf-text)))
    (let ((agent-ui-close-finished nil))
      (agent-ui-show '(:id "bar" :type "progress" :value 5 :max 5))
      (should-not (+test-auf-left "bar"))
      (agent-ui-update "bar" '(:close 2))
      (should (= (+test-auf-left "bar") 2)))))

(ert-deftest agent-ui-finished/todo-and-progress ()
  "A todo all ticked, a bar at its end: they count down too; failed: not."
  (+test-auf
    (agent-ui-show '(:id "todo" :type "todo" :items ("A" "B")))
    (agent-ui-show '(:id "bar" :type "progress" :value 3 :max 12))
    (should-not (+test-auf-left "todo"))
    (should-not (+test-auf-left "bar"))
    (agent-ui-append "todo" '(:items ((:label "A" :done t) (:label "B" :done t))))
    (agent-ui-update "bar" '(:value 12))
    (should (= (+test-auf-left "todo") 10))
    (should (= (+test-auf-left "bar") 10))
    (agent-ui-update "bar" '(:status "failed"))
    (should-not (+test-auf-left "bar"))
    ;; The todo closes; the bar, failed, stays, its pane too.
    (+test-auf-tick 10)
    (should-not (+test-auf-there-p "todo"))
    (should (+test-auf-there-p "bar"))
    (should (get-buffer-window canvas))))

(ert-deftest agent-ui-finished/waits-while-not-shown ()
  "Its canvas in no window: the countdown waits; shown again, it goes on."
  (+test-auf
    (agent-ui-show +test-auf-done)
    (switch-to-buffer (get-buffer-create "*scratch*"))
    (+test-auf-tick 20)
    (should (= (+test-auf-left "plan") 10))
    (switch-to-buffer canvas)
    (+test-auf-tick 3)
    (should (= (+test-auf-left "plan") 7))))

(ert-deftest agent-ui-finished/not-in-a-project-panel ()
  "A project panel's elements never count down: it stays."
  (+test-auf
    (with-current-buffer canvas
      (setq-local agent-ui-panels--state 'a-panel))
    (agent-ui-show +test-auf-done)
    (should-not (+test-auf-left "plan"))))
