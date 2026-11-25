;;; $DOOMDIR/examples/agent-ui.el -*- lexical-binding: t; -*-
;; Example: Agent UI in its session's pane (config/agent-ui.el,
;; docs/agent-ui.md). M-x +my/example-agent-ui starts an agent-shell session
;; with a stand-in agent (examples/agent-workspace/stand-in.el: offline, at no
;; cost) and asks it to release a project; as it runs the tests and the
;; build, its Agent UI fills in under the conversation, played out over a few
;; seconds: its canvas (the release's steps, the build's progress bar, a chart
;; of the last builds' times), its tests canvas (figures, the tests' table
;; filling in, one failing) and a question on its ask canvas (how to go on).
;; An agent's way of doing it is cmd/agent-ui; here, the same through Lisp. q
;; closes a view. The folder is deleted once the session is closed.

;; ====== VARIABLES ======

(defvar +my/example-agent-ui--timer nil "What plays the example out.")
(defvar +my/example-agent-ui--done nil "Non-nil once its canvases are played out.")
(defvar +my/example-agent-ui--answered nil "Non-nil once the agent's turn is over.")

(defconst +my/example-agent-ui--stand-in
  (expand-file-name "agent-workspace/stand-in.el" (file-name-directory (or load-file-name buffer-file-name)))
  "The stand-in agent.")

(defconst +my/example-agent-ui--prompt
  "Release v2.4: run the tests, build it, and publish it if all's well."
  "What the agent is asked (the stand-in's \"Release\").")

;; ====== CODE ======

(defun +my/example-agent-ui--config (dir)
  "An agent-shell config whose agent is the stand-in, run by this Emacs in
batch (its home in DIR)."
  (require 'agent-shell)
  (agent-shell-make-agent-config
   :identifier 'example-agent
   :mode-line-name "Agent"
   :buffer-name "Agent"
   :shell-prompt "Agent> "
   :shell-prompt-regexp "Agent> "
   :welcome-function (lambda (_config) "\n  A stand-in agent (examples/agent-ui.el), offline.\n")
   :client-maker (lambda (buffer)
                   (agent-shell--make-acp-client
                    :command (expand-file-name invocation-name invocation-directory)
                    :command-params (list "--batch" "-Q" (concat "--init-directory=" (expand-file-name "stand-in/" dir))
                                          "-l" +my/example-agent-ui--stand-in "-f" "mock-acp-main")
                    :context-buffer buffer))))

(defun +my/example-agent-ui--summary (canvas passed failed)
  "The tests' figures on CANVAS: PASSED and FAILED so far."
  (agent-ui-show `(:id "summary" :type "stats"
                   :figures ((:label "Passed" :value ,passed :face "success")
                             (:label "Failed" :value ,failed :good "down" :face ,(if (> failed 0) "error" "muted"))
                             (:label "Coverage" :value 87.1 :unit "%" :change 2.3)))
                 :canvas canvas))

(defun +my/example-agent-ui--steps (session)
  "What the agent shows as it works, a step per tick: functions. SESSION:
its canvas's name."
  (let ((tests-canvas (agent-ui-sub-canvas session "tests"))
        (ask (agent-ui-sub-canvas session "ask"))
        (tests '(("lexer" "passed" "0.4s") ("parser" "passed" "1.1s") ("checker" "failed" "0.7s")
                 ("codegen" "passed" "2.3s") ("linker" "passed" "0.9s") ("repl" "passed" "1.6s"))))
    (append
     (list
      (lambda ()
        (agent-ui-show '(:id "plan" :type "steps" :title "Release v2.4" :close :false
                         :steps ((:name "Run the tests" :status "running") "Build" "Publish"))
                       :canvas session)
        (+my/example-agent-ui--summary tests-canvas 0 0)
        (agent-ui-show '(:id "tests" :type "table" :title "Tests"
                         :columns ("Test" "Result" "Time") :key "Test")
                       :canvas tests-canvas)))
     ;; Each test running, then its result, counted.
     (let ((passed 0) (failed 0))
       (mapcan (lambda (test)
                 (list (lambda ()
                         (agent-ui-append "tests" `(:rows ((,(car test) "running" nil))) :canvas tests-canvas))
                       (lambda ()
                         (if (equal (nth 1 test) "failed") (cl-incf failed) (cl-incf passed))
                         (+my/example-agent-ui--summary tests-canvas passed failed)
                         (agent-ui-append "tests" `(:rows (,test)) :canvas tests-canvas))))
               tests))
     (list
      (lambda ()
        (agent-ui-append "plan" '(:steps ((:name "Run the tests" :status "failed" :detail "5 passed, 1 failed")
                                          (:name "Build" :status "running")))
                         :canvas session)
        ;; Kept once done (not closed by itself): the release talked through.
        (agent-ui-show '(:id "build" :type "progress" :title "Build" :max 12 :label "configuring" :close :false)
                       :canvas session)))
     (mapcar (lambda (n)
               (lambda ()
                 (agent-ui-update "build" (list :value n :label (format "compiling unit %d of 12" n))
                                  :canvas session)))
             (number-sequence 1 12))
     (list
      (lambda ()
        (agent-ui-update "build" '(:status "done" :label "built in 29s") :canvas session)
        (agent-ui-show '(:id "times" :type "chart" :title "Build time" :unit "s" :height 5
                         :labels ("v2.0" "v2.1" "v2.2" "v2.3" "v2.4")
                         :series ((:name "this machine" :values (42 40 45 38 29))
                                  (:name "CI" :values (61 63 58 60 52))))
                       :canvas session))
      (lambda ()
        (agent-ui-append "plan" '(:steps ((:name "Build" :status "done" :seconds 29)
                                          (:name "Publish" :status "waiting" :detail "asks you")))
                         :canvas session)
        (agent-ui-show '(:id "next" :type "choice"
                         :question "checker's test expects the old error message. How do I go on?"
                         :options ((:label "Fix the test" :detail "then publish v2.4")
                                   (:label "Publish anyway" :detail "the test fixed after")
                                   (:label "Stop here" :detail "you look into it")))
                       :canvas ask)
        (setq +my/example-agent-ui--done t)
        (message "Agent UI example: an agent's views under its conversation; q closes one"))))))

(defun +my/example-agent-ui--stop ()
  (when (timerp +my/example-agent-ui--timer)
    (cancel-timer +my/example-agent-ui--timer))
  (setq +my/example-agent-ui--timer nil))

(defun +my/example-agent-ui--play (buffer steps)
  "Do the first of STEPS, the others after, a tick apart; stopped if the
session BUFFER was closed."
  (+my/example-agent-ui--stop)
  (when (and steps (buffer-live-p buffer))
    (funcall (car steps))
    (setq +my/example-agent-ui--timer
          (run-with-timer 0.25 nil #'+my/example-agent-ui--play buffer (cdr steps)))))

(defun +my/example-agent-ui--ask (buffer)
  "The release asked for in session BUFFER, its canvases played out as it
runs."
  (when (buffer-live-p buffer)
    (agent-shell-insert :text +my/example-agent-ui--prompt :submit t :no-focus t :shell-buffer buffer)
    (+my/example-agent-ui--play buffer (+my/example-agent-ui--steps (agent-ui--session-name buffer)))))

(defun +my/example-agent-ui--answered (buffer)
  "The agent's turn over in session BUFFER: the conversation shown to its
end, its window full (shrunk as Agent UI opened, it kept its start)."
  (when-let* ((window (get-buffer-window buffer)))
    (with-selected-window window
      (goto-char (point-max))
      (recenter -1)))
  (setq +my/example-agent-ui--answered t))

(defun +my/example-agent-ui-ready ()
  "Non-nil once the example has played out (the screenshots wait for it):
its canvases, and the agent's turn."
  (and +my/example-agent-ui--done +my/example-agent-ui--answered))

(defun +my/example-agent-ui ()
  "Example: an agent's session, its Agent UI filled in under the
conversation as it works (the folder deleted once the session is closed).
See examples/agent-ui.el."
  (interactive)
  (+my/example-agent-ui--stop)
  (setq +my/example-agent-ui--done nil
        +my/example-agent-ui--answered nil)
  (let* ((dir (+my/example-folder "agent-ui"))
         (config (+my/example-agent-ui--config dir)))
    (+my/example-alone)
    (let ((buffer (agent-shell--start :config config :no-focus t :new-session t
                                      :session-strategy 'new :cwd dir)))
      (switch-to-buffer buffer)
      (with-current-buffer buffer
        ;; Closing it asks nothing (its queue, its transcript, its process).
        (remove-hook 'kill-buffer-query-functions #'agent-shell--prompt-queue-confirm-kill-buffer t)
        (setq-local shell-maker-prompt-before-killing-buffer nil)
        (when-let* ((process (ignore-errors (shell-maker--process))))
          (set-process-query-on-exit-flag process nil))
        (add-hook 'kill-buffer-hook #'+my/example-agent-ui--stop nil t))
      ;; Asked once it's ready; its turn over, said.
      (agent-shell-subscribe-to
       :shell-buffer buffer :event 'init-finished
       :on-event (lambda (_event) (run-at-time 0 nil #'+my/example-agent-ui--ask buffer)))
      (agent-shell-subscribe-to
       :shell-buffer buffer :event 'turn-complete
       :on-event (lambda (_event) (run-at-time 0 nil #'+my/example-agent-ui--answered buffer)))
      (+my/example-delete-when-closed dir (list buffer))
      buffer)))
