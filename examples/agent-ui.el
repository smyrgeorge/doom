;;; $DOOMDIR/examples/agent-ui.el -*- lexical-binding: t; -*-
;; Example: Agent UI's canvas (config/agent-ui.el, docs/agent-ui.md). M-x
;; +my/example-agent-ui opens a conversation with an agent releasing a
;; project (release.md, in the temp folder, standing in for its agent-shell
;; session) and, beside it, the canvas the agent keeps up to date as it works,
;; played out over a few seconds: a checklist of the release's steps, the
;; tests' table filling in (one fails), the build's progress bar, a chart of
;; the last builds' times. The agent's way of doing it is cmd/agent-ui; here,
;; the same through Lisp. The file is deleted once both are closed.

;; ====== VARIABLES ======

(defvar +my/example-agent-ui--timer nil "What plays the example out.")
(defvar +my/example-agent-ui--done nil "Non-nil once it's played out.")

(defconst +my/example-agent-ui--canvas "example"
  "The example's canvas's name.")

(defconst +my/example-agent-ui--conversation
  "# Release v2.4

**You:** Release v2.4: run the tests, build it, and publish it if all's well.

**Agent:** On it. I'll keep the steps, the tests and the build beside us on the canvas while they run.

**Agent:** `checker` fails: its test expects the old error message. I won't publish: the build is done, publishing waits for a fix. Shall I fix the test?
"
  "release.md: the conversation the canvas goes with.")

;; ====== CODE ======

(defun +my/example-agent-ui--steps ()
  "What the agent does, a step per tick: functions."
  (let ((canvas +my/example-agent-ui--canvas)
        (tests '(("lexer" "passed" "0.4s") ("parser" "passed" "1.1s") ("checker" "failed" "0.7s")
                 ("codegen" "passed" "2.3s") ("linker" "passed" "0.9s"))))
    (append
     (list
      (lambda ()
        (agent-ui-show '(:id "plan" :type "steps" :title "Release v2.4"
                         :steps ((:name "Run the tests" :status "running") "Build" "Publish"))
                       :canvas canvas)
        (agent-ui-show '(:id "tests" :type "table" :title "Tests"
                         :columns ("Test" "Result" "Time") :key "Test")
                       :canvas canvas)))
     ;; Each test running, then its result.
     (mapcan (lambda (test)
               (list (lambda ()
                       (agent-ui-append "tests" `(:rows ((,(car test) "running" nil))) :canvas canvas))
                     (lambda ()
                       (agent-ui-append "tests" `(:rows (,test)) :canvas canvas))))
             tests)
     (list
      (lambda ()
        (agent-ui-append "plan" '(:steps ((:name "Run the tests" :status "failed" :detail "4 passed, 1 failed")
                                          (:name "Build" :status "running")))
                         :canvas canvas)
        (agent-ui-show '(:id "build" :type "progress" :title "Build" :max 12 :label "configuring")
                       :canvas canvas)))
     (mapcar (lambda (n)
               (lambda ()
                 (agent-ui-update "build" (list :value n :label (format "compiling unit %d of 12" n))
                                  :canvas canvas)))
             (number-sequence 1 12))
     (list
      (lambda ()
        (agent-ui-update "build" '(:status "done" :label "built in 29s") :canvas canvas)
        (agent-ui-show '(:id "times" :type "chart" :title "Build time" :unit "s" :height 5
                         :labels ("v2.0" "v2.1" "v2.2" "v2.3" "v2.4")
                         :series ((:name "this machine" :values (42 40 45 38 29))
                                  (:name "CI" :values (61 63 58 60 52))))
                       :canvas canvas))
      (lambda ()
        (agent-ui-append "plan" '(:steps ((:name "Build" :status "done" :seconds 29)
                                          (:name "Publish" :status "skipped" :detail "a test failed")))
                         :canvas canvas)
        (setq +my/example-agent-ui--done t)
        (message "Agent UI example: the canvas an agent fills in beside its conversation as it works; q hides it"))))))

(defun +my/example-agent-ui--stop ()
  (when (timerp +my/example-agent-ui--timer)
    (cancel-timer +my/example-agent-ui--timer))
  (setq +my/example-agent-ui--timer nil))

(defun +my/example-agent-ui--play (steps)
  "Do the first of STEPS, the others after, a tick apart; stopped if the
canvas was closed."
  (+my/example-agent-ui--stop)
  (when (and steps (get-buffer (agent-ui-canvas-buffer-name +my/example-agent-ui--canvas)))
    (funcall (car steps))
    (setq +my/example-agent-ui--timer
          (run-with-timer 0.25 nil #'+my/example-agent-ui--play (cdr steps)))))

(defun +my/example-agent-ui-ready ()
  "Non-nil once the example has played out (the screenshots wait for it)."
  +my/example-agent-ui--done)

(defun +my/example-agent-ui ()
  "Example: an agent's canvas beside its conversation, filled in as it
works (the file deleted once both are closed). See examples/agent-ui.el."
  (interactive)
  (+my/example-agent-ui--stop)
  (setq +my/example-agent-ui--done nil)
  (when-let* ((old (get-buffer (agent-ui-canvas-buffer-name +my/example-agent-ui--canvas))))
    (kill-buffer old))
  (let* ((dir (+my/example-folder "agent-ui"))
         (file (+my/example-write dir "release.md" +my/example-agent-ui--conversation)))
    (delete-other-windows)
    (find-file file)
    (let ((conversation (current-buffer))
          (canvas (agent-ui-canvas +my/example-agent-ui--canvas)))
      (with-current-buffer canvas
        (add-hook 'kill-buffer-hook #'+my/example-agent-ui--stop nil t))
      (+my/example-delete-when-closed dir (list conversation canvas))
      ;; The canvas opens beside the conversation with its first element.
      (+my/example-agent-ui--play (+my/example-agent-ui--steps))
      (list conversation canvas))))
